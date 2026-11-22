/**
 * The class Core finds by name (registered in its catalog row) to add Fundraising's steps to the
 * one nightly run (ADR-0166 nightly-job-dispatcher): the five jobs `GivingScheduler` switches
 * together (the pledge reminders among them, shipped off because they email donors, G-37), then
 * the acknowledgment send, switched on its own page and shipped off for the same reason, then
 * the nightly runs of the two gift mirrors (X-01, X-07), each in tonight's run only while that
 * mirror's direction is chosen and its object exists, and switched on its own page (ADR-0228).
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
				.withSummary(GivingState.text(GivingState.ACKNOWLEDGMENTS_SUMMARY))
		);
		steps.add(OpportunityMirrorSchedulable.step());
		steps.add(GiftTransactionMirrorSchedulable.step());
		return steps;
	}
}
