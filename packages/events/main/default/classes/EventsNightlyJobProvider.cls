/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to add the Event Management
 * steps to the one nightly run (ADR-0166): the morning event email run (EV-14).
 */
@NamespaceAccessible
public with sharing class EventsNightlyJobProvider implements NightlyStepProvider {
	@NamespaceAccessible
	public EventsNightlyJobProvider() {
		// Built by name from Core (NightlyJobs), so it needs a public constructor.
	}

	public List<NightlyStep> nightlySteps() {
		return new List<NightlyStep>{ EventEmailScheduler.step() };
	}
}
