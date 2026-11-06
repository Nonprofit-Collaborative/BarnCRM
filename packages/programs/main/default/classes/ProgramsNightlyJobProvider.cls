/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to add the Programs step to
 * the one nightly run (ADR-0166 nightly-job-dispatcher): the run that keeps repeating session
 * schedules' sessions created to the horizon (R-SS3).
 */
@NamespaceAccessible
public with sharing class ProgramsNightlyJobProvider implements NightlyStepProvider {
	@NamespaceAccessible
	public ProgramsNightlyJobProvider() {
		// Built by name from Core (NightlyJobs), so it needs a public constructor.
	}

	public List<NightlyStep> nightlySteps() {
		return new List<NightlyStep>{ SessionScheduleBatch.step() };
	}
}
