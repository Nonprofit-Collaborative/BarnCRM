/**
 * Holders of Mirror's retired sets get the sets that replace them, keep the old ones, and an
 * inactive holder is named rather than given (ADR-0194, simpler permission sets, D4).
 */
@IsTest(testFor='ApexClass:MirrorAccessSync')
private class MirrorAccessSyncTest {
	private static final String RECORDS_SYNC = 'Salesforce_Records_Sync';
	private static final String INBOUND = 'Inbound_Gifts';

	@TestSetup
	static void createTestUsers() {
		System.runAs(TestUsers.admin()) {
			TestUsers.standardUserWith('Cam', new List<String>{ 'Campaign_Sync' });
			TestUsers.standardUserWith(
				'Opal',
				new List<String>{ 'Opportunity_Mirror', 'Gift_Transaction_Mirror' }
			);
			TestUsers.standardUserWith('Ina', new List<String>{ 'Inbound_Gift_API' });
			TestUsers.standardUserWith('Rec', new List<String>{ 'Record_Inbound_Gift_Action' });
			TestUsers.standardUser('Nobody');
			User gone = TestUsers.standardUserWith('Gone', new List<String>{ 'Campaign_Sync' });
			update new User(Id = gone.Id, IsActive = false);
		}
	}

	private static Set<String> setsOf(String lastName) {
		Set<String> names = new Set<String>();
		for (PermissionSetAssignment row : [
			SELECT PermissionSet.Name
			FROM PermissionSetAssignment
			WHERE Assignee.LastName = :lastName AND PermissionSet.IsOwnedByProfile = FALSE
			WITH SYSTEM_MODE
		]) {
			names.add(row.PermissionSet.Name);
		}
		return names;
	}

	@IsTest
	static void activeHoldersGetTheNewSetsAndKeepTheOld() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			Boolean more = MirrorAccessSync.syncOnce();
			Test.stopTest();

			Assert.isFalse(more, 'A small org is done in one pass');
			Assert.isTrue(
				setsOf('Cam').containsAll(new Set<String>{ RECORDS_SYNC, 'Campaign_Sync' })
			);
			Assert.isTrue(setsOf('Opal').contains(RECORDS_SYNC), 'Either mirror set carries over');
			Assert.isTrue(setsOf('Ina').contains(INBOUND), 'The API user gets Inbound Gifts');
			Assert.isTrue(setsOf('Rec').contains(INBOUND), 'So does the flow user');
			Assert.isFalse(setsOf('Cam').contains(INBOUND), 'Only the matching successor');
			Assert.isFalse(setsOf('Nobody').contains(RECORDS_SYNC), 'Nobody else gets one');
			Assert.isFalse(setsOf('Gone').contains(RECORDS_SYNC), 'An inactive user is not tried');
		}
	}

	@IsTest
	static void inactiveHoldersAreNamedAndNothingIsGiven() {
		System.runAs(TestUsers.admin()) {
			String goneName = [SELECT Name FROM User WHERE LastName = 'Gone' LIMIT 1].Name;

			Test.startTest();
			List<String> messages = MirrorAccessSync.logInactiveHolders();
			Test.stopTest();

			Assert.areEqual(1, messages.size(), 'Only the inactive holder: ' + messages);
			Assert.isTrue(messages[0].contains(goneName), 'By name: ' + messages[0]);
			Assert.isTrue(messages[0].contains('Salesforce Records Sync'), 'With the set owed');
			Assert.isFalse(setsOf('Gone').contains(RECORDS_SYNC), 'Reading only');
		}
	}

	@IsTest
	static void installingMirrorCarriesHoldersOver() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			Test.testInstall(new MirrorPostInstall(), new Version(1, 0), true);
			Test.stopTest();

			Assert.isTrue(setsOf('Cam').contains(RECORDS_SYNC), 'The upgrade queues the sync');
		}
	}
}
