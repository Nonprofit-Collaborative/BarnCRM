/**
 * The Programs at a Glance card on Core's person pages (modules-21, ADR-0167): open
 * enrollments, the last service attended and how many, with the button to the enrollments; no
 * card for a person with neither, no record, or someone who cannot read enrollments.
 */
@IsTest(testFor='ApexClass:ProgramsRecordGlanceExtension')
private class ProgramsRecordGlanceExtensionTest {
	private static final String ADMIN = 'Programs_Admin';

	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(ADMIN);
		TestUsers.standardUserWith('Noprogramsglance', new List<String>{ 'BarnCRM_Read_Only' });
	}

	private static void contactMode() {
		BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
			HouseholdTestDataFactory.MODE_CONTACT
		);
		settings.Auto_Create_Households__c = false;
		TestDataFactory.saveSettings(settings);
	}

	/** Ana: one open and one completed enrollment, two meals attended and one missed. */
	private static Contact ana() {
		Contact person = HouseholdTestDataFactory.newContact('Ana', 'Rivera');
		insert person;
		Program__c reading = new Program__c(Name = 'Summer Reading');
		Program__c pantry = new Program__c(Name = 'Pantry');
		insert new List<Program__c>{ reading, pantry };
		insert new List<Enrollment__c>{
			new Enrollment__c(
				Program__c = reading.Id,
				Contact__c = person.Id,
				Stage__c = 'Completed',
				Start_Date__c = Date.today().addDays(-30),
				End_Date__c = Date.today().addDays(-5)
			),
			new Enrollment__c(
				Program__c = pantry.Id,
				Contact__c = person.Id,
				Start_Date__c = Date.today().addDays(-20)
			)
		};
		Service__c meal = new Service__c(Name = 'Meal', Program__c = pantry.Id);
		insert meal;
		insert new List<Service_Delivery__c>{
			new Service_Delivery__c(
				Service__c = meal.Id,
				Contact__c = person.Id,
				Delivery_Date__c = Date.today().addDays(-7)
			),
			new Service_Delivery__c(
				Service__c = meal.Id,
				Contact__c = person.Id,
				Delivery_Date__c = Date.today().addDays(-3)
			),
			new Service_Delivery__c(
				Service__c = meal.Id,
				Contact__c = person.Id,
				Delivery_Date__c = Date.today(),
				Attendance__c = 'Unexcused Absence',
				Quantity__c = 0
			)
		};
		return person;
	}

	/** The card as the page reads it (JSON): Core's card fields are Core's own. */
	private static Map<String, Object> drawn(RecordGlance.Card card) {
		return card == null
			? null
			: (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(card));
	}

	/** Each figure by label: a number, or a date as the page receives it. */
	private static Map<String, Object> figures(Map<String, Object> card) {
		Map<String, Object> byLabel = new Map<String, Object>();
		for (Object tile : (List<Object>) card.get('tiles')) {
			Map<String, Object> figure = (Map<String, Object>) tile;
			Object value = figure.get('numberValue');
			byLabel.put(
				(String) figure.get('label'),
				value == null
					? figure.get('dateValue')
					: Decimal.valueOf(String.valueOf(value)).intValue()
			);
		}
		return byLabel;
	}

	@IsTest
	static void aPersonShowsTheirProgramsAtAGlance() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			contactMode();
			Contact person = ana();

			Test.startTest();
			Map<String, Object> card = drawn(new ProgramsRecordGlanceExtension().glance(person.Id));
			Test.stopTest();

			Assert.areEqual(
				ProgramsRecordGlanceExtension.KEY,
				card.get('key'),
				'The Programs card'
			);
			Assert.areEqual(Label.Programs_Glance_Title, card.get('title'), 'Programs at a Glance');
			Map<String, Object> byLabel = figures(card);
			Assert.areEqual(
				1,
				byLabel.get(Label.Programs_Glance_OpenEnrollments),
				'Only the open enrollment'
			);
			Assert.areEqual(
				String.valueOf(Date.today().addDays(-3)),
				byLabel.get(Label.Programs_Glance_LastService),
				'The last service attended, not the missed one'
			);
			Assert.areEqual(2, byLabel.get(Label.Programs_Glance_ServicesAttended), 'Two attended');
			List<Object> actions = (List<Object>) card.get('actions');
			Assert.areEqual(1, actions.size(), 'One button to the enrollments');
			Assert.areEqual(
				Label.Programs_Glance_ViewEnrollments,
				((Map<String, Object>) actions[0]).get('label'),
				'View Enrollments'
			);
		}
	}

	@IsTest
	static void noCardWithoutProgramsOrAccess() {
		Contact person;
		Contact newcomer;
		System.runAs(TestUsers.adminWith(ADMIN)) {
			contactMode();
			person = ana();
			newcomer = HouseholdTestDataFactory.newContact('Ben', 'Okafor');
			insert newcomer;
			Assert.isNull(
				new ProgramsRecordGlanceExtension().glance(newcomer.Id),
				'No enrollment and no service, no card'
			);
			Assert.isNull(new ProgramsRecordGlanceExtension().glance(null), 'No record, no card');
		}
		User reader = [
			SELECT Id
			FROM User
			WHERE LastName = 'Noprogramsglance'
			WITH SYSTEM_MODE
			LIMIT 1
		];
		System.runAs(reader) {
			Assert.isNull(
				new ProgramsRecordGlanceExtension().glance(person.Id),
				'No Programs access, no card'
			);
		}
	}

	@IsTest
	static void coreFindsTheCard() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			contactMode();
			Contact person = ana();
			Boolean found = false;
			for (RecordGlance.Card card : RecordGlanceExtensions.cardsFor(person.Id)) {
				found = found || drawn(card).get('key') == ProgramsRecordGlanceExtension.KEY;
			}
			Assert.isTrue(found, 'Registered in RecordGlanceExtensions');
		}
	}
}
