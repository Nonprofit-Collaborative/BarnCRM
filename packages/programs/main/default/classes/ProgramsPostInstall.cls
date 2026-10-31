/**
 * What the BarnCRM Programs module does at install and at every upgrade (ADR-0151
 * `0151-programs-module.md`).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Create the switch rows of the Automation page for the module's own automations (C-21).
 * 2. Queue the job that gives the installer the Programs Admin permission set. Queued because a
 *    permission set assignment is a setup object write, and this transaction has already written
 *    ordinary records (mixed DML).
 * 3. Give the Programs sets to BarnCRM's roles (`ProgramsAccessSync`), queued for the same
 *    reason. The installer's job runs it after its own grant, so the two never insert the
 *    installer's Programs Admin at the same moment; with no installer it is queued alone.
 *
 * The steps are `runSetup`, which also adds the module to Core's setup marker and is what
 * Finish Setup runs for a module copied into an org by hand (FS1, `ModuleSetups`).
 */
@NamespaceAccessible
public with sharing class ProgramsPostInstall implements InstallHandler, ModuleSetup {
    /** The module's key in the module catalog and the setup marker. */
    private static final String MODULE_KEY = 'Programs';
    private static final String SWITCH_CONTEXT = 'ProgramsPostInstall.ensureAutomationSwitches';
    @TestVisible
    private static final String ACCESS_CONTEXT = 'ProgramsPostInstall.grantInstallerAccess';

    /**
     * Called by the platform after the module is installed or upgraded.
     *
     * @param context what the platform knows about this install
     */
    public void onInstall(InstallContext context) {
        if (context == null) {
            return;
        }
        runSetup(context.installerId());
    }

    /** Built by name from Core (`ModuleSetups`) for Finish Setup, so it needs a public constructor. */
    @NamespaceAccessible
    public ProgramsPostInstall() {
        // Nothing to set up: every step runs in runSetup.
    }

    /**
     * The install's steps (see the class comment), with the given person standing in for the
     * installer, then the module's key added to the setup marker. Never throws.
     *
     * @param installerId the person to give Programs Admin, or null for nobody
     */
    public void runSetup(Id installerId) {
        // Each entry point records its own failures and returns, so nothing here throws.
        AutomationControl.ensureDefaultsDuringInstall(SWITCH_CONTEXT);
        ModuleSetups.markRan(MODULE_KEY);
        if (installerId == null) {
            new ProgramsAccessSync().requestSync();
            return;
        }
        try {
            System.enqueueJob(new InstallerAccess(installerId));
        } catch (Exception e) {
            ErrorLogger.log(e, ACCESS_CONTEXT);
            new ProgramsAccessSync().requestSync();
        }
    }

    /**
     * Gives the installer the Programs Admin permission set, unless they hold it already, then
     * BarnCRM's roles their sets (`ProgramsAccessSync`), which then skips the installer. System
     * mode: the install runs as the platform's package user, who holds no BarnCRM set.
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
                if (ProgramsAccessSync.syncOnce() && !Test.isRunningTest()) {
                    System.enqueueJob(new ProgramsAccessSync.Job());
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
                    WHERE Name = :ProgramsAccessSync.ADMIN_SET AND IsOwnedByProfile = FALSE
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
