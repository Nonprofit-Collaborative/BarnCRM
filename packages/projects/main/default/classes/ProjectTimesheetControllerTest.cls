/**
 * The Timesheet page (PM-07, PM-08): the week starts on Monday, a person saves cells, submits and
 * recalls the week, adds an expense, cannot change submitted hours, and with approvals off the
 * page does nothing.
 */
@IsTest(testFor='ApexClass:ProjectTimesheetController, ApexClass:ProjectEntryHandler')
private class ProjectTimesheetControllerTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	private static void turnOn() {
		SettingsService.saveValues(
			'Projects_Settings__c',
			new Map<String, Object>{ 'Approvals_Enabled__c' => true, 'Expenses_Enabled__c' => true }
		);
	}

	private static ProjectTimesheetController.Cell cell(Id projectId, Date day, Decimal hours) {
		ProjectTimesheetController.Cell cell = new ProjectTimesheetController.Cell();
		cell.projectId = projectId;
		cell.workDate = day;
		cell.hours = hours;
		cell.billable = true;
		return cell;
	}

	@IsTest
	static void theWeekStartsOnMondayWhateverTheLocale() {
		System.runAs(ProjectsTestData.admin()) {
			Assert.areEqual(
				Date.newInstance(2026, 11, 9),
				ProjectTimesheetController.mondayOf(Date.newInstance(2026, 11, 12)),
				'Thursday'
			);
			Assert.areEqual(
				Date.newInstance(2026, 11, 9),
				ProjectTimesheetController.mondayOf(Date.newInstance(2026, 11, 15)),
				'Sunday belongs to the week before the next Monday'
			);
			Assert.areEqual(
				Date.newInstance(2026, 11, 9),
				ProjectTimesheetController.mondayOf(Date.newInstance(2026, 11, 9)),
				'Monday'
			);
		}
	}

	@IsTest
	static void withApprovalsOffThePageShowsNothingAndChangesNothing() {
		System.runAs(ProjectsTestData.admin()) {
			Project__c project = ProjectsTestData.project('Active', null);
			ProjectsTestData.time(project.Id, 2, true);

			ProjectTimesheetController.Week week = ProjectTimesheetController.getWeek(Date.today());
			Assert.isFalse(week.enabled, 'Off');
			Assert.isTrue(week.entries.isEmpty(), 'No rows are read');
			try {
				ProjectTimesheetController.saveWeek(
					new List<ProjectTimesheetController.Cell>{ cell(project.Id, Date.today(), 1) }
				);
				Assert.fail('Saving is refused while off');
			} catch (AuraHandledException refused) {
				Assert.isTrue(
					refused.getMessage().contains('Approve time and expenses'),
					refused.getMessage()
				);
			}
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Time_Entry__c WITH SYSTEM_MODE],
				'Nothing was added'
			);
		}
	}

	@IsTest
	static void aPersonSavesSubmitsAndRecallsAWeekAndCannotChangeSubmittedHours() {
		User staffer = ProjectsTestData.staff('Staffer');
		Project__c project;
		System.runAs(ProjectsTestData.admin()) {
			turnOn();
			project = ProjectsTestData.project('Active', null);
		}
		System.runAs(staffer) {
			Date monday = ProjectTimesheetController.mondayOf(Date.today());
			Test.startTest();
			Integer saved = ProjectTimesheetController.saveWeek(
				new List<ProjectTimesheetController.Cell>{
					cell(project.Id, monday, 4),
					cell(project.Id, monday.addDays(1), 3)
				}
			);
			ProjectTimesheetController.Week week = ProjectTimesheetController.getWeek(Date.today());
			Assert.areEqual(2, saved, 'Two new entries');
			Assert.areEqual(2, week.entries.size(), 'Both are on the page');
			Assert.areEqual('Open', week.entries[0].status, 'New time is Open');
			Assert.areEqual(1, week.projects.size(), 'The project to log to');

			ProjectTimesheetController.Cell edit = cell(project.Id, monday, 5);
			edit.id = week.entries[0].id;
			Assert.areEqual(
				1,
				ProjectTimesheetController.saveWeek(
					new List<ProjectTimesheetController.Cell>{ edit }
				),
				'Changed one'
			);

			Assert.areEqual(2, ProjectTimesheetController.submitWeek(monday), 'Both submitted');
			edit.hours = 6;
			try {
				ProjectTimesheetController.saveWeek(
					new List<ProjectTimesheetController.Cell>{ edit }
				);
				Assert.fail('Submitted hours are locked to the person');
			} catch (AuraHandledException locked) {
				Assert.isTrue(locked.getMessage().contains('locked'), locked.getMessage());
			}
			Assert.areEqual(2, ProjectTimesheetController.recallWeek(monday), 'Recalled');
			Assert.areEqual(
				1,
				ProjectTimesheetController.saveWeek(
					new List<ProjectTimesheetController.Cell>{ edit }
				),
				'Open again'
			);
			Test.stopTest();

			Assert.areEqual(
				6,
				[SELECT Hours__c FROM Time_Entry__c WHERE Id = :edit.id WITH SYSTEM_MODE].Hours__c,
				'The change was kept'
			);
		}
	}

	@IsTest
	static void aWeekWithNothingOpenCannotBeSubmittedAndHoursMustBePositive() {
		User staffer = ProjectsTestData.staff('Staffer');
		Project__c project;
		System.runAs(ProjectsTestData.admin()) {
			turnOn();
			project = ProjectsTestData.project('Active', null);
		}
		System.runAs(staffer) {
			try {
				ProjectTimesheetController.submitWeek(Date.today());
				Assert.fail('Nothing to submit');
			} catch (AuraHandledException refused) {
				Assert.isNotNull(refused.getMessage(), 'Told in words');
			}
			try {
				ProjectTimesheetController.saveWeek(
					new List<ProjectTimesheetController.Cell>{ cell(project.Id, Date.today(), 0) }
				);
				Assert.fail('Zero hours');
			} catch (AuraHandledException refused) {
				Assert.isNotNull(refused.getMessage(), 'Told in words');
			}
		}
	}

	@IsTest
	static void anExpenseIsAddedOpenAndGoesWithTheWeek() {
		User staffer = ProjectsTestData.staff('Staffer');
		Project__c project;
		System.runAs(ProjectsTestData.admin()) {
			turnOn();
			project = ProjectsTestData.project('Active', null);
		}
		System.runAs(staffer) {
			Id added = ProjectTimesheetController.addExpense(
				project.Id,
				Date.today(),
				'Travel',
				42.5,
				true,
				'Train'
			);
			ProjectTimesheetController.Week week = ProjectTimesheetController.getWeek(Date.today());
			Assert.areEqual(1, week.expenses.size(), 'On the page');
			Assert.areEqual('Open', week.expenses[0].status, 'Open (R-PM13)');
			Assert.areEqual(
				1,
				ProjectTimesheetController.submitWeek(Date.today()),
				'Submitted with the week'
			);
			Assert.areEqual(
				'Submitted',
				[SELECT Status__c FROM Project_Expense__c WHERE Id = :added WITH SYSTEM_MODE]
				.Status__c,
				'Submitted'
			);
		}
	}
}
