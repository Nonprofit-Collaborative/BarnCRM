/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to have the nightly rollup
 * recalculation counted and scheduled by Health Check's "Schedule all nightly jobs" fix (ADR-0075,
 * ADR-0125 `0125-rollup-builder-module.md`). Without the Rollup Builder module there is no
 * nightly rollup run to schedule.
 */
@NamespaceAccessible
public with sharing class RollupsNightlyJobProvider implements NightlyJobProvider {
    @NamespaceAccessible
    public RollupsNightlyJobProvider() {
        // Built by name from Core (NightlyJobs), so it needs a public constructor.
    }

    public List<NightlyJob> nightlyJobs() {
        return new List<NightlyJob>{ new RollupJob() };
    }

    /** The nightly rollup recalculation, started and stopped on the Rollup Builder page. */
    @NamespaceAccessible
    public class RollupJob implements NightlyJob {
        public String label() {
            return System.Label.Core_HealthCheck_JobRollups;
        }

        public Boolean isScheduled() {
            return RollupScheduler.isScheduled();
        }

        public void schedule() {
            RollupScheduler.start();
        }
    }
}
