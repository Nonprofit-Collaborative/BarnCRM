/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to add Giving's steps to the
 * one nightly run (ADR-0166 nightly-job-dispatcher): the four jobs `GivingScheduler` switches
 * together, then the acknowledgment send and the pledge reminders, each switched on its own page
 * and shipped off because they email donors.
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
		steps.add(AcknowledgmentScheduler.step());
		steps.add(PledgeReminderScheduler.step());
		return steps;
	}
}
