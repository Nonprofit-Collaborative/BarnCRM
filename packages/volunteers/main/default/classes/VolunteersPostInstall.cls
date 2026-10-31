/**
 * What the BarnCRM Volunteers module does at install and at every upgrade (ADR-0127
 * `0127-volunteers-module.md`).
 *
 * Each step is safe to run twice and none can abort an install, since every failure is written
 * to the Error Log instead:
 *
 * 1. Create the switch rows of the Automation page for the module's own automations (C-21).
 * 2. Create the Rollup Definitions the module ships (canonical model Section 29O), as Giving does
 *    (ADR-0029): the Rollup Builder module's `RollupService` materializes every shipped
 *    `Rollup_Definition_Default__mdt` row whose objects exist, and leaves one already here as the
 *    administrator left it. Core and Rollup Builder install first, before the Volunteers objects
 *    exist, so this is the first moment the rows can be created.
 * 3. Queue the job that gives the installer the Volunteers Admin permission set. Queued because
 *    a permission set assignment is a setup object write, and this transaction has already
 *    written ordinary records (mixed DML).
 * 4. Give the Volunteers sets to BarnCRM's roles (`VolunteersAccessSync`), queued for the same
 *    reason. The installer's job runs it after its own grant, so the two never insert the
 *    installer's Volunteers Admin at the same moment; with no installer it is queued alone.
 *
 * 5. Add the module's shipped import templates (the volunteer hours template, V-06) beside the
 *    templates the org already has, through Core's `materializeDefaultsDuringInstall`, because
 *    Core installs first and cannot see a module's templates. Only the row for the org's
 *    people is added, and none unless Volunteer Hours is in the org.
 * 6. Copy the shipped letter templates the org does not have (R-VL5,
 *    `VolunteerLetterTemplates.installDefaultsDuringInstall`), never changing one it has.
 *
 * The steps are `runSetup`, which also adds the module to Core's setup marker and is what
 * Finish Setup runs for a module copied into an org by hand (FS1, `ModuleSetups`).
 */
@NamespaceAccessible
public with sharing class VolunteersPostInstall implements InstallHandler, ModuleSetup {
    /** The module's key in the module catalog and the setup marker. */
    private static final String MODULE_KEY = 'Volunteers';
    private static final String SWITCH_CONTEXT = 'VolunteersPostInstall.ensureAutomationSwitches';
    private static final String IMPORT_CONTEXT = 'VolunteersPostInstall.ensureImportTemplates';
    @TestVisible
    private static final String ROLLUP_CONTEXT = 'VolunteersPostInstall.ensureRollupDefaults';
    @TestVisible
    private static final String ACCESS_CONTEXT = 'VolunteersPostInstall.grantInstallerAccess';

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
    public VolunteersPostInstall() {
        // Nothing to set up: every step runs in runSetup.
    }

    /**
     * The install's steps (see the class comment), with the given person standing in for the
     * installer, then the module's key added to the setup marker. Never throws.
     *
     * @param installerId the person to give Volunteers Admin, or null for nobody
     */
    public void runSetup(Id installerId) {
        // Each entry point records its own failures and returns, so nothing here throws.
        AutomationControl.ensureDefaultsDuringInstall(SWITCH_CONTEXT);
        ImportTemplateService.materializeDefaultsDuringInstall(IMPORT_CONTEXT);
        // Copies only, and records its own failures: it comes before anything is queued.
        VolunteerLetterTemplates.installDefaultsDuringInstall();
        RollupService.ensureDefaultsDuringInstall(ROLLUP_CONTEXT);
        ModuleSetups.markRan(MODULE_KEY);
        if (installerId == null) {
            new VolunteersAccessSync().requestSync();
            return;
        }
        try {
            System.enqueueJob(new InstallerAccess(installerId));
        } catch (Exception e) {
            ErrorLogger.log(e, ACCESS_CONTEXT);
            new VolunteersAccessSync().requestSync();
        }
    }

    /**
     * Gives the installer the Volunteers Admin permission set, unless they hold it already, then
     * BarnCRM's roles their sets (`VolunteersAccessSync`), which then skips the installer.
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
                if (VolunteersAccessSync.syncOnce() && !Test.isRunningTest()) {
                    System.enqueueJob(new ModuleAccessSyncBase.Job(new VolunteersAccessSync()));
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
                    WHERE Name = :VolunteersAccessSync.ADMIN_SET AND IsOwnedByProfile = FALSE
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
