/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to add territory assignment to
 * the one nightly run (ADR-0166; ADR-0205 `0205-territory-management-module.md`, decision 6). The
 * step ships off: an administrator turns it on from the Nightly Jobs panel once the rules are
 * right. It assigns only records with no territory, so a person's own moves are kept.
 */
@NamespaceAccessible
public with sharing class TerritoryNightlyJobProvider implements NightlyStepProvider {
	public static final String JOB_NAME = 'BarnCRM Territory Assignment';

	@NamespaceAccessible
	public TerritoryNightlyJobProvider() {
		// Built by name from Core (NightlyJobs), so it needs a public constructor.
	}

	public List<NightlyStep> nightlySteps() {
		return new List<NightlyStep>{ step() };
	}

	/** The step as BarnCRM's nightly run lists it, with a switch that ships off. */
	public static NightlyStep step() {
		return new NightlyStep(
				JOB_NAME,
				BarnHelp.text('Territory', 'Territory_Nightly_StepName'),
				5,
				45,
				new Assign()
			)
			.withSwitch(false);
	}

	/** Starts an Assign run of unassigned records, unless a run is busy or no rule is active. */
	public with sharing class Assign implements Schedulable {
		public void execute(SchedulableContext jobContext) {
			try {
				if (TerritoryRunBatch.busy()) {
					return;
				}
				List<String> kinds = TerritoryRunBatch.kindsToRun();
				if (kinds.isEmpty()) {
					return;
				}
				TerritoryRunBatch.launch(TerritoryRunBatch.MODE_ASSIGN, true, kinds);
			} catch (TerritoryRunBatch.TerritoryException refused) {
				ErrorLogger.logMessage(
					refused.getMessage(),
					'TerritoryNightlyJobProvider',
					ErrorLogger.SEVERITY_WARNING
				);
			} catch (Exception e) {
				ErrorLogger.log(e, 'TerritoryNightlyJobProvider');
			}
		}
	}
}
