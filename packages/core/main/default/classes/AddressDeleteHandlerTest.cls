/**
 * Addresses of deleted records (canonical model R-AD11, D-184): a deleted organization's or
 * person's addresses go to the Recycle Bin with it and come back with it, the Keep setting
 * leaves them, and a merge keeps them on the record that stays.
 */
@IsTest(testFor='ApexClass:AddressDeleteHandler')
private class AddressDeleteHandlerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Address__c addressOf(Schema.SObjectField owner, Id ownerId, String street) {
		Address__c address = new Address__c(Street__c = street, Is_Default__c = true);
		address.put(owner, ownerId);
		Database.insert(address, AccessLevel.SYSTEM_MODE);
		return address;
	}

	private static Address__c reread(Id addressId) {
		return [
			SELECT Id, IsDeleted, Account__c, Contact__c, Deleted_With__c
			FROM Address__c
			WHERE Id = :addressId
			WITH SYSTEM_MODE
			ALL ROWS
		];
	}

	@IsTest
	static void anOrganizationsAddressGoesAndComesBackWithIt() {
		System.runAs(TestUsers.admin()) {
			Account funder = AddressTestDataFactory.newOrganization('Riverside Foundation');
			Database.insert(funder, AccessLevel.SYSTEM_MODE);
			Address__c office = addressOf(Address__c.Account__c, funder.Id, '55 Foundation Way');

			Test.startTest();
			Database.delete(funder, AccessLevel.SYSTEM_MODE);
			Address__c whileDeleted = reread(office.Id);
			Database.undelete(funder, AccessLevel.SYSTEM_MODE);
			Test.stopTest();

			Assert.isTrue(whileDeleted.IsDeleted, 'Deleted with the organization');
			Address__c back = reread(office.Id);
			Assert.isFalse(back.IsDeleted, 'Restored with it');
			Assert.areEqual(funder.Id, back.Account__c, 'Linked to it again');
			Assert.isNull(back.Deleted_With__c, 'The mark is cleared');
		}
	}

	@IsTest
	static void keepLeavesTheAddresses() {
		System.runAs(TestUsers.admin()) {
			SettingsService.saveSystemValue('Address_Delete_Behavior__c', 'Keep');
			Contact lee = TestDataFactory.person(new Contact(LastName = 'Lee'));
			Database.insert(lee, AccessLevel.SYSTEM_MODE);
			Address__c home = addressOf(Address__c.Contact__c, lee.Id, '12 Elm Street');

			Test.startTest();
			Database.delete(lee, AccessLevel.SYSTEM_MODE);
			Test.stopTest();

			Address__c kept = reread(home.Id);
			Assert.isFalse(kept.IsDeleted, 'Kept, as the setting says');
			Assert.isNull(kept.Deleted_With__c, 'Never marked');
		}
	}

	@IsTest
	static void aPersonsAddressGoesWithThemButAMergeKeepsIt() {
		System.runAs(TestUsers.admin()) {
			Contact sam = TestDataFactory.person(
				new Contact(LastName = 'Rivera', FirstName = 'Sam')
			);
			Contact samuel = TestDataFactory.person(
				new Contact(LastName = 'Rivera', FirstName = 'Samuel')
			);
			Contact ana = TestDataFactory.person(
				new Contact(LastName = 'Ortiz', FirstName = 'Ana')
			);
			Database.insert(new List<Contact>{ sam, samuel, ana }, AccessLevel.SYSTEM_MODE);
			Address__c samuels = addressOf(Address__c.Contact__c, samuel.Id, '9 Oak Road');
			Address__c anas = addressOf(Address__c.Contact__c, ana.Id, '3 Pine Court');

			Test.startTest();
			Database.merge(sam, samuel.Id, AccessLevel.SYSTEM_MODE);
			Database.delete(ana, AccessLevel.SYSTEM_MODE);
			Test.stopTest();

			Address__c merged = reread(samuels.Id);
			Assert.isFalse(merged.IsDeleted, 'A merge is not a delete');
			Assert.areEqual(sam.Id, merged.Contact__c, 'It moved to the survivor');
			Assert.isNull(merged.Deleted_With__c, 'Its mark is cleared');
			Assert.isTrue(reread(anas.Id).IsDeleted, 'Ana\'s address went with her');
		}
	}

	/**
	 * QA review Q4: the marks noted before delete are kept in a static map until after delete.
	 * A delete of 205 records runs the trigger in two chunks, so the second chunk's before
	 * must add to the map, not replace it, or the first chunk's addresses stay behind.
	 */
	@IsTest
	static void deletingMoreThanTwoHundredOrganizationsTakesEveryAddress() {
		System.runAs(TestUsers.admin()) {
			List<Account> funders = new List<Account>();
			for (Integer i = 0; i < 205; i++) {
				funders.add(AddressTestDataFactory.newOrganization('Foundation ' + i));
			}
			Database.insert(funders, AccessLevel.SYSTEM_MODE);
			List<Address__c> offices = new List<Address__c>();
			for (Account funder : funders) {
				offices.add(
					new Address__c(
						Account__c = funder.Id,
						Street__c = '1 Main Street',
						Is_Default__c = true
					)
				);
			}
			Database.insert(offices, AccessLevel.SYSTEM_MODE);

			Test.startTest();
			Database.delete(funders, AccessLevel.SYSTEM_MODE);
			Test.stopTest();

			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Address__c WHERE Id IN :offices WITH SYSTEM_MODE],
				'Every address went with its organization, in both chunks'
			);
		}
	}
}
