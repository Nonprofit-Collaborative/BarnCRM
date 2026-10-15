/**
 * The healthCheckPanel component's entry point (feature C-11).
 *
 * Reading the report needs no permission: anyone who can open the BarnCRM app can look at
 * it and tell an administrator what it says. Acting on a finding needs the
 * Manage_BarnCRM_Settings custom permission, checked here rather than trusted from the
 * component.
 *
 * `applyFix` is also called by a module's tests, which press a fix the module owns the way the
 * panel does (ADR-NEXT `NEXT-rollup-builder-module.md`).
 */
@NamespaceAccessible
public with sharing class HealthCheckController {
    /**
     * The whole report: findings, org shape, current and recommended mode.
     */
    @AuraEnabled
    public static HealthCheckService.Report getReport() {
        try {
            return HealthCheckService.buildReport();
        } catch (Exception e) {
            ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
            throw new AuraHandledException(System.Label.Core_HealthCheck_LoadFailed);
        }
    }

    /**
     * When Health Check last ran in full and how many findings it had, without running it
     * (ADMIN-7). The panel shows this first where its lastResultFirst property is set.
     */
    @AuraEnabled
    public static HealthCheckLastRun.Summary getLastRun() {
        try {
            return HealthCheckLastRun.read();
        } catch (Exception e) {
            ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
            throw new AuraHandledException(System.Label.Core_HealthCheck_LoadFailed);
        }
    }

    /**
     * Take the recommendation: set the coexistence mode detection proposes, and return the
     * re-run report so the panel shows the result of what it just did.
     */
    @AuraEnabled
    public static HealthCheckService.Report applyRecommendedMode() {
        requireManageSettings();
        try {
            CoexistenceService.applyMode(OrgShapeDetector.recommendedCoexistenceMode());
            return HealthCheckService.buildReport();
        } catch (CoexistenceService.CoexistenceException e) {
            throw new AuraHandledException(e.getMessage());
        } catch (Exception e) {
            ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
            throw new AuraHandledException(System.Label.Core_HealthCheck_FixFailed);
        }
    }

    /**
     * Move household membership to the junction, which is what a Person Accounts org needs.
     */
    @AuraEnabled
    public static HealthCheckService.Report applyJunctionMembership() {
        requireManageSettings();
        try {
            CoexistenceService.applyJunctionMembership();
            return HealthCheckService.buildReport();
        } catch (CoexistenceService.CoexistenceException e) {
            throw new AuraHandledException(e.getMessage());
        } catch (Exception e) {
            ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
            throw new AuraHandledException(System.Label.Core_HealthCheck_FixFailed);
        }
    }

    /**
     * Turn automatic household creation on, which is what the org needs when household
     * membership is on the junction and no new person is getting a household (ADR-0037).
     */
    @AuraEnabled
    public static HealthCheckService.Report enableAutomaticHouseholds() {
        requireManageSettings();
        try {
            HouseholdService.enableAutomaticHouseholds();
            return HealthCheckService.buildReport();
        } catch (Exception e) {
            ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
            throw new AuraHandledException(System.Label.Core_HealthCheck_FixFailed);
        }
    }

    /** What a fix is recorded under in the settings change history, before its button label. */
    private static final String CHANGE_PREFIX = 'Health Check: ';

    /** Set by a test to make a fix fail after it has written, so the rollback can be seen. */
    @TestVisible
    private static Boolean failAfterFixForTest = false;

    /**
     * Run one of the fixes ADR-0048 allows, by its key, and return the re-run report with a
     * sentence saying what the fix did.
     *
     * The panel sends back the fix scope of the finding the administrator confirmed. The fix
     * runs only when what it would change now is exactly that: otherwise something changed
     * since Health Check last ran, and the fix is refused with a sentence rather than creating
     * something she has not read (ADR-0048 condition 5). Everything runs inside one savepoint,
     * so a failure leaves the org as it was, and a fix that ran is recorded in the settings
     * change history like any other change made on the console.
     *
     * @param fixKey which fix, one of the FIX_KEY constants on HealthCheckService
     * @param expectedScope the fix scope the confirmed finding carried
     */
    @AuraEnabled
    public static HealthCheckService.Report applyFix(String fixKey, List<String> expectedScope) {
        return applyFixFor(fixKey, expectedScope);
    }

    /**
     * The same fix as applyFix, for a module package's Apex. NamespaceAccessible is not paired
     * with AuraEnabled on one method, so module callers use this one.
     *
     * @param fixKey which fix, one of the FIX_KEY constants on HealthCheckService
     * @param expectedScope the fix scope the confirmed finding carried
     */
    @NamespaceAccessible
    public static HealthCheckService.Report applyFixFor(String fixKey, List<String> expectedScope) {
        requireManageSettings();
        String fixLabel = fixLabel(fixKey);
        if (fixLabel == null) {
            throw userError(System.Label.Core_HealthCheck_FixUnknown);
        }
        Savepoint beforeFix = Database.setSavepoint();
        try {
            List<String> scope = HealthCheckService.fixScope(fixKey);
            if (scope.isEmpty() || !sameScope(scope, expectedScope)) {
                throw userError(System.Label.Core_HealthCheck_FixStale);
            }
            String outcome = runFix(fixKey, scope);
            SettingsService.logChange(CHANGE_PREFIX + fixLabel, '', String.join(scope, ', '));
            if (failAfterFixForTest) {
                throw new HealthCheckFixException('A failure after the fix had written.');
            }
            HealthCheckService.Report report = HealthCheckService.buildReport();
            report.fixOutcome = outcome;
            return report;
        } catch (AuraHandledException e) {
            Database.rollback(beforeFix);
            throw e;
        } catch (Exception e) {
            Database.rollback(beforeFix);
            ErrorLogger.log(e, System.Label.Core_HealthCheck_ErrorContext);
            throw userError(System.Label.Core_HealthCheck_FixFailed);
        }
    }

    /** The button label of a fix, which also names it in the change history; null if unknown. */
    private static String fixLabel(String fixKey) {
        if (HealthCheckService.FIX_KEY_RESTORE_AUTOMATION_SWITCHES.equals(fixKey)) {
            return System.Label.Core_HealthCheck_SwitchesMissingFix;
        }
        if (HealthCheckService.FIX_KEY_RESTORE_IMPORT_TEMPLATES.equals(fixKey)) {
            return System.Label.Core_HealthCheck_TemplatesMissingFix;
        }
        if (HealthCheckService.FIX_KEY_SCHEDULE_NIGHTLY_JOBS.equals(fixKey)) {
            return System.Label.Core_HealthCheck_NightlyJobsFix;
        }
        if (HealthCheckService.FIX_KEY_RESCHEDULE_INACTIVE_OWNER_JOBS.equals(fixKey)) {
            return System.Label.Core_HealthCheck_InactiveOwnerJobsFix;
        }
        HealthCheckFixExtension owner = HealthCheckService.fixOwner(fixKey);
        return owner == null ? null : owner.fixLabel(fixKey);
    }

    /** Runs the fix and returns the sentence that says what it did. */
    private static String runFix(String fixKey, List<String> scope) {
        HealthCheckFixExtension owner = HealthCheckService.fixOwner(fixKey);
        if (owner != null) {
            return owner.runFix(fixKey, scope);
        }
        if (HealthCheckService.FIX_KEY_RESCHEDULE_INACTIVE_OWNER_JOBS.equals(fixKey)) {
            List<String> stoppedOnly = NightlyJobs.rescheduleAsRunningUser(scope);
            List<String> again = new List<String>();
            for (String name : scope) {
                if (!stoppedOnly.contains(name)) {
                    again.add(name);
                }
            }
            String outcome = again.isEmpty()
                ? ''
                : String.format(
                      System.Label.Core_HealthCheck_FixScheduled,
                      new List<Object>{ String.join(again, ', ') }
                  );
            if (!stoppedOnly.isEmpty()) {
                outcome +=
                    (outcome == '' ? '' : ' ') +
                    String.format(
                        System.Label.Core_HealthCheck_FixStoppedOnly,
                        new List<Object>{ String.join(stoppedOnly, ', ') }
                    );
            }
            return outcome;
        }
        if (HealthCheckService.FIX_KEY_SCHEDULE_NIGHTLY_JOBS.equals(fixKey)) {
            return String.format(
                System.Label.Core_HealthCheck_FixScheduled,
                new List<Object>{ String.join(NightlyJobs.scheduleAll(), ', ') }
            );
        }
        String outcome = String.format(
            System.Label.Core_HealthCheck_FixCreated,
            new List<Object>{ String.join(scope, ', ') }
        );
        if (HealthCheckService.FIX_KEY_RESTORE_AUTOMATION_SWITCHES.equals(fixKey)) {
            AutomationControl.ensureDefaults();
        } else {
            ImportTemplateService.materializeDefaults();
        }
        return outcome;
    }

    /** Whether two scopes name the same things, in any order. */
    private static Boolean sameScope(List<String> current, List<String> expected) {
        if (expected == null || expected.size() != current.size()) {
            return false;
        }
        List<String> left = current.clone();
        List<String> right = expected.clone();
        left.sort();
        right.sort();
        return left.equals(right);
    }

    /** An error the panel shows as it is; the message is set so a test can read it too. */
    private static AuraHandledException userError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }

    private class HealthCheckFixException extends Exception {
    }

    private static void requireManageSettings() {
        if (!HealthCheckService.canManageSettings()) {
            throw new AuraHandledException(System.Label.Core_HealthCheck_PermissionRequired);
        }
    }
}
