/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to have Mirror's nightly job
 * counted and scheduled by Health Check's "Schedule all nightly jobs" fix (ADR-0075,
 * health-check-schedules-every-nightly-job).
 *
 * It lists the Opportunity mirror's nightly run, and only while a mirror direction is chosen. A
 * mirror that is Off has nothing to copy, so scheduling its run would report a job that does
 * nothing and take a place in the org's scheduled job limit for no reason. The run is scheduled
 * under the name the Opportunity mirror page already looks for (ADR-0038).
 *
 * `@NamespaceAccessible` for the reason `MirrorHealthCheckExtension` is: Core resolves it with
 * `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class MirrorNightlyJobProvider implements NightlyJobProvider {
    @NamespaceAccessible
    public MirrorNightlyJobProvider() {
        return;
    }

    public List<NightlyJob> nightlyJobs() {
        if (
            !OpportunityMirrorService.isAvailable() ||
            OpportunityMirrorService.direction() == OpportunityMirrorService.OFF
        ) {
            return new List<NightlyJob>();
        }
        return new List<NightlyJob>{ new MirrorJob() };
    }

    /** The Opportunity mirror's nightly run, started and stopped on the Opportunity mirror page. */
    @TestVisible
    private class MirrorJob implements NightlyJob {
        public String label() {
            return System.Label.Mirror_NightlyJob_MirrorName;
        }

        public Boolean isScheduled() {
            return OpportunityMirrorSchedulable.scheduledAt() != null;
        }

        public void schedule() {
            // A second call returns the job already there, so this is safe to repeat.
            OpportunityMirrorSchedulable.schedule();
        }
    }
}
