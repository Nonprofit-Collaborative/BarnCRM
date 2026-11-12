/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to add the Scholarships
 * reminders and cycle dates to the one nightly run (ADR-0166; ADR-0204
 * `0204-scholarships-outbound-grants-module.md` decision 11).
 */
@NamespaceAccessible
public with sharing class ScholarshipsNightlyJobProvider implements NightlyStepProvider {
	@NamespaceAccessible
	public ScholarshipsNightlyJobProvider() {
		// Built by name from Core (NightlyJobs), so it needs a public constructor.
	}

	public List<NightlyStep> nightlySteps() {
		return new List<NightlyStep>{ ScholarshipReminders.step() };
	}
}
