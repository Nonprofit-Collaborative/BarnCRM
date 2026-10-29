/**
 * The Module Manager (C-24, plan Section 4.8): which modules this org is offered, whether each is
 * installed and on, turning an installed module's automation off and on, and what uninstalling
 * one would delete.
 *
 * Nothing here installs or removes a package: Salesforce does not let an app do that, and the
 * owner ruled it out (0072-suite-choice-is-the-first-setup-step.md). A module is turned off by
 * listing it in `Modules_Turned_Off__c`, which `AutomationControl.isEnabled` reads, so each of its
 * automation switches keeps its own value
 * (0073-module-manager-turns-automation-off-and-never-installs.md).
 *
 * Callers check `Manage_BarnCRM_Settings` before any method that changes something or counts
 * records (`ModuleManagerController`).
 */
@NamespaceAccessible
public with sharing class ModuleManagerService {
    public static final String STATUS_NOT_INSTALLED = 'NotInstalled';
    @NamespaceAccessible
    public static final String STATUS_OFF = 'Off';
    @NamespaceAccessible
    public static final String STATUS_ON = 'On';

    private static final String CORE = 'Core';
    private static final String TURNED_OFF_KEY = 'Modules_Turned_Off__c';
    private static final Integer TURNED_OFF_LENGTH = 255;
    private static final String HIDE_NONPROFIT_KEY = 'Hide_Nonprofit_Modules__c';

    /** A count stops here, so no object is ever too big to count inside the query limits. */
    @TestVisible
    private static Integer countCap = 50000;

    /**
     * Every counted row counts toward the transaction's query row limit, shared by all the
     * objects counted, so each count gets a share of what is left (ADMIN-2). Tests lower it.
     */
    @TestVisible
    private static Integer rowLimit = Limits.getLimitQueryRows();

    /** Rows kept back for the rest of the transaction. */
    @TestVisible
    private static Integer rowMargin = 500;

    /**
     * detection-only: the objects each module owns, which its uninstall deletes. Names only,
     * resolved by describe, never referenced statically (ADR-0009).
     * `scripts/ci/check-module-objects.py` fails when a list and the module's objects disagree.
     */
    @TestVisible
    private static Map<String, List<String>> ownedObjects = new Map<String, List<String>>{
        'Giving' => new List<String>{
            'Acknowledgment__c',
            'Acknowledgment_Rule__c',
            'Acknowledgment_Run__c',
            'Appeal__c',
            'Commitment__c',
            'Donor_Level__c',
            'Fund__c',
            'Gift__c',
            'Gift_Allocation__c',
            'Gift_Batch__c',
            'Gift_Batch_Row__c',
            'Installment__c',
            'Receipt__c',
            'Receipt_Number_Sequence__c',
            'Receipt_Run__c',
            'Receipt_Template__c',
            'Soft_Credit__c',
            'Stewardship_Plan__c',
            'Stewardship_Plan_Step__c',
            'Stewardship_Plan_Template__c',
            'Tribute__c'
        },
        'Rollups' => new List<String>{ 'Rollup_Definition__c', 'Rollup_Queue__c' },
        'Mirror' => new List<String>(),
        'Volunteers' => new List<String>{
            'Job_Skill__c',
            'Shift_Schedule__c',
            'Skill__c',
            'Volunteer_Hours__c',
            'Volunteer_Job__c',
            'Volunteer_Letter_Template__c',
            'Volunteer_Requirement__c',
            'Volunteer_Shift__c',
            'Volunteer_Signup__c',
            'Volunteer_Skill__c'
        }
    };

    /** The permission set Turn on gives the person who turned the module on. */
    @TestVisible
    private static Map<String, String> adminPermissionSets = new Map<String, String>{
        'Giving' => 'Giving_Admin',
        'Rollups' => 'Rollup_Builder_Admin',
        'Volunteers' => 'Volunteers_Admin'
    };

    /** Raised for a module the org does not have, or one that cannot be switched. */
    public class ModuleManagerException extends Exception {
    }

    /**
     * One row of the Module Manager. A module's tests read its own row (ADR-0017 rule 1). The
     * fields carry `@AuraEnabled` only: the platform rejects `@NamespaceAccessible` on an
     * `@AuraEnabled` field (see HealthCheckService), so the module tests read them through the
     * `@NamespaceAccessible` getters below, on a row they get from `getModules()`.
     */
    @NamespaceAccessible
    public class ModuleStatus {
        @AuraEnabled
        public String name;
        /** The name shown, such as BarnCRM Giving. */
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Boolean canSwitch;
        @AuraEnabled
        public String docsUrl;
        @AuraEnabled
        public String installUrl;
        /** The module's own app, where its Settings tab lives, or null. */
        @AuraEnabled
        public String appUrl;
        /** The modules to install before this one, by name shown, or null (ADR-0125 D3). */
        @AuraEnabled
        public String installFirst;
        /** True when only the Nonprofit Edition offers it, so the page groups it under Nonprofit Modules. */
        @AuraEnabled
        public Boolean nonprofitOnly;
        /** True when it is here but its setup steps never ran, so the page offers Finish Setup (FS1). */
        @AuraEnabled
        public Boolean setupPending;

        @NamespaceAccessible
        public String getName() {
            return name;
        }

        @NamespaceAccessible
        public String getStatus() {
            return status;
        }

        @NamespaceAccessible
        public Boolean getCanSwitch() {
            return canSwitch;
        }
    }

    /** One line of the uninstall report: a kind of record and how many there are. */
    public class RecordCount {
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public Integer count;
        /** True when there are at least `count` records and the count stopped there. */
        @AuraEnabled
        public Boolean capped;
    }

    /** The modules this org is offered, in the order the Setup Assistant lists them. */
    @NamespaceAccessible
    public static List<ModuleStatus> getModules() {
        Set<String> off = turnedOff();
        Set<String> setupRan = ModuleSetups.ran();
        List<ModuleStatus> rows = new List<ModuleStatus>();
        for (ModuleDetectionService.ModuleInfo info : ModuleDetectionService.getModules()) {
            ModuleStatus row = new ModuleStatus();
            row.name = info.name;
            row.label = info.label;
            row.docsUrl = info.docsUrl;
            row.installUrl = info.installUrl;
            row.appUrl = info.appUrl;
            row.installFirst = info.installFirst;
            row.nonprofitOnly = info.nonprofitOnly == true;
            row.setupPending = info.present == true && ModuleSetups.isPending(info.name, setupRan);
            row.canSwitch = info.present == true && info.name != CORE;
            row.status = info.present != true
                ? STATUS_NOT_INSTALLED
                : off.contains(info.name.toLowerCase()) && row.canSwitch ? STATUS_OFF : STATUS_ON;
            rows.add(row);
        }
        return rows;
    }

    /**
     * Whether the Module Manager lists the nonprofit modules. The stored field is the opposite
     * sense, `Hide_Nonprofit_Modules__c`, so a settings row saved before the field existed, or a
     * blank value, shows them: only a deliberate tick hides.
     */
    public static Boolean showNonprofitModules() {
        return SettingsService.getSettings().Hide_Nonprofit_Modules__c != true;
    }

    /**
     * Saves the Show Nonprofit Modules checkbox, org wide, as its opposite `Hide_Nonprofit_Modules__c`
     * through the settings save path, which audits the change. It hides rows only: nothing is
     * installed, removed or turned off. The caller checks Manage BarnCRM Settings
     * (`ModuleManagerController`).
     */
    public static void setShowNonprofitModules(Boolean show) {
        SettingsService.saveSystemValue(HIDE_NONPROFIT_KEY, show == false);
    }

    /**
     * The modules listed as turned off, lower case. Read on every automation check, and by a
     * module's own entry points that must stop while it is off.
     */
    @NamespaceAccessible
    public static Set<String> turnedOff() {
        Set<String> names = new Set<String>();
        String stored = SettingsService.getSettings().Modules_Turned_Off__c;
        if (String.isBlank(stored)) {
            return names;
        }
        for (String part : stored.split(',')) {
            if (String.isNotBlank(part)) {
                names.add(part.trim().toLowerCase());
            }
        }
        return names;
    }

    /** Stops an installed module's automation. Its records and switches are left as they are. */
    @NamespaceAccessible
    public static void turnOff(String moduleName) {
        ModuleStatus row = switchable(moduleName);
        setTurnedOff(row.name, true);
    }

    /**
     * Lets an installed module's automation run again, with each switch as it was, and creates
     * any switch row that is missing, which is Core's part of a module's post-install work.
     * The rollup engine, when installed, then catches up on what it skipped while its module was
     * off (ADR-0125 decision 9), through its seam, and the module's access sync, when it has
     * one, gives its sets to people given a role meanwhile (ADR-0131
     * `0131-module-access-sync-by-role.md`); Core names no module class.
     */
    @NamespaceAccessible
    public static void turnOn(String moduleName) {
        ModuleStatus row = switchable(moduleName);
        setTurnedOff(row.name, false);
        AutomationControl.ensureDefaults();
        afterTurnedOn(row.name);
        ModuleAccessSyncs.requestFor(row.name);
    }

    /** Tells the rollup engine a module is on again; a failure is logged, never in the way. */
    private static void afterTurnedOn(String moduleName) {
        try {
            RollupEngineExtensionV2 engine = RollupEngineExtensions.findV2();
            if (engine != null) {
                engine.afterModuleTurnedOn(moduleName);
            }
        } catch (Exception failed) {
            ErrorLogger.log(failed, 'ModuleManagerService.turnOn');
        }
    }

    /**
     * Gives the current person the module's admin permission set, in a call of its own: a
     * permission set assignment cannot share a transaction with the settings write (mixed DML).
     * Written in user mode, so it takes the same Salesforce permission as the Access page.
     * Returns false when the module ships no admin set or the org does not have it.
     */
    public static Boolean grantAdminAccess(String moduleName) {
        ModuleStatus row = switchable(moduleName);
        String setName = adminPermissionSets.get(row.name);
        if (String.isBlank(setName)) {
            return false;
        }
        List<PermissionSet> sets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :setName AND IsOwnedByProfile = FALSE
            WITH USER_MODE
            LIMIT 1
        ];
        if (sets.isEmpty()) {
            return false;
        }
        Id userId = UserInfo.getUserId();
        Integer held = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetId = :sets[0].Id
            WITH USER_MODE
        ];
        if (held == 0) {
            Database.insert(
                new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = sets[0].Id),
                AccessLevel.USER_MODE
            );
        }
        return true;
    }

    /**
     * How many records of each kind the module owns, which uninstalling it would delete.
     * Counted in system mode: an administrator who cannot see a record still loses it, so a
     * user mode count would under-state the loss. Only counts are returned, never a record, and
     * the controller allows it only to someone who may manage settings.
     */
    public static List<RecordCount> uninstallReport(String moduleName) {
        ModuleStatus row = switchable(moduleName);
        List<RecordCount> lines = new List<RecordCount>();
        List<String> objects = ownedObjects.get(row.name);
        Map<String, Schema.SObjectType> describes = NamespaceUtil.globalDescribe();
        List<String> apiNames = new List<String>();
        for (String unqualified : objects == null ? new List<String>() : objects) {
            String apiName = ModuleDetectionService.resolveObject(unqualified);
            if (apiName != null) {
                apiNames.add(apiName);
                RecordCount line = new RecordCount();
                line.objectLabel = describes.get(apiName)
                    .getDescribe(SObjectDescribeOptions.DEFERRED)
                    .getLabelPlural();
                lines.add(line);
            }
        }
        // Each object gets an equal share of the rows still left, so no count can use up the
        // room the next one needs, and what a small object leaves unused passes to the rest.
        // A count that stops at its share reads "N or more".
        for (Integer i = 0; i < lines.size(); i++) {
            RecordCount line = lines[i];
            Integer room = (rowLimit - Limits.getQueryRows() - rowMargin) / (lines.size() - i);
            Integer cap = Math.max(0, Math.min(countCap, room - 1));
            // The name comes from describe, never from the caller, and is escaped as well.
            Integer found = Database.countQueryWithBinds(
                'SELECT COUNT() FROM ' + String.escapeSingleQuotes(apiNames[i]) + ' LIMIT :cap',
                new Map<String, Object>{ 'cap' => cap + 1 },
                AccessLevel.SYSTEM_MODE
            );
            line.capped = found > cap;
            line.count = Math.min(found, cap);
        }
        return lines;
    }

    /** The row for an installed module other than Core, or an exception Maria can read. */
    private static ModuleStatus switchable(String moduleName) {
        String wanted = moduleName == null ? '' : moduleName.trim();
        for (ModuleStatus row : getModules()) {
            if (row.name == wanted && row.canSwitch) {
                return row;
            }
        }
        throw new ModuleManagerException(System.Label.Core_ModuleManager_UnknownModuleError);
    }

    private static void setTurnedOff(String moduleName, Boolean off) {
        List<String> names = new List<String>();
        Boolean listed = false;
        String stored = SettingsService.getSettings().Modules_Turned_Off__c;
        for (String part : String.isBlank(stored) ? new List<String>() : stored.split(',')) {
            String name = part.trim();
            if (String.isBlank(name)) {
                continue;
            }
            if (name.equalsIgnoreCase(moduleName)) {
                listed = true;
                if (!off) {
                    continue;
                }
            }
            names.add(name);
        }
        if (off && !listed) {
            names.add(moduleName);
        }
        String joined = String.join(names, ',');
        if (joined.length() > TURNED_OFF_LENGTH) {
            throw new ModuleManagerException(System.Label.Core_ModuleManager_SaveErrorMessage);
        }
        SettingsService.saveSystemValue(TURNED_OFF_KEY, joined);
        AutomationControl.clearCache();
    }
}
