/**
 * The nightly donor level pass. Scheduled by `GivingScheduler` with the module's other daily jobs
 * so that Maria never opens Setup to schedule Apex (Principle 1).
 *
 * It runs after the rollups have settled and is safe to run twice on the same night: assignment
 * is idempotent, so a second run over unchanged data writes nothing (R-DL6).
 *
 * Every donor is re-placed only when something no save announces can have moved them (D-200
 * P1): no recalculation recorded yet, a ladder rung or a donor setting changed since the last
 * one, a fiscal year started since, or a week gone by. Otherwise, with donor scores switched
 * on, the pass reads only the donors whose days since their last gift crossed a recency cutoff,
 * the one score that moves with the date alone.
 */
public with sharing class DonorLevelSchedulable implements Schedulable {
	/** Accounts per chunk. Placement is arithmetic on fields already queried, so the default is fine. */
	public static final Integer CHUNK_SIZE = 200;

	/** Days after which every donor is re-placed whatever changed, as a backstop. */
	@TestVisible
	private static final Integer FULL_PASS_DAYS = 7;

	@TestVisible
	private static Date todayOverride;

	public void execute(SchedulableContext context) {
		Datetime last = Giving_Settings__c.getOrgDefaults().Donor_Levels_Last_Recalculated__c;
		if (needsFullPass(last)) {
			// Donor scores are kept whether or not levels are on (the Automation page switches
			// them); the batch places levels only when they are enabled (G-19, R-DT5).
			Database.executeBatch(new DonorLevelBatch(), CHUNK_SIZE);
		} else if (scoresOn()) {
			Database.executeBatch(
				DonorLevelBatch.recencyEdges(recencyEdges(last.date())),
				CHUNK_SIZE
			);
		}
	}

	/** True when every donor must be re-placed tonight. */
	@TestVisible
	private static Boolean needsFullPass(Datetime last) {
		if (last == null || last < Datetime.now().addDays(-FULL_PASS_DAYS)) {
			return true;
		}
		Date today = today();
		Integer month = FiscalYearSelector.fiscalYearStartMonth();
		Date fiscalStart = Date.newInstance(
			today.month() >= month ? today.year() : today.year() - 1,
			month,
			1
		);
		if (fiscalStart > last.date()) {
			return true;
		}
		if (
			[
				SELECT Id
				FROM Donor_Level__c
				WHERE SystemModstamp >= :last
				WITH SYSTEM_MODE
				LIMIT 1
				ALL ROWS
			]
			.size() > 0
		) {
			return true;
		}
		// Donor level and donor score settings, and their Automation switches.
		return [
				SELECT Id
				FROM Setting_Change__c
				WHERE Setting_Name__c LIKE '%Donor%' AND CreatedDate >= :last
				WITH SYSTEM_MODE
				LIMIT 1
			]
			.size() > 0;
	}

	/**
	 * Last gift date ranges, in pairs, for the donors whose days since their last gift crossed a
	 * recency cutoff between the last recalculation and today, with a day of margin each side.
	 */
	@TestVisible
	private static List<Date> recencyEdges(Date last) {
		Date today = today();
		List<Date> edges = new List<Date>();
		for (Decimal cutoff : DonorScoreService.cutoffs().recency) {
			Integer days = cutoff.intValue();
			edges.add(last.addDays(-days - 1));
			edges.add(today.addDays(-days + 1));
		}
		return edges;
	}

	private static Boolean scoresOn() {
		return AutomationControl.isEnabled('Donor_Score_Assignment_Account') ||
			AutomationControl.isEnabled('Donor_Score_Assignment_Contact');
	}

	private static Date today() {
		return todayOverride == null ? Date.today() : todayOverride;
	}
}
