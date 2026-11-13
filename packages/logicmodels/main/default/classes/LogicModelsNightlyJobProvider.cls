/**
 * The class Core finds by name (registered in its catalog row) to add the Logic Models step
 * to the one nightly run (ADR-0166 nightly-job-dispatcher, ADR-0158 `0158-indicator-sources.md`):
 * the run that works out computed indicators' results.
 */
@NamespaceAccessible
public with sharing class LogicModelsNightlyJobProvider implements NightlyStepProvider {
	@NamespaceAccessible
	public LogicModelsNightlyJobProvider() {
		// Built by name from Core (NightlyJobs), so it needs a public constructor.
	}

	public List<NightlyStep> nightlySteps() {
		return new List<NightlyStep>{ IndicatorResultsScheduler.step() };
	}
}
