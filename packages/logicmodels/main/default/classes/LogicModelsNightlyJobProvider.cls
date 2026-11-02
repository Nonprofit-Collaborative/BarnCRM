/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to have the Logic Models
 * nightly job counted and scheduled by Health Check's "Schedule all nightly jobs" fix (ADR-0075,
 * ADR-NEXT `NEXT-indicator-sources.md`): the run that works out computed indicators' results.
 */
@NamespaceAccessible
public with sharing class LogicModelsNightlyJobProvider implements NightlyJobProvider {
    @NamespaceAccessible
    public LogicModelsNightlyJobProvider() {
        // Built by name from Core (NightlyJobs), so it needs a public constructor.
    }

    public List<NightlyJob> nightlyJobs() {
        return new List<NightlyJob>{ IndicatorResultsScheduler.nightlyJob() };
    }
}
