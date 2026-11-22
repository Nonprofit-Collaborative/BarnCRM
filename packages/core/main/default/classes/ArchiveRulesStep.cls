/**
 * The nightly Archive Rules step (canonical model R-SQ18, ADR-0166 nightly-job-dispatcher, ADR-NEXT
 * archive rules and big object archive): at 3:00, every archive rule due today starts its run, as
 * the user who scheduled the nightly run. Shipped on; with no scheduled rule it does nothing. The
 * step's switch on the Nightly Jobs card and each rule's Active switch turn the automation off.
 *
 * A nightly step runs inside a queueable, which may queue only one job, and each rule's run is a
 * queueable chain of its own. So the step starts a batch of the due rules, one rule per chunk, and
 * each chunk starts one rule's run.
 */
public with sharing class ArchiveRulesStep implements Schedulable, Database.Batchable<SObject> {
	/** The step's key. */
	public static final String JOB_NAME = 'BarnCRM Archive Rules';
	private static final String LOG_SOURCE = 'ArchiveRulesStep';

	private final Date day;

	public ArchiveRulesStep() {
		this(null);
	}

	public ArchiveRulesStep(Date day) {
		this.day = day;
	}

	public static NightlyStep step() {
		return new NightlyStep(JOB_NAME, BarnHelp.text('Core', 'Core_ArchiveRules_StepLabel'), 3, 0, new ArchiveRulesStep())
			.withSwitch(true);
	}

	/** Starts the batch when a rule is due today; otherwise nothing. */
	public void execute(SchedulableContext context) {
		Date today = OrgDate.today();
		if (!ArchiveRuleService.dueRuleIds(today).isEmpty()) {
			AsyncStarter.batch(new ArchiveRulesStep(today), 1, LOG_SOURCE);
		}
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		Set<Id> due = ArchiveRuleService.dueRuleIds(day);
		return Database.getQueryLocatorWithBinds(
			'SELECT Id FROM Saved_Query__c WHERE Id IN :due ORDER BY Name',
			new Map<String, Object>{ 'due' => due },
			AccessLevel.SYSTEM_MODE
		);
	}

	public void execute(Database.BatchableContext context, List<SObject> scope) {
		for (SObject query : scope) {
			ArchiveRuleService.runDueRule(query.Id);
		}
	}

	public void finish(Database.BatchableContext context) {
		return;
	}
}
