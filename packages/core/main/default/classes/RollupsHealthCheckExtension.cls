/**
 * The rollup engine's Health Check findings and its one fix (ADR-NEXT,
 * `NEXT-rollup-builder-module.md`): shipped rollups that are missing, nightly rollups with no
 * nightly run, and a Rollup Queue that failed or stalled. Core finds this class by name
 * (`HealthCheckExtensions`) and folds the findings into its report; an org without the Rollup
 * Builder module has no rollups, so it has none of these findings.
 *
 * The checks read organization-wide state and their fix needs the settings permission, so they
 * are asked only of a viewer who may manage settings, as Core's own settings checks are. Each
 * check is isolated: one that throws becomes a single "check failed" finding, under the key it
 * had in Core's report, and the rest still stand.
 */
@NamespaceAccessible
public with sharing class RollupsHealthCheckExtension implements HealthCheckExtension, HealthCheckFixExtension {
    /** The fix that creates the shipped rollups this org does not have (ADR-0029, ADR-0048). */
    @NamespaceAccessible
    public static final String FIX_KEY_RESTORE_ROLLUPS = 'restoreShippedRollups';

    /** How long a Pending entry may wait before Health Check calls the queue stuck. */
    @TestVisible
    private static Integer queueStuckAfterMinutes = 60;

    @NamespaceAccessible
    public RollupsHealthCheckExtension() {
        // Built by name from Core (HealthCheckExtensions), so it needs a public constructor.
    }

    public List<HealthCheckService.Finding> findings() {
        List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
        if (!HealthCheckService.canManageSettings()) {
            return found;
        }
        addIsolated(found, 'shipped_rollups', new ShippedRollupsCheck());
        addIsolated(found, 'nightly_rollups', new NightlyRollupsCheck());
        addIsolated(found, 'rollup_queue', new RollupQueueCheck());
        return found;
    }

    public List<String> fixScope(String fixKey) {
        return FIX_KEY_RESTORE_ROLLUPS.equals(fixKey) ? RollupService.missingDefaultNames() : null;
    }

    public String fixLabel(String fixKey) {
        return FIX_KEY_RESTORE_ROLLUPS.equals(fixKey)
            ? System.Label.Core_HealthCheck_RollupsMissingFix
            : null;
    }

    public String runFix(String fixKey, List<String> scope) {
        if (!FIX_KEY_RESTORE_ROLLUPS.equals(fixKey)) {
            return null;
        }
        String outcome = String.format(
            System.Label.Core_HealthCheck_FixCreated,
            new List<Object>{ String.join(scope, ', ') }
        );
        List<String> skipped = RollupService.skippedDefaultNames();
        RollupService.ensureDefaults();
        if (!skipped.isEmpty()) {
            outcome +=
                ' ' +
                String.format(
                    System.Label.Core_HealthCheck_RollupsSkippedDetail,
                    new List<Object>{ String.join(skipped, ', ') }
                );
        }
        return outcome;
    }

    /** One rollup check, run on its own. */
    @TestVisible
    private interface RollupCheck {
        HealthCheckService.Finding run();
    }

    private static void addIsolated(
        List<HealthCheckService.Finding> found,
        String checkKey,
        RollupCheck check
    ) {
        try {
            HealthCheckService.Finding finding = check.run();
            if (finding != null) {
                found.add(finding);
            }
        } catch (Exception e) {
            found.add(HealthCheckService.checkFailed(checkKey, e));
        }
    }

    /**
     * Shipped rollups this org does not have (ADR-0006, ADR-0048). A shipped total that one of
     * the administrator's own active totals already writes is not restored, and the finding
     * says so rather than hiding it.
     */
    @TestVisible
    private class ShippedRollupsCheck implements RollupCheck {
        public HealthCheckService.Finding run() {
            List<String> missingNames = RollupService.missingDefaultNames();
            if (missingNames == null || missingNames.isEmpty()) {
                return null;
            }
            List<Object> values = new List<Object>{
                String.valueOf(missingNames.size()),
                String.join(missingNames, ', ')
            };
            HealthCheckService.Finding finding = new HealthCheckService.Finding(
                    'shipped_rollups_missing',
                    String.format(System.Label.Core_HealthCheck_RollupsMissingTitle, values),
                    String.format(System.Label.Core_HealthCheck_RollupsMissingDetail, values),
                    HealthCheckService.SEVERITY_WARNING,
                    HealthCheckService.CATEGORY_SETTINGS
                )
                .withScope(missingNames);
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
                HealthCheckService.FIX_ACTION_PREFIX + FIX_KEY_RESTORE_ROLLUPS
            );
        }
    }

    /**
     * Rollups set to recalculate in the nightly run while the run is not scheduled. A rollup
     * set to Scheduled alone is then never recalculated, which is a warning; one set to Both
     * still updates as records change and only misses the nightly correction, which is
     * information. Its fix is the nightly jobs finding's, which schedules this run with the
     * rest, so one cause has one button.
     */
    @TestVisible
    private class NightlyRollupsCheck implements RollupCheck {
        public HealthCheckService.Finding run() {
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
            );
        }
    }

    /**
     * Totals the Rollup Queue could not finish (ADR-0098 async rollups): records whose
     * recalculation failed five times, or entries waiting longer than an hour, which means no
     * processor is running for them. The errors themselves are in the Error Log.
     */
    @TestVisible
    private with sharing class RollupQueueCheck implements RollupCheck {
        public HealthCheckService.Finding run() {
            Integer failed = [
                SELECT COUNT()
                FROM Rollup_Queue__c
                WHERE Status__c = :RollupQueue.STATUS_FAILED
                WITH USER_MODE
                LIMIT 10000
            ];
            Datetime stuckBefore = Datetime.now().addMinutes(-queueStuckAfterMinutes);
            Integer stuck = [
                SELECT COUNT()
                FROM Rollup_Queue__c
                WHERE Status__c = :RollupQueue.STATUS_PENDING AND CreatedDate < :stuckBefore
                WITH USER_MODE
                LIMIT 10000
            ];
            if (failed == 0 && stuck == 0) {
                return null;
            }
            String fixTarget = '/lightning/n/' + NamespaceUtil.qualify('Rollup_Builder');
            if (failed > 0) {
                return new HealthCheckService.Finding(
                        'rollup_queue_failed',
                        System.Label.Core_HealthCheck_RollupQueueFailedTitle,
                        String.format(
                            System.Label.Core_HealthCheck_RollupQueueFailedDetail,
                            new List<Object>{ failed.format() }
                        ),
                        HealthCheckService.SEVERITY_WARNING,
                        HealthCheckService.CATEGORY_SETTINGS
                    )
                    .withFix(System.Label.Core_HealthCheck_RollupQueueFix, fixTarget);
            }
            return new HealthCheckService.Finding(
                    'rollup_queue_stuck',
                    System.Label.Core_HealthCheck_RollupQueueStuckTitle,
                    String.format(
                        System.Label.Core_HealthCheck_RollupQueueStuckDetail,
                        new List<Object>{ stuck.format(), queueStuckAfterMinutes.format() }
                    ),
                    HealthCheckService.SEVERITY_WARNING,
                    HealthCheckService.CATEGORY_SETTINGS
                )
                .withFix(System.Label.Core_HealthCheck_RollupQueueFix, fixTarget);
        }
    }
}
