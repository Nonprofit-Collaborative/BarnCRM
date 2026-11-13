/**
 * The class Core finds by name (registered in its catalog row) to add the project health
 * check and, while Show financials and recognize revenue is on, the monthly revenue rows to the
 * one nightly run (ADR-0166; ADR-0208 `0208-project-management-module.md` decision 5; ADR-0219
 * `0219-projects-psa.md` decision 7).
 */
@NamespaceAccessible
public with sharing class ProjectsNightlyJobProvider implements NightlyStepProvider {
	@NamespaceAccessible
	public ProjectsNightlyJobProvider() {
		// Built by name from Core (NightlyJobs), so it needs a public constructor.
	}

	public List<NightlyStep> nightlySteps() {
		return new List<NightlyStep>{ ProjectHealth.step(), ProjectRevenue.step() };
	}
}
