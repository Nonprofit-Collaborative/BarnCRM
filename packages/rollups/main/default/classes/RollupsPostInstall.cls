/**
 * What the BarnCRM Rollup Builder module does at install and at every upgrade (ADR-NEXT
 * `NEXT-rollup-builder-module.md`, decision 5).
 *
 * Three things, each safe to run twice and none able to abort an install, since every failure
 * is written to the Error Log instead:
 *
 * 1. Create the shipped Rollup Definitions this org does not have yet, so a fresh org has its
 *    totals without anybody pressing a button, and leave every definition already here exactly
 *    as the administrator left it (R-R6, ADR-0029). The module sees only the shipped defaults
 *    whose source and target are in the org; Giving makes the same call from its own script.
 * 2. Create the switch rows of the Automation page for the module's own automations (C-21).
 * 3. Queue the job that gives the installer the Rollup Builder Admin permission set. Queued
 *    because a permission set assignment is a setup object write, and this transaction has
 *    already written ordinary records (mixed DML).
 */
public with sharing class RollupsPostInstall implements InstallHandler {
    @TestVisible
    private static final String ROLLUP_CONTEXT = 'RollupsPostInstall.ensureRollupDefaults';
    private static final String SWITCH_CONTEXT = 'RollupsPostInstall.ensureAutomationSwitches';
    private static final String ACCESS_CONTEXT = 'RollupsPostInstall.grantInstallerAccess';

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
        RollupService.ensureDefaultsDuringInstall(ROLLUP_CONTEXT);
        AutomationControl.ensureDefaultsDuringInstall(SWITCH_CONTEXT);
        Id installerId = context.installerId();
        if (installerId == null) {
            return;
        }
        try {
            System.enqueueJob(new InstallerAccess(installerId));
        } catch (Exception e) {
            ErrorLogger.log(e, ACCESS_CONTEXT);
        }
    }

    /**
     * Gives the installer the Rollup Builder Admin permission set, unless they hold it already.
     * System mode: the install runs as the platform's package user, who holds no BarnCRM set.
     */
    public without sharing class InstallerAccess implements Queueable {
        private final Id installerId;

        public InstallerAccess(Id installerId) {
            this.installerId = installerId;
        }

        public void execute(QueueableContext jobContext) {
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
                if (held == 0) {
                    Database.insert(
                        new PermissionSetAssignment(
                            AssigneeId = installerId,
                            PermissionSetId = sets[0].Id
                        ),
                        AccessLevel.SYSTEM_MODE
                    );
                }
            } catch (Exception e) {
                ErrorLogger.log(e, ACCESS_CONTEXT);
            }
        }
    }
}
