/**
 * The Programs sample data set, shipped as ProgramsSampleData.json and loaded by Core's
 * SampleDataFile (D-200 S2): the load builds three programs, five services and 18 enrollments of
 * Core's sample people through the enrollment rules, with two cohorts, sessions, a repeating
 * session schedule and service plan goals; the removal takes every one of them and
 * leaves real records alone, keeping a sample program a real person is enrolled in and naming it
 * in the Error Log. Run as a BarnCRM admin holding Programs Admin, the person who loads sample
 * data. The stages are called directly, because a test runs only the first stage of a batch.
 */
@IsTest(testFor='ApexClass:SampleDataFile')
private class ProgramSampleDataTest {
	private static final String ADMIN = 'Programs_Admin';
	private static final String FILE = 'ProgramsSampleData';

	/** The first twelve of Core's sample people, in key order, as the file names them. */
	private static final List<String> KEYS = new List<String>{
		'H001-1',
		'H001-2',
		'H001-3',
		'H002-1',
		'H002-2',
		'H002-3',
		'H002-4',
		'H002-5',
		'H002-6',
		'H003-1',
		'H003-2',
		'H004-1'
	};

	@TestSetup
	static void makeAdmin() {
		TestUsers.adminWith(ADMIN);
	}

	private static User admin() {
		return TestUsers.adminWith(ADMIN);
	}

	private static List<Contact> samplePeople(Integer howMany) {
		BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
			HouseholdTestDataFactory.MODE_CONTACT
		);
		settings.Auto_Create_Households__c = false;
		TestDataFactory.saveSettings(settings);
		List<Contact> people = new List<Contact>();
		for (Integer i = 0; i < howMany; i++) {
			Contact person = HouseholdTestDataFactory.newContact('Sample', 'Person' + i);
			person.Sample_Data__c = true;
			person.Sample_Data_Key__c = KEYS[i];
			people.add(person);
		}
		insert people;
		return people;
	}

	private static void loadEverything() {
		SampleDataFile.LoadStages stages = new SampleDataFile.LoadStages(FILE);
		for (Integer stage = 0; stage < stages.stageCount(); stage++) {
			stages.runStage(stage);
		}
	}

	private static void removeEverything() {
		SampleDataFile.RemoveStages stages = new SampleDataFile.RemoveStages(FILE);
		Integer stageCount = stages.stageCount();
		for (Integer stage = 0; stage < stageCount; stage++) {
			stages.runStage(stage);
		}
		stages.finish();
	}

	private static Integer countAt(String stage) {
		return [SELECT COUNT() FROM Enrollment__c WHERE Stage__c = :stage];
	}

	private static List<Error_Log__c> keptWarnings() {
		return [SELECT Message__c FROM Error_Log__c WHERE Context__c = 'SampleDataFile'];
	}

	@IsTest
	static void theLoadBuildsTheWholeSet() {
		System.runAs(admin()) {
			samplePeople(12);

			Test.startTest();
			loadEverything();
			Test.stopTest();

			Assert.areEqual(3, [SELECT COUNT() FROM Program__c WHERE Sample_Data__c = TRUE]);
			Assert.areEqual(5, [SELECT COUNT() FROM Service__c], 'Five services.');
			Assert.areEqual(18, [SELECT COUNT() FROM Enrollment__c], 'Eighteen enrollments.');
			Assert.areEqual(12, countAt('Enrolled'), 'Four in tutoring and eight in the pantry.');
			Assert.areEqual(1, countAt('Applied'), 'One applied.');
			Assert.areEqual(1, countAt('Withdrawn'), 'One withdrew.');
			Assert.areEqual(4, countAt('Completed'), 'Four completed summer reading.');
			Assert.areEqual(
				40,
				[
					SELECT COUNT()
					FROM Service_Delivery__c
					WHERE Enrollment__c != NULL AND Session__c = NULL
				],
				'Four weeks of bags for eight and two sessions for four, each linked.'
			);
			Cohort__c cohort = [
				SELECT Id, Status__c, (SELECT Id FROM Enrollments__r)
				FROM Cohort__c
				WHERE Name = 'Fall homework club'
			];
			Assert.areEqual('Active', cohort.Status__c, 'One active cohort.');
			Assert.areEqual(4, cohort.Enrollments__r.size(), 'Holding the four in tutoring.');
			Assert.areEqual(
				3,
				[
					SELECT COUNT()
					FROM Session__c
					WHERE Cohort__c = :cohort.Id AND Session_Schedule__c = NULL
				],
				'Three sessions set by hand.'
			);
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Session__c
					WHERE Status__c = 'Scheduled' AND Session_Schedule__c = NULL
				]
			);
			Session_Schedule__c schedule = [
				SELECT Id, Active__c, Cohort__c
				FROM Session_Schedule__c
			];
			Assert.isTrue(schedule.Active__c, 'One active repeating schedule.');
			Assert.areEqual(cohort.Id, schedule.Cohort__c, 'For the homework club.');
			Assert.isTrue(
				[
					SELECT COUNT()
					FROM Session__c
					WHERE Session_Schedule__c = :schedule.Id AND Status__c = 'Scheduled'
				] > 0,
				'Its save queued a run that created the coming sessions.'
			);
			Cohort__c circle = [
				SELECT Id, Status__c, (SELECT Id FROM Enrollments__r)
				FROM Cohort__c
				WHERE Name = 'Summer reading circle'
			];
			Assert.areEqual('Completed', circle.Status__c, 'One completed cohort.');
			Assert.areEqual(4, circle.Enrollments__r.size(), 'Holding the four who completed.');
			Assert.areEqual(
				8,
				[SELECT COUNT() FROM Service_Delivery__c WHERE Session__c != NULL],
				'Attendance for four people at two held sessions.'
			);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Service_Delivery__c WHERE Attendance__c = 'Excused Absence']
			);
			Assert.areEqual(
				0,
				[
					SELECT Quantity__c
					FROM Service_Delivery__c
					WHERE Attendance__c = 'Unexcused Absence'
				]
				.Quantity__c,
				'One missed week, which delivered nothing.'
			);
			Assert.areEqual(
				6,
				[SELECT COUNT() FROM Goal__c],
				'A goal for each in tutoring, one in summer reading and one in the pantry.'
			);
			Assert.areEqual(
				6,
				[SELECT COUNT() FROM Goal__c WHERE Assigned_To__c = :UserInfo.getUserId()],
				'Each assigned to the person who loaded them.'
			);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Goal__c WHERE Next_Review_Date__c < TODAY],
				'One review is due.'
			);
			Goal__c achieved = [SELECT Closed_Date__c FROM Goal__c WHERE Status__c = 'Achieved'];
			Assert.areEqual(Date.today().addDays(-95), achieved.Closed_Date__c, 'Kept as loaded.');
			Assert.areEqual(7, [SELECT COUNT() FROM Goal_Step__c WHERE Status__c = 'Done']);
			Assert.areEqual(12, [SELECT COUNT() FROM Goal_Step__c], 'Two steps each.');
			SampleDataModule module = SampleDataFile.find(FILE);
			Assert.areEqual('Programs', module.moduleName(), 'The name startAfter looks for.');
			Assert.areEqual(18, module.countLoaded(), 'The card counts them.');
			Assert.isTrue(module.hasSampleRecords(), 'Sample programs exist.');
		}
	}

	@IsTest
	static void fewSamplePeopleAreEnrolledAndTheRestLeftOut() {
		System.runAs(admin()) {
			samplePeople(2);

			Test.startTest();
			loadEverything();
			Test.stopTest();

			Assert.isTrue(
				[SELECT COUNT() FROM Enrollment__c] > 0,
				'The two people are enrolled without a refused save.'
			);
		}
	}

	@IsTest
	static void removalTakesEverySampleRecordAndLeavesRealOnesAlone() {
		System.runAs(admin()) {
			samplePeople(12);
			loadEverything();
			Program__c real = new Program__c(Name = 'Our own program');
			insert real;
			Contact person = HouseholdTestDataFactory.newContact('Rita', 'Real');
			insert person;
			insert new Enrollment__c(Program__c = real.Id, Contact__c = person.Id);
			SampleDataFile.removeChunkSize = 20;

			Test.startTest();
			removeEverything();
			Test.stopTest();

			Assert.areEqual(0, [SELECT COUNT() FROM Program__c WHERE Sample_Data__c = TRUE]);
			Assert.areEqual(0, [SELECT COUNT() FROM Service__c], 'Services went with them.');
			Assert.areEqual(1, [SELECT COUNT() FROM Enrollment__c], 'Only the real one is left.');
			Assert.areEqual(0, [SELECT COUNT() FROM Service_Delivery__c], 'Deliveries went first.');
			Assert.areEqual(0, [SELECT COUNT() FROM Session__c], 'Sessions went.');
			Assert.areEqual(0, [SELECT COUNT() FROM Session_Schedule__c], 'The schedule went.');
			Assert.areEqual(0, [SELECT COUNT() FROM Cohort__c], 'The cohorts went.');
			Assert.areEqual(0, [SELECT COUNT() FROM Goal__c], 'Goals went with enrollments.');
			Assert.isFalse(SampleDataFile.find(FILE).hasSampleRecords(), 'Nothing left.');
			Assert.isTrue(keptWarnings().isEmpty(), 'Nothing was kept.');
		}
	}

	@IsTest
	static void aRealPersonsEnrollmentKeepsTheSampleProgram() {
		System.runAs(admin()) {
			samplePeople(12);
			loadEverything();
			Program__c pantry = [SELECT Id FROM Program__c WHERE Name = 'Food pantry'];
			Contact person = HouseholdTestDataFactory.newContact('Rita', 'Real');
			insert person;
			insert new Enrollment__c(Program__c = pantry.Id, Contact__c = person.Id);

			Test.startTest();
			removeEverything();
			Test.stopTest();

			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Program__c WHERE Sample_Data__c = TRUE],
				'The pantry stays, with its real enrollment.'
			);
			Assert.areEqual(1, [SELECT COUNT() FROM Enrollment__c], 'The real enrollment stays.');
			List<Error_Log__c> logged = keptWarnings();
			Assert.areEqual(1, logged.size(), 'One Warning names it.');
			Assert.isTrue(logged[0].Message__c.contains('Food pantry'), 'By name.');
		}
	}

	@IsTest
	static void aSampleEnrollmentWithACaseNoteKeepsItsProgram() {
		System.runAs(admin()) {
			samplePeople(12);
			loadEverything();
			Enrollment__c noted = [
				SELECT Id
				FROM Enrollment__c
				WHERE Program__r.Name = 'Food pantry'
				LIMIT 1
			];
			insert new Case_Note__c(Enrollment__c = noted.Id, Subject__c = 'Kept', Note__c = 'x');

			Test.startTest();
			removeEverything();
			Test.stopTest();

			Assert.areEqual(
				new List<Id>{ noted.Id },
				new List<Id>(new Map<Id, Enrollment__c>([SELECT Id FROM Enrollment__c]).keySet()),
				'Only the enrollment with a case note stays, so removal does not fail on it.'
			);
			Assert.areEqual(
				'Food pantry',
				[SELECT Name FROM Program__c WHERE Sample_Data__c = TRUE].Name,
				'Its program stays.'
			);
			Assert.isTrue(
				keptWarnings()[0].Message__c.contains('Food pantry'),
				'And is named, like a program with real enrollments.'
			);
		}
	}

	@IsTest
	static void withNoSamplePeopleTheProgramsStillLoad() {
		System.runAs(admin()) {
			Assert.areEqual(0, SampleDataFile.find(FILE).countLoaded(), 'Nothing loaded yet.');

			Test.startTest();
			loadEverything();
			Test.stopTest();

			Assert.areEqual(3, [SELECT COUNT() FROM Program__c], 'The programs load.');
			Assert.areEqual(0, [SELECT COUNT() FROM Enrollment__c], 'Nobody to enroll.');
		}
	}
}
