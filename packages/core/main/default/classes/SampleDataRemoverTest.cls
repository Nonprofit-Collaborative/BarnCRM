/**
 * Sample data removal past sharing (SR-01, D-219): an admin holding Manage BarnCRM Settings who
 * cannot see another admin's private saved queries still finds and deletes the ones tracked as
 * sample data, and only those; a search that does not test the sample tracking, and a person
 * without the permission, are refused.
 */
@IsTest(testFor='ApexClass:SampleDataRemover')
private class SampleDataRemoverTest {
	private static final String FLAGGED = 'Sample_Data__c = TRUE';

	@TestSetup
	static void makeAdmin() {
		TestUsers.admin();
	}

	@IsTest
	static void aSettingsAdminRemovesSomeoneElsesSampleRecordsOnly() {
		Saved_Query__c sample = new Saved_Query__c(Name = 'Sample query', Object_Name__c = 'Contact', Sample_Data__c = true);
		Saved_Query__c own = new Saved_Query__c(Name = 'Our own query', Object_Name__c = 'Contact');
		System.runAs(TestUsers.admin()) {
			insert new List<Saved_Query__c>{ sample, own };
		}
		User remover = TestUsers.standardUserWith('SampleRemover', new List<String>{ TestUsers.CORE_ADMIN });

		Integer seen;
		Integer counted;
		List<Id> found;
		Map<Id, String> names;
		List<Database.DeleteResult> results;
		Test.startTest();
		System.runAs(remover) {
			seen = [SELECT COUNT() FROM Saved_Query__c WITH USER_MODE];
			counted = SampleDataRemover.count('Saved_Query__c', FLAGGED);
			found = SampleDataRemover.ids('Saved_Query__c', FLAGGED, null, 10);
			names = SampleDataRemover.names('Saved_Query__c', new Set<Id>(found));
			results = SampleDataRemover.remove(found, false);
		}
		Test.stopTest();

		Assert.isTrue(seen <= 1, 'Saved queries are private, so the remover need not see the sample one.');
		Assert.areEqual(1, counted, 'The sample one is counted all the same.');
		Assert.areEqual(new List<Id>{ sample.Id }, found, 'Only the one tracked as sample data is found.');
		Assert.areEqual('Sample query', names.get(sample.Id), 'Named for the Warning.');
		Assert.isTrue(results[0].isSuccess(), 'And deleted.');
		System.runAs(TestUsers.admin()) {
			Assert.areEqual(
				new List<Id>{ own.Id },
				new List<Id>(new Map<Id, Saved_Query__c>([SELECT Id FROM Saved_Query__c]).keySet()),
				'The query not tracked as sample data stays.'
			);
		}
	}

	@IsTest
	static void aSearchOutsideTheSampleTrackingAndAPersonWithoutThePermissionAreRefused() {
		User noSettings = TestUsers.standardUser('NoSettings');
		String untracked;
		Integer missingObject;
		System.runAs(TestUsers.admin()) {
			try {
				SampleDataRemover.ids('Saved_Query__c', 'Name != NULL', null, 10);
			} catch (SampleDataException expected) {
				untracked = expected.getMessage();
			}
			missingObject = SampleDataRemover.count('No_Such_Object__c', FLAGGED);
			Assert.isTrue(SampleDataRemover.remove(new List<Id>(), true).isEmpty(), 'Nothing to delete.');
		}
		String refused;
		System.runAs(noSettings) {
			try {
				SampleDataRemover.remove(new List<Id>{ UserInfo.getUserId() }, false);
			} catch (SampleDataException expected) {
				refused = expected.getMessage();
			}
		}

		Assert.areEqual(BarnHelp.text('Core', 'Core_SampleData_NotTracked'), untracked, 'Only sample tracking is searched.');
		Assert.areEqual(0, missingObject, 'An object that is not installed counts nothing.');
		Assert.areEqual(BarnHelp.text('Core', 'Core_SampleData_NoPermission'), refused, 'Manage BarnCRM Settings is needed.');
	}
}
