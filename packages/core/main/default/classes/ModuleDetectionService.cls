/**
 * Which BarnCRM packages are in this org, and what their objects are called.
 *
 * Core never references another package's schema statically (ADR-0009, plan Section 4.2):
 * every name below is a describe probe held as a string, and every caller has to cope with
 * the answer "not installed". A module is present when its probe object exists, or when it
 * has shipped Setting Definition rows naming itself (ADR-0017), which is how a module that
 * Core knows nothing else about announces itself to the settings console.
 */
public with sharing class ModuleDetectionService {
    // detection-only: Giving package is optional
    private static final String GIVING_FUND_OBJECT = 'Fund__c';
    // detection-only: Giving package is optional
    private static final String GIVING_APPEAL_OBJECT = 'Appeal__c';
    // detection-only: the Import framework (C-14) ships later in Core
    private static final String IMPORT_BATCH_OBJECT = 'Import_Batch__c';

    private static final String MODULE_CORE = 'Core';
    private static final String MODULE_GIVING = 'Giving';

    /** Each module's own README, which says what the module is without assuming a suite. */
    private static final String DOCS_BASE = 'https://github.com/Nonprofit-Collaborative/BarnCRM/blob/main/packages/';

    /** The two editions the Setup Assistant's first step offers, as `Suite__c` stores them (C-30). */
    public static final String SUITE_STANDARD = 'Standard';
    public static final String SUITE_NONPROFIT = 'Nonprofit';

    /**
     * The values `Suite__c` stored before ADR-0143 (`0143-edition-internal-values.md`), lower
     * case, by the value that replaced each. `CorePostInstall` rewrites a stored one; until it
     * has run (an org gate deploys without it), `chosenSuite` and Recent Changes read them as the
     * new values. Only BarnCRM's own test orgs ever stored them.
     */
    public static final Map<String, String> SUITE_BY_OLD_VALUE = new Map<String, String>{
        'community' => SUITE_STANDARD,
        'impact' => SUITE_NONPROFIT
    };

    /** Salesforce's installer for one package version, relative to the org's own domain. */
    private static final String INSTALL_PATH = '/packaging/installPackage.apexp?p0=';

    /** A Lightning app by its developer name, relative to the org's own domain. */
    private static final String APP_PATH = '/lightning/app/';

    /**
     * Stands in for the shipped module catalog (`BarnCRM_Module__mdt`) in tests. The catalog
     * says which editions offer each module and where its installer is; Core never installs
     * anything, it only links to Salesforce's installer (ADR-0124).
     */
    @TestVisible
    private static List<BarnCRM_Module__mdt> catalogOverride;

    /** Stands in for the Giving probe in tests, whose answer otherwise depends on the org. */
    @TestVisible
    private static Boolean givingPresentOverride;

    /** One row of the module list the Setup Assistant shows in step six. */
    public class ModuleInfo {
        @AuraEnabled
        public String name;
        /** The name shown to administrators, such as BarnCRM Giving (the catalog's label). */
        @AuraEnabled
        public String label;
        @AuraEnabled
        public Boolean present;
        /** The module's own app, where its Settings tab lives, or null when it has none yet. */
        @AuraEnabled
        public String appUrl;
        @AuraEnabled
        public String docsUrl;
        /** Salesforce's installer for this module, or null when it is here or not published. */
        @AuraEnabled
        public String installUrl;
        /**
         * For a module that is not here, the modules its package needs that are not here
         * either, by name shown, in install order (`Requires__c`, ADR-0125 D3); otherwise null.
         */
        @AuraEnabled
        public String installFirst;
        /**
         * True when only the Nonprofit Edition offers this module: the catalog names editions and
         * the Standard edition (`Standard`) is not among them. False for Core and for a module
         * both editions offer.
         */
        @AuraEnabled
        public Boolean nonprofitOnly;
        /**
         * For a module that is here, its tabs that belong in the BarnCRM and BarnCRM Console apps
         * (`Staff_Tabs__c`) and in the two admin apps (`Admin_Tabs__c`), by label and comma
         * separated, so an administrator can add them in App Manager after a package install;
         * otherwise null (ADR-0137).
         */
        @AuraEnabled
        public String staffTabs;
        @AuraEnabled
        public String adminTabs;
    }

    /**
     * True when the Giving package is installed. The package announcing itself with its own
     * Setting Definition rows is the primary signal (ADR-0017): it survives a namespace and
     * cannot be imitated by an org's own object. The describe probe is the fallback, and is
     * only trusted when both objects are there, so that an org with its own `Fund__c` and no
     * appeal object is not mistaken for Giving.
     */
    public static Boolean isGivingPresent() {
        return givingPresent(announcedModules());
    }

    /** The same, for a caller that has already read the announced modules. */
    private static Boolean givingPresent(Set<String> announced) {
        if (givingPresentOverride != null) {
            return givingPresentOverride;
        }
        if (announced.contains(MODULE_GIVING.toLowerCase())) {
            return true;
        }
        return objectExists(GIVING_FUND_OBJECT) && objectExists(GIVING_APPEAL_OBJECT);
    }

    /** True when the Import framework's staging object is in this org, so the Import tab is worth linking to. */
    public static Boolean isImportPresent() {
        return objectExists(IMPORT_BATCH_OBJECT);
    }

    /**
     * The edition the administrator chose, `Standard` or `Nonprofit`, or null before anyone
     * chose. A value from before ADR-0143 reads as the value that replaced it; any other value
     * typed in Setup counts as no choice.
     */
    public static String chosenSuite() {
        String suite = SettingsService.getSettings().Suite__c;
        if (String.isBlank(suite)) {
            return null;
        }
        for (String known : new List<String>{ SUITE_STANDARD, SUITE_NONPROFIT }) {
            if (known.equalsIgnoreCase(suite.trim())) {
                return known;
            }
        }
        return SUITE_BY_OLD_VALUE.get(suite.trim().toLowerCase());
    }

    /** True only when the Nonprofit Edition is chosen: the one switch for nonprofit modules. */
    public static Boolean isNonprofitEdition() {
        return chosenSuite() == SUITE_NONPROFIT;
    }

    /** The Giving module alone, for the suite step: whether it is here, and where to read and install it. */
    public static ModuleInfo givingModule() {
        BarnCRM_Module__mdt row = catalogRow(MODULE_GIVING);
        if (row == null) {
            row = new BarnCRM_Module__mdt(
                DeveloperName = MODULE_GIVING,
                Package_Folder__c = 'giving'
            );
        }
        Boolean present = isGivingPresent();
        return module(row, present, present ? appIds(new List<BarnCRM_Module__mdt>{ row }) : null);
    }

    /** Salesforce's installer for a published version, or null when none is published. */
    private static String installUrl(String versionId) {
        if (String.isBlank(versionId) || !versionId.trim().startsWith('04t')) {
            return null;
        }
        return INSTALL_PATH + versionId.trim();
    }

    /**
     * The BarnCRM packages this org is offered, each saying whether it is here: Core, then
     * every module the catalog says the chosen edition offers (the Standard Edition's, before
     * one is chosen), and any module that is already installed whatever the edition (ADR-0124).
     */
    public static List<ModuleInfo> getModules() {
        Set<String> announced = announcedModules();
        String edition = chosenSuite() == null ? SUITE_STANDARD : chosenSuite();
        List<ModuleInfo> offered = new List<ModuleInfo>{
            module(
                new BarnCRM_Module__mdt(DeveloperName = MODULE_CORE, Package_Folder__c = 'core'),
                true,
                null
            )
        };
        List<BarnCRM_Module__mdt> rows = catalog();
        Map<String, Boolean> presentByName = new Map<String, Boolean>();
        Map<String, String> labelByName = new Map<String, String>();
        for (BarnCRM_Module__mdt row : rows) {
            presentByName.put(row.DeveloperName, isPresent(row, announced));
            labelByName.put(row.DeveloperName, labelOf(row));
        }
        List<BarnCRM_Module__mdt> hereRows = new List<BarnCRM_Module__mdt>();
        for (BarnCRM_Module__mdt row : rows) {
            if (presentByName.get(row.DeveloperName)) {
                hereRows.add(row);
            }
        }
        Map<String, String> appIds = appIds(hereRows);
        Map<String, String> tabLabels = tabLabels(hereRows);
        for (BarnCRM_Module__mdt row : rows) {
            Boolean present = presentByName.get(row.DeveloperName);
            if (present || offeredIn(row, edition)) {
                ModuleInfo info = module(row, present, appIds);
                info.installFirst = present ? null : missing(row, presentByName, labelByName);
                info.staffTabs = present ? labelsOf(row.Staff_Tabs__c, tabLabels) : null;
                info.adminTabs = present ? labelsOf(row.Admin_Tabs__c, tabLabels) : null;
                offered.add(info);
            }
        }
        return offered;
    }

    /**
     * The modules a module's package needs that are not here, by name shown and in the order
     * `Requires__c` lists them, or null when none is missing. A key the catalog does not know
     * is shown as it is written.
     */
    private static String missing(
        BarnCRM_Module__mdt row,
        Map<String, Boolean> presentByName,
        Map<String, String> labelByName
    ) {
        List<String> names = new List<String>();
        String required = row.Requires__c == null ? '' : row.Requires__c;
        for (String part : required.split(';')) {
            String key = part.trim();
            if (String.isBlank(key) || presentByName.get(key) == true) {
                continue;
            }
            names.add(labelByName.containsKey(key) ? labelByName.get(key) : key);
        }
        return names.isEmpty() ? null : String.join(names, ', ');
    }

    private static String labelOf(BarnCRM_Module__mdt row) {
        return String.isBlank(row.MasterLabel) ? row.DeveloperName : row.MasterLabel;
    }

    /**
     * True when the module announced itself with Setting Definition rows, when the catalog
     * names an object of its own that this package has, or, for Giving, when its probe says so.
     */
    private static Boolean isPresent(BarnCRM_Module__mdt row, Set<String> announced) {
        String name = row.DeveloperName;
        if (announced.contains(name.toLowerCase())) {
            return true;
        }
        if (name == MODULE_GIVING && givingPresent(announced)) {
            return true;
        }
        return String.isNotBlank(row.Probe_Object__c) && objectExists(row.Probe_Object__c.trim());
    }

    /** True when the catalog says the chosen edition (Standard before one is chosen) offers it. */
    public static Boolean isOffered(String moduleName) {
        String edition = chosenSuite() == null ? SUITE_STANDARD : chosenSuite();
        return offeredIn(catalogRow(moduleName), edition);
    }

    /** True when the catalog row lists the given edition among those that offer it. */
    @TestVisible
    private static Boolean offeredIn(BarnCRM_Module__mdt row, String edition) {
        if (row == null || String.isBlank(row.Editions__c) || String.isBlank(edition)) {
            return false;
        }
        for (String part : row.Editions__c.split(';')) {
            if (part.trim().equalsIgnoreCase(edition)) {
                return true;
            }
        }
        return false;
    }

    /**
     * True when the catalog names at least one edition for the module and the Standard edition
     * is not among them, so only the Nonprofit Edition offers it. Data driven: no module name.
     */
    @TestVisible
    private static Boolean isNonprofitOnly(BarnCRM_Module__mdt row) {
        return row != null && String.isNotBlank(row.Editions__c) && !offeredIn(row, SUITE_STANDARD);
    }

    /** The shipped module catalog, lowest Sort Order first. */
    private static List<BarnCRM_Module__mdt> catalog() {
        List<BarnCRM_Module__mdt> rows = catalogOverride != null
            ? catalogOverride
            : BarnCRM_Module__mdt.getAll().values();
        List<BarnCRM_Module__mdt> sorted = new List<BarnCRM_Module__mdt>();
        for (BarnCRM_Module__mdt row : rows) {
            Integer at = sorted.size();
            while (at > 0 && orderOf(sorted[at - 1]) > orderOf(row)) {
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

    private static Decimal orderOf(BarnCRM_Module__mdt row) {
        return row.Sort_Order__c == null ? 1000 : row.Sort_Order__c;
    }

    private static BarnCRM_Module__mdt catalogRow(String name) {
        for (BarnCRM_Module__mdt row : catalog()) {
            if (row.DeveloperName == name) {
                return row;
            }
        }
        return null;
    }

    /** The modules that have shipped settings console rows naming themselves. */
    private static Set<String> announcedModules() {
        Set<String> names = new Set<String>();
        try {
            for (Setting_Definition__mdt definition : SettingDefinitionSelector.getAll()) {
                if (String.isNotBlank(definition.Module__c)) {
                    names.add(definition.Module__c.trim().toLowerCase());
                }
            }
        } catch (Exception e) {
            ErrorLogger.log(e, 'BarnCRM module detection');
        }
        return names;
    }

    private static ModuleInfo module(
        BarnCRM_Module__mdt row,
        Boolean present,
        Map<String, String> appIds
    ) {
        ModuleInfo info = new ModuleInfo();
        info.name = row.DeveloperName;
        info.label = labelOf(row);
        info.present = present;
        info.nonprofitOnly = isNonprofitOnly(row);
        info.docsUrl = DOCS_BASE + row.Package_Folder__c + '/README.md';
        info.installUrl = present ? null : installUrl(row.Install_Version_Id__c);
        info.appUrl = present && String.isNotBlank(row.App_Name__c)
            ? appUrl(row.App_Name__c.trim(), appIds)
            : null;
        return info;
    }

    /**
     * The app's address by Id, which opens it however it is packaged; by name only when the
     * app is not found (not installed, or not visible to the user). Lightning addresses an
     * unmanaged app as `c__Name`, a managed one as `namespace__Name`.
     */
    private static String appUrl(String appName, Map<String, String> appIds) {
        String appId = appIds == null ? null : appIds.get(appName);
        if (String.isNotBlank(appId)) {
            return APP_PATH + appId;
        }
        String prefix = NamespaceUtil.prefix();
        return APP_PATH + (String.isBlank(prefix) ? 'c__' : prefix) + appName;
    }

    /**
     * Stands in for the app list in tests, by app developer name: the DurableId `AppDefinition`
     * gives it. An empty map means no app is found.
     */
    @TestVisible
    private static Map<String, String> appIdsOverride;

    /**
     * The DurableIds (06m) Lightning addresses the apps these catalog rows name by, by
     * developer name, from one `AppDefinition` query. Only an app in this package's namespace counts (none today), so another package's
     * app with the same developer name is not picked up.
     */
    private static Map<String, String> appIds(List<BarnCRM_Module__mdt> rows) {
        Map<String, String> found = new Map<String, String>();
        Set<String> names = new Set<String>();
        for (BarnCRM_Module__mdt row : rows) {
            if (String.isNotBlank(row.App_Name__c)) {
                names.add(row.App_Name__c.trim());
            }
        }
        if (names.isEmpty()) {
            return found;
        }
        if (appIdsOverride != null) {
            return appIdsOverride;
        }
        String namespace = NamespaceUtil.prefix().removeEnd('__');
        try {
            for (AppDefinition item : [
                SELECT DurableId, DeveloperName, NamespacePrefix
                FROM AppDefinition
                WHERE DeveloperName IN :names
                WITH USER_MODE
            ]) {
                if ((item.NamespacePrefix == null ? '' : item.NamespacePrefix) == namespace) {
                    found.put(item.DeveloperName, item.DurableId);
                }
            }
        } catch (Exception e) {
            ErrorLogger.log(e, 'BarnCRM module app links');
        }
        return found;
    }

    /** The entries in a catalog field, each `Name` or `Name:Label`, in the order written. */
    private static List<String> tabEntries(String field) {
        List<String> entries = new List<String>();
        for (String part : (field == null ? '' : field).split(';')) {
            if (String.isNotBlank(part)) {
                entries.add(part.trim());
            }
        }
        return entries;
    }

    /** The tab names in a catalog field, unprefixed, in the order written. */
    private static List<String> tabNames(String field) {
        List<String> names = new List<String>();
        for (String entry : tabEntries(field)) {
            names.add(entry.substringBefore(':').trim());
        }
        return names;
    }

    /**
     * The tabs' labels, comma separated, or null when the field names none: the label an
     * entry carries, else its object's, else its name with spaces.
     */
    private static String labelsOf(String field, Map<String, String> tabLabels) {
        List<String> labels = new List<String>();
        for (String entry : tabEntries(field)) {
            String name = entry.substringBefore(':').trim();
            String written = entry.substringAfter(':').trim();
            labels.add(
                String.isNotBlank(written)
                    ? written
                    : tabLabels.containsKey(name)
                          ? tabLabels.get(name)
                          : name.removeEnd('__c').replace('_', ' ')
            );
        }
        return labels.isEmpty() ? null : String.join(labels, ', ');
    }

    /** Stands in for the tab labels in tests, by unprefixed tab name. */
    @TestVisible
    private static Map<String, String> tabLabelsOverride;

    /**
     * The labels of the object tabs these catalog rows name, by unprefixed name: an object
     * tab is labelled with its object's plural label. A page tab, or an object not here, is
     * left out, and its name stands in for its label (page tabs are named after their label).
     */
    private static Map<String, String> tabLabels(List<BarnCRM_Module__mdt> rows) {
        if (tabLabelsOverride != null) {
            return tabLabelsOverride;
        }
        Map<String, String> found = new Map<String, String>();
        for (BarnCRM_Module__mdt row : rows) {
            List<String> names = tabNames(row.Staff_Tabs__c);
            names.addAll(tabNames(row.Admin_Tabs__c));
            for (String name : names) {
                Schema.SObjectType type = name.endsWith('__c')
                    ? NamespaceUtil.packagedObjectType(name)
                    : null;
                if (type != null) {
                    found.put(
                        name,
                        type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural()
                    );
                }
            }
        }
        return found;
    }

    private static Boolean objectExists(String objectName) {
        return resolveObject(objectName) != null;
    }

    /**
     * The API name a BarnCRM object has in this org, with whatever prefix the package carries
     * (Decision D-01), or null when the package's object is not here. Another package's object
     * with the same name, such as another package's `Fund__c`, does not count.
     */
    public static String resolveObject(String unqualifiedName) {
        Schema.SObjectType type = NamespaceUtil.packagedObjectType(unqualifiedName);
        return type == null ? null : type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
    }
}
