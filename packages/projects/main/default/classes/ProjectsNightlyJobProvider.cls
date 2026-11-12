/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to add the project health
 * check to the one nightly run (ADR-0166; ADR-0208 `0208-project-management-module.md`
 * decision 5).
 */
@NamespaceAccessible
public with sharing class ProjectsNightlyJobProvider implements NightlyStepProvider {
	@NamespaceAccessible
	public ProjectsNightlyJobProvider() {
		// Built by name from Core (NightlyJobs), so it needs a public constructor.
	}

	public List<NightlyStep> nightlySteps() {
		return new List<NightlyStep>{ ProjectHealth.step() };
	}
}
