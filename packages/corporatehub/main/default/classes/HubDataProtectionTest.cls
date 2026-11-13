/**
 * The GDPR records (CH-05, canonical model 29CH16 to 29CH18): the nightly step reminds once of a
 * DPIA review, an open data subject request and an unreported breach, leaves a breach judged
 * unlikely to be a risk alone, links an erasure to its request by reference (R-DS2), and the
 * Corporate Hub page lists open requests and unreported breaches.
 */
@IsTest(testFor='ApexClass:HubReminders, ApexClass:CorporateHubController')
private class HubDataProtectionTest {
	private static final String ADMIN_SET = 'Corporate_Hub_Admin';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ADMIN_SET);
	}

	private static Data_Subject_Request__c request(String type) {
		Data_Subject_Request__c row = new Data_Subject_Request__c(
			Request_Type__c = type,
			Status__c = 'Received',
			Received_Date__c = Date.today(),
			Due_Date__c = Date.today().addDays(10)
		);
		insert row;
		return [SELECT Id, Name FROM Data_Subject_Request__c WHERE Id = :row.Id];
	}

	private static Data_Breach__c breach(String risk) {
		Data_Breach__c row = new Data_Breach__c(
			Name = 'Laptop lost ' + risk,
			Status__c = 'Open',
			Discovered_At__c = Datetime.now(),
			Risk__c = risk
		);
		insert row;
		return row;
	}

	@IsTest
	static void eachRecordIsRemindedOnceAndALowRiskBreachIsNot() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			insert new Processing_Activity__c(
				Name = 'Donor records',
				Status__c = 'Active',
				DPIA_Required__c = true,
				DPIA_Review_Date__c = Date.today().addDays(5)
			);
			Data_Subject_Request__c open = request('Access');
			Data_Breach__c risky = breach('Risk');
			breach('Unlikely');

			Test.startTest();
			new HubReminders().execute(null);
			new HubReminders().execute(null);
			Test.stopTest();

			Assert.areEqual(
				3,
				HubReminders.sentTitles.size(),
				'One DPIA, one request, one breach, once each'
			);
			Assert.areEqual(
				Date.today().addDays(10),
				[SELECT Reminded_For__c FROM Data_Subject_Request__c WHERE Id = :open.Id]
				.Reminded_For__c,
				'The request remembers its reminder'
			);
			Assert.isNotNull(
				[SELECT Reminded_For__c FROM Data_Breach__c WHERE Id = :risky.Id].Reminded_For__c,
				'The breach remembers its reminder'
			);
		}
	}

	@IsTest
	static void anErasureWithTheRequestNumberIsLinked() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Data_Subject_Request__c erase = request('Erasure');
			Contact person = TestDataFactory.person(new Contact(LastName = 'Erased'));
			insert person;
			Erasure__c audit = new Erasure__c(
				Contact__c = person.Id,
				Erased_Record_Id__c = person.Id,
				Request_Reference__c = erase.Name.toLowerCase()
			);
			insert as system audit;

			Test.startTest();
			new HubReminders().execute(null);
			Test.stopTest();

			Data_Subject_Request__c after = [
				SELECT Erasure_Record__c, Status__c
				FROM Data_Subject_Request__c
				WHERE Id = :erase.Id
			];
			Assert.areEqual(
				audit.Id,
				after.Erasure_Record__c,
				'Linked by its reference, ignoring case'
			);
			Assert.areEqual('Received', after.Status__c, 'The person completes the request');
		}
	}

	@IsTest
	static void thePageListsOpenRequestsAndUnreportedBreaches() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Data_Subject_Request__c open = request('Access');
			Data_Breach__c risky = breach('High Risk');
			Data_Breach__c reported = breach('Risk');
			reported.Authority_Notified_At__c = Datetime.now();
			update reported;

			Test.startTest();
			CorporateHubController.Home home = CorporateHubController.getHome();
			Test.stopTest();

			Assert.areEqual(2, home.privacy.size(), 'The request and the unreported breach');
			Assert.areEqual(open.Id, home.privacy[0].id, 'Requests first');
			Assert.areEqual(risky.Id, home.privacy[1].id, 'Then the breach');
			Assert.isTrue(home.privacy[0].name.contains(open.Name), 'Named by its number');
		}
	}
}
