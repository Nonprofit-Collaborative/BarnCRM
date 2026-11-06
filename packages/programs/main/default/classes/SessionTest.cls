/**
 * Sessions (P-11, canonical model 29ZA6): scheduling them in a batch (R-SE4), the rule that a
 * session's cohort is of its service's program (R-SE1), and attendance taken on a session as
 * Service Delivery (R-SE2, R-SE3, R-SD7), including adopting a delivery with no session and one
 * the user cannot see.
 */
@IsTest(
	testFor='ApexClass:SessionScheduleController, ApexClass:SessionAttendance, ApexClass:ServiceDeliveryLogController, ApexClass:ServiceDeliveryIntegrity, ApexClass:CohortSelector'
)
private class SessionTest {
	private static final String ADMIN = 'Programs_Admin';
	private static final List<String> STAFF = new List<String>{ 'BarnCRM_Staff', 'Programs_Staff' };

	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(ADMIN);
	}

	private static User admin() {
		return TestUsers.adminWith(ADMIN);
	}

	private static void contactMode() {
		BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
			HouseholdTestDataFactory.MODE_CONTACT
		);
		settings.Auto_Create_Households__c = false;
		TestDataFactory.saveSettings(settings);
	}

	/** A program with an active Tutoring service, run as the admin. */
	private static Service__c tutoring() {
		Program__c program = new Program__c(Name = 'After School');
		insert program;
		Service__c service = new Service__c(
			Program__c = program.Id,
			Name = 'Tutoring',
			Unit_Of_Measure__c = 'hours'
		);
		insert service;
		return service;
	}

	private static Cohort__c cohortOf(Id programId, String name) {
		Cohort__c cohort = new Cohort__c(
			Name = name,
			Program__c = programId,
			Start_Date__c = Date.newInstance(2027, 3, 1),
			End_Date__c = Date.newInstance(2027, 3, 31)
		);
		insert cohort;
		return cohort;
	}

	private static Enrollment__c enroll(Id programId, Id cohortId, String lastName) {
		Contact person = HouseholdTestDataFactory.newContact('Pat', lastName);
		insert person;
		Enrollment__c enrollment = new Enrollment__c(
			Program__c = programId,
			Contact__c = person.Id,
			Cohort__c = cohortId
		);
		insert enrollment;
		return enrollment;
	}

	private static Session__c sessionOf(Service__c service, Id cohortId, Date day) {
		Session__c session = new Session__c(
			Name = 'Tutoring',
			Service__c = service.Id,
			Cohort__c = cohortId,
			Session_Date__c = day
		);
		insert session;
		return session;
	}

	private static ServiceDeliveryLogController.Row rowOf(
		ServiceDeliveryLogController.Log log,
		Id person
	) {
		for (ServiceDeliveryLogController.Row row : log.rows) {
			if (row.key == person) {
				return row;
			}
		}
		return null;
	}

	private static ServiceDeliveryLogController.Entry entry(
		Enrollment__c enrollment,
		Id deliveryId,
		String attendance,
		Decimal quantity
	) {
		ServiceDeliveryLogController.Entry entry = new ServiceDeliveryLogController.Entry();
		entry.contactId = enrollment.Contact__c;
		entry.enrollmentId = enrollment.Id;
		entry.deliveryId = deliveryId;
		entry.attendance = attendance;
		entry.quantity = quantity;
		return entry;
	}

	// ------------------------------------------------------------------------------ scheduling

	@IsTest
	static void schedulingOnACohortCreatesOneSessionPerDateForTheCohort() {
		System.runAs(admin()) {
			Service__c service = tutoring();
			Cohort__c spring = cohortOf(service.Program__c, 'Spring');
			Date first = Date.newInstance(2027, 3, 2);
			Date second = Date.newInstance(2027, 3, 9);

			Test.startTest();
			SessionScheduleController.Schedule offered = SessionScheduleController.getSchedule(
				spring.Id
			);
			SessionScheduleController.Schedule done = SessionScheduleController.scheduleSessions(
				spring.Id,
				service.Id,
				new List<Date>{ second, first, second, null },
				'18:30:00.000'
			);
			Test.stopTest();

			Assert.areEqual(
				spring.Start_Date__c,
				offered.startDate,
				'The cohort\'s dates offered.'
			);
			Assert.areEqual(1, offered.services.size(), 'The program\'s active service.');
			Assert.isTrue(offered.canSchedule, 'The admin may schedule.');
			Assert.areEqual(2, done.created, 'One per distinct date.');
			List<Session__c> sessions = [
				SELECT Name, Cohort__c, Session_Date__c, Start_Time__c, Status__c
				FROM Session__c
				WITH SYSTEM_MODE
				ORDER BY Session_Date__c
			];
			Assert.areEqual(2, sessions.size());
			Assert.areEqual(first, sessions[0].Session_Date__c);
			Assert.areEqual(spring.Id, sessions[0].Cohort__c, 'For the cohort.');
			Assert.areEqual(Time.newInstance(18, 30, 0, 0), sessions[0].Start_Time__c);
			Assert.areEqual(SessionAttendance.SCHEDULED, sessions[0].Status__c);
			Assert.isTrue(sessions[0].Name.startsWith('Tutoring '), 'Named after the service.');
		}
	}

	@IsTest
	static void schedulingOnAProgramCreatesSessionsWithNoCohort() {
		System.runAs(admin()) {
			Service__c service = tutoring();

			Test.startTest();
			SessionScheduleController.Schedule done = SessionScheduleController.scheduleSessions(
				service.Program__c,
				service.Id,
				new List<Date>{ Date.newInstance(2027, 4, 5) },
				null
			);
			Test.stopTest();

			Assert.areEqual(1, done.created);
			Assert.isNull(done.cohortId);
			Session__c session = [
				SELECT Cohort__c, Start_Time__c
				FROM Session__c
				WITH SYSTEM_MODE
				LIMIT 1
			];
			Assert.isNull(session.Cohort__c, 'For everyone in the program.');
			Assert.isNull(session.Start_Time__c, 'No start time given.');
		}
	}

	@IsTest
	static void schedulingTwiceSkipsDaysThatAlreadyHaveASessionForTheSameCohort() {
		System.runAs(admin()) {
			Service__c service = tutoring();
			Cohort__c spring = cohortOf(service.Program__c, 'Spring');
			Date first = Date.newInstance(2027, 3, 2);
			Date second = Date.newInstance(2027, 3, 9);
			Date third = Date.newInstance(2027, 3, 16);
			// Another cohort's session and a program-wide one on the first day do not count; a
			// cancelled session of this cohort on the third day does not either.
			Cohort__c fall = cohortOf(service.Program__c, 'Fall');
			sessionOf(service, fall.Id, first);
			sessionOf(service, null, first);
			Session__c cancelled = sessionOf(service, spring.Id, third);
			cancelled.Status__c = SessionAttendance.CANCELLED;
			update cancelled;

			Test.startTest();
			SessionScheduleController.Schedule once = SessionScheduleController.scheduleSessions(
				spring.Id,
				service.Id,
				new List<Date>{ first, second },
				null
			);
			List<Date> taken = SessionScheduleController.getTakenDays(
				spring.Id,
				service.Id,
				first,
				third
			);
			SessionScheduleController.Schedule twice = SessionScheduleController.scheduleSessions(
				spring.Id,
				service.Id,
				new List<Date>{ first, second, third },
				null
			);
			Test.stopTest();

			Assert.areEqual(2, once.created, 'The other cohort and program-wide sessions differ.');
			Assert.areEqual(0, once.skipped);
			Assert.areEqual(new List<Date>{ first, second }, taken, 'Cancelled days are free.');
			Assert.areEqual(1, twice.created, 'Only the day with no session of the cohort.');
			Assert.areEqual(2, twice.skipped, 'Both days scheduled the first time.');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Session__c
					WHERE Cohort__c = :spring.Id AND Session_Date__c = :second
					WITH SYSTEM_MODE
				],
				'No duplicate session.'
			);
			Assert.areEqual(
				0,
				SessionScheduleController.getTakenDays(spring.Id, service.Id, third, first).size(),
				'A range ending before it starts has no days.'
			);
		}
	}

	@IsTest
	static void schedulingIsRefusedForAnotherServiceTooManyDatesOrABadTime() {
		System.runAs(admin()) {
			Service__c service = tutoring();
			Program__c other = new Program__c(Name = 'Pantry');
			insert other;
			Service__c meal = new Service__c(Program__c = other.Id, Name = 'Meal');
			insert meal;
			Service__c inactive = new Service__c(
				Program__c = service.Program__c,
				Name = 'Old',
				Active__c = false
			);
			insert inactive;
			List<Date> tooMany = new List<Date>();
			for (Integer i = 0; i <= SessionScheduleController.MAX_SESSIONS; i++) {
				tooMany.add(Date.newInstance(2027, 1, 1).addDays(i));
			}
			List<Date> one = new List<Date>{ Date.newInstance(2027, 4, 5) };

			Test.startTest();
			List<String> refusals = new List<String>();
			for (Integer attempt = 0; attempt < 6; attempt++) {
				try {
					switch on attempt {
						when 0 {
							SessionScheduleController.scheduleSessions(
								service.Program__c,
								meal.Id,
								one,
								null
							);
						}
						when 1 {
							SessionScheduleController.scheduleSessions(
								service.Program__c,
								inactive.Id,
								one,
								null
							);
						}
						when 2 {
							SessionScheduleController.scheduleSessions(
								service.Program__c,
								service.Id,
								tooMany,
								null
							);
						}
						when 3 {
							SessionScheduleController.scheduleSessions(
								service.Program__c,
								service.Id,
								one,
								'25:00'
							);
						}
						when 4 {
							SessionScheduleController.scheduleSessions(
								service.Program__c,
								service.Id,
								new List<Date>(),
								null
							);
						}
						when else {
							SessionScheduleController.getSchedule(service.Id);
						}
					}
					refusals.add(null);
				} catch (AuraHandledException refused) {
					refusals.add(refused.getMessage());
				}
			}
			Test.stopTest();

			Assert.areEqual(
				Label.Programs_Schedule_ServiceRequired,
				refusals[0],
				'Not its service.'
			);
			Assert.areEqual(Label.Programs_Schedule_ServiceRequired, refusals[1], 'Not active.');
			Assert.areEqual(
				String.format(
					Label.Programs_Schedule_TooMany,
					new List<Object>{ SessionScheduleController.MAX_SESSIONS }
				),
				refusals[2]
			);
			Assert.areEqual(Label.Programs_Schedule_BadTime, refusals[3]);
			Assert.areEqual(Label.Programs_Schedule_NoDates, refusals[4]);
			Assert.areEqual(
				BarnHelp.text('Programs', 'Programs_Fail_Schedule'),
				refusals[5],
				'Not a cohort or program.'
			);
			Assert.areEqual(0, [SELECT COUNT() FROM Session__c WITH SYSTEM_MODE], 'Nothing made.');
		}
	}

	@IsTest
	static void aSessionsCohortMustBeOfItsServicesProgram() {
		System.runAs(admin()) {
			Service__c service = tutoring();
			Program__c other = new Program__c(Name = 'Pantry');
			insert other;
			Cohort__c elsewhere = cohortOf(other.Id, 'Elsewhere');

			Test.startTest();
			Database.SaveResult result = Database.insert(
				new Session__c(
					Name = 'Wrong',
					Service__c = service.Id,
					Cohort__c = elsewhere.Id,
					Session_Date__c = Date.today()
				),
				false
			);
			Test.stopTest();

			Assert.isFalse(result.isSuccess(), 'R-SE1: a cohort of another program is refused.');
		}
	}

	// ------------------------------------------------------------------------------ attendance

	@IsTest
	static void attendanceOnACohortSessionListsTheCohortAndMarksItHeld() {
		System.runAs(admin()) {
			contactMode();
			Service__c service = tutoring();
			Cohort__c spring = cohortOf(service.Program__c, 'Spring');
			Enrollment__c ana = enroll(service.Program__c, spring.Id, 'Ana');
			Enrollment__c ben = enroll(service.Program__c, spring.Id, 'Ben');
			Enrollment__c cara = enroll(service.Program__c, null, 'Cara');
			Session__c session = sessionOf(service, spring.Id, Date.newInstance(2027, 3, 2));

			Test.startTest();
			ServiceDeliveryLogController.Log before = ServiceDeliveryLogController.getSessionLog(
				session.Id
			);
			ServiceDeliveryLogController.Log after = ServiceDeliveryLogController.saveSession(
				session.Id,
				new List<ServiceDeliveryLogController.Entry>{
					entry(ana, null, 'Present', 2),
					entry(ben, null, 'Unexcused Absence', 2)
				}
			);
			ServiceDeliveryLogController.Row anaRow = rowOf(after, ana.Contact__c);
			ServiceDeliveryLogController.Log again = ServiceDeliveryLogController.saveSession(
				session.Id,
				new List<ServiceDeliveryLogController.Entry>{
					entry(ana, anaRow.deliveryId, 'Present', 3)
				}
			);
			Test.stopTest();

			Assert.areEqual(2, before.rows.size(), 'The cohort only.');
			Assert.isNull(rowOf(before, cara.Contact__c), 'Not in the cohort.');
			Assert.areEqual(session.Id, before.sessionId);
			Assert.areEqual('Spring', before.cohortName);
			Assert.areEqual(service.Id, before.serviceId, 'The session\'s service.');
			Assert.areEqual(session.Session_Date__c, before.deliveryDate, 'The session\'s day.');
			Assert.isTrue(before.canEdit);
			Assert.areEqual(2, after.saved);
			Assert.areEqual(1, again.saved);
			List<Service_Delivery__c> rows = [
				SELECT Contact__c, Session__c, Quantity__c, Delivery_Date__c
				FROM Service_Delivery__c
				WITH SYSTEM_MODE
			];
			Assert.areEqual(2, rows.size(), 'R-SD7: one row per person per session.');
			for (Service_Delivery__c row : rows) {
				Assert.areEqual(session.Id, row.Session__c, 'Each names the session.');
				Assert.areEqual(session.Session_Date__c, row.Delivery_Date__c);
				if (row.Contact__c == ana.Contact__c) {
					Assert.areEqual(3, row.Quantity__c, 'Changed, not doubled.');
				} else {
					Assert.areEqual(0, row.Quantity__c, 'R-SD2: an absence delivers nothing.');
				}
			}
			Assert.areEqual(
				SessionAttendance.HELD,
				[SELECT Status__c FROM Session__c WHERE Id = :session.Id WITH SYSTEM_MODE]
				.Status__c,
				'R-SE2: saving marks it Held.'
			);
		}
	}

	@IsTest
	static void aSessionWithNoCohortListsTheProgramAndAdoptsADeliveryWithNoSession() {
		System.runAs(admin()) {
			contactMode();
			Service__c service = tutoring();
			Enrollment__c ana = enroll(service.Program__c, null, 'Ana');
			Date day = Date.newInstance(2027, 3, 2);
			Session__c session = sessionOf(service, null, day);
			Service_Delivery__c earlier = new Service_Delivery__c(
				Service__c = service.Id,
				Contact__c = ana.Contact__c,
				Enrollment__c = ana.Id,
				Delivery_Date__c = day,
				Attendance__c = 'Present',
				Quantity__c = 1
			);
			insert earlier;

			Test.startTest();
			ServiceDeliveryLogController.Log before = ServiceDeliveryLogController.getSessionLog(
				session.Id
			);
			// Sent as new, as a page opened before the earlier row was made would.
			ServiceDeliveryLogController.saveSession(
				session.Id,
				new List<ServiceDeliveryLogController.Entry>{ entry(ana, null, 'Present', 2) }
			);
			Test.stopTest();

			Assert.areEqual(1, before.rows.size(), 'The program\'s open enrollments.');
			Assert.isNull(before.cohortName, 'No cohort: everyone in the program.');
			Assert.areEqual(earlier.Id, before.rows[0].deliveryId, 'The no-session row is shown.');
			List<Service_Delivery__c> rows = [
				SELECT Id, Session__c, Quantity__c
				FROM Service_Delivery__c
				WITH SYSTEM_MODE
			];
			Assert.areEqual(1, rows.size(), 'R-SD7: adopted, not doubled.');
			Assert.areEqual(earlier.Id, rows[0].Id);
			Assert.areEqual(session.Id, rows[0].Session__c, 'It now names the session.');
			Assert.areEqual(2, rows[0].Quantity__c);
		}
	}

	@IsTest
	static void aHiddenDeliveryWithNoSessionIsAdoptedNotDoubled() {
		Service__c service;
		Enrollment__c ana;
		Session__c session;
		Date day = Date.newInstance(2027, 3, 2);
		User staff = TestUsers.standardUserWith('Coordinator', STAFF);
		System.runAs(admin()) {
			contactMode();
			service = tutoring();
			ana = enroll(service.Program__c, null, 'Ana');
			session = sessionOf(service, null, day);
			insert new Service_Delivery__c(
				Service__c = service.Id,
				Contact__c = ana.Contact__c,
				Enrollment__c = ana.Id,
				Delivery_Date__c = day,
				Attendance__c = 'Present',
				Quantity__c = 1
			);
			// As under the Private preset: the coordinator sees the enrollment, not the delivery.
			delete [
				SELECT Id
				FROM Service_Delivery__Share
				WHERE RowCause = :Schema.Service_Delivery__Share.RowCause.Programs_Participants__c
				WITH SYSTEM_MODE
			];
			insert new Enrollment__Share(
				ParentId = ana.Id,
				UserOrGroupId = staff.Id,
				AccessLevel = 'Edit',
				RowCause = Schema.Enrollment__Share.RowCause.Manual
			);
		}

		Test.startTest();
		Integer seen;
		System.runAs(staff) {
			seen = [SELECT COUNT() FROM Service_Delivery__c WITH USER_MODE];
			ServiceDeliveryLogController.saveSession(
				session.Id,
				new List<ServiceDeliveryLogController.Entry>{ entry(ana, null, 'Present', 4) }
			);
		}
		Test.stopTest();

		Assert.areEqual(0, seen, 'The coordinator cannot see the delivery.');
		List<Service_Delivery__c> rows = [
			SELECT Session__c, Quantity__c
			FROM Service_Delivery__c
			WITH SYSTEM_MODE
		];
		Assert.areEqual(1, rows.size(), 'R-SD7 with R-SD4: changed, not doubled.');
		Assert.areEqual(session.Id, rows[0].Session__c, 'Adopted by the session.');
		Assert.areEqual(4, rows[0].Quantity__c);
	}

	@IsTest
	static void aCancelledSessionTakesNoAttendance() {
		System.runAs(admin()) {
			contactMode();
			Service__c service = tutoring();
			Enrollment__c ana = enroll(service.Program__c, null, 'Ana');
			Session__c session = sessionOf(service, null, Date.today());
			session.Status__c = SessionAttendance.CANCELLED;
			update session;

			Test.startTest();
			ServiceDeliveryLogController.Log log = ServiceDeliveryLogController.getSessionLog(
				session.Id
			);
			String refusal;
			try {
				ServiceDeliveryLogController.saveSession(
					session.Id,
					new List<ServiceDeliveryLogController.Entry>{ entry(ana, null, 'Present', 1) }
				);
			} catch (AuraHandledException refused) {
				refusal = refused.getMessage();
			}
			Test.stopTest();

			Assert.isTrue(log.cancelled, 'R-SE3.');
			Assert.isFalse(log.canEdit, 'No controls on a cancelled session.');
			Assert.areEqual(Label.Programs_Session_CancelledNoAttendance, refusal);
			Assert.areEqual(0, [SELECT COUNT() FROM Service_Delivery__c WITH SYSTEM_MODE]);
		}
	}

	@IsTest
	static void aDeliverysSessionMustBeOfItsServiceAndASessionWithAttendanceIsKept() {
		System.runAs(admin()) {
			contactMode();
			Service__c service = tutoring();
			Service__c other = new Service__c(Program__c = service.Program__c, Name = 'Snack');
			insert other;
			Enrollment__c ana = enroll(service.Program__c, null, 'Ana');
			Session__c session = sessionOf(service, null, Date.today());
			insert new Service_Delivery__c(
				Service__c = service.Id,
				Session__c = session.Id,
				Contact__c = ana.Contact__c,
				Attendance__c = 'Present'
			);

			Test.startTest();
			Database.SaveResult wrong = Database.insert(
				new Service_Delivery__c(
					Service__c = other.Id,
					Session__c = session.Id,
					Contact__c = ana.Contact__c,
					Attendance__c = 'Present'
				),
				false
			);
			Database.DeleteResult deleted = Database.delete(session, false);
			Test.stopTest();

			Assert.isFalse(wrong.isSuccess(), 'R-SD7: a session of another service is refused.');
			Assert.isFalse(deleted.isSuccess(), 'R-SE5: a session with attendance is kept.');
		}
	}

	@IsTest
	static void aMissingSessionIsReportedPlainly() {
		List<String> refusals = new List<String>();
		System.runAs(admin()) {
			Session__c gone = sessionOf(tutoring(), null, Date.today());
			delete gone;
			Test.startTest();
			for (Id sessionId : new List<Id>{ null, gone.Id }) {
				try {
					ServiceDeliveryLogController.getSessionLog(sessionId);
				} catch (AuraHandledException refused) {
					refusals.add(refused.getMessage());
				}
				try {
					ServiceDeliveryLogController.saveSession(sessionId, null);
				} catch (AuraHandledException refused) {
					refusals.add(refused.getMessage());
				}
			}
			Test.stopTest();
		}
		Assert.areEqual(
			new List<String>{
				BarnHelp.text('Programs', 'Programs_Fail_Log'),
				BarnHelp.text('Programs', 'Programs_Fail_Log'),
				Label.Programs_Session_NotFound,
				Label.Programs_Session_NotFound
			},
			refusals
		);
	}

	@IsTest
	static void namesAndTimesAreReadAsWritten() {
		System.runAs(admin()) {
			Assert.areEqual(
				80,
				SessionScheduleController.sessionName('x'.repeat(100), Date.today()).length()
			);
			Assert.isNull(SessionScheduleController.parsedTime(' '));
			Assert.areEqual(
				Time.newInstance(9, 5, 0, 0),
				SessionScheduleController.parsedTime('09:05')
			);
		}
	}
}
