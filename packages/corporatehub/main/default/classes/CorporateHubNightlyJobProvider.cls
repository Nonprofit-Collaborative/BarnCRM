/**
 * The class Core finds by name (registered in its catalog row) to add the Corporate Hub
 * reminders and agreement renewals to the one nightly run (ADR-0166; ADR-0196
 * `0196-corporate-hub-module.md` decision 7).
 */
@NamespaceAccessible
public with sharing class CorporateHubNightlyJobProvider implements NightlyStepProvider {
	@NamespaceAccessible
	public CorporateHubNightlyJobProvider() {
		// Built by name from Core (NightlyJobs), so it needs a public constructor.
	}

	public List<NightlyStep> nightlySteps() {
		return new List<NightlyStep>{ HubReminders.step() };
	}
}
