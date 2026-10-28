/**
 * The other products the Settings, Integrations page lists, and whether each is in this org.
 *
 * Core never depends on any of them. The catalog is `Integration_App__mdt`, shipped records that
 * name each product's own objects as strings, and a product counts as installed when the org's
 * describe has one of those objects. Nothing here references another product's schema or class,
 * so Core deploys and runs on an org with none of them (ADR-0009, ADR-0013). The names are data
 * a row can change without code. A packaged object is written `namespace.Object__c` in the row,
 * with a dot where the platform has two underscores.
 *
 * The global describe is read once per transaction.
 */
public with sharing class IntegrationAppService {
    public static final String CATEGORY_COMPLEMENT = 'Complement';
    public static final String CATEGORY_IN_DEVELOPMENT = 'InDevelopment';
    public static final String CATEGORY_ALTERNATIVE = 'Alternative';

    /** Planned and not built; the status of every row until an integration exists. */
    public static final String STATUS_IN_PROGRESS = 'InProgress';
    public static final String STATUS_AVAILABLE = 'Available';

    /** Stands in for the shipped catalog in tests. */
    @TestVisible
    private static List<Integration_App__mdt> catalogOverride;

    /** Stands in for the org's object names, lower case, in tests. */
    @TestVisible
    private static Set<String> objectNamesOverride;

    private static Set<String> objectNames;

    /** One product as the page shows it. */
    public class AppInfo {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String category;
        /** InProgress (planned, not built) or Available. */
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String maintainer;
        @AuraEnabled
        public String licenseCost;
        @AuraEnabled
        public String linkUrl;
        @AuraEnabled
        @AuraEnabled
        public String relatedModule;
        @AuraEnabled
        public String compatibility;
        /** Where to find BarnCRM's migration to the matching module, or null while none exists. */
        @AuraEnabled
        public String migrationPath;
        /** True when one of the product's objects is in this org. */
        @AuraEnabled
        public Boolean installed;
    }

    /**
     * Every product the page lists, lowest Sort Order first, each saying whether it is here. A
     * product marked Show Only When Installed is left out of an org that does not have it.
     */
    public static List<AppInfo> getApps() {
        List<AppInfo> apps = new List<AppInfo>();
        for (Integration_App__mdt row : catalog()) {
            Boolean installed = isDetected(row);
            if (row.Show_Only_When_Installed__c == true && !installed) {
                continue;
            }
            AppInfo info = new AppInfo();
            info.key = row.DeveloperName;
            info.name = String.isBlank(row.MasterLabel) ? row.DeveloperName : row.MasterLabel;
            info.category = categoryOf(row);
            info.status = STATUS_AVAILABLE.equalsIgnoreCase(row.Status__c)
                ? STATUS_AVAILABLE
                : STATUS_IN_PROGRESS;
            info.description = row.Description__c;
            info.maintainer = row.Maintainer__c;
            info.licenseCost = row.License_Cost__c;
            info.linkUrl = row.Link_Url__c;
            info.relatedModule = row.Related_Module__c;
            info.compatibility = row.Compatibility__c;
            info.migrationPath = row.Migration_Path__c;
            info.installed = installed;
            apps.add(info);
        }
        return apps;
    }

    /** The row's category, or Complement when it is blank or none of the three. */
    @TestVisible
    private static String categoryOf(Integration_App__mdt row) {
        for (
            String known : new List<String>{
                CATEGORY_COMPLEMENT,
                CATEGORY_IN_DEVELOPMENT,
                CATEGORY_ALTERNATIVE
            }
        ) {
            if (known.equalsIgnoreCase((row.Category__c == null ? '' : row.Category__c).trim())) {
                return known;
            }
        }
        return CATEGORY_COMPLEMENT;
    }

    /** True when the org has any one of the objects the row names. */
    private static Boolean isDetected(Integration_App__mdt row) {
        if (String.isBlank(row.Detection_Objects__c)) {
            return false;
        }
        Set<String> present = presentObjects();
        for (String entry : row.Detection_Objects__c.split(';')) {
            String apiName = entry.trim().replace('.', '__').toLowerCase();
            if (String.isNotBlank(apiName) && present.contains(apiName)) {
                return true;
            }
        }
        return false;
    }

    private static Set<String> presentObjects() {
        if (objectNamesOverride != null) {
            return objectNamesOverride;
        }
        if (objectNames == null) {
            objectNames = Schema.getGlobalDescribe().keySet();
        }
        return objectNames;
    }

    /** The shipped catalog, lowest Sort Order first, then by name. */
    private static List<Integration_App__mdt> catalog() {
        List<Integration_App__mdt> rows = catalogOverride != null
            ? catalogOverride
            : Integration_App__mdt.getAll().values();
        List<Integration_App__mdt> sorted = new List<Integration_App__mdt>();
        for (Integration_App__mdt row : rows) {
            Integer at = sorted.size();
            while (at > 0 && comesAfter(sorted[at - 1], row)) {
                at--;
            }
            if (at == sorted.size()) {
                sorted.add(row);
            } else {
                sorted.add(at, row);
            }
        }
        return sorted;
    }

    private static Boolean comesAfter(Integration_App__mdt first, Integration_App__mdt second) {
        Decimal firstOrder = first.Sort_Order__c == null ? 1000 : first.Sort_Order__c;
        Decimal secondOrder = second.Sort_Order__c == null ? 1000 : second.Sort_Order__c;
        if (firstOrder != secondOrder) {
            return firstOrder > secondOrder;
        }
        return String.valueOf(first.DeveloperName) > String.valueOf(second.DeveloperName);
    }
}
