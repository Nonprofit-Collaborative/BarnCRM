/**
 * The Volunteering at a Glance card on Core's person pages (modules-21, ADR-0167): volunteer
 * status, hours this year and in all, last volunteer date, labelled from the fields, with the
 * button to the hours; no card for a non-volunteer, an organization, no record, or someone who
 * cannot read the Volunteer Profile fields.
 */
@IsTest(testFor='ApexClass:VolunteersRecordGlanceExtension')
private class VolunteersRecordGlanceExtensionTest {
	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(VolunteersTestData.ADMIN);
		TestUsers.standardUserWith('Novolunteerglance', new List<String>{ 'BarnCRM_Read_Only' });
	}

	private static Contact person(String lastName, String status, Decimal total) {
		Contact record = HouseholdTestDataFactory.newContact('Glance', lastName);
		record.Volunteer_Status__c = status;
		record.Volunteer_Hours_This_Year__c = total == null ? null : total / 2;
		record.Volunteer_Hours_Total__c = total;
		record.Last_Volunteer_Date__c = total == null ? null : Date.today().addDays(-4);
		insert record;
		return record;
	}

	/** The card as the page reads it (JSON): Core's card fields are Core's own. */
	private static Map<String, Object> drawn(RecordGlance.Card card) {
		return card == null
			? null
			: (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(card));
	}

	/** Each figure by label: text, a whole number, or a date as the page receives it. */
	private static Map<String, Object> figures(Map<String, Object> card) {
		Map<String, Object> byLabel = new Map<String, Object>();
		for (Object tile : (List<Object>) card.get('tiles')) {
			Map<String, Object> figure = (Map<String, Object>) tile;
			Object value = figure.get('numberValue');
			if (value != null) {
				value = Decimal.valueOf(String.valueOf(value)).intValue();
			} else if (figure.get('textValue') != null) {
				value = figure.get('textValue');
			} else {
				value = figure.get('dateValue');
			}
			byLabel.put((String) figure.get('label'), value);
		}
		return byLabel;
	}

	private static String labelOf(Schema.SObjectField field) {
		return field.getDescribe().getLabel();
	}

	@IsTest
	static void aVolunteerShowsTheirProfileAtAGlance() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			VolunteersTestData.contactModeWithoutAutomaticHouseholds();
			Contact ana = person('Ana', 'Active', 40);

			Test.startTest();
			Map<String, Object> card = drawn(new VolunteersRecordGlanceExtension().glance(ana.Id));
			Test.stopTest();

			Assert.areEqual(VolunteersRecordGlanceExtension.KEY, card.get('key'), 'The card');
			Assert.areEqual(Label.Volunteers_Glance_Title, card.get('title'), 'Its title');
			Map<String, Object> byLabel = figures(card);
			Assert.areEqual(
				'Active',
				byLabel.get(labelOf(Contact.Volunteer_Status__c)),
				'The status, by its label'
			);
			Assert.areEqual(
				20,
				byLabel.get(labelOf(Contact.Volunteer_Hours_This_Year__c)),
				'This year'
			);
			Assert.areEqual(40, byLabel.get(labelOf(Contact.Volunteer_Hours_Total__c)), 'In all');
			Assert.areEqual(
				String.valueOf(Date.today().addDays(-4)),
				byLabel.get(labelOf(Contact.Last_Volunteer_Date__c)),
				'Last volunteer date'
			);
			List<Object> actions = (List<Object>) card.get('actions');
			Assert.areEqual(1, actions.size(), 'One button to the hours');
			Assert.areEqual(
				Label.Volunteers_Glance_ViewHours,
				((Map<String, Object>) actions[0]).get('label'),
				'View Volunteer Hours'
			);
		}
	}

	@IsTest
	static void noCardForANonVolunteerOrWithoutAccess() {
		Contact ana;
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			VolunteersTestData.contactModeWithoutAutomaticHouseholds();
			ana = person('Ana', 'Active', 40);
			Contact ben = person('Ben', null, null);
			Assert.isNull(new VolunteersRecordGlanceExtension().glance(ben.Id), 'Not a volunteer');
			Assert.isNull(new VolunteersRecordGlanceExtension().glance(null), 'No record');
			Assert.isNull(
				new VolunteersRecordGlanceExtension().glance(ana.AccountId),
				'A person card only'
			);
		}
		User reader = [
			SELECT Id
			FROM User
			WHERE LastName = 'Novolunteerglance'
			WITH SYSTEM_MODE
			LIMIT 1
		];
		System.runAs(reader) {
			Assert.isNull(
				new VolunteersRecordGlanceExtension().glance(ana.Id),
				'No Volunteer Profile access, no card'
			);
		}
	}

	@IsTest
	static void coreFindsTheCard() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			VolunteersTestData.contactModeWithoutAutomaticHouseholds();
			Contact ana = person('Ana', 'Active', 40);
			Boolean found = false;
			for (RecordGlance.Card card : RecordGlanceExtensions.cardsFor(ana.Id)) {
				found = found || drawn(card).get('key') == VolunteersRecordGlanceExtension.KEY;
			}
			Assert.isTrue(found, 'Registered in RecordGlanceExtensions');
		}
	}
}
