/**
 * The class Core finds by name (registered in its catalog row) to add Mirror's step to the one
 * nightly run (ADR-0166 nightly-job-dispatcher): the Case requests step (D-201, while Send Cases to
 * a service provider is on), whose work keeps the hourly check scheduled (N-10). The gift mirrors'
 * steps are BarnCRM Fundraising's (`GivingNightlyJobProvider`).
 *
 * `@NamespaceAccessible` for the reason `MirrorHealthCheckExtension` is: Core resolves it with
 * `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class MirrorNightlyJobProvider implements NightlyStepProvider {
	@NamespaceAccessible
	public MirrorNightlyJobProvider() {
		return;
	}

	public List<NightlyStep> nightlySteps() {
		return new List<NightlyStep>{ CaseProviderRequests.step() };
	}
}
