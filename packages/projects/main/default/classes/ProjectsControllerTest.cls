/**
 * Projects Home, the project board and the at-risk card return what they draw; task status,
 * Log Time, Draft Status Update (R-PM8), utilization (R-PM5) and the billable export (R-PM7)
 * do what the guides say; and a refusal reaches the screen in words.
 */
@IsTest(testFor='ApexClass:ProjectsController, ApexClass:ProjectReporting, ApexClass:Projects')
private class ProjectsControllerTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	@IsTest
	static void theBoardAndHomeReturnWhatTheyDraw() {
		System.runAs(ProjectsTestData.admin()) {
			Project__c project = ProjectsTestData.project('Active', null);
			Project_Phase__c phase = new Project_Phase__c(
				Project__c = project.Id,
				Name = 'Build',
				Sort_Order__c = 10
			);
			insert phase;
			Project_Task__c task = ProjectsTestData.task(
				project.Id,
				'Configure',
				Date.today().addDays(3),
				false
			);

			Test.startTest();
			Id added = ProjectsController.addTask(
				project.Id,
				phase.Id,
				'Go-Live',
				Date.today().addDays(5),
				true
			);
			ProjectsController.setTaskStatus(task.Id, 'Done');
			ProjectsController.Board board = ProjectsController.getBoard(project.Id);
			ProjectsController.Home home = ProjectsController.getHome();
			Test.stopTest();

			Assert.areEqual(1, board.phases.size(), 'The phase');
			Assert.areEqual(2, board.tasks.size(), 'Both tasks');
			Assert.areEqual(1, board.project.Tasks_Done__c, 'One done');
			Assert.isTrue(board.timeTracking, 'Time tracking ships on');
			Project_Task__c done = [
				SELECT Completed_Date__c
				FROM Project_Task__c
				WHERE Id = :task.Id
				WITH SYSTEM_MODE
			];
			Assert.areEqual(Date.today(), done.Completed_Date__c, 'Done stamps today (R-PM4)');
			Assert.isNotNull(added, 'Add Task');
			Assert.isTrue(home.canManage, 'Admin manages');
			Assert.areEqual(2, home.templates.size(), 'The two shipped templates');
			Assert.areEqual(
				0,
				home.myTasks.size(),
				'Assigned task is done; the added one has no owner'
			);
		}
	}

	@IsTest
	static void logTimeDraftAndTheAtRiskCard() {
		System.runAs(ProjectsTestData.admin()) {
			Project__c project = ProjectsTestData.project('Active', 10);
			Project_Task__c finished = ProjectsTestData.task(
				project.Id,
				'Interviews',
				Date.today(),
				false
			);
			ProjectsTestData.task(project.Id, 'Design sign-off', Date.today().addDays(7), true);
			Project_Task__c blocked = ProjectsTestData.task(
				project.Id,
				'Data cleanup',
				Date.today().addDays(-10),
				false
			);
			update new Project_Task__c(Id = blocked.Id, Status__c = 'Blocked');

			Test.startTest();
			ProjectsController.setTaskStatus(finished.Id, 'Done');
			ProjectsController.logTime(project.Id, finished.Id, null, 4, true, 'Interviews');
			ProjectsController.refreshHealth(project.Id);
			Id updateId = ProjectsController.draftStatusUpdate(project.Id);
			List<Project__c> atRisk = ProjectsController.getAtRisk(true);
			Test.stopTest();

			Project_Status_Update__c draft = [
				SELECT
					Health__c,
					Percent_Complete__c,
					Actual_Hours__c,
					Summary__c,
					Accomplishments__c,
					Next_Steps__c,
					Risks__c
				FROM Project_Status_Update__c
				WHERE Id = :updateId
				WITH SYSTEM_MODE
			];
			Assert.areEqual('At Risk', draft.Health__c, 'The blocked task is ten days late');
			Assert.areEqual(33, draft.Percent_Complete__c, 'One of three tasks');
			Assert.areEqual(4, draft.Actual_Hours__c, 'The logged hours');
			Assert.isTrue(draft.Accomplishments__c.contains('Interviews'), 'Done since the start');
			Assert.isTrue(
				draft.Next_Steps__c.contains('Design sign-off'),
				'Due in the next 14 days'
			);
			Assert.isTrue(draft.Risks__c.contains('Data cleanup'), 'Blocked and late');
			Assert.isNotNull(draft.Summary__c, 'A summary line');
			Assert.areEqual(1, atRisk.size(), 'On the at-risk card, only mine');
		}
	}

	@IsTest
	static void utilizationAndTheBillableExport() {
		System.runAs(ProjectsTestData.admin()) {
			Project__c project = ProjectsTestData.project('Active', null);
			ProjectsTestData.time(project.Id, 6, true);
			ProjectsTestData.time(project.Id, 2, false);
			Date monday = Date.today().toStartOfWeek();
			insert new Project_Assignment__c(
				Project__c = project.Id,
				Resource__c = UserInfo.getUserId(),
				Planned_Hours__c = 28,
				Start_Date__c = monday,
				End_Date__c = monday.addDays(13)
			);

			Test.startTest();
			List<ProjectReporting.Utilization> people = ProjectsController.getUtilization(
				monday,
				monday.addDays(6)
			);
			List<Map<String, Object>> first = ProjectsController.exportBillable(
				Date.today(),
				Date.today(),
				false
			);
			List<Map<String, Object>> second = ProjectsController.exportBillable(
				Date.today(),
				Date.today(),
				false
			);
			List<Map<String, Object>> again = ProjectsController.exportBillable(
				Date.today(),
				Date.today(),
				true
			);
			Test.stopTest();

			Assert.areEqual(1, people.size(), 'One person');
			Assert.areEqual(8, people[0].logged, 'All hours');
			Assert.areEqual(6, people[0].billable, 'Billable hours');
			Assert.areEqual(14, people[0].planned, 'Half the assignment falls in the week');
			Assert.areEqual(40, people[0].capacity, 'One week of capacity');
			Assert.areEqual(1, first.size(), 'Only the billable entry');
			Assert.areEqual(600, first[0].get('amount'), 'Hours times the project rate');
			Assert.areEqual(0, second.size(), 'Exported entries are skipped');
			Assert.areEqual(1, again.size(), 'Unless asked for');
		}
	}

	@IsTest
	static void aRefusalIsShownInWords() {
		User staff = ProjectsTestData.staff('Staff');
		Project__c project;
		System.runAs(ProjectsTestData.admin()) {
			project = ProjectsTestData.project('Active', null);
		}
		System.runAs(staff) {
			try {
				ProjectsController.exportBillable(Date.today(), Date.today(), false);
				Assert.fail('Staff cannot export');
			} catch (AuraHandledException expected) {
				Assert.areEqual(
					BarnHelp.text('Projects', 'Projects_Error_NoPermission'),
					expected.getMessage(),
					'In words'
				);
			}
			try {
				ProjectsController.getUtilization(Date.today(), Date.today().addDays(-1));
				Assert.fail('A backwards range is refused');
			} catch (AuraHandledException expected) {
				Assert.areEqual(
					BarnHelp.text('Projects', 'Projects_Range_Invalid'),
					expected.getMessage(),
					'In words'
				);
			}
			try {
				ProjectsController.logTime(project.Id, null, Date.today(), 0, false, null);
				Assert.fail('Zero hours are refused');
			} catch (AuraHandledException expected) {
				Assert.isTrue(
					expected.getMessage().contains('24'),
					'The validation rule message (R-PM6)'
				);
			}
		}
	}
}
