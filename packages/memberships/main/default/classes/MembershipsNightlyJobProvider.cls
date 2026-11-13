/**
 * The class Core finds by name (registered in its catalog row) to add the Memberships step,
 * renewals, lapse handling and reminders, to the one nightly run (ADR-0166; ADR-0206
 * `0206-memberships-module.md` decision 5).
 */
@NamespaceAccessible
public with sharing class MembershipsNightlyJobProvider implements NightlyStepProvider {
	@NamespaceAccessible
	public MembershipsNightlyJobProvider() {
		// Built by name from Core (NightlyJobs), so it needs a public constructor.
	}

	public List<NightlyStep> nightlySteps() {
		return new List<NightlyStep>{ MembershipRenewals.step() };
	}
}
