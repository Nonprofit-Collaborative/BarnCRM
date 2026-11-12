/**
 * Field History Keeper (C-68, R-FH1 to R-FH4): only offered objects and stored fields, one row
 * per changed record in a bulk save, nothing while off or paused, the history shown with the
 * record and an earlier value restored. Addresses stand in for any BarnCRM object: Core ships
 * them with a dispatched trigger.
 */
@IsTest(
	testFor='ApexClass:FieldHistoryService, ApexClass:FieldHistoryController, ApexClass:TriggerDispatcher, ApexTrigger:AddressTrigger'
)
private class FieldHistoryServiceTest {
	private static final String CITY = 'Address__c.City__c';

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static void turnOn(Boolean enabled, List<String> fieldNames) {
		BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
		settings.Field_History_Enabled__c = enabled;
		HouseholdTestDataFactory.save(settings);
		FieldHistoryService.rowsForTest = new List<History_Field__mdt>();
		for (String name : fieldNames) {
			FieldHistoryService.rowsForTest.add(
				new History_Field__mdt(Field_Name__c = name, Active__c = true)
			);
		}
	}

	private static List<Address__c> addresses(Integer howMany) {
		Account household = HouseholdTestDataFactory.insertHouseholds(
			new List<Account>{ HouseholdTestDataFactory.newHousehold('Zztest History') }
		)[0];
		List<Address__c> result = new List<Address__c>();
		for (Integer i = 0; i < howMany; i++) {
			result.add(
				new Address__c(
					Account__c = household.Id,
					Type__c = 'Other',
					Street__c = i + ' Main St',
					City__c = 'Springfield',
					Is_Default__c = false
				)
			);
		}
		insert result;
		return result;
	}

	private static void moveTo(List<Address__c> places, String city) {
		for (Address__c place : places) {
			place.City__c = city;
		}
		update places;
	}

	@IsTest
	static void keepsOneRowPerChangedRecordInABulkSave() {
		System.runAs(TestUsers.admin()) {
			turnOn(true, new List<String>{ CITY });
			List<Address__c> places = addresses(20);

			Test.startTest();
			moveTo(places, 'Shelbyville');
			Test.stopTest();

			Assert.areEqual(
				20,
				[SELECT COUNT() FROM Field_History__c WITH SYSTEM_MODE],
				'One row per changed address, none for the insert'
			);
			List<FieldHistoryService.Entry> entries = FieldHistoryService.historyFor(places[0].Id);
			Assert.areEqual(1, entries.size(), 'One change on the first address');
			Assert.areEqual('Springfield', entries[0].before, 'The value before');
			Assert.areEqual('Shelbyville', entries[0].after, 'The value after');
			Assert.isTrue(entries[0].canRestore, 'An admin may restore it');
		}
	}

	@IsTest
	static void keepsAChangeWhoeverSavesIt() {
		User noAccess;
		System.runAs(TestUsers.admin()) {
			turnOn(true, new List<String>{ CITY });
			noAccess = TestUsers.minimumAccessUserWith('Zztest NoFls', new List<String>());
		}
		Id recordId =
			Address__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() +
			'000000000001';
		Test.startTest();
		System.runAs(noAccess) {
			FieldHistoryService.capture(
				'Address__c',
				new List<SObject>{ new Address__c(Id = recordId, City__c = 'Shelbyville') },
				new Map<Id, SObject>{
					recordId => new Address__c(Id = recordId, City__c = 'Springfield')
				}
			);
		}
		Test.stopTest();

		Assert.areEqual(
			1,
			[SELECT COUNT() FROM Field_History__c WHERE Record_Id__c = :recordId WITH SYSTEM_MODE],
			'A person with no access to the field still has the change kept'
		);
	}

	@IsTest
	static void keepsNothingWhileOffOrPaused() {
		System.runAs(TestUsers.admin()) {
			turnOn(false, new List<String>{ CITY });
			List<Address__c> places = addresses(2);

			Test.startTest();
			moveTo(places, 'Shelbyville');
			turnOn(true, new List<String>{ CITY });
			AutomationControl.pauseAll(1);
			moveTo(places, 'Capital City');
			Test.stopTest();

			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Field_History__c WITH SYSTEM_MODE],
				'Nothing is kept while the setting is off or automation is paused'
			);
		}
	}

	@IsTest
	static void restorePutsTheEarlierValueBackAndKeepsThatToo() {
		System.runAs(TestUsers.admin()) {
			turnOn(true, new List<String>{ CITY });
			List<Address__c> places = addresses(1);
			moveTo(places, 'Shelbyville');
			Field_History__c row = [SELECT Id FROM Field_History__c WITH SYSTEM_MODE LIMIT 1];

			Test.startTest();
			FieldHistoryController.HistoryView view = FieldHistoryController.restore(
				places[0].Id,
				row.Id,
				Address__c.City__c.getDescribe().getName()
			);
			Test.stopTest();

			Assert.areEqual(
				'Springfield',
				[SELECT City__c FROM Address__c WHERE Id = :places[0].Id WITH SYSTEM_MODE].City__c,
				'The earlier value is back'
			);
			Assert.areEqual(2, view.entries.size(), 'The restore is itself a kept change');
		}
	}

	@IsTest
	static void aCutValueCannotBeRestored() {
		System.runAs(TestUsers.admin()) {
			Field_History__c row = new Field_History__c(
				Record_Id__c = '001000000000001AAA',
				Changes__c = '[{"f":"City__c","o":"x","n":"y","t":true}]'
			);
			insert as system row;

			Test.startTest();
			try {
				FieldHistoryService.restore(row.Id, 'City__c');
				Assert.fail('A value cut to 1,000 characters is never written back');
			} catch (FieldHistoryService.FieldHistoryException expected) {
				Assert.isTrue(String.isNotBlank(expected.getMessage()), 'Told why');
			}
			Test.stopTest();
		}
	}

	@IsTest
	static void offersOnlyStoredFieldsOfDispatchedBarnObjects() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			Schema.DescribeFieldResult city = FieldHistoryService.keepable(CITY);
			Schema.DescribeFieldResult person = FieldHistoryService.keepable('Contact.LastName');
			Schema.DescribeFieldResult log = FieldHistoryService.keepable(
				'Error_Log__c.Message__c'
			);
			Schema.DescribeFieldResult bare = FieldHistoryService.keepable('City__c');
			Test.stopTest();

			Assert.isNotNull(city, 'A stored field of a BarnCRM object with a trigger');
			Assert.isNull(person, 'Standard objects keep Salesforce history');
			Assert.isNull(log, 'BarnCRM\'s own log is never history');
			Assert.isNull(bare, 'A name without its object is refused');
			try {
				new FieldHistoryService.Validator()
					.validate(new Map<String, Object>{ 'Field_Name__c' => 'Contact.LastName' });
				Assert.fail('The custom metadata page refuses it');
			} catch (CustomMetadataManagerService.CustomMetadataManagerException expected) {
				Assert.isTrue(expected.getMessage().contains('Contact.LastName'), 'Named');
			}
		}
	}

	@IsTest
	static void healthCheckAsksForFieldsOnlyWhileOn() {
		System.runAs(TestUsers.admin()) {
			turnOn(false, new List<String>());
			Assert.isNull(new FieldHistoryService.HealthCheck().run(), 'Silent while off');
			turnOn(true, new List<String>());
			HealthCheckService.Finding none = new FieldHistoryService.HealthCheck().run();
			turnOn(true, new List<String>{ CITY, 'Address__c.Nowhere__c' });
			HealthCheckService.Finding gone = new FieldHistoryService.HealthCheck().run();
			turnOn(true, new List<String>{ CITY });

			Test.startTest();
			HealthCheckService.Finding fine = new FieldHistoryService.HealthCheck().run();
			Test.stopTest();

			Assert.isNotNull(none, 'On with no field chosen is a warning');
			Assert.isTrue(gone.detail.contains('Address__c.Nowhere__c'), 'Names the bad field');
			Assert.isNull(fine, 'Nothing to say when every field can be kept');
		}
	}
}
