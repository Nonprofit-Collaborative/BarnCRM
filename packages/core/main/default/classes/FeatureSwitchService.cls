/**
 * The Core features of BarnCRM Settings, General, Features and of first-run setup (ADR-0124,
 * edition gates visibility): one place that knows what each feature covers and turns it on.
 *
 * A feature comes with Core; a module is a separate package with its own on and off (the
 * Module Manager). Features are off on a new install until an administrator turns them on, and
 * turning one on is one-way. `Features_Turned_On__c` lists the keys that are on: empty means
 * every feature is on (an org upgraded from before features existed), `None` means none is (a
 * new install before first-run setup), and `NoneChosen` means none is and first-run setup is
 * finished (every feature was unticked).
 *
 * Two kinds of feature:
 * - a tool (Data Manager, Duplicate Review, Org Optimizer), whose tabs `TabAccessService` gives
 *   once it is on;
 * - a Core feature group, whose Automation Registry switches are turned on with it and whose
 *   automations do not run while it is off (`automationsOff`, read by `AutomationControl`).
 *   Validations that enforce a rule belong to no group; the rollup automations belong to the
 *   BarnCRM Rollup Builder module.
 *
 * While a feature is off its rows in BarnCRM Settings are hidden (`hiddenSettingRows`). The
 * list is owner-overridable: it is held here, in one place, so a change is one edit.
 */
public with sharing class FeatureSwitchService {
    public static final String KIND_TOOL = 'Tool';
    public static final String KIND_FEATURE = 'Feature';

    public static final String DATA_MANAGER = 'DataManager';
    public static final String DUPLICATE_REVIEW = 'DuplicateReview';
    public static final String ORG_OPTIMIZER = 'OrgOptimizer';
    public static final String HOUSEHOLD_UPKEEP = 'HouseholdUpkeep';
    public static final String ADDRESSES = 'Addresses';
    public static final String RELATIONSHIPS = 'Relationships';
    public static final String AFFILIATIONS = 'Affiliations';
    public static final String PREFERRED_EMAIL = 'PreferredEmail';

    /** What a new install stores until first-run setup: no feature is on. */
    public static final String NONE_ON = 'None';

    /**
     * What first-run setup stores when the administrator finished it with every feature
     * unticked: still no feature on, but setup is done, so the window does not come back.
     * Turning any feature on later replaces it with that feature's key.
     */
    public static final String NONE_CHOSEN = 'NoneChosen';

    private static final String ON_KEY = 'Features_Turned_On__c';

    /** Raised for a key that is not a Core feature. */
    public class FeatureSwitchException extends Exception {
    }

    /** One feature: what it covers. */
    public class Item {
        public String key;
        public String kind;
        /** The BarnCRM Tab permission sets of a tool. */
        public List<String> tabSets = new List<String>();
        /** The Automation Registry names a feature group runs. */
        public List<String> automations = new List<String>();
        /** The Setting Definition DeveloperNames hidden while the feature is off. */
        public List<String> settingRows = new List<String>();

        Item(String key, String kind) {
            this.key = key;
            this.kind = kind;
        }

        Item tabs(List<String> names) {
            this.tabSets = names;
            return this;
        }

        Item runs(List<String> names) {
            this.automations = names;
            return this;
        }

        Item rows(List<String> names) {
            this.settingRows = names;
            return this;
        }
    }

    /** The three tools, in the order General lists them. */
    public static List<Item> tools() {
        return new List<Item>{
            new Item(DATA_MANAGER, KIND_TOOL)
                .tabs(
                    new List<String>{
                        TabAccessService.DATA_MANAGER_TAB,
                        TabAccessService.IMPORT_TAB,
                        TabAccessService.FIND_TAB,
                        TabAccessService.BULK_UPDATE_TAB
                    }
                )
                .rows(
                    new List<String>{
                        'Import_Wizard',
                        'Import_Chunk_Size',
                        'Import_Trial_Rows',
                        'Import_Row_Retention_Days',
                        'Import_Undo_Retention_Days',
                        'Bulk_Chunk_Size',
                        'Bulk_Update_Run_Limit',
                        'Bulk_Delete_Run_Limit',
                        'Find_Export_Row_Limit'
                    }
                ),
            new Item(DUPLICATE_REVIEW, KIND_TOOL).rows(new List<String>{ 'Duplicate_Review' }),
            new Item(ORG_OPTIMIZER, KIND_TOOL)
                .tabs(new List<String>{ TabAccessService.DATA_HYGIENE_TAB })
                .rows(
                    new List<String>{
                        'Health_Check',
                        'Stale_Record_Years',
                        'Unused_Login_Days',
                        'Unused_Report_Days'
                    }
                )
        };
    }

    /** The five Core feature groups, in the order General lists them. */
    public static List<Item> featureGroups() {
        return new List<Item>{
            new Item(HOUSEHOLD_UPKEEP, KIND_FEATURE)
                .runs(
                    new List<String>{
                        'AccountTriggerHandler',
                        'ContactTriggerHandler',
                        'HouseholdMemberTriggerHandler'
                    }
                )
                .rows(
                    new List<String>{
                        'Auto_Create_Households',
                        'Delete_Empty_Households',
                        'Include_Deceased_In_Name',
                        'Keep_Households_Of_Deleted_People',
                        'Household_Naming_Preview',
                        'Household_Name_Pattern',
                        'Formal_Greeting_Pattern',
                        'Informal_Greeting_Pattern'
                    }
                ),
            new Item(ADDRESSES, KIND_FEATURE)
                .runs(
                    new List<String>{
                        'Account_Address_Capture',
                        'Address_Default_Propagation',
                        'Contact_Address_Capture'
                    }
                )
                .rows(
                    new List<String>{ 'Contact_Address_Change_Behavior', 'Seasonal_Address_Job' }
                ),
            new Item(RELATIONSHIPS, KIND_FEATURE)
                .runs(new List<String>{ 'Relationship_Reciprocal' })
                .rows(new List<String>{ 'Relationship_Auto_Reciprocal' }),
            new Item(AFFILIATIONS, KIND_FEATURE).runs(new List<String>{ 'Affiliation_Primary' }),
            new Item(PREFERRED_EMAIL, KIND_FEATURE)
                .runs(
                    new List<String>{
                        'Preferred_Email_Contact',
                        'Preferred_Email_Person_Account',
                        'Preferred_Phone_Contact'
                    }
                )
        };
    }

    /** Every feature: the tools, then the groups. */
    public static List<Item> all() {
        List<Item> features = tools();
        features.addAll(featureGroups());
        return features;
    }

    /** The feature with this key, or null when there is none. */
    public static Item item(String key) {
        for (Item candidate : all()) {
            if (candidate.key.equalsIgnoreCase(key)) {
                return candidate;
            }
        }
        return null;
    }

    /** The keys of the features that are on, lower case. */
    public static Set<String> featuresOn() {
        Set<String> keys = new Set<String>();
        String stored = SettingsService.getSettings().Features_Turned_On__c;
        if (String.isBlank(stored)) {
            for (Item feature : all()) {
                keys.add(feature.key.toLowerCase());
            }
            return keys;
        }
        for (String part : stored.split(',')) {
            String key = part.trim();
            if (String.isNotBlank(key) && key != NONE_ON && key != NONE_CHOSEN) {
                keys.add(key.toLowerCase());
            }
        }
        return keys;
    }

    /**
     * Whether first-run setup is still to be finished as far as features go: the list holds
     * `None`, which only a new install stores. Blank (an upgraded org) and `NoneChosen` (setup
     * finished with nothing ticked) are both done.
     */
    public static Boolean awaitingFirstRun() {
        String stored = SettingsService.getSettings().Features_Turned_On__c;
        return stored != null && stored.trim() == NONE_ON;
    }

    /**
     * First-run setup's save: turns the ticked features on and always leaves the list saying
     * setup is done, as `NoneChosen` when nothing was ticked, so the window cannot loop.
     */
    public static void finishFirstRun(Set<String> keys) {
        if (keys != null && !keys.isEmpty()) {
            turnOn(keys);
        }
        if (awaitingFirstRun()) {
            SettingsService.saveSystemValue(ON_KEY, NONE_CHOSEN);
        }
    }

    /** Whether the feature is on. */
    public static Boolean isOn(String key) {
        return String.isNotBlank(key) && featuresOn().contains(key.toLowerCase());
    }

    /** Turns one feature on, for good. Callers check Manage BarnCRM Settings first. */
    public static void turnOn(String key) {
        turnOn(new Set<String>{ key });
    }

    /**
     * Turns features on, for good: lists them, switches on their automations and queues their
     * tabs. One already on changes nothing. Used by General and by first-run setup.
     */
    public static void turnOn(Set<String> keys) {
        Set<String> current = featuresOn();
        List<Item> newlyOn = new List<Item>();
        Set<String> newKeys = new Set<String>();
        for (String key : keys) {
            Item feature = item(key);
            if (feature == null) {
                throw new FeatureSwitchException(System.Label.Core_Feature_UnknownKeyError);
            }
            String lower = feature.key.toLowerCase();
            if (!current.contains(lower) && !newKeys.contains(lower)) {
                newlyOn.add(feature);
                newKeys.add(lower);
            }
        }
        if (newlyOn.isEmpty()) {
            return;
        }
        List<String> stored = new List<String>();
        Boolean tabsChange = false;
        for (Item feature : all()) {
            String lower = feature.key.toLowerCase();
            if (current.contains(lower) || newKeys.contains(lower)) {
                stored.add(feature.key);
            }
        }
        SettingsService.saveSystemValue(ON_KEY, String.join(stored, ','));
        AutomationControl.clearCache();
        Boolean defaultsEnsured = false;
        for (Item feature : newlyOn) {
            tabsChange = tabsChange || !feature.tabSets.isEmpty();
            if (feature.automations.isEmpty()) {
                continue;
            }
            if (!defaultsEnsured) {
                AutomationControl.ensureDefaults();
                defaultsEnsured = true;
            }
            for (String automation : feature.automations) {
                AutomationControl.setEnabled(automation, true);
            }
        }
        if (tabsChange) {
            TabAccessService.requestSync();
        }
        // People added while household upkeep was off have no household: one batch gives them
        // one, as the trigger would have (it never throws).
        if (newKeys.contains(HOUSEHOLD_UPKEEP.toLowerCase())) {
            HouseholdCatchUpBatch.enqueue();
        }
    }

    /**
     * Marks a new install: no feature on until first-run setup. An org that already has a
     * value (an upgrade, or a reinstall that kept its settings) is left as it is.
     */
    public static void markNewInstall() {
        if (String.isBlank(SettingsService.getSettings().Features_Turned_On__c)) {
            SettingsService.saveBookkeeping(new Map<String, Object>{ ON_KEY => NONE_ON });
        }
    }

    /** The BarnCRM Tab permission sets whose tool is on. */
    public static Set<String> tabSetsOn() {
        Set<String> names = new Set<String>();
        Set<String> turnedOn = featuresOn();
        for (Item tool : tools()) {
            if (turnedOn.contains(tool.key.toLowerCase())) {
                names.addAll(tool.tabSets);
            }
        }
        return names;
    }

    /** The automations, lower case, of the feature groups that are off. */
    public static Set<String> automationsOff() {
        Set<String> names = new Set<String>();
        Set<String> turnedOn = featuresOn();
        for (Item feature : featureGroups()) {
            if (!turnedOn.contains(feature.key.toLowerCase())) {
                for (String automation : feature.automations) {
                    names.add(automation.toLowerCase());
                }
            }
        }
        return names;
    }

    /** The Setting Definition DeveloperNames hidden because their feature is off. */
    public static Set<String> hiddenSettingRows() {
        Set<String> hidden = new Set<String>();
        Set<String> turnedOn = featuresOn();
        for (Item feature : all()) {
            if (!turnedOn.contains(feature.key.toLowerCase())) {
                hidden.addAll(feature.settingRows);
            }
        }
        return hidden;
    }
}
