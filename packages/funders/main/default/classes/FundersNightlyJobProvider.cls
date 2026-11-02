/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to have the Funders morning
 * job counted and scheduled by Health Check's "Schedule all nightly jobs" fix (ADR-0075): the grant
 * requirement reminder run (F-02).
 */
@NamespaceAccessible
public with sharing class FundersNightlyJobProvider implements NightlyJobProvider {
    @NamespaceAccessible
    public FundersNightlyJobProvider() {
        // Built by name from Core (NightlyJobs), so it needs a public constructor.
    }

    public List<NightlyJob> nightlyJobs() {
        return new List<NightlyJob>{ GrantReminderScheduler.nightlyJob() };
    }
}
