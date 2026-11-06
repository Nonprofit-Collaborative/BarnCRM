/**
 * Giving at a Glance (people-14): the card Giving adds to Core's record pages through the
 * record glance seam (ADR-0167). The card is read as the page
 * reads it, through its JSON, because Core's fields are not visible across a namespace.
 */
@IsTest(testFor='ApexClass:GivingRecordGlanceExtension')
private class GivingRecordGlanceExtensionTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Giving_Admin');
	}

	private static Map<String, Object> view(RecordGlance.Card card) {
		return card == null
			? null
			: (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(card));
	}

	private static Map<String, Object> tile(Map<String, Object> card, Integer index) {
		return (Map<String, Object>) ((List<Object>) card.get('tiles'))[index];
	}

	private static List<Object> actions(Map<String, Object> card) {
		return (List<Object>) card.get('actions');
	}

	@IsTest
	static void aPersonGetsTheCardWithTotalsAndEnterAGift() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Contact person = GivingTestDataFactory.insertHouseholdContact(
				'Glance Household',
				'Gale',
				'Glance'
			);
			Test.startTest();
			Map<String, Object> card = view(new GivingRecordGlanceExtension().glance(person.Id));
			Test.stopTest();

			Assert.isNotNull(card, 'A Giving admin sees the card');
			Assert.areEqual(
				Label.Giving_Glance_Title,
				card.get('title'),
				'The card is Giving at a Glance'
			);
			Assert.areEqual(
				3,
				((List<Object>) card.get('tiles')).size(),
				'Total, last gift and donor level'
			);
			Assert.areEqual(
				Schema.SObjectType.Contact.fields.Total_Giving__c.getLabel(),
				tile(card, 0).get('label'),
				'The tile is named by the field label, so it reads like the record'
			);
			Assert.areEqual(
				0,
				(Decimal) tile(card, 0).get('numberValue'),
				'A person who never gave shows zero, not blank'
			);
			Assert.areEqual(
				1,
				actions(card).size(),
				'Someone who can create gifts gets Enter a Gift'
			);
			Map<String, Object> action = (Map<String, Object>) actions(card)[0];
			Map<String, Object> reference = (Map<String, Object>) JSON.deserializeUntyped(
				(String) action.get('pageReference')
			);
			Map<String, Object> state = (Map<String, Object>) reference.get('state');
			Assert.areEqual(
				(String) person.Id,
				(String) state.get(NamespaceUtil.stateKey('donorId')),
				'Quick Gift Entry opens with the donor'
			);
			Assert.isTrue(String.isNotBlank((String) action.get('label')), 'The button has a name');
		}
	}

	@IsTest
	static void anOrganizationGetsTheCardToo() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Account organization = GivingTestDataFactory.insertOrganization('Glance Hardware');
			Map<String, Object> card = view(
				new GivingRecordGlanceExtension().glance(organization.Id)
			);
			Assert.isNotNull(card, 'An organization has a card');
			Assert.areEqual(
				Schema.SObjectType.Account.fields.Last_Gift_Date__c.getLabel(),
				tile(card, 1).get('label'),
				'The account field labels are used on an account'
			);
		}
	}

	@IsTest
	static void figuresComeFromTheRecord() {
		Contact donor = (Contact) JSON.deserialize(
			JSON.serialize(
				new Map<String, Object>{
					'attributes' => new Map<String, Object>{ 'type' => 'Contact' },
					'Id' => FakeIds.of(Contact.SObjectType, 1),
					'Total_Giving__c' => 450,
					'Last_Gift_Date__c' => '2026-10-01',
					'Donor_Level__r' => new Map<String, Object>{
						'attributes' => new Map<String, Object>{ 'type' => 'Donor_Level__c' },
						'Name' => 'Friend'
					}
				}
			),
			Contact.class
		);
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Map<String, Object> card = view(
				GivingRecordGlanceExtension.card(donor, Contact.SObjectType)
			);
			Assert.areEqual(450, (Decimal) tile(card, 0).get('numberValue'), 'Total giving');
			Assert.areEqual('2026-10-01', tile(card, 1).get('dateValue'), 'Last gift date');
			Assert.areEqual('Friend', tile(card, 2).get('textValue'), 'Donor level name');
		}
	}

	@IsTest
	static void someoneWithoutGivingAccessGetsNoCard() {
		User reader = TestUsers.peopleReaderWith(
			'GlanceReader',
			new List<String>{ 'BarnCRM_Read_Only' }
		);
		Contact person;
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			person = GivingTestDataFactory.insertHouseholdContact(
				'Hidden Household',
				'Hal',
				'Hidden'
			);
		}
		System.runAs(reader) {
			Assert.isNull(
				new GivingRecordGlanceExtension().glance(person.Id),
				'No Giving access, no card'
			);
			Assert.isNull(new GivingRecordGlanceExtension().glance(null), 'No record, no card');
		}
	}

	@IsTest
	static void aReaderSeesTheCardWithoutEnterAGift() {
		User reader = TestUsers.peopleReaderWith(
			'GlanceGivingReader',
			new List<String>{ 'BarnCRM_Read_Only', 'Giving_Read_Only' }
		);
		Contact person;
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			person = GivingTestDataFactory.insertHouseholdContact(
				'Read Household',
				'Rae',
				'Reader'
			);
		}
		System.runAs(reader) {
			Map<String, Object> card = view(new GivingRecordGlanceExtension().glance(person.Id));
			Assert.isNotNull(card, 'A Giving reader sees the figures');
			Assert.isTrue(
				actions(card).isEmpty(),
				'Only someone who can create a gift gets Enter a Gift'
			);
		}
	}
}
