/**
 * The Budget panel on the event page's Details tab (EV-23, canonical model 29EV33, 29EV34 and
 * R-EXP1): the event's expense lines, its funding, and what registrations have paid. Thin by
 * design (plan Section 9.9): it only reads, in user mode; the totals and net cost are worked out
 * by the browser module `eventBudgetModel`, and lines are added, changed and removed through the
 * platform's record form and record API, so the person's own access decides.
 */
public with sharing class EventBudgetController {
	private static final String CONTEXT = 'EventBudgetController';
	private static final Integer ROW_LIMIT = 500;

	/** Everything the panel draws. */
	public class Budget {
		@AuraEnabled
		public List<ExpenseRow> expenses = new List<ExpenseRow>();
		@AuraEnabled
		public List<FundingRow> funding = new List<FundingRow>();
		/** What the event's registrations have paid, less refunds. */
		@AuraEnabled
		public Decimal registrationsPaid = 0;
		@AuraEnabled
		public Boolean canAddExpense = false;
		@AuraEnabled
		public Boolean canAddFunding = false;
		@AuraEnabled
		public Boolean canEdit = false;
		/** Field and object labels by key, so the panel needs no labels of its own. */
		@AuraEnabled
		public Map<String, String> fieldLabels = new Map<String, String>();
	}

	/** One expense line. */
	public class ExpenseRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String category;
		@AuraEnabled
		public Decimal budgeted;
		@AuraEnabled
		public Decimal actual;
		@AuraEnabled
		public String vendor;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Date dueDate;
	}

	/** One funding line. */
	public class FundingRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String type;
		@AuraEnabled
		public String organizationName;
		@AuraEnabled
		public String sponsorName;
		@AuraEnabled
		public Decimal expected;
		@AuraEnabled
		public Decimal received;
	}

	/**
	 * The event's expense lines, funding and registration payments.
	 *
	 * @param eventId the event
	 * @return the panel's contents and what the person may do
	 */
	@AuraEnabled
	public static Budget getBudget(Id eventId) {
		try {
			Budget result = new Budget();
			result.canAddExpense = Schema.SObjectType.Event_Expense__c.isCreateable();
			result.canAddFunding = Schema.SObjectType.Event_Funding__c.isCreateable();
			result.canEdit =
				Schema.SObjectType.Event_Expense__c.isUpdateable() ||
				Schema.SObjectType.Event_Funding__c.isUpdateable();
			fillLabels(result);
			for (Event_Expense__c line : [
				SELECT
					Id,
					Name,
					toLabel(Category__c),
					Budgeted__c,
					Actual__c,
					Vendor__c,
					toLabel(Status__c),
					Due_Date__c
				FROM Event_Expense__c
				WHERE Event__c = :eventId
				WITH USER_MODE
				ORDER BY Category__c, Name
				LIMIT :ROW_LIMIT
			]) {
				ExpenseRow row = new ExpenseRow();
				row.id = line.Id;
				row.name = line.Name;
				row.category = line.Category__c;
				row.budgeted = line.Budgeted__c;
				row.actual = line.Actual__c;
				row.vendor = line.Vendor__c;
				row.status = line.Status__c;
				row.dueDate = line.Due_Date__c;
				result.expenses.add(row);
			}
			for (Event_Funding__c line : [
				SELECT
					Id,
					Name,
					toLabel(Type__c),
					Account__r.Name,
					Event_Sponsor__r.Name,
					Expected__c,
					Received__c
				FROM Event_Funding__c
				WHERE Event__c = :eventId
				WITH USER_MODE
				ORDER BY Name
				LIMIT :ROW_LIMIT
			]) {
				FundingRow row = new FundingRow();
				row.id = line.Id;
				row.name = line.Name;
				row.type = line.Type__c;
				row.organizationName = line.Account__r?.Name;
				row.sponsorName = line.Event_Sponsor__r?.Name;
				row.expected = line.Expected__c;
				row.received = line.Received__c;
				result.funding.add(row);
			}
			result.registrationsPaid = registrationsPaid(eventId);
			return result;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getBudget', eventId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Budget_LoadFailed'));
		}
	}

	/** What the event's registrations have paid, as the person can read it; zero when none. */
	public static Decimal registrationsPaid(Id eventId) {
		AggregateResult total = [
			SELECT SUM(Amount_Paid__c) paid
			FROM Event_Registration__c
			WHERE Event__c = :eventId
			WITH USER_MODE
		];
		Decimal paid = (Decimal) total.get('paid');
		return paid == null ? 0 : paid;
	}

	private static void fillLabels(Budget result) {
		result.fieldLabels.put('Expenses', Schema.SObjectType.Event_Expense__c.getLabelPlural());
		result.fieldLabels.put('Funding', Schema.SObjectType.Event_Funding__c.getLabelPlural());
		Map<String, Schema.SObjectField> expenseFields = Schema.SObjectType.Event_Expense__c.fields.getMap();
		for (
			String name : new List<String>{
				'Name',
				'Category__c',
				'Budgeted__c',
				'Actual__c',
				'Vendor__c',
				'Status__c',
				'Due_Date__c'
			}
		) {
			result.fieldLabels.put(
				'Expense_' + name,
				expenseFields.get(name).getDescribe().getLabel()
			);
		}
		Map<String, Schema.SObjectField> fundingFields = Schema.SObjectType.Event_Funding__c.fields.getMap();
		for (
			String name : new List<String>{
				'Name',
				'Type__c',
				'Account__c',
				'Event_Sponsor__c',
				'Expected__c',
				'Received__c'
			}
		) {
			result.fieldLabels.put(
				'Funding_' + name,
				fundingFields.get(name).getDescribe().getLabel()
			);
		}
	}
}
