/**
 * The two before-save rules on time entries and project expenses (registry rows
 * `Time_Entry_Rates_And_Status` and `Project_Expense_Status`, both Always Runs;
 * ADR-0219 `0219-projects-psa.md` sections 2 to 4). With approvals on, a new entry or expense
 * with no Status is saved Open (R-PM11); with rate cards on, a time entry keeps the Bill Rate
 * and Cost Rate it was logged at, written on insert and again when its date, person, project or
 * task changes while it is neither Approved nor invoiced (R-PM9). With both off it changes
 * nothing, so the module behaves as before 1.20. Changes the saved records only: no DML, no
 * failure of a save.
 */
@NamespaceAccessible
public with sharing class ProjectEntryHandler extends TriggerHandler {
	/** Built by name from Core's dispatcher, so it needs a public constructor. */
	@NamespaceAccessible
	public ProjectEntryHandler() {
		return;
	}

	public override void beforeInsert() {
		prepare(newRecords(), null);
	}

	public override void beforeUpdate() {
		prepare(newRecords(), oldRecordsById());
	}

	private static void prepare(List<SObject> rows, Map<Id, SObject> before) {
		if (rows == null || rows.isEmpty()) {
			return;
		}
		Boolean isTime = rows[0] instanceof Time_Entry__c;
		if (
			before == null &&
			ProjectsSettings.approvalsEnabled() &&
			(isTime || ProjectsSettings.expensesEnabled())
		) {
			for (SObject row : rows) {
				if (row.get('Status__c') == null) {
					row.put('Status__c', 'Open');
				}
			}
		}
		if (!isTime || !ProjectsSettings.ratesEnabled()) {
			return;
		}
		List<SObject> toStamp = new List<SObject>();
		for (SObject row : rows) {
			if (
				before == null ? row.get('Bill_Rate__c') == null : repriced(row, before.get(row.Id))
			) {
				toStamp.add(row);
			}
		}
		if (!toStamp.isEmpty()) {
			ProjectRates.stamp(toStamp);
		}
	}

	/** An update that changes what the rate depends on, to an entry still open to repricing. */
	private static Boolean repriced(SObject row, SObject old) {
		return old != null &&
			row.get('Status__c') != 'Approved' &&
			old.get('Status__c') != 'Approved' &&
			row.get('Invoice_Line__c') == null &&
			(row.get('Date__c') != old.get('Date__c') ||
			row.get('User__c') != old.get('User__c') ||
			row.get('Project__c') != old.get('Project__c') ||
			row.get('Task__c') != old.get('Task__c'));
	}
}
