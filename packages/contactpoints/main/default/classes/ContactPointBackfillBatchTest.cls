/**
 * The backfill runs over every person and records when it finished and what it did, without
 * turning off a switch that was never saved (ADR-0035).
 */
@IsTest(testFor='ApexClass:ContactPointBackfillBatch')
private class ContactPointBackfillBatchTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	@IsTest
	static void recordsTheRunAndKeepsTheSwitches() {
		System.runAs(TestUsers.admin()) {
			Database.insert(
				TestDataFactory.pastDuplicateRules(new Contact(LastName = 'Rivera')),
				AccessLevel.SYSTEM_MODE
			);

			Test.startTest();
			ContactPointBackfillBatch.start();
			Test.stopTest();

			Contact_Point_Sync_Settings__c saved = Contact_Point_Sync_Settings__c.getOrgDefaults();
			Assert.isNotNull(saved.Last_Backfill__c, 'When it finished');
			Assert.isTrue(String.isNotBlank(saved.Last_Backfill_Summary__c), 'What it did');
			Assert.isTrue(saved.Sync_Emails__c, 'A never-saved switch stays on');
			Assert.isTrue(saved.Sync_Phones__c);
			Assert.isTrue(saved.Sync_Addresses__c);
		}
	}
}
