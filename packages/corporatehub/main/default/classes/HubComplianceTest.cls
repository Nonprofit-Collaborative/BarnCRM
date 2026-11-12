/**
 * Maria files the annual report and marks it done: a Compliance Cycle records it and the due date
 * moves to next year; a one-time filing is simply Done (R-CO1).
 */
@IsTest(testFor='ApexClass:HubCompliance')
private class HubComplianceTest {
	private static final String ADMIN_SET = 'Corporate_Hub_Admin';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ADMIN_SET);
	}

	private static Compliance_Obligation__c obligation(String recurrence, Date due) {
		Compliance_Obligation__c row = new Compliance_Obligation__c(
			Name = 'State annual report',
			Status__c = 'Active',
			Recurrence__c = recurrence,
			Due_Date__c = due
		);
		insert row;
		return row;
	}

	@IsTest
	static void aMonthEndStaysAMonthEnd() {
		// runs-as: deploying user (date arithmetic only, no records or permissions)
		Assert.areEqual(
			Date.newInstance(2027, 2, 28),
			HubCompliance.nextDue(Date.newInstance(2027, 1, 31), 1),
			'Feb end'
		);
		Assert.areEqual(
			Date.newInstance(2027, 5, 31),
			HubCompliance.nextDue(Date.newInstance(2027, 4, 30), 1),
			'May end'
		);
		Assert.areEqual(
			Date.newInstance(2027, 6, 15),
			HubCompliance.nextDue(Date.newInstance(2027, 3, 15), 3),
			'Mid month'
		);
		Assert.areEqual(
			Date.newInstance(2029, 2, 28),
			HubCompliance.nextDue(Date.newInstance(2027, 2, 28), 24),
			'Two years'
		);
	}

	@IsTest
	static void aYearlyObligationRecordsTheCycleAndMovesOn() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Date due = Date.newInstance(2027, 5, 15);
			Compliance_Obligation__c row = obligation('Yearly', due);

			Id cycleId = HubCompliance.completeCycle(row.Id, null, null, 'Filed online');

			Compliance_Cycle__c cycle = [
				SELECT Due_Date__c, Completed_On__c, Completed_By__c, Outcome__c, Notes__c
				FROM Compliance_Cycle__c
				WHERE Id = :cycleId
				WITH USER_MODE
			];
			Assert.areEqual(due, cycle.Due_Date__c, 'For the due date it met');
			Assert.areEqual(Date.today(), cycle.Completed_On__c, 'Today when not given');
			Assert.areEqual(UserInfo.getUserId(), cycle.Completed_By__c, 'By Maria');
			Assert.areEqual('Done', cycle.Outcome__c, 'Done when not given');
			Compliance_Obligation__c after = [
				SELECT Status__c, Due_Date__c, Last_Completed_On__c
				FROM Compliance_Obligation__c
				WHERE Id = :row.Id
				WITH USER_MODE
			];
			Assert.areEqual(Date.newInstance(2028, 5, 15), after.Due_Date__c, 'Next year');
			Assert.areEqual('Active', after.Status__c, 'Still active');
			Assert.areEqual(Date.today(), after.Last_Completed_On__c, 'Last completed today');
		}
	}

	@IsTest
	static void aOneTimeObligationIsDone() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Compliance_Obligation__c row = obligation('One Time', Date.today().addDays(-3));

			HubCompliance.completeCycle(row.Id, Date.today().addDays(-1), 'Done Late', null);

			Compliance_Obligation__c after = [
				SELECT Status__c, (SELECT Outcome__c, Completed_On__c FROM Compliance_Cycles__r)
				FROM Compliance_Obligation__c
				WHERE Id = :row.Id
				WITH USER_MODE
			];
			Assert.areEqual('Done', after.Status__c, 'Nothing more to do');
			Assert.areEqual(1, after.Compliance_Cycles__r.size(), 'One cycle');
			Assert.areEqual('Done Late', after.Compliance_Cycles__r[0].Outcome__c, 'As recorded');
			Assert.areEqual(
				Date.today().addDays(-1),
				after.Compliance_Cycles__r[0].Completed_On__c,
				'On the given day'
			);
		}
	}
}
