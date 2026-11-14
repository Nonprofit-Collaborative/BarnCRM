/**
 * Resource management (PM-09): nothing happens with Manage resources off; people are kept one
 * row each; the allocation call returns active people, planned assignments and counted logged
 * hours only; Fill makes the assignment and marks the request Filled (R-PM15); and utilization
 * uses a person's own capacity and counted time (R-PM5, R-PM14).
 */
@IsTest(testFor='ApexClass:ProjectStaffingController, ApexClass:ProjectReporting')
private class ProjectStaffingControllerTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	private static void turnOn() {
		SettingsService.saveValues(
			ProjectsSettings.SETTINGS_OBJECT,
			new Map<String, Object>{ 'Resources_Enabled__c' => true }
		);
	}

	private static Project_Resource__c resource(Id userId, String skills, Decimal capacity) {
		Project_Resource__c row = new Project_Resource__c(
			User__c = userId,
			Skills__c = skills,
			Weekly_Capacity_Hours__c = capacity,
			Active__c = true
		);
		insert row;
		return row;
	}

	private static Resource_Request__c request(Id projectId, Date starts, Date ends) {
		Resource_Request__c row = new Resource_Request__c(
			Project__c = projectId,
			Role__c = 'Data Migration',
			Skills__c = 'Data Migration',
			Hours__c = 20,
			Start_Date__c = starts,
			End_Date__c = ends
		);
		insert row;
		return row;
	}

	@IsTest
	static void nothingChangesWhileManageResourcesIsOff() {
		System.runAs(ProjectsTestData.admin()) {
			Project__c project = ProjectsTestData.project('Active', null);
			Date monday = Date.today().toStartOfWeek();
			request(project.Id, monday, monday.addDays(4));

			Test.startTest();
			ProjectStaffingController.Staffing staffing = ProjectStaffingController.getStaffing();
			ProjectStaffingController.Allocation view = ProjectStaffingController.getAllocation(
				monday,
				monday.addDays(6)
			);
			Test.stopTest();

			Assert.isFalse(staffing.enabled, 'Ships off');
			Assert.isTrue(staffing.resources.isEmpty(), 'No people');
			Assert.isTrue(staffing.requests.isEmpty(), 'No requests are read');
			Assert.isTrue(view.resources.isEmpty(), 'No allocation');
			Assert.isTrue(view.requests.isEmpty(), 'No demand');
			try {
				ProjectStaffingController.saveResource(UserInfo.getUserId(), null, 30, null, true);
				Assert.fail('Saving is refused while off');
			} catch (AuraHandledException expected) {
				Assert.areEqual(
					BarnHelp.text('Projects', 'Projects_Staffing_Off'),
					expected.getMessage(),
					'In words'
				);
			}
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Project_Resource__c WITH SYSTEM_MODE],
				'Nothing was written'
			);
		}
	}

	@IsTest
	static void aPersonIsOneRowAndStaffCanKeepTheirOwn() {
		User staff = ProjectsTestData.staff('Resource');
		System.runAs(ProjectsTestData.admin()) {
			turnOn();
		}
		System.runAs(staff) {
			Test.startTest();
			Id first = ProjectStaffingController.saveResource(
				staff.Id,
				'Data Migration;Training',
				32,
				'Consultant',
				true
			);
			Id second = ProjectStaffingController.saveResource(
				staff.Id,
				'Training',
				null,
				null,
				false
			);
			ProjectStaffingController.Staffing staffing = ProjectStaffingController.getStaffing();
			Test.stopTest();

			Assert.areEqual(first, second, 'The same row is edited');
			Assert.areEqual(1, staffing.resources.size(), 'One row per person');
			Project_Resource__c saved = staffing.resources[0];
			Assert.areEqual('Training', saved.Skills__c, 'Skills replaced');
			Assert.isNull(saved.Weekly_Capacity_Hours__c, 'Blank uses the setting');
			Assert.isFalse(saved.Active__c, 'Deactivated');
			Assert.areEqual(40, staffing.defaultCapacity, 'The shipped capacity setting');
			Assert.isTrue(staffing.skills.contains('Data Migration'), 'The skill list');
			try {
				ProjectStaffingController.saveResource(staff.Id, null, 200, null, true);
				Assert.fail('A week has 168 hours');
			} catch (AuraHandledException expected) {
				Assert.isTrue(expected.getMessage().contains('168'), 'The rule message');
			}
		}
	}

	@IsTest
	static void allocationReturnsActivePeoplePlansAndCountedTimeOnly() {
		System.runAs(ProjectsTestData.admin()) {
			turnOn();
			Project__c project = ProjectsTestData.project('Active', null);
			Project__c done = ProjectsTestData.project('Completed', null);
			Date monday = Date.today().toStartOfWeek();
			Project_Resource__c active = resource(UserInfo.getUserId(), 'Training', 30);
			User other = ProjectsTestData.staff('Gone');
			insert new Project_Resource__c(User__c = other.Id, Active__c = false);
			insert new List<Project_Assignment__c>{
				new Project_Assignment__c(
					Project__c = project.Id,
					Resource__c = UserInfo.getUserId(),
					Planned_Hours__c = 20,
					Start_Date__c = monday,
					End_Date__c = monday.addDays(4)
				),
				new Project_Assignment__c(
					Project__c = done.Id,
					Resource__c = UserInfo.getUserId(),
					Planned_Hours__c = 99,
					Start_Date__c = monday,
					End_Date__c = monday.addDays(4)
				)
			};
			ProjectsTestData.time(project.Id, 5, true);
			Time_Entry__c open = ProjectsTestData.time(project.Id, 3, true);
			update new Time_Entry__c(Id = open.Id, Status__c = 'Open');
			Resource_Request__c wanted = request(project.Id, monday, monday.addDays(4));
			request(project.Id, monday.addDays(60), monday.addDays(64));

			Test.startTest();
			ProjectStaffingController.Allocation view = ProjectStaffingController.getAllocation(
				monday,
				monday.addDays(6)
			);
			Test.stopTest();

			Assert.areEqual(1, view.resources.size(), 'Only the active person');
			Assert.areEqual(active.Id, view.resources[0].Id, 'The active row');
			Assert.areEqual(1, view.assignments.size(), 'Completed projects do not plan hours');
			Assert.areEqual(20, view.assignments[0].Planned_Hours__c, 'The planned hours');
			Assert.areEqual(1, view.logged.size(), 'One day of counted time');
			Assert.areEqual(5, (Decimal) view.logged[0].get('hours'), 'The Open entry is left out');
			Assert.areEqual(1, view.requests.size(), 'Only the request in these weeks');
			Assert.areEqual(wanted.Id, view.requests[0].Id, 'The open request');
			try {
				ProjectStaffingController.getAllocation(monday, monday.addDays(400));
				Assert.fail('More than 26 weeks is refused');
			} catch (AuraHandledException expected) {
				Assert.areEqual(
					BarnHelp.text('Projects', 'Projects_Allocation_Range'),
					expected.getMessage(),
					'In words'
				);
			}
		}
	}

	@IsTest
	static void fillMakesTheAssignmentAndMarksTheRequestFilled() {
		System.runAs(ProjectsTestData.admin()) {
			turnOn();
			Project__c project = ProjectsTestData.project('Active', null);
			Date monday = Date.today().toStartOfWeek();
			resource(UserInfo.getUserId(), 'Data Migration', null);
			User stranger = ProjectsTestData.staff('Stranger');
			Resource_Request__c wanted = request(project.Id, monday, monday.addDays(4));

			Test.startTest();
			try {
				ProjectStaffingController.fill(wanted.Id, stranger.Id);
				Assert.fail('Only a person with a Project Resource can be picked');
			} catch (AuraHandledException expected) {
				Assert.areEqual(
					BarnHelp.text('Projects', 'Projects_Staffing_NotResource'),
					expected.getMessage(),
					'In words'
				);
			}
			Id assignmentId = ProjectStaffingController.fill(wanted.Id, UserInfo.getUserId());
			Test.stopTest();

			Project_Assignment__c assignment = [
				SELECT
					Project__c,
					Resource__c,
					Role__c,
					Planned_Hours__c,
					Start_Date__c,
					End_Date__c
				FROM Project_Assignment__c
				WHERE Id = :assignmentId
				WITH SYSTEM_MODE
			];
			Assert.areEqual(project.Id, assignment.Project__c, 'On the request project');
			Assert.areEqual(UserInfo.getUserId(), assignment.Resource__c, 'The chosen person');
			Assert.areEqual('Data Migration', assignment.Role__c, 'The request role');
			Assert.areEqual(20, assignment.Planned_Hours__c, 'The request hours');
			Assert.areEqual(monday, assignment.Start_Date__c, 'The request start');
			Assert.areEqual(monday.addDays(4), assignment.End_Date__c, 'The request end');
			Resource_Request__c filled = [
				SELECT Status__c, Assignment__c
				FROM Resource_Request__c
				WHERE Id = :wanted.Id
				WITH SYSTEM_MODE
			];
			Assert.areEqual('Filled', filled.Status__c, 'Filled');
			Assert.areEqual(assignmentId, filled.Assignment__c, 'Linked');
			try {
				ProjectStaffingController.fill(wanted.Id, UserInfo.getUserId());
				Assert.fail('A filled request cannot be filled again');
			} catch (AuraHandledException expected) {
				Assert.areEqual(
					BarnHelp.text('Projects', 'Projects_Staffing_NotOpen'),
					expected.getMessage(),
					'In words'
				);
			}
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Project_Assignment__c WITH SYSTEM_MODE],
				'No second assignment'
			);
		}
	}

	@IsTest
	static void utilizationUsesTheirOwnCapacityAndCountedTime() {
		System.runAs(ProjectsTestData.admin()) {
			Project__c project = ProjectsTestData.project('Active', null);
			ProjectsTestData.time(project.Id, 6, true);
			Time_Entry__c open = ProjectsTestData.time(project.Id, 4, true);
			update new Time_Entry__c(Id = open.Id, Status__c = 'Open');
			Date monday = Date.today().toStartOfWeek();

			List<ProjectReporting.Utilization> before = ProjectReporting.utilization(
				monday,
				monday.addDays(6)
			);
			turnOn();
			resource(UserInfo.getUserId(), null, 24);
			List<ProjectReporting.Utilization> after = ProjectReporting.utilization(
				monday,
				monday.addDays(6)
			);

			Assert.areEqual(6, before[0].logged, 'Open time is not logged');
			Assert.areEqual(40, before[0].capacity, 'The setting while the part is off');
			Assert.areEqual(24, after[0].capacity, 'Their own capacity with the part on');
			Assert.areEqual(6, after[0].logged, 'Counted time only');
		}
	}
}
