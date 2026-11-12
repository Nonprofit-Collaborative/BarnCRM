/**
 * Projects Home, the project board and the Projects at Risk card (ADR-0208
 * `0208-project-management-module.md`). Thin by design (plan Section 9.9): it returns plain
 * records and shapes, in user mode, and leaves grouping, progress and the timeline to
 * `c/projectsModel`. A refusal written for the person, or a save's own message, is shown as it
 * is; anything else is logged and shown as one message.
 */
public with sharing class ProjectsController {
	private static final String CONTEXT = 'ProjectsController';

	public class Board {
		@AuraEnabled
		public Project__c project;
		@AuraEnabled
		public List<Project_Phase__c> phases;
		@AuraEnabled
		public List<Project_Task__c> tasks;
		@AuraEnabled
		public Boolean timeTracking = false;
		@AuraEnabled
		public Boolean expensesEnabled = false;
		@AuraEnabled
		public Boolean approvalsEnabled = false;
		@AuraEnabled
		public Boolean canCreateTime = false;
		@AuraEnabled
		public Boolean canCreateExpense = false;
	}

	public class Home {
		@AuraEnabled
		public List<Project_Task__c> myTasks;
		@AuraEnabled
		public List<ProjectTemplates.Template> templates;
		@AuraEnabled
		public Boolean canManage = false;
		@AuraEnabled
		public Boolean timeTracking = false;
		@AuraEnabled
		public Boolean ratesEnabled = false;
	}

	@AuraEnabled
	public static Board getBoard(Id projectId) {
		try {
			Board board = new Board();
			board.project = [
				SELECT
					Id,
					Name,
					Status__c,
					Health__c,
					Health_Reasons__c,
					Start_Date__c,
					Target_Date__c,
					Is_Template__c,
					Tasks__c,
					Tasks_Done__c,
					Estimated_Hours__c,
					Actual_Hours__c,
					Budget_Hours__c,
					Change_Hours__c,
					Budget_Amount__c,
					Actual_Cost__c,
					Remaining_Budget__c
				FROM Project__c
				WHERE Id = :projectId
				WITH USER_MODE
			];
			board.phases = [
				SELECT Id, Name, Sort_Order__c, Start_Date__c, End_Date__c
				FROM Project_Phase__c
				WHERE Project__c = :projectId
				WITH USER_MODE
				ORDER BY Sort_Order__c NULLS LAST, Start_Date__c
				LIMIT 200
			];
			board.tasks = [
				SELECT
					Id,
					Name,
					Phase__c,
					Status__c,
					Milestone__c,
					Start_Date__c,
					Due_Date__c,
					Completed_Date__c,
					Estimated_Hours__c,
					Sort_Order__c,
					Assigned_To__r.Name
				FROM Project_Task__c
				WHERE Project__c = :projectId
				WITH USER_MODE
				ORDER BY Sort_Order__c NULLS LAST, Due_Date__c
				LIMIT 2000
			];
			board.timeTracking = ProjectsSettings.timeTracking();
			board.expensesEnabled = ProjectsSettings.expensesEnabled();
			board.approvalsEnabled = ProjectsSettings.approvalsEnabled();
			// Read Only users see the board but not the buttons that would fail for them.
			board.canCreateTime = Schema.SObjectType.Time_Entry__c.isCreateable();
			board.canCreateExpense = Schema.SObjectType.Project_Expense__c.isCreateable();
			return board;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** Sets a task's status; Done stamps Completed Date with today, anything else clears it (R-PM4). */
	@AuraEnabled
	public static void setTaskStatus(Id taskId, String status) {
		try {
			update as user new Project_Task__c(
				Id = taskId,
				Status__c = status,
				Completed_Date__c = status == Projects.DONE ? Date.today() : null
			);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Id addTask(
		Id projectId,
		Id phaseId,
		String name,
		Date dueDate,
		Boolean milestone
	) {
		try {
			if (String.isBlank(name)) {
				throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Task_NameNeeded'));
			}
			Project_Task__c task = new Project_Task__c(
				Project__c = projectId,
				Phase__c = phaseId,
				Name = name.trim().abbreviate(80),
				Status__c = 'Not Started',
				Due_Date__c = dueDate,
				Milestone__c = milestone == true
			);
			insert as user task;
			return task.Id;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** Log Time: hours for the running user on a day, on a task or the project. */
	@AuraEnabled
	public static Id logTime(
		Id projectId,
		Id taskId,
		Date workDate,
		Decimal hours,
		Boolean billable,
		String notes
	) {
		try {
			if (!ProjectsSettings.timeTracking()) {
				throw Projects.refuse(BarnHelp.text('Projects', 'Projects_Time_Off'));
			}
			Time_Entry__c entry = new Time_Entry__c(
				Project__c = projectId,
				Task__c = taskId,
				User__c = UserInfo.getUserId(),
				Date__c = workDate == null ? Date.today() : workDate,
				Hours__c = hours,
				Billable__c = billable == true,
				Notes__c = notes == null ? null : notes.abbreviate(255)
			);
			insert as user entry;
			return entry.Id;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static void refreshHealth(Id projectId) {
		try {
			ProjectHealth.refresh(projectId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Id draftStatusUpdate(Id projectId) {
		try {
			return ProjectReporting.draftStatusUpdate(projectId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Home getHome() {
		try {
			Home home = new Home();
			home.canManage = Projects.canManage();
			home.timeTracking = ProjectsSettings.timeTracking();
			home.ratesEnabled = ProjectsSettings.ratesEnabled();
			home.templates = ProjectTemplates.available();
			home.myTasks = [
				SELECT Id, Name, Status__c, Milestone__c, Due_Date__c, Project__c, Project__r.Name
				FROM Project_Task__c
				WHERE
					Assigned_To__c = :UserInfo.getUserId()
					AND Status__c NOT IN ('Done', 'Cancelled')
					AND Project__r.Is_Template__c = FALSE
				WITH USER_MODE
				ORDER BY Due_Date__c NULLS LAST
				LIMIT 100
			];
			return home;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** The Projects at Risk card: Active projects At Risk or Off Track, worst first. */
	@AuraEnabled
	public static List<Project__c> getAtRisk(Boolean onlyMine) {
		try {
			Id me = UserInfo.getUserId();
			List<Project__c> rows = new List<Project__c>();
			for (Project__c project : [
				SELECT Id, Name, Health__c, Health_Reasons__c, Target_Date__c, OwnerId, Owner.Name
				FROM Project__c
				WHERE
					Status__c = :Projects.ACTIVE
					AND Is_Template__c = FALSE
					AND Health__c IN ('At Risk', 'Off Track')
				WITH USER_MODE
				ORDER BY Health__c DESC, Target_Date__c NULLS LAST
				LIMIT 200
			]) {
				if (onlyMine != true || project.OwnerId == me) {
					rows.add(project);
				}
			}
			return rows;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Id createFromTemplate(
		String templateKey,
		String name,
		Date startDate,
		Id accountId,
		Id contactId
	) {
		try {
			return ProjectTemplates.create(templateKey, name, startDate, accountId, contactId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static List<ProjectReporting.Utilization> getUtilization(Date fromDate, Date toDate) {
		try {
			return ProjectReporting.utilization(fromDate, toDate);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** Apply Rates (Manage Projects): fills the rates of entries logged before rates were on. */
	@AuraEnabled
	public static Integer applyRates() {
		try {
			return ProjectRates.applyRates();
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static List<Map<String, Object>> exportBillable(
		Date fromDate,
		Date toDate,
		Boolean includeExported
	) {
		try {
			return ProjectReporting.exportBillable(fromDate, toDate, includeExported);
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
