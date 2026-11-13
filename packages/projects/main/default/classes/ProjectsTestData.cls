/** Records the Project Management tests share: users, an active project and its tasks. */
@IsTest
public class ProjectsTestData {
	public static final String ADMIN_SET = 'Projects_Admin';

	public static User admin() {
		return TestUsers.adminWith(ADMIN_SET);
	}

	/** A Team Member-like user: Projects Staff only, no Manage Projects. */
	public static User staff(String lastName) {
		return TestUsers.standardUserWith(lastName, new List<String>{ 'Projects_Staff' });
	}

	/**
	 * The shipped Requests queue, by its developer name. A test compares a request's OwnerId
	 * with it rather than reading Owner.Type, which came back blank for a queue owner on the
	 * barn-platform gate run (2026-11-13).
	 */
	public static Id requestsQueueId() {
		return [
			SELECT Id
			FROM Group
			WHERE DeveloperName = 'Project_Requests' AND Type = 'Queue'
			WITH SYSTEM_MODE
			LIMIT 1
		]
		.Id;
	}

	public static Project__c project(String status, Decimal budgetHours) {
		Project__c project = new Project__c(
			Name = 'Test Rollout',
			Type__c = 'Salesforce Implementation',
			Status__c = status,
			Start_Date__c = Date.today().addDays(-30),
			Target_Date__c = Date.today().addDays(30),
			Budget_Hours__c = budgetHours,
			Hourly_Rate__c = 100
		);
		insert project;
		return project;
	}

	public static Project_Task__c task(Id projectId, String name, Date due, Boolean milestone) {
		Project_Task__c task = new Project_Task__c(
			Project__c = projectId,
			Name = name,
			Status__c = 'Not Started',
			Due_Date__c = due,
			Milestone__c = milestone,
			Assigned_To__c = UserInfo.getUserId()
		);
		insert task;
		return task;
	}

	public static Time_Entry__c time(Id projectId, Decimal hours, Boolean billable) {
		Time_Entry__c entry = new Time_Entry__c(
			Project__c = projectId,
			User__c = UserInfo.getUserId(),
			Date__c = Date.today(),
			Hours__c = hours,
			Billable__c = billable
		);
		insert entry;
		return entry;
	}
}
