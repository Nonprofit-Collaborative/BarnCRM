/**
 * Volunteering at a Glance (D-200 R1): the card Volunteers adds to Core's record pages through
 * the record glance seam (ADR-0167), read through its JSON as the page reads it.
 */
@IsTest(testFor='ApexClass:VolunteersRecordGlanceExtension')
private class VolunteersRecordGlanceExtensionTest {
	@TestSetup
	static void makeData() {
		TestUsers.adminWith(VolunteersTestData.ADMIN);
	}

	private static Map<String, Object> view(RecordGlance.Card card) {
		return card == null
			? null
			: (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(card));
	}

	@IsTest
	static void aPersonGetsHoursLastDateAndLogHours() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			Contact person = VolunteersTestData.contacts(1)[0];

			Test.startTest();
			Map<String, Object> card = view(
				new VolunteersRecordGlanceExtension().glance(person.Id)
			);
			Test.stopTest();

			Assert.isNotNull(card, 'An admin sees the card');
			Assert.areEqual(Label.Volunteers_Glance_Title, card.get('title'), 'The card title');
			List<Object> tiles = (List<Object>) card.get('tiles');
			Assert.areEqual(2, tiles.size(), 'Hours this year and last volunteer date');
			Assert.areEqual(
				0,
				(Decimal) ((Map<String, Object>) tiles[0]).get('numberValue'),
				'No hours shows zero, not blank'
			);
			List<Object> actions = (List<Object>) card.get('actions');
			Assert.areEqual(1, actions.size(), 'Log Hours');
			Map<String, Object> reference = (Map<String, Object>) JSON.deserializeUntyped(
				(String) ((Map<String, Object>) actions[0]).get('pageReference')
			);
			Map<String, Object> state = (Map<String, Object>) reference.get('state');
			Assert.areEqual(
				(String) person.Id,
				(String) state.get(NamespaceUtil.stateKey('personId')),
				'The Log Hours tab opens on the person'
			);
		}
	}

	@IsTest
	static void anOrganizationGetsNoCard() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			Account organization = AccountKindsTestData.organization('Glance Hardware');
			insert organization;
			Assert.isNull(
				new VolunteersRecordGlanceExtension().glance(organization.Id),
				'Hours belong to a person'
			);
		}
	}

	@IsTest
	static void someoneWithoutVolunteersAccessGetsNoCard() {
		User reader = TestUsers.peopleReaderWith(
			'GlanceVolReader',
			new List<String>{ 'BarnCRM_Read_Only' }
		);
		Contact person;
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			person = VolunteersTestData.contacts(1)[0];
		}
		System.runAs(reader) {
			Assert.isNull(
				new VolunteersRecordGlanceExtension().glance(person.Id),
				'No Volunteers access, no card'
			);
		}
	}
}
