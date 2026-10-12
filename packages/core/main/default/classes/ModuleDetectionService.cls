/**
 * Which Open Impact packages are in this org, and what their objects are called.
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

    private static final String DOCS_BASE = 'https://github.com/Nonprofit-Collaborative/OpenImpact/blob/main/docs/product-plan.md';

    /** One row of the module list the Setup Assistant shows in step six. */
    public class ModuleInfo {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Boolean present;
        @AuraEnabled
        public String docsUrl;
    }

    /**
     * True when the Giving package is installed. The package announcing itself with its own
     * Setting Definition rows is the primary signal (ADR-0017): it survives a namespace and
     * cannot be imitated by an org's own object. The describe probe is the fallback, and is
     * only trusted when both objects are there, so that an org with its own `Fund__c` and no
     * appeal object is not mistaken for Giving.
     */
    public static Boolean isGivingPresent() {
        if (announcedModules().contains(MODULE_GIVING.toLowerCase())) {
            return true;
        }
        return objectExists(GIVING_FUND_OBJECT) && objectExists(GIVING_APPEAL_OBJECT);
    }

    /** True when the Import framework's staging object is in this org, so the Import tab is worth linking to. */
    public static Boolean isImportPresent() {
        return objectExists(IMPORT_BATCH_OBJECT);
    }

    /** The six Open Impact packages, each saying whether it is in this org. */
    public static List<ModuleInfo> getModules() {
        Set<String> announced = announcedModules();
        List<ModuleInfo> modules = new List<ModuleInfo>();
        modules.add(module(MODULE_CORE, true, '#51-core-package'));
        modules.add(
            module(
                MODULE_GIVING,
                isGivingPresent() || announced.contains(MODULE_GIVING.toLowerCase()),
                '#52-giving-package'
            )
        );
        modules.add(
            module('Volunteers', announced.contains('volunteers'), '#53-volunteers-package')
        );
        modules.add(module('Programs', announced.contains('programs'), '#54-programs-package'));
        modules.add(module('Funders', announced.contains('funders'), '#55-funders-package'));
        modules.add(module('Connect', announced.contains('connect'), '#56-connect-package'));
        return modules;
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
            ErrorLogger.log(e, 'Open Impact module detection');
        }
        return names;
    }

    private static ModuleInfo module(String name, Boolean present, String anchor) {
        ModuleInfo info = new ModuleInfo();
        info.name = name;
        info.present = present;
        info.docsUrl = DOCS_BASE + anchor;
        return info;
    }

    private static Boolean objectExists(String objectName) {
        return resolveObject(objectName) != null;
    }

    /**
     * The API name an object actually has in this org, matching the unqualified name so that
     * the same probe works before and after a namespace is assigned (Decision D-01), or null
     * when no object matches.
     */
    private static String resolveObject(String unqualifiedName) {
        String wanted = unqualifiedName.toLowerCase();
        Map<String, Schema.SObjectType> describes = Schema.getGlobalDescribe();
        if (describes.containsKey(wanted)) {
            return describes.get(wanted).getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        }
        String suffix = '__' + wanted;
        for (String name : describes.keySet()) {
            if (name.endsWith(suffix)) {
                return describes.get(name).getDescribe(SObjectDescribeOptions.DEFERRED).getName();
            }
        }
        return null;
    }
}
