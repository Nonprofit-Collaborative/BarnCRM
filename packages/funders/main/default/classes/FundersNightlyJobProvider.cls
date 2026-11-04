/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to add the Funders step to the
 * one nightly run (ADR-NEXT nightly-job-dispatcher): the grant requirement reminder run (F-02).
 */
@NamespaceAccessible
public with sharing class FundersNightlyJobProvider implements NightlyStepProvider {
    @NamespaceAccessible
    public FundersNightlyJobProvider() {
        // Built by name from Core (NightlyJobs), so it needs a public constructor.
    }

    public List<NightlyStep> nightlySteps() {
        return new List<NightlyStep>{ GrantReminderScheduler.step() };
    }
}
