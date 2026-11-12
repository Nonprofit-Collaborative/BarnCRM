/**
 * The Open status (PM-07, R-PM11): with approvals on a new time entry or expense is saved Open,
 * 200 at a time; an explicit status stays; with a setting off the status stays blank and the
 * hours count as before 1.20; and the Status cannot be cleared again.
 */
@IsTest(
	testFor='ApexClass:ProjectEntryHandler, ApexTrigger:TimeEntryTrigger, ApexTrigger:ProjectExpenseTrigger'
)
private class ProjectEntryHandlerTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	private static Project_Expense__c expense(Id projectId) {
		return new Project_Expense__c(
			Project__c = projectId,
			User__c = UserInfo.getUserId(),
			Date__c = Date.today(),
			Category__c = 'Travel',
			Amount__c = 40,
			Billable__c = true
		);
	}

	@IsTest
	static void nothingChangesWhileApprovalsAreOff() {
		System.runAs(ProjectsTestData.admin()) {
			Project__c project = ProjectsTestData.project('Active', null);
			Time_Entry__c entry = ProjectsTestData.time(project.Id, 3, true);
			Project_Expense__c cost = expense(project.Id);
			insert cost;

			Assert.isNull(
				[SELECT Status__c FROM Time_Entry__c WHERE Id = :entry.Id WITH SYSTEM_MODE]
				.Status__c,
				'Time stays blank'
			);
			Assert.isNull(
				[SELECT Status__c FROM Project_Expense__c WHERE Id = :cost.Id WITH SYSTEM_MODE]
				.Status__c,
				'The expense stays blank'
			);
			Assert.areEqual(
				3,
				[SELECT Actual_Hours__c FROM Project__c WHERE Id = :project.Id WITH SYSTEM_MODE]
				.Actual_Hours__c,
				'The hours count as they were saved'
			);
		}
	}

	@IsTest
	static void withApprovalsOnNewTimeAndExpensesAreOpenAndOpenTimeDoesNotCount() {
		System.runAs(ProjectsTestData.admin()) {
			SettingsService.saveValues(
				'Projects_Settings__c',
				new Map<String, Object>{
					'Approvals_Enabled__c' => true,
					'Expenses_Enabled__c' => true
				}
			);
			Project__c project = ProjectsTestData.project('Active', null);
			List<Time_Entry__c> entries = new List<Time_Entry__c>();
			for (Integer i = 0; i < 200; i++) {
				entries.add(
					new Time_Entry__c(
						Project__c = project.Id,
						User__c = UserInfo.getUserId(),
						Date__c = Date.today(),
						Hours__c = 1
					)
				);
			}
			entries[0].Status__c = 'Approved';
			Project_Expense__c cost = expense(project.Id);

			Test.startTest();
			insert entries;
			insert cost;
			Test.stopTest();

			Assert.areEqual(
				199,
				[SELECT COUNT() FROM Time_Entry__c WHERE Status__c = 'Open' WITH SYSTEM_MODE],
				'Every new entry with no status is Open'
			);
			Assert.areEqual(
				'Open',
				[SELECT Status__c FROM Project_Expense__c WHERE Id = :cost.Id WITH SYSTEM_MODE]
				.Status__c,
				'The expense is Open'
			);
			Assert.areEqual(
				1,
				[SELECT Actual_Hours__c FROM Project__c WHERE Id = :project.Id WITH SYSTEM_MODE]
				.Actual_Hours__c,
				'Only the approved hour counts (R-PM10)'
			);
			try {
				update new Time_Entry__c(Id = entries[1].Id, Status__c = null);
				Assert.fail('A status is never cleared');
			} catch (DmlException refused) {
				Assert.isTrue(
					refused.getMessage().contains('Status cannot be cleared'),
					refused.getMessage()
				);
			}
		}
	}

	@IsTest
	static void expensesStayBlankWhileTheExpensesSettingIsOff() {
		System.runAs(ProjectsTestData.admin()) {
			SettingsService.saveValues(
				'Projects_Settings__c',
				new Map<String, Object>{ 'Approvals_Enabled__c' => true }
			);
			Project__c project = ProjectsTestData.project('Active', null);
			Project_Expense__c cost = expense(project.Id);
			insert cost;
			Assert.isNull(
				[SELECT Status__c FROM Project_Expense__c WHERE Id = :cost.Id WITH SYSTEM_MODE]
				.Status__c,
				'Expenses are not in the flow until Track expenses is on'
			);
		}
	}
}
