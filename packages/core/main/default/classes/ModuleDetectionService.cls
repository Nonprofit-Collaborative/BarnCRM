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

    /**
     * The modules every organization is offered (ADR-0046: the Community Suite is Core with
     * the modules that fit). The others are offered only once Giving is installed, since
     * until the suite choice exists (C-30) Giving being here is what says the org is a
     * nonprofit (ADR-0062).
     */
    private static final Set<String> OFFERED_TO_EVERY_ORG = new Set<String>{
        MODULE_CORE,
        'Volunteers'
    };

    /** Stands in for the Giving probe in tests, whose answer otherwise depends on the org. */
    @TestVisible
    private static Boolean givingPresentOverride;

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
        if (givingPresentOverride != null) {
            return givingPresentOverride;
        }
        if (announcedModules().contains(MODULE_GIVING.toLowerCase())) {
            return true;
        }
        return objectExists(GIVING_FUND_OBJECT) && objectExists(GIVING_APPEAL_OBJECT);
    }

    /** True when the Import framework's staging object is in this org, so the Import tab is worth linking to. */
    public static Boolean isImportPresent() {
        return objectExists(IMPORT_BATCH_OBJECT);
    }

    /**
     * The BarnCRM packages this org is offered, each saying whether it is here. Every org sees
     * Core and Volunteers; the rest are listed once Giving is installed, and any module that
     * is already installed is always listed.
     */
    public static List<ModuleInfo> getModules() {
        Set<String> announced = announcedModules();
        Boolean givingPresent =
            isGivingPresent() || announced.contains(MODULE_GIVING.toLowerCase());
        List<ModuleInfo> all = new List<ModuleInfo>{
            module(MODULE_CORE, true, 'core'),
            module(MODULE_GIVING, givingPresent, 'giving'),
            module('Volunteers', announced.contains('volunteers'), 'volunteers'),
            module('Programs', announced.contains('programs'), 'programs'),
            module('Funders', announced.contains('funders'), 'funders'),
            module('Connect', announced.contains('connect'), 'connect')
        };
        List<ModuleInfo> offered = new List<ModuleInfo>();
        for (ModuleInfo info : all) {
            if (givingPresent || info.present || OFFERED_TO_EVERY_ORG.contains(info.name)) {
                offered.add(info);
            }
        }
        return offered;
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

    private static ModuleInfo module(String name, Boolean present, String folder) {
        ModuleInfo info = new ModuleInfo();
        info.name = name;
        info.present = present;
        info.docsUrl = DOCS_BASE + folder + '/README.md';
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
