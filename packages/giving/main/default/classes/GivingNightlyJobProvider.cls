/**
 * The class Core finds by name (registered in its catalog row) to add Giving's steps to the
 * one nightly run (ADR-0166 nightly-job-dispatcher): the five jobs `GivingScheduler` switches
 * together (the pledge reminders among them, shipped off because they email donors, G-37), then
 * the acknowledgment send, switched on its own page and shipped off for the same reason.
 *
 * `@NamespaceAccessible` for the reason `GivingHealthCheckExtension` is: Core resolves it with
 * `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class GivingNightlyJobProvider implements NightlyStepProvider {
	@NamespaceAccessible
	public GivingNightlyJobProvider() {
		return;
	}

	public List<NightlyStep> nightlySteps() {
		List<NightlyStep> steps = GivingScheduler.steps();
		steps.add(
			AcknowledgmentScheduler.step()
				.withSummary(
					Giving_Settings__c.getOrgDefaults().Acknowledgments_Last_Run_Summary__c
				)
		);
		return steps;
	}
}
