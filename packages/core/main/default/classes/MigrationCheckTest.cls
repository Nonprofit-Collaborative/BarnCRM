/**
 * MigrationCheck, the count a migration kit extension reports for one step (MIG-01, R-MR3).
 * Core's own tests cover it, since the kits that build it live in module packages.
 */
@IsTest(testFor='ApexClass:MigrationCheck')
private class MigrationCheckTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	@IsTest
	static void holdsTheCountsItWasGiven() {
		System.runAs(TestUsers.admin()) {
			MigrationCheck check = new MigrationCheck(12, 9);

			Assert.areEqual(12, check.source, 'The number to move');
			Assert.areEqual(9, check.done, 'The number moved');
		}
	}

	@IsTest
	static void aStepIsVerifiedWhenTheTwoCountsAgree() {
		System.runAs(TestUsers.admin()) {
			MigrationCheck agreed = new MigrationCheck(5, 5);
			MigrationCheck incomplete = new MigrationCheck(5, 4);

			Assert.areEqual(agreed.source, agreed.done, 'Equal counts verify the step');
			Assert.areNotEqual(incomplete.source, incomplete.done, 'A short count does not');
		}
	}
}
