/**
 * Session schedules (modules-24, canonical model 29ZA7): the days rule and horizon (R-SS2), the
 * run on save, nightly and at once (R-SS3), editing and ending deleting nothing (R-SS4), Remove
 * Future Sessions keeping attended, held and cancelled sessions (R-SS5), and the pattern rule
 * (R-SS1).
 */
@IsTest(
	testFor='ApexClass:SessionScheduleService, ApexClass:SessionScheduleSelector, ApexClass:SessionScheduleBatch, ApexClass:SessionScheduleJob, ApexClass:SessionScheduleTriggerHandler, ApexClass:ProgramsNightlyJobProvider, ApexClass:SessionScheduleController'
)
private class SessionScheduleServiceTest {
	private static final String ADMIN = 'Programs_Admin';
	/** A Monday: the horizon runs to 26 April 2027. */
	private static final Date MONDAY = Date.newInstance(2027, 3, 1);

	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(ADMIN);
	}

	private static User admin() {
		SessionScheduleService.todayOverride = MONDAY;
		return TestUsers.adminWith(ADMIN);
	}

	private static Service__c tutoring() {
		Program__c program = new Program__c(Name = 'After School');
		insert program;
		Service__c service = new Service__c(Program__c = program.Id, Name = 'Tutoring');
		insert service;
		return service;
	}

	private static Session_Schedule__c scheduleOf(Service__c service, String days, Integer every) {
		return new Session_Schedule__c(
			Name = 'Homework club',
			Program__c = service.Program__c,
			Service__c = service.Id,
			Weekdays__c = days,
			Every_N_Weeks__c = every,
			Start_Date__c = MONDAY,
			Start_Time__c = Time.newInstance(16, 0, 0, 0),
			End_Time__c = Time.newInstance(17, 30, 0, 0)
		);
	}

	private static List<Session__c> sessionsOf(Id scheduleId) {
		return [
			SELECT Name, Session_Date__c, Start_Time__c, End_Time__c, Status__c, Cohort__c
			FROM Session__c
			WHERE Session_Schedule__c = :scheduleId
			WITH SYSTEM_MODE
			ORDER BY Session_Date__c
		];
	}

	@IsTest
	static void savingASchedulesCreatesItsSessionsToTheHorizon() {
		System.runAs(admin()) {
			Service__c service = tutoring();
			Session_Schedule__c schedule = scheduleOf(service, 'Tuesday;Thursday', 1);

			Test.startTest();
			insert schedule;
			Test.stopTest();

			List<Session__c> sessions = sessionsOf(schedule.Id);
			Assert.areEqual(16, sessions.size(), 'Tuesdays and Thursdays for eight weeks.');
			Assert.areEqual(MONDAY.addDays(1), sessions[0].Session_Date__c, 'The first Tuesday.');
			Assert.areEqual(Time.newInstance(17, 30, 0, 0), sessions[0].End_Time__c);
			Assert.areEqual(SessionAttendance.SCHEDULED, sessions[0].Status__c);
			Assert.isTrue(
				sessions[0].Name.startsWith('Tutoring '),
				'Named as the panel names one.'
			);
			Assert.areEqual(
				MONDAY.addDays(7 * SessionScheduleService.DEFAULT_HORIZON_WEEKS),
				[SELECT Created_Through__c FROM Session_Schedule__c WITH SYSTEM_MODE]
				.Created_Through__c
			);
			Assert.areEqual(
				0,
				SessionScheduleService.run(new Set<Id>{ schedule.Id }),
				'A second run creates nothing.'
			);
		}
	}

	@IsTest
	static void everyOtherWeekAndAnEndDateLimitTheDays() {
		// runs-as: deploying user (pure date arithmetic on an unsaved record, no access involved)
		Session_Schedule__c schedule = new Session_Schedule__c(
			Weekdays__c = 'Monday;Sunday',
			Every_N_Weeks__c = 2,
			Start_Date__c = Date.newInstance(2027, 3, 3),
			End_Date__c = Date.newInstance(2027, 3, 29)
		);
		List<Date> days = SessionScheduleService.sessionDays(
			schedule,
			Date.newInstance(2027, 3, 1),
			Date.newInstance(2027, 6, 1)
		);
		Assert.areEqual(
			new List<Date>{
				Date.newInstance(2027, 3, 7),
				Date.newInstance(2027, 3, 15),
				Date.newInstance(2027, 3, 21),
				Date.newInstance(2027, 3, 29)
			},
			days,
			'From Start Date, weeks 0 and 2 of the pattern, through End Date.'
		);
		Assert.areEqual(
			'Monday;Sunday',
			SessionScheduleService.weekdayNames(new List<String>{ '0', '1' })
		);
	}

	@IsTest
	static void aDayWithASessionOfTheSameGroupIsSkippedAndEditingDeletesNothing() {
		System.runAs(admin()) {
			Service__c service = tutoring();
			// A session the panel made on the first Tuesday, for everyone in the program.
			insert new Session__c(
				Name = 'Tutoring',
				Service__c = service.Id,
				Session_Date__c = MONDAY.addDays(1)
			);
			Session_Schedule__c schedule = scheduleOf(service, 'Tuesday', 1);
			insert schedule;
			SessionScheduleService.run(new Set<Id>{ schedule.Id });

			Test.startTest();
			update new Session_Schedule__c(
				Id = schedule.Id,
				Weekdays__c = 'Wednesday',
				Active__c = false
			);
			Test.stopTest();

			Assert.areEqual(
				7,
				sessionsOf(schedule.Id).size(),
				'Eight Tuesdays less the one taken.'
			);
			Assert.areEqual(8, [SELECT COUNT() FROM Session__c WITH SYSTEM_MODE], 'No duplicate.');
			Assert.areEqual(
				0,
				SessionScheduleService.run(new Set<Id>{ schedule.Id }),
				'An inactive schedule creates nothing, and ending it deleted nothing.'
			);
		}
	}

	@IsTest
	static void removeFutureSessionsKeepsAttendedHeldAndCancelledSessions() {
		System.runAs(admin()) {
			BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
				HouseholdTestDataFactory.MODE_CONTACT
			);
			settings.Auto_Create_Households__c = false;
			TestDataFactory.saveSettings(settings);
			Service__c service = tutoring();
			Session_Schedule__c schedule = scheduleOf(service, 'Tuesday', 1);
			insert schedule;
			SessionScheduleService.run(new Set<Id>{ schedule.Id });
			List<Session__c> sessions = sessionsOf(schedule.Id);
			Contact person = HouseholdTestDataFactory.newContact('Pat', 'Lee');
			insert person;
			Enrollment__c enrollment = new Enrollment__c(
				Program__c = service.Program__c,
				Contact__c = person.Id
			);
			insert enrollment;
			insert new Service_Delivery__c(
				Service__c = service.Id,
				Session__c = sessions[0].Id,
				Contact__c = person.Id,
				Enrollment__c = enrollment.Id,
				Delivery_Date__c = sessions[0].Session_Date__c
			);
			sessions[1].Status__c = SessionAttendance.CANCELLED;
			update sessions[1];
			update new Session_Schedule__c(
				Id = schedule.Id,
				Start_Time__c = Time.newInstance(15, 0, 0, 0)
			);

			Test.startTest();
			Integer removed = SessionScheduleService.removeFutureSessions(schedule.Id);
			Test.stopTest();

			Assert.areEqual(6, removed, 'Eight Tuesdays less the attended and the cancelled one.');
			List<Session__c> after = sessionsOf(schedule.Id);
			Assert.areEqual(8, after.size(), 'Recreated from the current pattern.');
			Assert.areEqual(
				Time.newInstance(16, 0, 0, 0),
				after[0].Start_Time__c,
				'Attended: kept.'
			);
			Assert.areEqual(SessionAttendance.CANCELLED, after[1].Status__c, 'Cancelled: kept.');
			Assert.areEqual(Time.newInstance(15, 0, 0, 0), after[2].Start_Time__c, 'Recreated.');
		}
	}

	@IsTest
	static void theNightlyStepRunsEveryActiveSchedule() {
		System.runAs(admin()) {
			Service__c service = tutoring();
			SessionScheduleJob.queue(new Set<Id>());
			List<Session_Schedule__c> schedules = new List<Session_Schedule__c>{
				scheduleOf(service, 'Monday', 1),
				scheduleOf(service, 'Friday', 4)
			};
			schedules[1].Active__c = false;
			insert schedules;
			List<NightlyStep> steps = new ProgramsNightlyJobProvider().nightlySteps();

			Test.startTest();
			steps[0].run();
			Test.stopTest();

			Assert.areEqual(SessionScheduleBatch.JOB_NAME, steps[0].key);
			Assert.areEqual(
				9,
				sessionsOf(schedules[0].Id).size(),
				'Nine Mondays, today through the horizon day.'
			);
			Assert.areEqual(0, sessionsOf(schedules[1].Id).size(), 'Inactive: nothing.');
		}
	}

	@IsTest
	static void aLargeSaveHandsItsSchedulesToTheBatch() {
		System.runAs(admin()) {
			Service__c service = tutoring();
			List<Session_Schedule__c> many = new List<Session_Schedule__c>();
			for (Integer i = 0; i <= SessionScheduleBatch.CHUNK_SIZE; i++) {
				many.add(scheduleOf(service, 'Monday', 1));
			}
			AutomationControl.bypass('Session_Schedule_Rules');
			insert many;
			Set<Id> ids = new Map<Id, Session_Schedule__c>(many).keySet();
			// One deleted, so the batch reads a single chunk: a test runs one execute only.
			delete many[0];
			AutomationControl.clearBypass('Session_Schedule_Rules');

			Test.startTest();
			new SessionScheduleJob(ids).execute(null);
			Test.stopTest();

			Assert.areEqual(
				9,
				[SELECT COUNT() FROM Session__c WITH SYSTEM_MODE],
				'The batch ran the ten left, and ten schedules for one group made each Monday once.'
			);
		}
	}

	@IsTest
	static void twoSchedulesForOneGroupMakeEachDayOnceInOneRun() {
		System.runAs(admin()) {
			Service__c service = tutoring();
			Session_Schedule__c first = scheduleOf(service, 'Monday;Wednesday', 1);
			Session_Schedule__c second = scheduleOf(service, 'Monday', 1);
			AutomationControl.bypass('Session_Schedule_Rules');
			insert new List<Session_Schedule__c>{ first, second };
			AutomationControl.clearBypass('Session_Schedule_Rules');

			Test.startTest();
			Integer created = SessionScheduleService.run(new Set<Id>{ first.Id, second.Id });
			Test.stopTest();

			Assert.areEqual(17, created, 'Nine Mondays and eight Wednesdays, each once.');
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Session__c WHERE Session_Date__c = :MONDAY WITH SYSTEM_MODE],
				'One session on the first Monday, not two.'
			);
		}
	}

	@IsTest
	static void theHorizonFollowsWeeksAheadToCreateSessions() {
		System.runAs(admin()) {
			upsert new Programs_Settings__c(
				SetupOwnerId = UserInfo.getOrganizationId(),
				Session_Horizon_Weeks__c = 2
			);
			Service__c service = tutoring();
			Session_Schedule__c schedule = scheduleOf(service, 'Monday', 1);
			AutomationControl.bypass('Session_Schedule_Rules');
			insert schedule;
			AutomationControl.clearBypass('Session_Schedule_Rules');

			Test.startTest();
			Integer created = SessionScheduleService.run(new Set<Id>{ schedule.Id });
			Test.stopTest();

			Assert.areEqual(2, SessionScheduleService.horizonWeeks());
			Assert.areEqual(3, created, 'Mondays today through two weeks ahead.');
		}
	}

	@IsTest
	static void aPatternThatCannotWorkIsRefused() {
		System.runAs(admin()) {
			Service__c service = tutoring();
			Session_Schedule__c backwards = scheduleOf(service, 'Monday', 1);
			backwards.End_Time__c = Time.newInstance(15, 0, 0, 0);
			Session_Schedule__c noDays = scheduleOf(service, null, 1);
			Program__c other = new Program__c(Name = 'Pantry');
			insert other;
			Session_Schedule__c otherProgram = scheduleOf(service, 'Monday', 1);
			otherProgram.Program__c = other.Id;

			Test.startTest();
			List<Database.SaveResult> results = Database.insert(
				new List<Session_Schedule__c>{ backwards, noDays, otherProgram },
				false
			);
			Test.stopTest();

			for (Database.SaveResult result : results) {
				Assert.isFalse(result.isSuccess(), 'R-SS1 refuses it.');
			}
		}
	}

	// ------------------------------------------------------------------------------ the panels

	@IsTest
	static void thePanelSavesItsPatternAsARepeatingSchedule() {
		System.runAs(admin()) {
			Service__c service = tutoring();
			Cohort__c spring = new Cohort__c(Name = 'Spring', Program__c = service.Program__c);
			insert spring;

			Test.startTest();
			SessionScheduleController.Schedule saved = SessionScheduleController.saveRepeatingSchedule(
				spring.Id,
				service.Id,
				MONDAY,
				MONDAY.addDays(13),
				new List<String>{ '1', '3' },
				'16:00',
				null
			);
			Test.stopTest();

			Assert.isTrue(saved.canSaveSchedule, 'The admin may save schedules.');
			Assert.areEqual(4, saved.created, 'Two Mondays and two Wednesdays.');
			Session_Schedule__c schedule = [
				SELECT Name, Cohort__c, Weekdays__c, Every_N_Weeks__c, End_Date__c
				FROM Session_Schedule__c
				WHERE Id = :saved.scheduleId
				WITH SYSTEM_MODE
			];
			Assert.areEqual('Tutoring, Spring', schedule.Name);
			Assert.areEqual(spring.Id, schedule.Cohort__c);
			Assert.areEqual('Monday;Wednesday', schedule.Weekdays__c);
			Assert.areEqual(1, schedule.Every_N_Weeks__c);
			Assert.areEqual(spring.Id, sessionsOf(schedule.Id)[0].Cohort__c, 'For the cohort.');
		}
	}

	@IsTest
	static void theSchedulePagePreviewsCreatesAndRemoves() {
		System.runAs(admin()) {
			Service__c service = tutoring();
			Session_Schedule__c schedule = scheduleOf(service, 'Tuesday;Thursday', 1);
			insert schedule;

			Test.startTest();
			SessionScheduleController.Preview before = SessionScheduleController.getSchedulePreview(
				schedule.Id
			);
			SessionScheduleController.Preview created = SessionScheduleController.createSessionsNow(
				schedule.Id
			);
			SessionScheduleController.Preview removed = SessionScheduleController.removeFutureSessions(
				schedule.Id
			);
			String refusal;
			try {
				SessionScheduleController.getSchedulePreview(null);
			} catch (AuraHandledException refused) {
				refusal = refused.getMessage();
			}
			Test.stopTest();

			Assert.areEqual(16, before.missing);
			Assert.isTrue(before.canCreate && before.canRemove, 'The admin may do both.');
			Assert.areEqual(MONDAY.addDays(56), before.through);
			Assert.areEqual(16, created.created);
			Assert.areEqual(0, created.missing);
			Assert.areEqual(16, removed.removed, 'None attended: all removed, then recreated.');
			Assert.areEqual(16, sessionsOf(schedule.Id).size());
			Assert.areEqual(BarnHelp.text('Programs', 'Programs_Fail_Schedule'), refusal);
		}
	}
}
