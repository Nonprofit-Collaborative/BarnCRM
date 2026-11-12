/**
 * The Timesheet page (PM-07, PM-08; canonical model R-PM11, R-PM13): one person's week, Monday
 * to Sunday, of time entries and expenses; saving cells, Submit Week, Recall and Add Expense.
 * Thin by design (plan Section 9.9): the grid is worked out in `c/projectsTimesheetModel`. User
 * mode throughout, so a lock is a validation rule's refusal, not code here. With Approve time
 * and expenses off the page shows nothing and no method changes anything.
 */
public with sharing class ProjectTimesheetController {
	private static final String CONTEXT = 'ProjectTimesheetController';
	private static final Date A_MONDAY = Date.newInstance(1900, 1, 1);

	public class Week {
		@AuraEnabled
		public Date weekStart;
		@AuraEnabled
		public Boolean enabled = false;
		@AuraEnabled
		public Boolean expensesEnabled = false;
		@AuraEnabled
		public List<Time_Entry__c> entries = new List<Time_Entry__c>();
		@AuraEnabled
		public List<Project_Expense__c> expenses = new List<Project_Expense__c>();
		@AuraEnabled
		public List<Project__c> projects = new List<Project__c>();
	}

	/** One grid cell: an existing entry to change (id) or a new one for a project and day. */
	public class Cell {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public Id projectId;
		@AuraEnabled
		public Id taskId;
		@AuraEnabled
		public Date workDate;
		@AuraEnabled
		public Decimal hours;
		@AuraEnabled
		public Boolean billable;
		@AuraEnabled
		public String notes;
	}

	@AuraEnabled
	public static Week getWeek(Date weekStart) {
		try {
			Week week = new Week();
			Date monday = mondayOf(weekStart);
			week.weekStart = monday;
			week.enabled = ProjectsSettings.approvalsEnabled();
			if (!week.enabled) {
				return week;
			}
			Id me = UserInfo.getUserId();
			week.expensesEnabled = ProjectsSettings.expensesEnabled();
			week.entries = [
				SELECT
					Id,
					Project__c,
					Project__r.Name,
					Task__c,
					Task__r.Name,
					Date__c,
					Hours__c,
					Billable__c,
					Notes__c,
					Status__c,
					Rejection_Reason__c
				FROM Time_Entry__c
				WHERE User__c = :me AND Date__c >= :monday AND Date__c <= :monday.addDays(6)
				WITH USER_MODE
				ORDER BY Project__r.Name, Date__c
				LIMIT 500
			];
			if (week.expensesEnabled) {
				week.expenses = [
					SELECT
						Id,
						Project__c,
						Project__r.Name,
						Date__c,
						Category__c,
						Amount__c,
						Billable__c,
						Description__c,
						Status__c,
						Rejection_Reason__c
					FROM Project_Expense__c
					WHERE User__c = :me AND Date__c >= :monday AND Date__c <= :monday.addDays(6)
					WITH USER_MODE
					ORDER BY Date__c
					LIMIT 200
				];
			}
			week.projects = [
				SELECT Id, Name
				FROM Project__c
				WHERE Status__c IN ('Planned', 'Active') AND Is_Template__c = FALSE
				WITH USER_MODE
				ORDER BY Name
				LIMIT 200
			];
			return week;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** The open tasks of a project, for a new timesheet row. */
	@AuraEnabled
	public static List<Project_Task__c> getTasks(Id projectId) {
		try {
			return [
				SELECT Id, Name
				FROM Project_Task__c
				WHERE Project__c = :projectId AND Status__c NOT IN ('Done', 'Cancelled')
				WITH USER_MODE
				ORDER BY Sort_Order__c NULLS LAST, Name
				LIMIT 200
			];
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/**
	 * Saves the cells: a new entry for each cell without an id, the hours, billable flag and
	 * notes of an existing one. A cell cannot be emptied here: Staff cannot delete time, so a
	 * mistaken entry is changed or an admin removes it.
	 */
	@AuraEnabled
	public static Integer saveWeek(List<Cell> cells) {
		try {
			requireEnabled();
			List<Time_Entry__c> added = new List<Time_Entry__c>();
			List<Time_Entry__c> changed = new List<Time_Entry__c>();
			for (Cell cell : cells == null ? new List<Cell>() : cells) {
				if (cell.hours == null || cell.hours <= 0) {
					throw Projects.refuse(
						BarnHelp.text('Projects', 'Projects_Timesheet_HoursNeeded')
					);
				}
				String notes = cell.notes == null ? null : cell.notes.abbreviate(255);
				if (cell.id == null) {
					added.add(
						new Time_Entry__c(
							Project__c = cell.projectId,
							Task__c = cell.taskId,
							User__c = UserInfo.getUserId(),
							Date__c = cell.workDate,
							Hours__c = cell.hours,
							Billable__c = cell.billable == true,
							Notes__c = notes
						)
					);
				} else {
					changed.add(
						new Time_Entry__c(
							Id = cell.id,
							Hours__c = cell.hours,
							Billable__c = cell.billable == true,
							Notes__c = notes
						)
					);
				}
			}
			insert as user added;
			update as user changed;
			return added.size() + changed.size();
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** Open and Rejected time and expenses of the week become Submitted; returns how many. */
	@AuraEnabled
	public static Integer submitWeek(Date weekStart) {
		try {
			Integer count = move(weekStart, new List<String>{ 'Open', 'Rejected' }, 'Submitted');
			if (count == 0) {
				throw Projects.refuse(
					BarnHelp.text('Projects', 'Projects_Timesheet_NothingToSubmit')
				);
			}
			return count;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** Submitted time and expenses of the week go back to Open until they are decided. */
	@AuraEnabled
	public static Integer recallWeek(Date weekStart) {
		try {
			return move(weekStart, new List<String>{ 'Submitted' }, 'Open');
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Id addExpense(
		Id projectId,
		Date workDate,
		String category,
		Decimal amount,
		Boolean billable,
		String description
	) {
		try {
			if (!ProjectsSettings.expensesEnabled()) {
				throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Expense_Off'));
			}
			Project_Expense__c expense = new Project_Expense__c(
				Project__c = projectId,
				User__c = UserInfo.getUserId(),
				Date__c = workDate == null ? Date.today() : workDate,
				Category__c = category,
				Amount__c = amount,
				Billable__c = billable == true,
				Description__c = description == null ? null : description.abbreviate(255)
			);
			insert as user expense;
			return expense.Id;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** Monday on or before a day (null reads as today), whatever the user's locale says. */
	@TestVisible
	private static Date mondayOf(Date day) {
		Date base = day == null ? Date.today() : day;
		return base.addDays(-Math.mod(A_MONDAY.daysBetween(base), 7));
	}

	private static Integer move(Date weekStart, List<String> before, String target) {
		requireEnabled();
		Id me = UserInfo.getUserId();
		Date monday = mondayOf(weekStart);
		List<SObject> moved = new List<SObject>();
		for (Time_Entry__c entry : [
			SELECT Id
			FROM Time_Entry__c
			WHERE
				User__c = :me
				AND Date__c >= :monday
				AND Date__c <= :monday.addDays(6)
				AND Status__c IN :before
			WITH USER_MODE
			LIMIT 500
		]) {
			moved.add(new Time_Entry__c(Id = entry.Id, Status__c = target));
		}
		if (ProjectsSettings.expensesEnabled()) {
			for (Project_Expense__c expense : [
				SELECT Id
				FROM Project_Expense__c
				WHERE
					User__c = :me
					AND Date__c >= :monday
					AND Date__c <= :monday.addDays(6)
					AND Status__c IN :before
				WITH USER_MODE
				LIMIT 200
			]) {
				moved.add(new Project_Expense__c(Id = expense.Id, Status__c = target));
			}
		}
		update as user moved;
		return moved.size();
	}

	private static void requireEnabled() {
		if (!ProjectsSettings.approvalsEnabled()) {
			throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Approvals_Off'));
		}
	}

	private static AuraHandledException failure(Exception e) {
		if (!(e instanceof Projects.ProjectsException) && !(e instanceof DmlException)) {
			ErrorLogger.log(e, CONTEXT);
		}
		return UserErrors.wrapShowingDml(e, BarnHelp.text('Projects', 'Projects_Error_Generic'));
	}
}
