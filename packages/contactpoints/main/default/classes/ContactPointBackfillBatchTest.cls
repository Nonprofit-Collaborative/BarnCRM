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

			Assert.isNotNull(SettingsState.moment(ContactPointSyncService.KEY_LAST_BACKFILL), 'When it finished');
			Assert.isTrue(
				String.isNotBlank(SettingsState.text(ContactPointSyncService.KEY_LAST_SUMMARY)),
				'What it did'
			);
			Assert.isTrue(ContactPointSyncService.switchedOn(ContactPointPlan.EMAIL), 'A never-saved switch stays on');
			Assert.isTrue(ContactPointSyncService.switchedOn(ContactPointPlan.PHONE));
			Assert.isTrue(ContactPointSyncService.switchedOn(ContactPointPlan.ADDRESS));
		}
	}
}
