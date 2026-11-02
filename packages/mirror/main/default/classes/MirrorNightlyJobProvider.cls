/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to have Mirror's nightly job
 * counted and scheduled by Health Check's "Schedule all nightly jobs" fix (ADR-0075,
 * health-check-schedules-every-nightly-job).
 *
 * It lists the nightly run of the Opportunity mirror and of the Gift Transaction mirror (X-07),
 * each only while that mirror's direction is chosen and its object exists. A mirror that is Off
 * has nothing to copy, so scheduling its run would report a job that does nothing and take a
 * place in the org's scheduled job limit for no reason. Each run is scheduled under the name its
 * mirror page already looks for (ADR-0038).
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
        List<NightlyJob> jobs = new List<NightlyJob>();
        if (
            OpportunityMirrorService.isAvailable() &&
            OpportunityMirrorService.direction() != OpportunityMirrorService.OFF
        ) {
            jobs.add(OpportunityMirrorSchedulable.nightlyJob());
        }
        if (GiftTransactionMirrorService.isOn()) {
            jobs.add(GiftTransactionMirrorSchedulable.nightlyJob());
        }
        return jobs;
    }
}
