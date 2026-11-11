/**
 * Program capacity and the waitlist (P-09, R-EN10): off by default; with Waitlist When Full on,
 * an enrollment into a full program is waitlisted, and the waitlist moves up, oldest first, when
 * someone leaves Enrolled, is deleted, or Capacity is raised or cleared.
 */
@IsTest(
	testFor='ApexClass:EnrollmentCapacity, ApexClass:EnrollmentRulesHandler, ApexClass:EnrollmentService, ApexTrigger:ProgramTrigger, ApexTrigger:EnrollmentTrigger'
)
private class EnrollmentCapacityTest {
	private static final String ADMIN = 'Programs_Admin';

	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(ADMIN);
	}

	private static void setUp(Boolean waitlist) {
		BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
			HouseholdTestDataFactory.MODE_CONTACT
		);
		settings.Auto_Create_Households__c = false;
		TestDataFactory.saveSettings(settings);
		OrgSettingsSystemWriter.save(
			Programs_Settings__c.SObjectType,
			new Map<Schema.SObjectField, Object>{
				Programs_Settings__c.Waitlist_Enabled__c => waitlist
			}
		);
		SettingsService.clearCaches();
	}

	private static Program__c program(Integer capacity) {
		Program__c record = new Program__c(
			Name = 'Tutoring',
			Status__c = 'Active',
			Capacity__c = capacity
		);
		insert record;
		return record;
	}

	private static List<Enrollment__c> enroll(Id programId, Integer howMany) {
		List<Contact> people = new List<Contact>();
		for (Integer i = 0; i < howMany; i++) {
			people.add(HouseholdTestDataFactory.newContact('Pat', 'Person' + i));
		}
		insert people;
		List<Enrollment__c> records = new List<Enrollment__c>();
		for (Contact person : people) {
			records.add(
				new Enrollment__c(
					Program__c = programId,
					Contact__c = person.Id,
					Stage__c = 'Enrolled'
				)
			);
		}
		insert records;
		return records;
	}

	private static Map<Id, Enrollment__c> stored() {
		return new Map<Id, Enrollment__c>(
			[
				SELECT Id, Stage__c, Start_Date__c
				FROM Enrollment__c
				WITH SYSTEM_MODE
				ORDER BY CreatedDate, Id
			]
		);
	}

	private static Integer countAt(String stage) {
		return [SELECT COUNT() FROM Enrollment__c WHERE Stage__c = :stage WITH SYSTEM_MODE];
	}

	@IsTest
	static void withTheSettingOffCapacityOnlyShows() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			setUp(false);
			Program__c full = program(1);

			Test.startTest();
			enroll(full.Id, 3);
			Test.stopTest();

			Assert.areEqual(
				3,
				countAt('Enrolled'),
				'Nothing is waitlisted while the setting is off.'
			);
		}
	}

	@IsTest
	static void aFullProgramWaitlistsTheRestOfABulkSave() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			setUp(true);
			Program__c tutoring = program(2);

			Test.startTest();
			List<Enrollment__c> saved = enroll(tutoring.Id, 5);
			Test.stopTest();

			Map<Id, Enrollment__c> byId = stored();
			Assert.areEqual('Enrolled', byId.get(saved[0].Id).Stage__c, 'The first fits.');
			Assert.areEqual('Enrolled', byId.get(saved[1].Id).Stage__c, 'The second fits.');
			for (Integer i = 2; i < 5; i++) {
				Assert.areEqual(
					'Waitlisted',
					byId.get(saved[i].Id).Stage__c,
					'Past Capacity, in order.'
				);
				Assert.isNull(
					byId.get(saved[i].Id).Start_Date__c,
					'A waitlisted person has not started.'
				);
			}
			Database.SaveResult again = Database.insert(
				new Enrollment__c(
					Program__c = tutoring.Id,
					Contact__c = saved[4].Contact__c,
					Stage__c = 'Applied'
				),
				false
			);
			Assert.isFalse(
				again.isSuccess(),
				'Waitlisted is open: one open enrollment per person (R-EN2).'
			);
		}
	}

	@IsTest
	static void leavingEnrolledOrDeletingMovesTheOldestUp() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			setUp(true);
			Program__c tutoring = program(1);
			List<Enrollment__c> saved = enroll(tutoring.Id, 3);

			Test.startTest();
			update new Enrollment__c(Id = saved[0].Id, Stage__c = 'Withdrawn');
			Map<Id, Enrollment__c> afterWithdraw = stored();
			delete new Enrollment__c(Id = saved[1].Id);
			Test.stopTest();

			Assert.areEqual(
				'Enrolled',
				afterWithdraw.get(saved[1].Id).Stage__c,
				'The oldest waiting moves up.'
			);
			Assert.areEqual(
				Date.today(),
				afterWithdraw.get(saved[1].Id).Start_Date__c,
				'R-EN3 fills the Start Date.'
			);
			Assert.areEqual(
				'Waitlisted',
				afterWithdraw.get(saved[2].Id).Stage__c,
				'One place, one moved.'
			);
			Assert.areEqual(
				'Enrolled',
				stored().get(saved[2].Id).Stage__c,
				'A deleted enrollment frees its place.'
			);
		}
	}

	@IsTest
	static void raisingOrClearingCapacityMovesTheWaitlistUp() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			setUp(true);
			Program__c tutoring = program(1);
			enroll(tutoring.Id, 4);

			Test.startTest();
			tutoring.Capacity__c = 2;
			update tutoring;
			Integer enrolledAtTwo = countAt('Enrolled');
			tutoring.Capacity__c = null;
			update tutoring;
			Test.stopTest();

			Assert.areEqual(2, enrolledAtTwo, 'Raised by one, one more enrolled.');
			Assert.areEqual(4, countAt('Enrolled'), 'No Capacity: everyone waiting is enrolled.');
			Assert.areEqual(0, countAt('Waitlisted'), 'Nobody is left waiting.');
		}
	}
}
