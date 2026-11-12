/**
 * Maria closes her books each month (PM-11, R-PM19): the morning run stores one Project Revenue
 * row per billed project for the month just closed, by billing type, and never moves it; late
 * approved time lands in the next month; Recognize Revenue redoes a month. With Show financials
 * and recognize revenue off, nothing is written.
 */
@IsTest(
	testFor='ApexClass:ProjectRevenue, ApexClass:ProjectsNightlyJobProvider, ApexClass:ProjectBilling'
)
public class ProjectRevenueTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	public static void revenue(Boolean turnedOn) {
		OrgSettingsSystemWriter.save(
			Projects_Settings__c.SObjectType,
			new Map<Schema.SObjectField, Object>{
				Projects_Settings__c.Revenue_Enabled__c => turnedOn
			}
		);
		SettingsService.clearCaches();
	}

	private static Date lastMonth() {
		return Date.today().toStartOfMonth().addMonths(-1);
	}

	private static Time_Entry__c entry(Id projectId, Decimal hours, Date day) {
		return new Time_Entry__c(
			Project__c = projectId,
			User__c = UserInfo.getUserId(),
			Date__c = day,
			Hours__c = hours,
			Billable__c = true,
			Cost_Rate__c = 40
		);
	}

	@IsTest
	static void theMorningRunStoresClosedMonthsInBulkAndNeverMovesThem() {
		System.runAs(ProjectsTestData.admin()) {
			revenue(true);
			List<Project__c> projects = new List<Project__c>();
			for (Integer i = 0; i < 60; i++) {
				projects.add(
					new Project__c(
						Name = 'Client ' + i,
						Status__c = 'Active',
						Start_Date__c = lastMonth(),
						Hourly_Rate__c = 100
					)
				);
			}
			Project__c notBilled = new Project__c(
				Name = 'Internal',
				Status__c = 'Active',
				Billing_Type__c = 'Not Billed'
			);
			projects.add(notBilled);
			insert projects;
			List<Time_Entry__c> entries = new List<Time_Entry__c>();
			for (Integer i = 0; i < 60; i++) {
				entries.add(entry(projects[i].Id, 2, lastMonth().addDays(3)));
				entries.add(entry(projects[i].Id, 1, Date.today().addDays(1)));
			}
			insert entries;

			Test.startTest();
			new ProjectsNightlyJobProvider().nightlySteps()[1].run();
			Test.stopTest();

			Assert.areEqual(
				60,
				[SELECT COUNT() FROM Project_Revenue__c],
				'One row per billed project'
			);
			Project_Revenue__c row = [
				SELECT Recognized_Amount__c, Cost_Amount__c, Method__c, Month__c
				FROM Project_Revenue__c
				WHERE Project__c = :projects[0].Id
			];
			Assert.areEqual(200, row.Recognized_Amount__c, 'Two hours at the Hourly Rate');
			Assert.areEqual(80, row.Cost_Amount__c, 'Two hours at the cost rate');
			Assert.areEqual('Time and Materials', row.Method__c, 'Blank bills by time');
			Assert.areEqual(lastMonth(), row.Month__c, 'The month just closed');

			insert entry(projects[0].Id, 3, lastMonth().addDays(5));
			new ProjectRevenue(lastMonth(), null, 0).execute((QueueableContext) null);
			Assert.areEqual(
				200,
				[
					SELECT Recognized_Amount__c
					FROM Project_Revenue__c
					WHERE Project__c = :projects[0].Id
				]
				.Recognized_Amount__c,
				'A closed month never moves'
			);
		}
	}

	@IsTest
	static void lateTimeLandsInTheNextMonthAndFixedFeeAndRetainerEarnTheirWay() {
		System.runAs(ProjectsTestData.admin()) {
			revenue(true);
			Date twoAgo = lastMonth().addMonths(-1);
			Project__c tm = new Project__c(
				Name = 'T and M',
				Status__c = 'Active',
				Start_Date__c = twoAgo,
				Hourly_Rate__c = 100
			);
			Project__c fixed = new Project__c(
				Name = 'Fixed',
				Status__c = 'Active',
				Billing_Type__c = 'Fixed Fee',
				Budget_Amount__c = 1000,
				Start_Date__c = twoAgo
			);
			Project__c retainer = new Project__c(
				Name = 'Retainer',
				Status__c = 'Active',
				Billing_Type__c = 'Retainer',
				Retainer_Amount__c = 500,
				Start_Date__c = twoAgo
			);
			insert new List<Project__c>{ tm, fixed, retainer };
			insert new List<Project_Task__c>{
				new Project_Task__c(Project__c = fixed.Id, Name = 'Design', Status__c = 'Done'),
				new Project_Task__c(
					Project__c = fixed.Id,
					Name = 'Build',
					Status__c = 'Not Started'
				)
			};
			insert entry(tm.Id, 1, twoAgo);

			Test.startTest();
			ProjectRevenue.recognizeMonth(tm.Id, twoAgo);
			insert entry(tm.Id, 2, twoAgo.addDays(1));
			Id redone = ProjectRevenue.recognizeMonth(tm.Id, lastMonth());
			ProjectRevenue.recognizeMonth(fixed.Id, lastMonth());
			ProjectRevenue.recognizeMonth(retainer.Id, lastMonth());
			Id again = ProjectRevenue.recognizeMonth(tm.Id, lastMonth());
			Test.stopTest();

			Assert.areEqual(redone, again, 'A rerun updates the same row');
			Assert.areEqual(
				200,
				[SELECT Recognized_Amount__c FROM Project_Revenue__c WHERE Id = :redone]
				.Recognized_Amount__c,
				'Late time lands in the next closed month'
			);
			Project_Revenue__c fee = [
				SELECT Recognized_Amount__c, Percent_Complete__c
				FROM Project_Revenue__c
				WHERE Project__c = :fixed.Id
			];
			Assert.areEqual(500, fee.Recognized_Amount__c, 'Fee times percent complete');
			Assert.areEqual(50, fee.Percent_Complete__c, 'Kept on the row');
			Assert.areEqual(
				1000,
				[
					SELECT Recognized_Amount__c
					FROM Project_Revenue__c
					WHERE Project__c = :retainer.Id
				]
				.Recognized_Amount__c,
				'Two months of retainer'
			);
			Assert.areEqual(
				1000,
				[SELECT Recognized_Revenue__c FROM Project__c WHERE Id = :retainer.Id]
				.Recognized_Revenue__c,
				'Rolled up on the project'
			);
		}
	}

	@IsTest
	static void nothingIsWrittenWhenOffForTheOpenMonthOrForStaff() {
		User staff = ProjectsTestData.staff('Reader');
		Project__c project;
		System.runAs(ProjectsTestData.admin()) {
			project = ProjectsTestData.project('Active', 10);
			Assert.isFalse(ProjectRevenue.step().active, 'The step sleeps while off');
			new ProjectRevenue().execute((SchedulableContext) null);
			try {
				ProjectRevenue.recognizeMonth(project.Id, lastMonth());
				Assert.fail('Off');
			} catch (Projects.ProjectsException expected) {
				Assert.isNotNull(expected.getMessage(), 'Says so');
			}
			revenue(true);
			try {
				ProjectRevenue.recognizeMonth(project.Id, Date.today());
				Assert.fail('The open month is never stored');
			} catch (Projects.ProjectsException expected) {
				Assert.isNotNull(expected.getMessage(), 'Says so');
			}
		}
		System.runAs(staff) {
			Test.startTest();
			try {
				ProjectRevenue.recognizeMonth(project.Id, lastMonth());
				Assert.fail('Staff cannot recognize');
			} catch (Projects.ProjectsException expected) {
				Assert.isNotNull(expected.getMessage(), 'Refused in words');
			}
			Test.stopTest();
		}
		Assert.areEqual(0, [SELECT COUNT() FROM Project_Revenue__c], 'Nothing written');
	}
}
