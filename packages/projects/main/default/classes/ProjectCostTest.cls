/**
 * A project's stored Actual Cost gives what the formula it replaces gave: Actual Hours times the
 * Hourly Rate with rate cards off (blank without a rate), Time Amount with them on; it follows
 * each time entry and rate change, and ProjectCostSync puts every project right after the
 * setting changes.
 */
@IsTest(testFor='ApexClass:ProjectCostHandler, ApexClass:ProjectCostSync, ApexTrigger:ProjectTrigger')
private class ProjectCostTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	private static Project__c read(Id projectId) {
		return [
			SELECT Actual_Cost_Amount__c, Actual_Hours__c, Time_Amount__c, Hourly_Rate__c
			FROM Project__c
			WHERE Id = :projectId
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void withRateCardsOffTheCostIsHoursTimesTheProjectRate() {
		System.runAs(ProjectsTestData.admin()) {
			Project__c project = ProjectsTestData.project('Active', 10);
			Assert.areEqual(0, read(project.Id).Actual_Cost_Amount__c, 'No time yet: nothing spent');

			ProjectsTestData.time(project.Id, 3, true);
			Assert.areEqual(300, read(project.Id).Actual_Cost_Amount__c, 'A time entry moves the cost');

			update new Project__c(Id = project.Id, Hourly_Rate__c = 50);
			Assert.areEqual(150, read(project.Id).Actual_Cost_Amount__c, 'And so does the rate');

			update new Project__c(Id = project.Id, Hourly_Rate__c = null);
			Assert.isNull(read(project.Id).Actual_Cost_Amount__c, 'Blank without a rate, as before');
		}
	}

	@IsTest
	static void withRateCardsOnTheCostIsTheTimeAmount() {
		System.runAs(ProjectsTestData.admin()) {
			ModuleSettings.setForTest('Projects_Rates_Enabled', true);
			Project__c project = ProjectsTestData.project('Active', 10);
			ProjectsTestData.time(project.Id, 2, true);

			Project__c saved = read(project.Id);
			Assert.isTrue(saved.Time_Amount__c > 0, 'The entry was priced');
			Assert.areEqual(saved.Time_Amount__c, saved.Actual_Cost_Amount__c, 'The cost is the time amount');
		}
	}

	@IsTest
	static void theSyncPutsEveryProjectRightOnceTheSettingChanges() {
		System.runAs(ProjectsTestData.admin()) {
			Project__c project = ProjectsTestData.project('Active', 10);
			ProjectsTestData.time(project.Id, 3, true);
			update new Project__c(Id = project.Id, Hourly_Rate__c = 40);
			Assert.areEqual(120, read(project.Id).Actual_Cost_Amount__c, 'Stored with rate cards off');

			ModuleSettings.setForTest('Projects_Rates_Enabled', true);
			Test.startTest();
			ProjectCostSync.startIfRatesChanged();
			Test.stopTest();

			Project__c saved = read(project.Id);
			Assert.areEqual(saved.Time_Amount__c, saved.Actual_Cost_Amount__c, 'Put right for rate cards on');
			SettingsState.clearCache();
			Assert.isTrue(SettingsState.flag(ProjectCostSync.APPLIED_KEY), 'And the pass notes what it applied');
		}
	}

	@IsTest
	static void noPassStartsWhileTheSettingIsAsLastApplied() {
		System.runAs(ProjectsTestData.admin()) {
			SettingsState.put(new Map<String, Object>{ ProjectCostSync.APPLIED_KEY => false });

			Test.startTest();
			ProjectCostSync.startIfRatesChanged();
			Test.stopTest();

			Assert.areEqual(
				0,
				[SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'ProjectCostSync'],
				'Nothing changed, so nothing runs'
			);
		}
	}
}
