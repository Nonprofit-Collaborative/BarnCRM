/**
 * The Approvals page (PM-07, PM-08; canonical model R-PM11, R-PM13): the Submitted time and
 * expenses of the running user's projects (every project with Manage Projects), approved or
 * rejected by entry or by a person's week. Who may decide is the `Approval_By_Manager`
 * validation rule on the entry, not code here, so no other path (list edit, API) can skip it.
 * Thin by design (plan Section 9.9): `c/projectsTimesheetModel` groups the rows into weeks. Off
 * unless Approve time and expenses is on.
 */
public with sharing class ProjectApprovalsController {
	private static final String CONTEXT = 'ProjectApprovalsController';

	public class Queue {
		@AuraEnabled
		public Boolean enabled = false;
		@AuraEnabled
		public List<Time_Entry__c> entries = new List<Time_Entry__c>();
		@AuraEnabled
		public List<Project_Expense__c> expenses = new List<Project_Expense__c>();
	}

	@AuraEnabled
	public static Queue getQueue() {
		try {
			Queue queue = new Queue();
			queue.enabled = ProjectsSettings.approvalsEnabled();
			if (!queue.enabled) {
				return queue;
			}
			Id me = UserInfo.getUserId();
			Boolean all = Projects.canManage();
			for (Time_Entry__c entry : [
				SELECT
					Id,
					Project__c,
					Project__r.Name,
					Project__r.OwnerId,
					Task__r.Name,
					User__c,
					User__r.Name,
					Date__c,
					Hours__c,
					Billable__c,
					Notes__c
				FROM Time_Entry__c
				WHERE Status__c = 'Submitted'
				WITH USER_MODE
				ORDER BY User__r.Name, Date__c
				LIMIT 2000
			]) {
				if (all || entry.Project__r.OwnerId == me) {
					queue.entries.add(entry);
				}
			}
			if (ProjectsSettings.expensesEnabled()) {
				for (Project_Expense__c expense : [
					SELECT
						Id,
						Project__c,
						Project__r.Name,
						Project__r.OwnerId,
						User__c,
						User__r.Name,
						Date__c,
						Category__c,
						Amount__c,
						Billable__c,
						Description__c
					FROM Project_Expense__c
					WHERE Status__c = 'Submitted'
					WITH USER_MODE
					ORDER BY User__r.Name, Date__c
					LIMIT 1000
				]) {
					if (all || expense.Project__r.OwnerId == me) {
						queue.expenses.add(expense);
					}
				}
			}
			return queue;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/**
	 * Approves, or rejects with a reason, the Submitted time entries and expenses named (any
	 * mix, by id); stamps Approved By. Returns how many it decided.
	 */
	@AuraEnabled
	public static Integer decide(List<Id> ids, Boolean approve, String reason) {
		try {
			if (!ProjectsSettings.approvalsEnabled()) {
				throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Approvals_Off'));
			}
			if (approve != true && String.isBlank(reason)) {
				throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Approvals_ReasonNeeded'));
			}
			String status = approve == true ? 'Approved' : 'Rejected';
			String why = approve == true ? null : reason.abbreviate(255);
			Id me = UserInfo.getUserId();
			List<SObject> decided = new List<SObject>();
			for (Time_Entry__c entry : [
				SELECT Id
				FROM Time_Entry__c
				WHERE Id IN :ids AND Status__c = 'Submitted'
				WITH USER_MODE
				LIMIT 2000
			]) {
				decided.add(
					new Time_Entry__c(
						Id = entry.Id,
						Status__c = status,
						Approved_By__c = me,
						Rejection_Reason__c = why
					)
				);
			}
			for (Project_Expense__c expense : [
				SELECT Id
				FROM Project_Expense__c
				WHERE Id IN :ids AND Status__c = 'Submitted'
				WITH USER_MODE
				LIMIT 1000
			]) {
				decided.add(
					new Project_Expense__c(
						Id = expense.Id,
						Status__c = status,
						Approved_By__c = me,
						Rejection_Reason__c = why
					)
				);
			}
			update as user decided;
			return decided.size();
		} catch (Exception e) {
			throw failure(e);
		}
	}

	private static AuraHandledException failure(Exception e) {
		if (!(e instanceof Projects.ProjectsException) && !(e instanceof DmlException)) {
			ErrorLogger.log(e, CONTEXT);
		}
		return UserErrors.wrapShowingDml(e, BarnHelp.text('Projects', 'Projects_Error_Generic'));
	}
}
