/**
 * BrandDefaultHandler on its own (C-47d, R-BR4): it does nothing while brands are off or when no
 * records arrive, and a failure while defaulting is logged and shown on every record rather
 * than thrown. The defaulting itself is covered in BrandServiceTest.
 */
@IsTest(testFor='ApexClass:BrandDefaultHandler')
private class BrandDefaultHandlerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static void brands(Boolean enabled) {
		BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
		settings.Brand_Management__c = enabled;
		HouseholdTestDataFactory.save(settings);
	}

	private static Brand__c userBrand() {
		Brand__c mine = new Brand__c(Name = 'Mine');
		insert mine;
		insert new Brand_Assignment__c(Brand__c = mine.Id, User__c = UserInfo.getUserId());
		return mine;
	}

	@IsTest
	static void doesNothingWhileBrandsAreOff() {
		System.runAs(TestUsers.admin()) {
			brands(false);
			userBrand();
			List<Brand_Assignment__c> records = new List<Brand_Assignment__c>{ new Brand_Assignment__c() };

			TriggerHandler.setTestRecords(records, null);
			new BrandDefaultHandler().beforeInsert();

			Assert.isNull(records[0].Brand__c, 'A blank Brand stays blank while brands are off');
			Assert.isFalse(records[0].hasErrors(), 'Nothing was refused');
		}
	}

	@IsTest
	static void doesNothingWithNoRecords() {
		System.runAs(TestUsers.admin()) {
			brands(true);
			List<Brand_Assignment__c> records = new List<Brand_Assignment__c>();

			TriggerHandler.setTestRecords(records, null);
			new BrandDefaultHandler().beforeInsert();

			Assert.isTrue(records.isEmpty(), 'No records, nothing to do');
			Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c], 'And nothing logged');
		}
	}

	@IsTest
	static void aFailureIsLoggedAndShownOnEveryRecord() {
		System.runAs(TestUsers.admin()) {
			brands(true);
			// The first record has a Brand field, the second is of an object that has none:
			// reading its Brand while defaulting throws, as a handler registered on the wrong
			// object would.
			List<SObject> records = new List<SObject>{ new Brand_Assignment__c(), new Account(Name = 'Wrong object') };

			Test.startTest();
			TriggerHandler.setTestRecords(records, null);
			new BrandDefaultHandler().beforeInsert();
			Test.stopTest();

			String expected = BarnHelp.text('Core', 'Core_Brand_SaveFailed');
			for (SObject record : records) {
				Assert.isTrue(record.hasErrors(), 'The save is refused on every record');
				Assert.areEqual(expected, record.getErrors()[0].getMessage(), 'With the plain message');
			}
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'BrandDefaultHandler.beforeInsert'],
				'The failure is logged once, under the handler'
			);
		}
	}

	@IsTest
	static void aRecordWithoutALeadingParentTakesTheUsersBrand() {
		System.runAs(TestUsers.admin()) {
			brands(true);
			Brand__c mine = userBrand();
			List<Brand_Assignment__c> records = new List<Brand_Assignment__c>{ new Brand_Assignment__c() };

			TriggerHandler.setTestRecords(records, null);
			new BrandDefaultHandler().beforeInsert();

			Assert.areEqual(mine.Id, records[0].Brand__c, 'The user brand fills the blank');
			Assert.isNull(
				BrandDefaultHandler.parentField(Account.SObjectType),
				'An object with no Brand has no parent to copy it from'
			);
		}
	}
}
