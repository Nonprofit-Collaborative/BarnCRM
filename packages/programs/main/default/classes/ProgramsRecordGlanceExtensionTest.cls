/**
 * Programs at a Glance (D-200 R1): the card Programs adds to Core's record pages through the
 * record glance seam (ADR-0167), read through its JSON as the page reads it.
 */
@IsTest(testFor='ApexClass:ProgramsRecordGlanceExtension')
private class ProgramsRecordGlanceExtensionTest {
	private static final String ADMIN = 'Programs_Admin';

	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(ADMIN);
	}

	private static Map<String, Object> view(RecordGlance.Card card) {
		return card == null
			? null
			: (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(card));
	}

	private static Contact personWithOneOpenEnrollment() {
		BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
			HouseholdTestDataFactory.MODE_CONTACT
		);
		settings.Auto_Create_Households__c = false;
		TestDataFactory.saveSettings(settings);
		Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Glance');
		insert ana;
		Program__c reading = new Program__c(Name = 'Summer Reading');
		Program__c tutoring = new Program__c(Name = 'Tutoring');
		insert new List<Program__c>{ reading, tutoring };
		insert new List<Enrollment__c>{
			new Enrollment__c(
				Program__c = reading.Id,
				Contact__c = ana.Id,
				Stage__c = 'Completed',
				Start_Date__c = Date.today().addDays(-10),
				End_Date__c = Date.today().addDays(-5)
			),
			new Enrollment__c(
				Program__c = tutoring.Id,
				Contact__c = ana.Id,
				Start_Date__c = Date.today().addDays(-20)
			)
		};
		return ana;
	}

	@IsTest
	static void aPersonGetsOpenEnrollmentsAndTwoActions() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Contact ana = personWithOneOpenEnrollment();

			Test.startTest();
			Map<String, Object> card = view(new ProgramsRecordGlanceExtension().glance(ana.Id));
			Test.stopTest();

			Assert.isNotNull(card, 'An admin sees the card');
			Assert.areEqual(Label.Programs_Glance_Title, card.get('title'), 'The card title');
			List<Object> tiles = (List<Object>) card.get('tiles');
			Assert.areEqual(
				1,
				(Decimal) ((Map<String, Object>) tiles[0]).get('numberValue'),
				'Only the open enrollment counts'
			);
			List<Object> actions = (List<Object>) card.get('actions');
			Assert.areEqual(2, actions.size(), 'Enroll and Record Service');
			Map<String, Object> enroll = (Map<String, Object>) JSON.deserializeUntyped(
				(String) ((Map<String, Object>) actions[0]).get('pageReference')
			);
			Map<String, Object> enrollState = (Map<String, Object>) enroll.get('state');
			Assert.isTrue(
				((String) enrollState.get('defaultFieldValues')).endsWith('=' + ana.Id),
				'A new enrollment starts with the person'
			);
			Map<String, Object> service = (Map<String, Object>) JSON.deserializeUntyped(
				(String) ((Map<String, Object>) actions[1]).get('pageReference')
			);
			Map<String, Object> serviceState = (Map<String, Object>) service.get('state');
			Assert.areEqual(
				(String) ana.Id,
				(String) serviceState.get(NamespaceUtil.stateKey('personId')),
				'The Record Service tab opens on the person'
			);
		}
	}

	@IsTest
	static void anOrganizationGetsNoCard() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Account organization = AccountKindsTestData.organization('Glance Hardware');
			insert organization;
			Assert.isNull(
				new ProgramsRecordGlanceExtension().glance(organization.Id),
				'Enrollments belong to a person'
			);
		}
	}
}
