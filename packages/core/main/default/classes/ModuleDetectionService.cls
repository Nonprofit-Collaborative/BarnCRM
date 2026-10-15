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

    /** The two suites the Setup Assistant's first step offers, as `Suite__c` stores them (C-30). */
    public static final String SUITE_COMMUNITY = 'Community';
    public static final String SUITE_IMPACT = 'Impact';

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
     * The edition the administrator chose, `Community` or `Impact`, or null before anyone
     * chose. A value typed in Setup that is neither counts as no choice.
     */
    public static String chosenSuite() {
        String suite = SettingsService.getSettings().Suite__c;
        if (String.isBlank(suite)) {
            return null;
        }
        for (String known : new List<String>{ SUITE_COMMUNITY, SUITE_IMPACT }) {
            if (known.equalsIgnoreCase(suite.trim())) {
                return known;
            }
        }
        return null;
    }

    /** True only when the Nonprofit Edition is chosen: the one switch for nonprofit modules. */
    public static Boolean isNonprofitEdition() {
        return chosenSuite() == SUITE_IMPACT;
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
        return module(row, isGivingPresent());
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
        String edition = chosenSuite() == null ? SUITE_COMMUNITY : chosenSuite();
        List<ModuleInfo> offered = new List<ModuleInfo>{
            module(
                new BarnCRM_Module__mdt(DeveloperName = MODULE_CORE, Package_Folder__c = 'core'),
                true
            )
        };
        List<BarnCRM_Module__mdt> rows = catalog();
        Map<String, Boolean> presentByName = new Map<String, Boolean>();
        Map<String, String> labelByName = new Map<String, String>();
        for (BarnCRM_Module__mdt row : rows) {
            presentByName.put(row.DeveloperName, isPresent(row, announced));
            labelByName.put(row.DeveloperName, labelOf(row));
        }
        for (BarnCRM_Module__mdt row : rows) {
            Boolean present = presentByName.get(row.DeveloperName);
            if (present || offeredIn(row, edition)) {
                ModuleInfo info = module(row, present);
                info.installFirst = present ? null : missing(row, presentByName, labelByName);
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
        String edition = chosenSuite() == null ? SUITE_COMMUNITY : chosenSuite();
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

    private static ModuleInfo module(BarnCRM_Module__mdt row, Boolean present) {
        ModuleInfo info = new ModuleInfo();
        info.name = row.DeveloperName;
        info.label = labelOf(row);
        info.present = present;
        info.docsUrl = DOCS_BASE + row.Package_Folder__c + '/README.md';
        info.installUrl = present ? null : installUrl(row.Install_Version_Id__c);
        info.appUrl = present && String.isNotBlank(row.App_Name__c)
            ? APP_PATH + NamespaceUtil.prefix() + row.App_Name__c.trim()
            : null;
        return info;
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
