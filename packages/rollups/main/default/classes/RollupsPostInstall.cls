/**
 * What the BarnCRM Rollup Builder module does at install and at every upgrade (ADR-NEXT
 * `NEXT-rollup-builder-module.md`, decision 5).
 *
 * Five things, each safe to run twice and none able to abort an install, since every failure
 * is written to the Error Log instead:
 *
 * 1. Carry over the two rollup settings an org saved on Core's settings object before the
 *    module had its own (decision 6), while the module has saved none.
 * 2. Create the shipped Rollup Definitions this org does not have yet, so a fresh org has its
 *    totals without anybody pressing a button, and leave every definition already here exactly
 *    as the administrator left it (R-R6, ADR-0029). The module sees only the shipped defaults
 *    whose source and target are in the org; Giving makes the same call from its own script.
 * 3. Create the switch rows of the Automation page for the module's own automations (C-21).
 * 4. Queue the job that gives the installer the Rollup Builder Admin permission set. Queued
 *    because a permission set assignment is a setup object write, and this transaction has
 *    already written ordinary records (mixed DML).
 * 5. Give the Rollup Builder sets to BarnCRM's roles (`RollupAccessSync`, D2), queued for the
 *    same reason. The installer's job runs it after its own grant, so the two never insert the
 *    installer's Rollup Builder Admin at the same moment; with no installer it is queued alone.
 */
public with sharing class RollupsPostInstall implements InstallHandler {
    @TestVisible
    private static final String ROLLUP_CONTEXT = 'RollupsPostInstall.ensureRollupDefaults';
    private static final String SWITCH_CONTEXT = 'RollupsPostInstall.ensureAutomationSwitches';
    private static final String ACCESS_CONTEXT = 'RollupsPostInstall.grantInstallerAccess';
    @TestVisible
    private static final String CARRY_CONTEXT = 'RollupsPostInstall.carryOverCoreSettings';

    /** Core's settings object, where the two rollup settings lived before the module. */
    private static final String CORE_SETTINGS_OBJECT = 'BarnCRM_Settings__c';

    /** The settings carried over, under the same field name on both objects. */
    private static final List<String> CARRIED_KEYS = new List<String>{
        RollupService.MODE_DEFAULT_SETTING,
        RollupService.PROCESSING_SETTING
    };

    /**
     * Stands in for the old Core fields in a test, keyed like CARRIED_KEYS, since Core no longer
     * defines them and a test org cannot have them.
     */
    @TestVisible
    private static Map<String, Object> oldCoreValuesForTest;

    /** The permission set the installer is given. */
    public static final String ADMIN_PERMISSION_SET = 'Rollup_Builder_Admin';

    /**
     * Called by the platform after the module is installed or upgraded.
     *
     * @param context what the platform knows about this install
     */
    public void onInstall(InstallContext context) {
        if (context == null) {
            return;
        }
        // The entry points record their own failures and return, so nothing here throws.
        carryOverCoreSettings();
        RollupService.ensureDefaultsDuringInstall(ROLLUP_CONTEXT);
        AutomationControl.ensureDefaultsDuringInstall(SWITCH_CONTEXT);
        Id installerId = context.installerId();
        if (installerId == null) {
            RollupAccessSync.requestSync();
            return;
        }
        try {
            System.enqueueJob(new InstallerAccess(installerId));
        } catch (Exception e) {
            ErrorLogger.log(e, ACCESS_CONTEXT);
            RollupAccessSync.requestSync();
        }
    }

    /**
     * Copies the rollup settings an org saved on Core's settings object, before the module had
     * its own, to the module's settings object. Does nothing once the module's settings have
     * been saved: those win. Each old field is read by name and only when it is still in the
     * org, since Core no longer defines it. Blank values are left out, so the shipped defaults
     * apply. Also run by `scripts/org/deploy-packages.sh`, since a deployment runs no install
     * script. Never throws: a failure goes to the Error Log.
     */
    public static void carryOverCoreSettings() {
        try {
            if (Rollup_Settings__c.getOrgDefaults().Id != null) {
                return;
            }
            Map<String, Object> carried = new Map<String, Object>();
            for (String key : CARRIED_KEYS) {
                Object value = oldCoreValue(key);
                if (value != null && String.isNotBlank(String.valueOf(value))) {
                    carried.put(key, value);
                }
            }
            if (!carried.isEmpty()) {
                SettingsService.saveValues(RollupService.SETTINGS_OBJECT, carried);
            }
        } catch (Exception e) {
            ErrorLogger.log(e, CARRY_CONTEXT);
        }
    }

    /** The value an old Core field holds, or null when the field is not in this org. */
    private static Object oldCoreValue(String key) {
        if (oldCoreValuesForTest != null) {
            return oldCoreValuesForTest.get(key);
        }
        if (!SettingsService.hasKey(CORE_SETTINGS_OBJECT, key)) {
            return null;
        }
        return SettingsService.getValue(CORE_SETTINGS_OBJECT, key);
    }

    /**
     * Gives the installer the Rollup Builder Admin permission set, unless they hold it already,
     * then BarnCRM's roles their sets (`RollupAccessSync`), which then skips the installer.
     * System mode: the install runs as the platform's package user, who holds no BarnCRM set.
     */
    public without sharing class InstallerAccess implements Queueable {
        private final Id installerId;

        public InstallerAccess(Id installerId) {
            this.installerId = installerId;
        }

        public void execute(QueueableContext jobContext) {
            giveInstaller();
            try {
                // A test cannot chain one queued job from another.
                if (RollupAccessSync.syncOnce() && !Test.isRunningTest()) {
                    System.enqueueJob(new RollupAccessSync.Job());
                }
            } catch (Exception e) {
                ErrorLogger.log(e, ACCESS_CONTEXT);
            }
        }

        private void giveInstaller() {
            try {
                List<PermissionSet> sets = [
                    SELECT Id
                    FROM PermissionSet
                    WHERE Name = :ADMIN_PERMISSION_SET AND IsOwnedByProfile = FALSE
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];
                if (sets.isEmpty()) {
                    return;
                }
                Integer held = [
                    SELECT COUNT()
                    FROM PermissionSetAssignment
                    WHERE AssigneeId = :installerId AND PermissionSetId = :sets[0].Id
                    WITH SYSTEM_MODE
                ];
                if (held > 0) {
                    return;
                }
                Database.SaveResult saved = Database.insert(
                    new PermissionSetAssignment(
                        AssigneeId = installerId,
                        PermissionSetId = sets[0].Id
                    ),
                    false,
                    AccessLevel.SYSTEM_MODE
                );
                // A duplicate means another job gave it a moment before: what was wanted.
                for (Database.Error error : saved.getErrors()) {
                    if (error.getStatusCode() != StatusCode.DUPLICATE_VALUE) {
                        ErrorLogger.logMessage(
                            error.getMessage(),
                            ACCESS_CONTEXT,
                            ErrorLogger.SEVERITY_WARNING
                        );
                    }
                }
            } catch (Exception e) {
                ErrorLogger.log(e, ACCESS_CONTEXT);
            }
        }
    }
}
