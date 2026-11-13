/**
 * Address match keys (D-200 P6): set on every save, filled for older addresses by the batch,
 * offered by Health Check until filled, and used by matching once filled.
 */
@IsTest(
	testFor='ApexClass:AddressMatchKeyHandler, ApexClass:AddressMatchKeyBatch, ApexClass:MatchSourceService, ApexClass:MatchSourceSelector'
)
private class AddressMatchKeyTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	@IsTest
	static void aSaveSetsTheKeyFromPostalCodeAndHouseNumber() {
		System.runAs(TestUsers.admin()) {
			Contact person = insertPerson('Ana', 'Ruiz');
			Address__c home = new Address__c(
				Contact__c = person.Id,
				Street__c = '77 Massachusetts Avenue',
				Postal_Code__c = '02139-4307'
			);
			insert home;
			Assert.areEqual('02139|77', keyOf(home.Id), 'Postal code and house number');

			update new Address__c(
				Id = home.Id,
				Street__c = 'North Main St.',
				Postal_Code__c = '02140'
			);
			Assert.areEqual('02140|main', keyOf(home.Id), 'A shortened word is skipped');

			update new Address__c(Id = home.Id, Street__c = null);
			Assert.isNull(keyOf(home.Id), 'No street, no key');
			Assert.areEqual(
				AddressMatchKeyHandler.NO_KEY,
				AddressMatchKeyHandler.keyFor('---', '02139'),
				'A street that normalizes to nothing is marked, not left to fill'
			);
		}
	}

	@IsTest
	static void theFillMarksTheKeysFilledAndHealthCheckStopsAsking() {
		System.runAs(TestUsers.admin()) {
			Assert.isNotNull(
				new AddressMatchKeyHandler.FilledCheck().run(),
				'Not filled yet: Health Check offers the fill'
			);

			Test.startTest();
			AddressMatchKeyBatch.run();
			Test.stopTest();

			Assert.isTrue(SettingsService.getSettings().Match_Keys_Filled__c, 'Marked filled');
			Assert.isNull(new AddressMatchKeyHandler.FilledCheck().run(), 'Nothing to offer');
		}
	}

	@IsTest
	static void theFillKeysAddressesItIsGiven() {
		System.runAs(TestUsers.admin()) {
			Contact person = insertPerson('Ben', 'Okafor');
			Address__c home = new Address__c(
				Contact__c = person.Id,
				Street__c = '12 Elm Road',
				Postal_Code__c = '02139'
			);
			insert home;

			new AddressMatchKeyBatch().execute(null, new List<Address__c>{ home });

			Assert.areEqual('02139|12', keyOf(home.Id));
		}
	}

	@IsTest
	static void onceFilledMatchingReadsAddressesByKey() {
		System.runAs(TestUsers.admin()) {
			SettingsService.saveBookkeeping(
				new Map<String, Object>{ 'Match_Keys_Filled__c' => true }
			);
			MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{ addressSource() };
			Contact first = insertPerson('Ana', 'Ruiz');
			Contact second = insertPerson('Anna', 'Ruiz-Lopez');
			Contact other = insertPerson('Ben', 'Okafor');
			insert new List<Address__c>{
				new Address__c(
					Contact__c = first.Id,
					Street__c = '12 North Main Street',
					Postal_Code__c = '02139'
				),
				new Address__c(
					Contact__c = second.Id,
					Street__c = '12 n. MAIN st',
					Postal_Code__c = '02139-4307'
				),
				new Address__c(
					Contact__c = other.Id,
					Street__c = '99 Elm Road',
					Postal_Code__c = '02139'
				)
			};
			MatchSourceService.Source source = MatchSourceService.usableSources()[0];
			Assert.isTrue(AddressMatchKeyHandler.usable(source), 'The keys are used');

			Test.startTest();
			List<DuplicateService.Pair> pairs = MatchSourceService.pairsFor(
				new List<Id>{ first.Id, second.Id, other.Id }
			);
			Test.stopTest();

			Assert.areEqual(1, pairs.size(), 'Only the two at the same address: ' + pairs);
			Assert.areEqual(DuplicateService.pairKey(first.Id, second.Id), pairs[0].key);
		}
	}

	@IsTest
	static void untilFilledMatchingFallsBack() {
		System.runAs(TestUsers.admin()) {
			MatchSourceSelector.sourcesOverride = new List<Match_Source__mdt>{ addressSource() };
			MatchSourceService.Source source = MatchSourceService.usableSources()[0];
			Assert.isFalse(AddressMatchKeyHandler.usable(source), 'Not filled: LIKE as before');
		}
	}

	// ------------------------------------------------------------------ helpers

	private static Contact insertPerson(String firstName, String lastName) {
		Contact person = TestDataFactory.person(
			new Contact(FirstName = firstName, LastName = lastName)
		);
		TestDataFactory.pastDuplicateRules(person);
		insert person;
		return person;
	}

	private static String keyOf(Id addressId) {
		return [SELECT Match_Key__c FROM Address__c WHERE Id = :addressId].Match_Key__c;
	}

	private static Match_Source__mdt addressSource() {
		Map<String, Object> fields = new Map<String, Object>{
			'DeveloperName' => 'Address_Person',
			'MasterLabel' => 'Address_Person',
			NamespaceUtil.qualify('Object_Name__c') => NamespaceUtil.qualify('Address__c'),
			NamespaceUtil.qualify('Value_Field__c') => NamespaceUtil.qualify('Street__c'),
			NamespaceUtil.qualify('Postal_Code_Field__c') => NamespaceUtil.qualify(
				'Postal_Code__c'
			),
			NamespaceUtil.qualify('Parent_Field__c') => NamespaceUtil.qualify('Contact__c'),
			NamespaceUtil.qualify('Normalization__c') => MatchSourceService.ADDRESS
		};
		return (Match_Source__mdt) JSON.deserialize(
			JSON.serialize(fields),
			Match_Source__mdt.class
		);
	}
}
