/**
 * Minors and guardian consent (V-15, R-VU11): off by default; on, a minor's sign-up is flagged
 * and gets one Guardian consent step, named guardian included; current consent, an adult or no
 * Birthdate is not flagged; nothing is refused.
 */
@IsTest(
	testFor='ApexClass:VolunteerMinors, ApexClass:VolunteerSignupTriggerHandler, ApexTrigger:VolunteerSignupTrigger'
)
private class VolunteerMinorsTest {
	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			VolunteersTestData.contactModeWithoutAutomaticHouseholds();
			Date shiftDay = Date.today().addDays(7);
			List<Contact> people = new List<Contact>{
				HouseholdTestDataFactory.newContact('Mia', 'Minor'),
				HouseholdTestDataFactory.newContact('Ada', 'Adult'),
				HouseholdTestDataFactory.newContact('Nia', 'Nobirthdate'),
				HouseholdTestDataFactory.newContact('Gus', 'Guardian')
			};
			people[0].Birthdate = shiftDay.addYears(-15);
			people[1].Birthdate = shiftDay.addYears(-18);
			insert people;
			Volunteer_Job__c job = VolunteersTestData.job('Food pantry sort');
			Volunteer_Shift__c shift = VolunteersTestData.newShift(
				job.Id,
				Datetime.newInstance(shiftDay, Time.newInstance(9, 0, 0, 0)),
				3
			);
			shift.Volunteers_Needed__c = 10;
			insert shift;
		}
	}

	private static void consentRequired(Boolean required) {
		OrgSettingsSystemWriter.save(
			Volunteer_Settings__c.SObjectType,
			new Map<Schema.SObjectField, Object>{
				Volunteer_Settings__c.Minor_Consent_Required__c => required
			}
		);
		SettingsService.clearCaches();
	}

	private static Map<String, Id> people() {
		Map<String, Id> byName = new Map<String, Id>();
		for (Contact person : [SELECT Id, LastName FROM Contact WITH SYSTEM_MODE]) {
			byName.put(person.LastName, person.Id);
		}
		return byName;
	}

	private static List<Volunteer_Signup__c> signUp(List<Id> personIds) {
		Id shiftId = [SELECT Id FROM Volunteer_Shift__c WITH SYSTEM_MODE LIMIT 1].Id;
		List<Volunteer_Signup__c> signups = new List<Volunteer_Signup__c>();
		for (Id personId : personIds) {
			signups.add(VolunteersTestData.newSignup(shiftId, personId));
		}
		insert signups;
		return [
			SELECT Contact__r.LastName, Consent_Needed__c, Status__c
			FROM Volunteer_Signup__c
			WITH SYSTEM_MODE
		];
	}

	private static List<Volunteer_Requirement__c> consentSteps() {
		return [
			SELECT Contact__c, Guardian__c, Status__c
			FROM Volunteer_Requirement__c
			WHERE Type__c = :VolunteerMinors.TYPE_CONSENT
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void offByDefaultNobodyIsFlagged() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			Test.startTest();
			List<Volunteer_Signup__c> saved = signUp(new List<Id>{ people().get('Minor') });
			Test.stopTest();

			Assert.isFalse(saved[0].Consent_Needed__c, 'The setting ships off.');
			Assert.isTrue(consentSteps().isEmpty(), 'No step.');
		}
	}

	@IsTest
	static void onlyAMinorIsFlaggedAndGetsOneStepWithTheirGuardian() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			consentRequired(true);
			Map<String, Id> byName = people();
			VolunteerMinors.guardianByPerson.put(byName.get('Minor'), byName.get('Guardian'));

			Test.startTest();
			List<Volunteer_Signup__c> saved = signUp(
				new List<Id>{ byName.get('Minor'), byName.get('Adult'), byName.get('Nobirthdate') }
			);
			Test.stopTest();

			for (Volunteer_Signup__c signup : saved) {
				Assert.areEqual(
					signup.Contact__r.LastName == 'Minor',
					signup.Consent_Needed__c,
					signup.Contact__r.LastName
				);
				Assert.areEqual('Signed up', signup.Status__c, 'Nobody is refused.');
			}
			List<Volunteer_Requirement__c> steps = consentSteps();
			Assert.areEqual(1, steps.size(), 'One step, for the minor.');
			Assert.areEqual(byName.get('Minor'), steps[0].Contact__c, 'For the minor.');
			Assert.areEqual(
				byName.get('Guardian'),
				steps[0].Guardian__c,
				'The guardian the form named.'
			);
			Assert.areEqual('Not started', steps[0].Status__c, 'To be completed by a coordinator.');
		}
	}

	@IsTest
	static void currentOrOpenConsentAddsNoSecondStep() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			consentRequired(true);
			Id minor = people().get('Minor');
			insert new Volunteer_Requirement__c(
				Contact__c = minor,
				Type__c = VolunteerMinors.TYPE_CONSENT
			);

			Test.startTest();
			List<Volunteer_Signup__c> saved = signUp(new List<Id>{ minor });
			Test.stopTest();

			Assert.isTrue(saved[0].Consent_Needed__c, 'Not current yet, so flagged.');
			Assert.areEqual(1, consentSteps().size(), 'The open step is reused, not doubled.');
		}
	}
}
