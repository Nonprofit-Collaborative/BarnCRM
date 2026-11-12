/**
 * The Financials card (PM-11, R-PM21): budget with approved changes, revenue and cost to date,
 * invoiced and the stored months; cost only for Projects Admin; nothing while off. Change
 * requests (PM-12, R-PM20) move the budget the project is measured against, health included.
 */
@IsTest(
	testFor='ApexClass:ProjectFinancials, ApexClass:ProjectBillingController, ApexClass:ProjectHealth'
)
private class ProjectFinancialsTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	private static Project__c projectWithWork() {
		Project__c project = ProjectsTestData.project('Active', 10);
		project.Budget_Amount__c = 5000;
		update project;
		SettingsService.saveValues(
			'Projects_Settings__c',
			new Map<String, Object>{ 'Change_Requests_Enabled__c' => true }
		);
		insert new Project_Change_Request__c(
			Project__c = project.Id,
			Name = 'Extra report',
			Hours__c = 10,
			Amount__c = 1000,
			Status__c = 'Approved'
		);
		insert new Time_Entry__c(
			Project__c = project.Id,
			User__c = UserInfo.getUserId(),
			Date__c = Date.today(),
			Hours__c = 12,
			Billable__c = true,
			Cost_Rate__c = 50
		);
		return project;
	}

	@IsTest
	static void theCardShowsBudgetRevenueCostAndInvoiced() {
		System.runAs(ProjectsTestData.admin()) {
			ProjectRevenueTest.revenue(true);
			Project__c project = projectWithWork();

			Test.startTest();
			Map<String, Object> card = ProjectBillingController.getFinancials(project.Id);
			Test.stopTest();

			Assert.isTrue((Boolean) card.get('enabled'), 'On');
			Assert.areEqual(6000, card.get('budget'), 'Budget plus the approved change');
			Assert.areEqual(1200, card.get('revenue'), 'Twelve hours at the Hourly Rate');
			Assert.areEqual(600, card.get('cost'), 'Admin sees cost');
			Assert.areEqual(0, card.get('invoiced'), 'Nothing invoiced yet');
			Assert.isTrue(((List<Object>) card.get('months')).isEmpty(), 'No closed month yet');
		}
	}

	@IsTest
	static void staffSeeNoCostAndNothingShowsWhileOff() {
		User staff = ProjectsTestData.staff('Viewer');
		Project__c project;
		System.runAs(ProjectsTestData.admin()) {
			project = projectWithWork();
			Assert.isFalse(
				(Boolean) ProjectBillingController.getFinancials(project.Id).get('enabled'),
				'Off at install'
			);
			ProjectRevenueTest.revenue(true);
		}
		System.runAs(staff) {
			Test.startTest();
			Map<String, Object> card = ProjectBillingController.getFinancials(project.Id);
			Test.stopTest();
			Assert.isFalse((Boolean) card.get('withCost'), 'Cost is admin only');
			Assert.isNull(card.get('cost'), 'No cost figure');
			Assert.areEqual(1200, card.get('revenue'), 'Revenue is shown');
		}
	}

	@IsTest
	static void healthMeasuresAgainstBudgetPlusApprovedChanges() {
		System.runAs(ProjectsTestData.admin()) {
			Project__c project = projectWithWork();

			Test.startTest();
			ProjectHealth.refresh(project.Id);
			Test.stopTest();

			Project__c checked = [
				SELECT Health__c, Health_Reasons__c
				FROM Project__c
				WHERE Id = :project.Id
			];
			Assert.isFalse(
				checked.Health_Reasons__c != null &&
				checked.Health_Reasons__c.contains('logged against'),
				'12 of 20 hours is not over budget'
			);
		}
	}

	@IsTest
	static void aNewChangeRequestIsRefusedWhileTrackingIsOff() {
		System.runAs(ProjectsTestData.admin()) {
			Project__c project = ProjectsTestData.project('Active', 10);
			Database.SaveResult result = Database.insert(
				new Project_Change_Request__c(
					Project__c = project.Id,
					Name = 'Extra',
					Hours__c = 1
				),
				false
			);
			Assert.isFalse(result.isSuccess(), 'Track change requests is off by default');
		}
	}
}
