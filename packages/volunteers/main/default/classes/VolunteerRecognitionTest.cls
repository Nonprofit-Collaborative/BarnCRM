/**
 * Thank-you tasks (V-13, R-VP4): one per new hour milestone, one per volunteering anniversary,
 * never twice; off by default; a step of the nightly run at 7:30 AM.
 */
@IsTest(
	testFor='ApexClass:VolunteerRecognitionJob, ApexClass:VolunteerRecognitionScheduler, ApexClass:VolunteersNightlyJobProvider, ApexClass:VolunteerSettings'
)
private class VolunteerRecognitionTest {
	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			VolunteersTestData.contactModeWithoutAutomaticHouseholds();
			List<Contact> people = new List<Contact>{
				HouseholdTestDataFactory.newContact('Ana', 'Fifty'),
				HouseholdTestDataFactory.newContact('Ben', 'Thanked'),
				HouseholdTestDataFactory.newContact('Cy', 'Anniversary')
			};
			people[0].Volunteer_Hours_Total__c = 60;
			people[1].Volunteer_Hours_Total__c = 30;
			people[1].Last_Hour_Milestone__c = 25;
			people[2].Volunteer_Since__c = Date.today().addYears(-2);
			Database.insert(people, AccessLevel.SYSTEM_MODE);
		}
	}

	private static void recognition(Boolean enabled) {
		OrgSettingsSystemWriter.save(
			Volunteer_Settings__c.SObjectType,
			new Map<Schema.SObjectField, Object>{
				Volunteer_Settings__c.Recognition_Enabled__c => enabled
			}
		);
		SettingsService.clearCaches();
	}

	private static Map<String, Contact> people() {
		Map<String, Contact> byName = new Map<String, Contact>();
		for (Contact person : [
			SELECT Id, LastName, Last_Hour_Milestone__c
			FROM Contact
			WITH SYSTEM_MODE
		]) {
			byName.put(person.LastName, person);
		}
		return byName;
	}

	@IsTest
	static void eachMilestoneAndAnniversaryIsThankedOnce() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			Map<String, Contact> before = people();
			Set<Id> ids = new Map<Id, Contact>(before.values()).keySet();

			Test.startTest();
			Integer first = VolunteerRecognitionJob.thank(ids);
			Integer second = VolunteerRecognitionJob.thank(ids);
			Test.stopTest();

			Assert.areEqual(2, first, 'One milestone, one anniversary.');
			Assert.areEqual(0, second, 'Never twice.');
			Assert.areEqual(
				50,
				people().get('Fifty').Last_Hour_Milestone__c,
				'The highest reached is stamped.'
			);
			Task milestone = [
				SELECT Subject, ActivityDate, Status
				FROM Task
				WHERE WhoId = :before.get('Fifty').Id
				WITH SYSTEM_MODE
			];
			Assert.isTrue(
				milestone.Subject.contains('50'),
				'Names the milestone: ' + milestone.Subject
			);
			Assert.areEqual(Date.today(), milestone.ActivityDate, 'Due today.');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Task
					WHERE WhoId = :before.get('Anniversary').Id
					WITH SYSTEM_MODE
				],
				'One anniversary task.'
			);
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Task WHERE WhoId = :before.get('Thanked').Id WITH SYSTEM_MODE],
				'Already thanked for 25, short of 50.'
			);
		}
	}

	@IsTest
	static void theMorningStepRunsOnlyWhenTurnedOn() {
		System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
			VolunteerRecognitionScheduler.jobNameInUse = 'BarnCRM Volunteer Thank-Yous test';
			Assert.isNull(VolunteerRecognitionJob.startMorning(), 'Off by default.');
			recognition(true);
			NightlyStep step = new VolunteersNightlyJobProvider().nightlySteps()[3];

			Test.startTest();
			step.run();
			Test.stopTest();

			Assert.areEqual(450, step.minute, 'Half past seven in the morning.');
			Assert.areEqual(Label.Volunteers_NightlyJobs_RecognitionName, step.label, 'Its label.');
			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Task WITH SYSTEM_MODE],
				'The batch made the tasks.'
			);
		}
	}
}
