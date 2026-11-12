/**
 * Completing a compliance obligation's cycle (CH-03, canonical model R-CO1): one Compliance Cycle
 * for the current due date, then the due date moved on by the recurrence, or a one-time
 * obligation marked Done. Runs as the person, in user mode.
 */
public with sharing class HubCompliance {
	private static final Map<String, Integer> MONTHS = new Map<String, Integer>{
		'Monthly' => 1,
		'Quarterly' => 3,
		'Twice a Year' => 6,
		'Yearly' => 12,
		'Every Two Years' => 24
	};

	/**
	 * @param obligationId the obligation
	 * @param completedOn when it was done; null means today
	 * @param outcome Done, Done Late or Not Required; blank means Done
	 * @param notes free text
	 * @return the new cycle's Id, so its evidence can be attached to it
	 */
	public static Id completeCycle(
		Id obligationId,
		Date completedOn,
		String outcome,
		String notes
	) {
		Compliance_Obligation__c obligation = [
			SELECT Id, Due_Date__c, Recurrence__c
			FROM Compliance_Obligation__c
			WHERE Id = :obligationId
			WITH USER_MODE
		];
		Compliance_Cycle__c cycle = new Compliance_Cycle__c(
			Obligation__c = obligation.Id,
			Due_Date__c = obligation.Due_Date__c,
			Completed_On__c = completedOn == null ? Date.today() : completedOn,
			Completed_By__c = UserInfo.getUserId(),
			Outcome__c = String.isBlank(outcome) ? 'Done' : outcome,
			Notes__c = notes
		);
		insert as user cycle;
		Integer months = MONTHS.get(obligation.Recurrence__c);
		obligation.Last_Completed_On__c = cycle.Completed_On__c;
		if (months == null || obligation.Due_Date__c == null) {
			obligation.Status__c = 'Done';
		} else {
			obligation.Due_Date__c = nextDue(obligation.Due_Date__c, months);
		}
		update as user obligation;
		return cycle.Id;
	}

	/** The date `months` later; a month end stays a month end (31 January, then 28 February). */
	public static Date nextDue(Date due, Integer months) {
		Date next = due.addMonths(months);
		if (due.addDays(1).day() == 1) {
			next = next.toStartOfMonth().addMonths(1).addDays(-1);
		}
		return next;
	}
}
