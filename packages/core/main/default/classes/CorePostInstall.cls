/**
 * What BarnCRM Core does for itself at install and at every upgrade.
 *
 * Four things. The first is to make sure the person who installed the package can open
 * Nonprofit Settings. Without it nobody in the org holds the Manage Nonprofit Settings
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
 * 1. Assign the Nonprofit Admin permission set. A permission set has no calculation
 *    status, so this works the moment the job runs. This is the step that matters: after
 *    it, the installer can use the app.
 * 2. Assign the Nonprofit Admin role, which is a permission set group. The platform
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
 * The third is to create the Rollup Definitions the packages ship, so that a fresh org has
 * its totals without anybody being told to press a button (R-R6, ADR-0029). Core sees only
 * the shipped defaults whose source and target entities are in the org, so on a Core-only
 * install this creates Core's own rows and none of a module's; each module that ships
 * rollups calls the same method from its own post-install script, because Core installs
 * first and cannot see a module that is not there yet.
 *
 * The fourth is to create the switch rows of the Automation page, one per automation the
 * shipped registry names, so the page lists every automation from the first install rather
 * than staying empty until somebody finds the Health Check fix (C-21). Like the rollups, Core
 * sees only its own registry rows at this point, and each module that ships automations calls
 * the same method from its own script.
 *
 * The whole thing runs twice safely: a person who already holds a permission set or a role
 * is left alone, and a rollup or a switch that already exists is left exactly as the
 * administrator left it, so an upgrade is a no-op for an org that is already set up. Nothing here throws: an
 * install must never fail because of a bootstrap step, so every failure is written to the
 * Error Log instead.
 */
public with sharing class CorePostInstall implements InstallHandler {
    private static final String ACCESS_CONTEXT = 'CorePostInstall.grantInstallerAccess';
    private static final String ROLLUP_CONTEXT = 'CorePostInstall.ensureRollupDefaults';
    private static final String MODE_CONTEXT = 'CorePostInstall.applyRecommendedMode';
    private static final String SWITCH_CONTEXT = 'CorePostInstall.ensureAutomationSwitches';

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
        applyRecommendedMode();
        ensureRollupDefaults();
        AutomationControl.ensureDefaultsDuringInstall(SWITCH_CONTEXT);
        Id installerId = context.installerId();
        if (installerId == null) {
            return;
        }
        grantInstallerAccess(installerId);
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
     * How many problems the install and its upgrades have logged that nobody has looked at,
     * so that the Hub home page can say whether setup completed rather than looking the same
     * after a good install and a partly failed one. Null for a person who cannot read the
     * Error Log: what they cannot see is not evidence either way.
     *
     * A read shown to somebody, so it runs in user mode (ADR-0021). It sits on this class
     * rather than on the Hub's own controller because the contexts it counts are declared
     * here, and a count that drifted from them would be confidently wrong.
     */
    @AuraEnabled(cacheable=true)
    public static Integer countInstallProblems() {
        if (!ErrorLogCountSelector.isReadable()) {
            return null;
        }
        String pattern = CONTEXT_PREFIX + '%';
        String statusNew = ErrorLogger.STATUS_NEW;
        return [
            SELECT COUNT()
            FROM Error_Log__c
            WHERE Context__c LIKE :pattern AND Status__c = :statusNew
            WITH USER_MODE
        ];
    }

    /**
     * Creates the shipped Rollup Definitions this org does not have yet, and leaves every
     * definition that is already here exactly as the administrator left it (R-R6).
     *
     * This runs on every install and every upgrade of Core. It is deliberately not tied to the
     * installing person: the definitions belong to the org, not to whoever pressed Install.
     */
    private void ensureRollupDefaults() {
        // The catch is inside RollupService, so that every module's post-install script gets the
        // same guarantee from one place: an org with blank totals is two clicks from being right,
        // and an install the platform rolled back is not.
        RollupService.ensureDefaultsDuringInstall(ROLLUP_CONTEXT);
    }

    /**
     * Queues the job that gives the installer the Nonprofit Admin permission set and then the
     * Nonprofit Admin role. Queued rather than done here because both are setup object writes
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
