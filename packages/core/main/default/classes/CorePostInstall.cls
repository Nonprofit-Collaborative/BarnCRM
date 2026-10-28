/**
 * What BarnCRM Core does for itself at install and at every upgrade.
 *
 * Four things. The first is to make sure the person who installed the package can open
 * BarnCRM Settings. Without it nobody in the org holds the Manage BarnCRM Settings
 * custom permission, so the console opens read only for everyone, including the System
 * Administrator who installed it, because a custom permission is not implied by Modify All
 * Data. The only way out would be Salesforce Setup, which Principle 1 does not allow.
 *
 * Both assignments are setup object writes, and the other two things below write ordinary
 * records, which the platform will not allow in one transaction (mixed DML): whichever came
 * second was refused, so the installer was left without access and with only an Error Log
 * entry to show for it. So the install queues one job for the access, which runs as soon as
 * the install has committed, and does the rest itself. The job takes two steps, because the
 * platform makes the obvious one unreliable:
 *
 * 1. Assign the BarnCRM Admin permission set. A permission set has no calculation
 *    status, so this works the moment the job runs. This is the step that matters: after
 *    it, the installer can use the app.
 * 2. Assign the BarnCRM Admin role, which is a permission set group. The platform
 *    recalculates packaged groups in the background after an install and refuses to assign
 *    one while that is running, which is the usual state in the first minutes. So this is
 *    attempted, and if the group is not ready the job waits and tries again a few times.
 *    Either way the person is already working, thanks to step 1.
 *
 * The second is to put the coexistence mode detection recommends in force, and with it, in
 * a Person Accounts org, the flexible way of belonging to a household, because the simple
 * way cannot hold a person stored as an account and households would silently never form.
 * Only an org that has never chosen a mode is touched: an upgrade of an org whose
 * administrator has chosen is a no-op here, whatever they chose.
 *
 * The shipped Rollup Definitions are not Core's: the BarnCRM Rollup Builder module creates
 * them from its own post-install script, `RollupsPostInstall` (ADR-0029, ADR-0125
 * `0125-rollup-builder-module.md`).
 *
 * The third is to create the switch rows of the Automation page, one per automation the
 * shipped registry names, so the page lists every automation from the first install rather
 * than staying empty until somebody finds the Health Check fix (C-21). Core sees only its own
 * registry rows at this point, and each module that ships automations calls the same method
 * from its own script.
 *
 * The fourth is to add the import templates the packages ship (D-41), so the wizard and the
 * migration guides find them from the first install, and a template shipped in a later
 * version reaches an org that already has others. Core adds its own here; each module that
 * ships templates calls the same method from its own script.
 *
 * Alongside these (ADR-0124): a new install starts with every feature off, an upgrade with no
 * edition saved gets the recommended one, and every run schedules the nightly tab access check
 * unless it is already scheduled. When Seasonal Addresses is on and its nightly job is missing,
 * the job is scheduled too; an upgraded org that already runs the job has the switch turned on.
 *
 * An org built by deploying the source runs no install handler, so `runAsSourceDeploy` runs the
 * same steps there, called by `scripts/org/deploy-packages.sh` once Core is in. Finish Setup
 * runs them through `runSetup` for source copied in by hand (FS1), and every run ends by adding
 * Core to the setup marker (`ModuleSetups.markRan`).
 *
 * The whole thing runs twice safely: a person who already holds a permission set or a role
 * is left alone, and a switch or an import template that already exists is left exactly as the
 * administrator left it, so an upgrade is a no-op for an org that is already set up. Nothing here throws: an
 * install must never fail because of a bootstrap step, so every failure is written to the
 * Error Log instead.
 */
public with sharing class CorePostInstall implements InstallHandler, ModuleSetup {
    private static final String ACCESS_CONTEXT = 'CorePostInstall.grantInstallerAccess';
    private static final String MODE_CONTEXT = 'CorePostInstall.applyRecommendedMode';
    private static final String SWITCH_CONTEXT = 'CorePostInstall.ensureAutomationSwitches';
    private static final String TEMPLATE_CONTEXT = 'CorePostInstall.ensureImportTemplates';
    private static final String FEATURE_CONTEXT = 'CorePostInstall.markFeaturesOff';
    private static final String EDITION_CONTEXT = 'CorePostInstall.saveEditionOnAnUpgrade';
    private static final String TAB_CHECK_CONTEXT = 'CorePostInstall.scheduleTabAccessCheck';
    private static final String SEASONAL_CONTEXT = 'CorePostInstall.alignSeasonalAddresses';
    private static final String ORGANIZATION_CONTEXT = 'CorePostInstall.storeOrganizationRecordType';

    /** Test seam: true lets a test see the nightly tab access check scheduled. */
    @TestVisible
    private static Boolean scheduleTabCheckInTests = false;

    /**
     * Test seam: true lets a test see an existing seasonal swap schedule adopted on an upgrade.
     * Off in tests otherwise, because what the org the tests run in has scheduled is not the
     * test's to depend on.
     */
    @TestVisible
    private static Boolean adoptSeasonalScheduleInTests = false;

    /**
     * What every Error Log entry written by an install or upgrade starts with, including the
     * retry job's. The Hub home page counts them to say how the install went.
     */
    private static final String CONTEXT_PREFIX = 'CorePostInstall';

    /**
     * Called by the platform after the package is installed or upgraded.
     *
     * @param context what the platform knows about this install
     */
    public void onInstall(InstallContext context) {
        if (context == null) {
            return;
        }
        Boolean isUpgrade = context.previousVersion() != null;
        run(!isUpgrade, isUpgrade, context.installerId());
    }

    /**
     * The same steps for an org built by deploying the source rather than installing a package,
     * which runs no install handler: `scripts/org/deploy-packages.sh` calls this once Core is
     * deployed, and a developer can run it as anonymous Apex. The person running it stands in
     * for the installer.
     *
     * Safe on an org that already has BarnCRM: one that has saved its settings or holds a
     * household is treated as an upgrade, so its feature list, a saved edition, its coexistence
     * mode, switches and templates stay exactly as the administrator left them. Only an org with
     * neither is marked as a new install, so first-run setup comes up there as it does after a
     * package install. Running it again changes nothing. Never throws.
     */
    public static void runAsSourceDeploy() {
        new CorePostInstall().runSetup(UserInfo.getUserId());
    }

    /**
     * The same steps as `runAsSourceDeploy`, with the given person standing in for the
     * installer: what Finish Setup runs (FS1, `ModuleSetups`). Never throws.
     *
     * @param installerId the person to give BarnCRM Admin, or null for nobody
     */
    public void runSetup(Id installerId) {
        Boolean alreadySetUp = true;
        try {
            alreadySetUp = hasBeenSetUp();
        } catch (Exception e) {
            // Unsure means existing: marking a working org as new would turn its features off.
            ErrorLogger.log(e, FEATURE_CONTEXT);
        }
        run(!alreadySetUp, alreadySetUp, installerId);
    }

    /**
     * Whether the org already uses BarnCRM: its settings have been saved, or a household exists.
     * Either makes a source deploy an upgrade rather than a new install.
     */
    @TestVisible
    private static Boolean hasBeenSetUp() {
        if (BarnCRM_Settings__c.getOrgDefaults().Id != null) {
            return true;
        }
        Id householdType = HouseholdService.householdRecordTypeId();
        if (householdType == null) {
            return false;
        }
        Integer households = [
            SELECT COUNT()
            FROM Account
            WHERE RecordTypeId = :householdType
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return households > 0;
    }

    private void run(Boolean isNewInstall, Boolean isUpgrade, Id installerId) {
        markFeaturesOffOnANewInstall(isNewInstall);
        saveEditionOnAnUpgrade(isUpgrade);
        applyRecommendedMode();
        storeOrganizationRecordType();
        AutomationControl.ensureDefaultsDuringInstall(SWITCH_CONTEXT);
        ImportTemplateService.materializeDefaultsDuringInstall(TEMPLATE_CONTEXT);
        // Every install and upgrade gives the BarnCRM Tab sets of the features that are on to
        // whoever had those tabs before (ADR-0124); queued, since it writes setup objects. It
        // never throws.
        TabAccessService.requestSync();
        scheduleTabAccessCheck();
        alignSeasonalAddresses(isUpgrade);
        ModuleSetups.markRan(ModuleSetups.CORE);
        if (installerId == null) {
            return;
        }
        grantInstallerAccess(installerId);
    }

    /**
     * A new install starts with every Core feature off until first-run setup (ADR-0124). An
     * upgrade leaves the list empty, which means every feature is on, so an existing org loses
     * nothing it used.
     */
    private void markFeaturesOffOnANewInstall(Boolean isNewInstall) {
        try {
            if (isNewInstall) {
                FeatureSwitchService.markNewInstall();
            }
        } catch (Exception e) {
            ErrorLogger.log(e, FEATURE_CONTEXT);
        }
    }

    /**
     * An upgraded org with no edition saved gets the one the Setup Assistant recommends, or the
     * Standard Edition when nothing points to the Nonprofit one (what BarnCRM already shows with
     * no edition). Its features are all on, so without this the first-run window would stand in
     * front of an org that is already working (ADR-0124).
     */
    private void saveEditionOnAnUpgrade(Boolean isUpgrade) {
        try {
            if (isUpgrade && String.isBlank(SettingsService.getSettings().Suite__c)) {
                String suite = SetupAssistantService.recommendedSuite();
                SettingsService.saveSystemValue(
                    'Suite__c',
                    suite == null ? ModuleDetectionService.SUITE_COMMUNITY : suite
                );
            }
        } catch (Exception e) {
            ErrorLogger.log(e, EDITION_CONTEXT);
        }
    }

    /**
     * Schedules the nightly tab access check, the safety net for roles given outside BarnCRM's
     * Access page (ADR-0124). `start` finds a job already scheduled by name, so a reinstall or an
     * upgrade never doubles it. Skipped in tests unless a test asks, so that a test of something
     * else does not leave a scheduled job that runs at `Test.stopTest`.
     */
    private void scheduleTabAccessCheck() {
        if (Test.isRunningTest() && !scheduleTabCheckInTests) {
            return;
        }
        try {
            TabAccessScheduler.start();
        } catch (Exception e) {
            ErrorLogger.log(e, TAB_CHECK_CONTEXT);
        }
    }

    /**
     * Makes the seasonal swap schedule match the Seasonal Addresses switch. An upgrade first
     * turns the switch on for an org that already runs the job, then the job is scheduled when
     * the switch is on and it is missing. A new install has the switch off, so nothing is
     * scheduled for it. Never throws.
     */
    private void alignSeasonalAddresses(Boolean isUpgrade) {
        try {
            if (isUpgrade && (!Test.isRunningTest() || adoptSeasonalScheduleInTests)) {
                SeasonalAddressScheduler.adoptExistingSchedule();
            }
            SeasonalAddressScheduler.scheduleIfEnabled();
        } catch (Exception e) {
            ErrorLogger.log(e, SEASONAL_CONTEXT);
        }
    }

    /**
     * Puts the recommended coexistence mode in force on an org that has never chosen one, and
     * leaves an org that has exactly as its administrator left it. Like every step here it
     * never throws: an org left in the shipped default is what Health Check exists to report,
     * and an install the platform rolled back is not.
     */
    private void applyRecommendedMode() {
        try {
            CoexistenceService.applyRecommendedIfUnset();
        } catch (Exception e) {
            ErrorLogger.log(e, MODE_CONTEXT);
        }
    }

    /**
     * Stores the record type for organizations when none is stored, so the setting is never
     * blank (ADR-NEXT, R-O5). Detection picks one the org already has, or No record type; no
     * record type is created, activated or made visible, and a stored one is never replaced.
     * Never throws.
     */
    private void storeOrganizationRecordType() {
        try {
            AccountKinds.storeDetectedIfBlank();
        } catch (Exception e) {
            ErrorLogger.log(e, ORGANIZATION_CONTEXT);
        }
    }

    /**
     * How many problems the install and its upgrades have logged that nobody has looked at,
     * so that the Hub home page can say whether setup completed rather than looking the same
     * after a good install and a partly failed one. Null for a person who cannot read the
     * Error Log: what they cannot see is not evidence either way.
     *
     * A read shown to somebody, so it runs in user mode (ADR-0021). It sits on this class
     * rather than on the Hub's own controller because the contexts it counts are declared
     * here, and a count that drifted from them would be confidently wrong.
     *
     * The count stops at `cap + 1`, like every Error Log count on the home page (ADMIN-8); the
     * home model reads it, so the page makes one server call rather than two.
     */
    public static Integer countInstallProblemsUpTo(Integer cap) {
        if (!ErrorLogCountSelector.isReadable()) {
            return null;
        }
        String pattern = CONTEXT_PREFIX + '%';
        String statusNew = ErrorLogger.STATUS_NEW;
        Integer readUpTo = cap + 1;
        return [
            SELECT COUNT()
            FROM Error_Log__c
            WHERE Context__c LIKE :pattern AND Status__c = :statusNew
            WITH USER_MODE
            LIMIT :readUpTo
        ];
    }

    /**
     * Queues the job that gives the installer the BarnCRM Admin permission set and then the
     * BarnCRM Admin role. Queued rather than done here because both are setup object writes
     * and this transaction has already written ordinary records (see the class comment).
     *
     * @param installerId the person who installed or upgraded the package
     */
    private void grantInstallerAccess(Id installerId) {
        try {
            System.enqueueJob(new CorePostInstallRetryQueueable(installerId));
        } catch (Exception e) {
            ErrorLogger.log(e, ACCESS_CONTEXT);
        }
    }
}
