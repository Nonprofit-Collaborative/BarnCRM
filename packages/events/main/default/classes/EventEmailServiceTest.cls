/**
 * The gala's morning run: Jane gets her reminder once, Sam who came gets a thank-you, Max who did
 * not is marked No-Show, and nothing happens while the settings are off (EV-14).
 */
@IsTest(
	testFor='ApexClass:EventEmailService, ApexClass:EventEmailBatch, ApexClass:EventEmailScheduler, ApexClass:EventsNightlyJobProvider, ApexClass:EventsSettings'
)
private class EventEmailServiceTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static void settings(Boolean reminders, Boolean followUps, Boolean noShows) {
		OrgSettingsSystemWriter.save(
			Events_Settings__c.SObjectType,
			new Map<Schema.SObjectField, Object>{
				Events_Settings__c.Reminders_Enabled__c => reminders,
				Events_Settings__c.Follow_Ups_Enabled__c => followUps,
				Events_Settings__c.Mark_No_Shows__c => noShows,
				Events_Settings__c.Reminder_Lead_Days__c => 3
			}
		);
		SettingsService.clearCaches();
	}

	private static Event__c event(Datetime start) {
		Event__c record = new Event__c(
			Name = 'Spring Gala',
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(3)
		);
		insert as user record;
		return record;
	}

	private static Event_Attendee__c attendee(Event__c event, String last, String status) {
		Contact person = new Contact(
			FirstName = 'A',
			LastName = last,
			Email = last + '@example.org'
		);
		insert as user person;
		EventPersonMatcher.PersonInput input = new EventPersonMatcher.PersonInput();
		input.contactId = person.Id;
		EventRegistrationService.Request request = new EventRegistrationService.Request();
		request.eventId = event.Id;
		request.registrant = input;
		request.attendeeStatus = status;
		EventRegistrationService.register(request);
		return [
			SELECT Id, Contact__c, Status__c
			FROM Event_Attendee__c
			WHERE Contact__c = :person.Id
			WITH USER_MODE
		];
	}

	private static List<Event_Attendee__c> due(String phase) {
		Database.QueryLocatorIterator it = EventEmailService.locator(phase).iterator();
		List<Event_Attendee__c> found = new List<Event_Attendee__c>();
		while (it.hasNext()) {
			found.add((Event_Attendee__c) it.next());
		}
		return found;
	}

	@IsTest
	static void remindsOnceBeforeTheEvent() {
		System.runAs(staff()) {
			settings(true, false, false);
			Event_Attendee__c jane = attendee(event(Datetime.now().addDays(1)), 'Doe', null);
			event(Datetime.now().addDays(10));
			RecordingEmailSender stub = new RecordingEmailSender();
			EventEmailService.emailSender = stub;

			Test.startTest();
			List<Event_Attendee__c> first = due(EventEmailService.PHASE_REMIND);
			Integer sent = EventEmailService.run(EventEmailService.PHASE_REMIND, first);
			List<Event_Attendee__c> again = due(EventEmailService.PHASE_REMIND);
			Test.stopTest();

			Assert.areEqual(1, first.size(), 'Only the event inside the lead time');
			Assert.areEqual(1, sent, 'One reminder');
			Assert.areEqual(jane.Contact__c, stub.received[0].getTargetObjectId(), 'To Jane');
			Assert.areEqual(jane.Id, stub.received[0].getWhatId(), 'About her attendance');
			Assert.isTrue(again.isEmpty(), 'Stamped, so never sent twice');
		}
	}

	@IsTest
	static void clearsTheStampWhenTheSendFails() {
		System.runAs(staff()) {
			settings(true, false, false);
			attendee(event(Datetime.now().addDays(1)), 'Doe', null);
			RecordingEmailSender stub = new RecordingEmailSender();
			stub.failAll = true;
			EventEmailService.emailSender = stub;

			Test.startTest();
			Integer sent = EventEmailService.run(
				EventEmailService.PHASE_REMIND,
				due(EventEmailService.PHASE_REMIND)
			);
			Test.stopTest();

			Assert.areEqual(0, sent, 'Nothing went');
			Assert.areEqual(1, due(EventEmailService.PHASE_REMIND).size(), 'Tried again tomorrow');
		}
	}

	@IsTest
	static void followsUpAndMarksNoShowsAfterTheEvent() {
		System.runAs(staff()) {
			settings(false, true, true);
			Event__c past = event(Datetime.now().addDays(-2));
			Event_Attendee__c sam = attendee(past, 'Lee', 'Attended');
			Event_Attendee__c max = attendee(past, 'Ray', 'Registered');
			RecordingEmailSender stub = new RecordingEmailSender();
			EventEmailService.emailSender = stub;

			Test.startTest();
			Integer followed = EventEmailService.run(
				EventEmailService.PHASE_FOLLOW_UP,
				due(EventEmailService.PHASE_FOLLOW_UP)
			);
			Integer marked = EventEmailService.run(
				EventEmailService.PHASE_NO_SHOW,
				due(EventEmailService.PHASE_NO_SHOW)
			);
			Test.stopTest();

			Assert.areEqual(1, followed, 'One follow-up');
			Assert.areEqual(sam.Contact__c, stub.received[0].getTargetObjectId(), 'To Sam');
			Assert.areEqual(1, marked, 'One no-show');
			Assert.areEqual(
				'No-Show',
				[SELECT Status__c FROM Event_Attendee__c WHERE Id = :max.Id WITH USER_MODE]
				.Status__c,
				'Max did not come'
			);
		}
	}

	@IsTest
	static void doesNothingWhileTheSettingsAreOff() {
		System.runAs(staff()) {
			settings(false, false, false);
			Event_Attendee__c jane = attendee(event(Datetime.now().addDays(1)), 'Doe', null);

			Test.startTest();
			Id job = EventEmailBatch.startMorning();
			Integer sent = EventEmailService.run(
				EventEmailService.PHASE_REMIND,
				new List<Event_Attendee__c>{ jane }
			);
			List<NightlyStep> steps = new EventsNightlyJobProvider().nightlySteps();
			Test.stopTest();

			Assert.isNull(job, 'No run starts');
			Assert.areEqual(0, sent, 'Nothing sent');
			Assert.areEqual(1, steps.size(), 'One nightly step');
			Assert.isFalse(steps[0].active, 'Inactive while everything is off');
			Assert.areEqual(3, EventsSettings.reminderLeadDays(), 'Days before as saved');
		}
	}

	@IsTest
	static void runsTheBatchFromTheNightlyStep() {
		System.runAs(staff()) {
			settings(true, false, false);
			attendee(event(Datetime.now().addDays(1)), 'Doe', null);
			EventEmailService.emailSender = new RecordingEmailSender();

			Test.startTest();
			NightlyStep step = EventEmailScheduler.step();
			step.run();
			Test.stopTest();

			Assert.isTrue(step.active, 'Active with reminders on');
			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Event_Attendee__c
					WHERE Reminder_Sent_On__c != NULL
					WITH USER_MODE
				],
				'The batch stamped the reminder'
			);
			Assert.areEqual('BarnCRM_Event_Reminder', EventsSettings.reminderTemplate(), 'Default');
		}
	}
}
