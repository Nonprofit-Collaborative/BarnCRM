/**
 * The Health Check questions about how Open Impact is set up and what it has been doing:
 * whether automation is paused (and whether anything will end the pause), whether the two
 * fiscal years agree, and whether anything is waiting in the Error Log
 * (plan Section 4.8, feature C-11). Since C-21 it also asks whether the package defaults
 * materialized from shipped metadata are all here, and whether the nightly rollup run is
 * scheduled when a rollup needs it; those four findings carry a fix button (ADR-0048).
 *
 * The fiscal year check reads Setup's fiscal year dynamically through FiscalYearSelector, so a
 * Platform-only org is told nothing rather than told zero (ADR-0009, ADR-0013). Whether
 * receipt generation has been failing is Giving's question, asked through its Health Check
 * extension (ADR-0059).
 *
 * Every finding is created exactly as HealthCheckService created it before ADR-0039 moved
 * it here: same keys, same severities, same categories, same labels, same fix targets.
 */
public with sharing class HealthCheckSettingsChecks {
    /** Whether automation is running or paused, said out loud either way. */
    public class AutomationCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return automationFinding();
        }
    }

    /** Whether the fiscal year in Setup and the one in Nonprofit Settings agree. */
    public class FiscalYearCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return fiscalYearFinding();
        }
    }

    /** A scheduled error digest that has stopped running. */
    public class ErrorDigestCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return errorDigestFinding();
        }
    }

    /** How many Error Log rows nobody has read yet. */
    public class ErrorLogCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return errorLogFinding();
        }
    }

    /**
     * Shipped rollups this org does not have (ADR-0006, ADR-0048). A shipped total that one of
     * the administrator's own active totals already writes is not restored, and the finding
     * says so rather than hiding it.
     */
    public class ShippedRollupsCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            HealthCheckService.Finding finding = missingDefaultsFinding(
                'shipped_rollups_missing',
                HealthCheckService.FIX_KEY_RESTORE_ROLLUPS,
                System.Label.Core_HealthCheck_RollupsMissingTitle,
                System.Label.Core_HealthCheck_RollupsMissingDetail,
                HealthCheckService.SEVERITY_WARNING
            );
            if (finding == null) {
                return null;
            }
            List<String> skipped = RollupService.skippedDefaultNames();
            if (!skipped.isEmpty()) {
                finding.detail +=
                    ' ' +
                    String.format(
                        System.Label.Core_HealthCheck_RollupsSkippedDetail,
                        new List<Object>{ String.join(skipped, ', ') }
                    );
            }
            return finding.withFix(
                System.Label.Core_HealthCheck_RollupsMissingFix,
                HealthCheckService.FIX_ACTION_PREFIX + HealthCheckService.FIX_KEY_RESTORE_ROLLUPS
            );
        }
    }

    /** Shipped automations with no switch on the Automation page. */
    public class AutomationSwitchesCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return missingDefaultsFinding(
                    'automation_switches_missing',
                    HealthCheckService.FIX_KEY_RESTORE_AUTOMATION_SWITCHES,
                    System.Label.Core_HealthCheck_SwitchesMissingTitle,
                    System.Label.Core_HealthCheck_SwitchesMissingDetail,
                    HealthCheckService.SEVERITY_INFO
                )
                ?.withFix(
                    System.Label.Core_HealthCheck_SwitchesMissingFix,
                    HealthCheckService.FIX_ACTION_PREFIX +
                    HealthCheckService.FIX_KEY_RESTORE_AUTOMATION_SWITCHES
                );
        }
    }

    /** Shipped import templates this org does not have. */
    public class ImportTemplatesCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return missingDefaultsFinding(
                    'import_templates_missing',
                    HealthCheckService.FIX_KEY_RESTORE_IMPORT_TEMPLATES,
                    System.Label.Core_HealthCheck_TemplatesMissingTitle,
                    System.Label.Core_HealthCheck_TemplatesMissingDetail,
                    HealthCheckService.SEVERITY_INFO
                )
                ?.withFix(
                    System.Label.Core_HealthCheck_TemplatesMissingFix,
                    HealthCheckService.FIX_ACTION_PREFIX +
                    HealthCheckService.FIX_KEY_RESTORE_IMPORT_TEMPLATES
                );
        }
    }

    /** Active rollups waiting on a nightly run nobody has scheduled. */
    public class NightlyRollupsCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return nightlyRollupsFinding();
        }
    }

    /**
     * One finding naming the package defaults that are missing, or null when none is. The
     * title and detail take the count as {0} and the names as {1}, so the finding says what
     * its fix will create, counted from this org, and it carries the same names as its fix
     * scope, so the fix creates exactly those (ADR-0048 condition 5).
     */
    private static HealthCheckService.Finding missingDefaultsFinding(
        String key,
        String fixKey,
        String title,
        String detail,
        String severity
    ) {
        List<String> missingNames = HealthCheckService.fixScope(fixKey);
        if (missingNames == null || missingNames.isEmpty()) {
            return null;
        }
        List<Object> values = new List<Object>{
            String.valueOf(missingNames.size()),
            String.join(missingNames, ', ')
        };
        return new HealthCheckService.Finding(
                key,
                String.format(title, values),
                String.format(detail, values),
                severity,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withScope(missingNames);
    }

    /**
     * Rollups set to recalculate in the nightly run while the run is not scheduled. A rollup
     * set to Scheduled alone is then never recalculated, which is a warning; one set to Both
     * still updates as records change and only misses the nightly correction, which is
     * information.
     */
    private static HealthCheckService.Finding nightlyRollupsFinding() {
        if (RollupScheduler.isScheduled()) {
            return null;
        }
        List<Rollup_Definition__c> waiting = RollupSelector.selectActiveForModes(
            RollupService.scheduledModes()
        );
        if (waiting.isEmpty()) {
            return null;
        }
        Integer nightlyOnly = 0;
        for (Rollup_Definition__c definition : waiting) {
            if (RollupService.MODE_SCHEDULED.equals(definition.Mode__c)) {
                nightlyOnly++;
            }
        }
        List<Object> values = new List<Object>{
            String.valueOf(waiting.size()),
            String.valueOf(nightlyOnly)
        };
        return new HealthCheckService.Finding(
                'nightly_rollups_not_scheduled',
                System.Label.Core_HealthCheck_NightlyOffTitle,
                String.format(System.Label.Core_HealthCheck_NightlyOffDetail, values),
                nightlyOnly > 0
                    ? HealthCheckService.SEVERITY_WARNING
                    : HealthCheckService.SEVERITY_INFO,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(
                System.Label.Core_HealthCheck_NightlyOffFix,
                HealthCheckService.FIX_ACTION_PREFIX +
                HealthCheckService.FIX_KEY_SCHEDULE_NIGHTLY_ROLLUPS
            )
            .withScope(
                HealthCheckService.fixScope(HealthCheckService.FIX_KEY_SCHEDULE_NIGHTLY_ROLLUPS)
            );
    }

    private static HealthCheckService.Finding automationFinding() {
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        Datetime pausedUntil = settings == null ? null : settings.Automation_Paused_Until__c;
        if (pausedUntil == null || pausedUntil <= System.now()) {
            return new HealthCheckService.Finding(
                'automation_running',
                System.Label.Core_HealthCheck_AutomationRunningTitle,
                System.Label.Core_HealthCheck_AutomationRunningDetail,
                HealthCheckService.SEVERITY_INFO,
                HealthCheckService.CATEGORY_SETTINGS
            );
        }

        // A pause nothing will end on time is a warning rather than information: it was set
        // before automatic resume existed, or somewhere other than the Automation page (R-A5).
        Boolean withoutResume = AutomationControl.isPauseWithoutResume();
        String detail = String.format(
            withoutResume
                ? System.Label.Core_HealthCheck_PausedNoResumeDetail
                : System.Label.Core_HealthCheck_AutomationPausedDetail,
            new List<Object>{ pausedUntil.format() }
        );
        return new HealthCheckService.Finding(
                withoutResume ? 'automation_paused_no_resume' : 'automation_paused',
                withoutResume
                    ? System.Label.Core_HealthCheck_PausedNoResumeTitle
                    : System.Label.Core_HealthCheck_AutomationPausedTitle,
                detail,
                withoutResume
                    ? HealthCheckService.SEVERITY_WARNING
                    : HealthCheckService.SEVERITY_INFO,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(
                System.Label.Core_HealthCheck_AutomationFix,
                HealthCheckService.SECTION_AUTOMATION
            );
    }

    /**
     * Whether the fiscal year in Setup and the one in Nonprofit Settings start in the same
     * month (ADR-0025). They have to: the rollups are computed from the setting and the
     * packaged retention reports are filtered on Setup's fiscal year date literals, so a
     * disagreement makes every year based number quietly measure a different window.
     */
    private static HealthCheckService.Finding fiscalYearFinding() {
        Integer orgMonth = FiscalYearSelector.orgFiscalYearStartMonth();
        Integer settingsMonth = FiscalYearSelector.settingsFiscalYearStartMonth();
        if (orgMonth == null || settingsMonth == null || orgMonth == settingsMonth) {
            return null;
        }

        String detail = String.format(
            System.Label.Core_HealthCheck_FiscalYearMismatchDetail,
            new List<Object>{
                FiscalYearSelector.monthName(settingsMonth),
                FiscalYearSelector.monthName(orgMonth)
            }
        );
        return new HealthCheckService.Finding(
                'fiscal_year_mismatch',
                System.Label.Core_HealthCheck_FiscalYearMismatchTitle,
                detail,
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(
                System.Label.Core_HealthCheck_FiscalYearFix,
                HealthCheckService.SECTION_GENERAL
            );
    }

    private static HealthCheckService.Finding errorLogFinding() {
        Integer newErrors = ErrorLogCountSelector.countNew();
        if (newErrors <= 0) {
            return null;
        }

        List<Object> count = new List<Object>{ String.valueOf(newErrors) };
        return new HealthCheckService.Finding(
                'error_log_new',
                String.format(System.Label.Core_HealthCheck_ErrorLogTitle, count),
                String.format(System.Label.Core_HealthCheck_ErrorLogDetail, count),
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(
                System.Label.Core_HealthCheck_ErrorLogFix,
                ErrorLogCountSelector.listViewUrl()
            );
    }

    /** How long a scheduled daily digest may go without a run before it is a finding. */
    @TestVisible
    private static final Integer DIGEST_STALE_DAYS = 2;

    /**
     * Whether the error digest is scheduled but has not run for more than two days (ADR-0055).
     * The job runs as the person who scheduled it, so it stops when that person is deactivated,
     * and nothing else would say so: the panel still shows it as scheduled. A digest that has
     * never run is not reported; its first run is at most a day away.
     */
    private static HealthCheckService.Finding errorDigestFinding() {
        if (ErrorDigestScheduler.nextRunAt() == null) {
            return null;
        }
        Datetime lastRun = SettingsService.getSettings().Error_Digest_Last_Run__c;
        if (lastRun == null || lastRun > System.now().addDays(-DIGEST_STALE_DAYS)) {
            return null;
        }
        return new HealthCheckService.Finding(
                'error_digest_stale',
                System.Label.Core_HealthCheck_DigestStaleTitle,
                String.format(
                    System.Label.Core_HealthCheck_DigestStaleDetail,
                    new List<Object>{ lastRun.format() }
                ),
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withFix(System.Label.Core_HealthCheck_DigestStaleFix, SettingSections.ERROR_LOG);
    }
}
