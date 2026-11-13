/**
 * Dana budgets the community conference: a hall and lunch, partner funds from Acme, and one paid
 * registration; the dashboard shows the same net cost, and a read-only colleague sees the
 * budget without changing it (EV-23, R-EXP1).
 */
@IsTest(testFor='ApexClass:EventBudgetController, ApexClass:EventDashboardController')
private class EventBudgetControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static Event__c conference() {
		Datetime start = Datetime.now().addDays(30);
		Event__c record = new Event__c(
			Name = 'Community Dreamin',
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(8)
		);
		insert as user record;
		return record;
	}

	private static void budget(Event__c event) {
		insert as user new List<Event_Expense__c>{
			new Event_Expense__c(
				Event__c = event.Id,
				Name = 'Hall',
				Category__c = 'Venue',
				Budgeted__c = 1000,
				Actual__c = 1200
			),
			new Event_Expense__c(
				Event__c = event.Id,
				Name = 'Lunch',
				Category__c = 'Food and Beverage',
				Budgeted__c = 500
			)
		};
		insert as user new Event_Funding__c(
			Event__c = event.Id,
			Name = 'Acme MDF',
			Type__c = 'Partner Funds (MDF)',
			Expected__c = 800,
			Received__c = 300
		);
		Contact ana = TestDataFactory.person(new Contact(FirstName = 'Ana', LastName = 'Garcia'));
		insert as user ana;
		// System mode: Amount Paid is written by the payment listener, never typed by staff.
		insert as system new Event_Registration__c(
			Event__c = event.Id,
			Contact__c = ana.Id,
			Status__c = 'Registered',
			Amount_Paid__c = 100
		);
	}

	@IsTest
	static void readsTheLinesAndWhatRegistrationsPaid() {
		System.runAs(staff()) {
			Event__c event = conference();
			budget(event);

			Test.startTest();
			EventBudgetController.Budget result = EventBudgetController.getBudget(event.Id);
			Test.stopTest();

			Assert.areEqual(2, result.expenses.size(), 'Both expense lines');
			Assert.areEqual(1, result.funding.size(), 'The funding line');
			Assert.areEqual(100, result.registrationsPaid, 'What registrations paid');
			Assert.areEqual(300, result.funding[0].received, 'Received');
			Assert.isTrue(
				result.canAddExpense && result.canAddFunding && result.canEdit,
				'Staff edit'
			);
			Assert.isTrue(
				result.fieldLabels.containsKey('Expense_Budgeted__c'),
				'Labels for columns'
			);
		}
	}

	@IsTest
	static void theDashboardShowsNetCost() {
		System.runAs(staff()) {
			Event__c event = conference();
			Assert.isNull(
				EventDashboardController.getDashboard(event.Id).netCost,
				'No budget yet, no net cost'
			);
			budget(event);

			Test.startTest();
			EventDashboardController.Dashboard result = EventDashboardController.getDashboard(
				event.Id
			);
			Test.stopTest();

			Assert.areEqual(800, result.netCost, '1,200 less 300 less 100 (R-EXP1)');
		}
	}

	@IsTest
	static void readOnlyPeopleSeeTheBudgetWithoutChangingIt() {
		User viewer = TestUsers.standardUserWith(
			'BudgetViewer',
			new List<String>{ 'BarnCRM_Read_Only', 'Events_Read_Only' }
		);
		Event__c event;
		System.runAs(staff()) {
			event = conference();
			budget(event);
		}
		System.runAs(viewer) {
			EventBudgetController.Budget result = EventBudgetController.getBudget(event.Id);
			Assert.areEqual(2, result.expenses.size(), 'Read Only sees the lines');
			Assert.isFalse(result.canAddExpense || result.canAddFunding, 'Read Only cannot add');
			Assert.isFalse(result.canEdit, 'Read Only cannot change lines');
		}
	}
}
