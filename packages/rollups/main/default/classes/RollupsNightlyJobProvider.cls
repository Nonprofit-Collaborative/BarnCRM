/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to add the nightly rollup
 * recalculation to the one nightly run (ADR-0166 nightly-job-dispatcher, ADR-0125
 * `0125-rollup-builder-module.md`). Without the Rollup Builder module there is no rollup step.
 */
@NamespaceAccessible
public with sharing class RollupsNightlyJobProvider implements NightlyStepProvider {
	@NamespaceAccessible
	public RollupsNightlyJobProvider() {
		// Built by name from Core (NightlyJobs), so it needs a public constructor.
	}

	public List<NightlyStep> nightlySteps() {
		return new List<NightlyStep>{ RollupScheduler.step() };
	}
}
