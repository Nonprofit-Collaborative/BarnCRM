/**
 * Ana and Ben attend the community conference with the attendee app: Ana asks to connect, Ben
 * accepts and they see how to reach each other; messages wait for the setting; Ana builds her
 * agenda, a full or overlapping session is refused, and she rates a session once it has started
 * (EV-22, EV-29; R-ACN1, R-ACN2, R-AMS1, R-AGI1, R-AGI2).
 */
@IsTest(
	testFor='ApexClass:EventAttendeeApp, ApexClass:EventsPortalExtension, ApexClass:EventOperationsHandler, ApexTrigger:AgendaItemTrigger'
)
private class EventAttendeeAppTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Events_Admin');
	}

	private static User staff() {
		return TestUsers.adminWith('Events_Admin');
	}

	private class Conference {
		Event__c event;
		Contact ana;
		Contact ben;
		Event_Attendee__c anaRow;
		Event_Attendee__c benRow;
	}

	private static Conference conference() {
		Conference result = new Conference();
		Datetime start = Datetime.now().addDays(10);
		result.event = new Event__c(
			Name = 'Community Dreamin',
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(8)
		);
		insert as user result.event;
		result.ana = TestDataFactory.person(
			new Contact(FirstName = 'Ana', LastName = 'Garcia', Email = 'ana@example.org')
		);
		result.ben = TestDataFactory.person(
			new Contact(FirstName = 'Ben', LastName = 'Okafor', Email = 'ben@example.org')
		);
		insert as user new List<Contact>{ result.ana, result.ben };
		result.anaRow = attend(result.event, result.ana, 'ana.garcia@example.org');
		result.benRow = attend(result.event, result.ben, 'Ben on the conference chat');
		return result;
	}

	private static Event_Attendee__c attend(Event__c event, Contact person, String reach) {
		Event_Registration__c registration = new Event_Registration__c(
			Event__c = event.Id,
			Contact__c = person.Id,
			Status__c = 'Registered',
			Source__c = 'Staff'
		);
		insert as user registration;
		Event_Attendee__c row = new Event_Attendee__c(
			Event_Registration__c = registration.Id,
			Contact__c = person.Id,
			Status__c = 'Registered',
			Networking_Opt_In__c = true,
			Networking_Contact__c = reach
		);
		insert as user row;
		return row;
	}

	private static Event_Session__c session(
		Event__c event,
		String name,
		Integer hour,
		Decimal cap
	) {
		Datetime start = event.Start__c.addHours(hour);
		Event_Session__c record = new Event_Session__c(
			Event__c = event.Id,
			Name = name,
			Start__c = start,
			End__c = start.addHours(1),
			Capacity__c = cap,
			Status__c = 'Confirmed'
		);
		insert as user record;
		return record;
	}

	private static void setting(Schema.SObjectField field, Boolean value) {
		OrgSettingsSystemWriter.save(
			Events_Settings__c.SObjectType,
			new Map<Schema.SObjectField, Object>{ field => value }
		);
		SettingsService.clearCaches();
	}

	private static Attendee_Connection__c rowOf(Id personId) {
		return [
			SELECT Id, Status__c, Contact_Details__c, Other_Contact__c
			FROM Attendee_Connection__c
			WHERE Contact__c = :personId
		];
	}

	@IsTest
	static void coreFindsTheAppActionsThroughEvents() {
		System.runAs(staff()) {
			Set<String> names = new EventsPortalExtension().actionNames();
			Assert.isTrue(
				names.containsAll(EventAttendeeApp.actionNames()),
				'Every app action named'
			);
			Assert.isTrue(names.contains(EventsPortalExtension.APPLY), 'The speaker actions stay');
		}
	}

	@IsTest
	static void connectingNeedsBothSidesAndSharesDetailsOnlyOnAccept() {
		System.runAs(staff()) {
			Conference c = conference();
			EventsPortalExtension app = new EventsPortalExtension();

			Test.startTest();
			String sent = app.run(EventAttendeeApp.CONNECT, c.ana.Id, c.benRow.Id);
			String again = app.run(EventAttendeeApp.CONNECT, c.ben.Id, c.anaRow.Id);
			String self = app.run(EventAttendeeApp.CONNECT, c.ana.Id, c.anaRow.Id);
			Attendee_Connection__c before = rowOf(c.ana.Id);
			String refused = app.run(EventAttendeeApp.ACCEPT, c.ana.Id, before.Id);
			String accepted = app.run(EventAttendeeApp.ACCEPT, c.ben.Id, rowOf(c.ben.Id).Id);
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text('Events', 'Events_App_RequestSent'),
				sent,
				'Request sent'
			);
			Assert.areEqual(
				BarnHelp.text('Events', 'Events_App_AlreadyAsked'),
				again,
				'One pair once (R-ACN1)'
			);
			Assert.areEqual(BarnHelp.text('Events', 'Events_App_NotYou'), self, 'Not with oneself');
			Assert.areEqual('Requested', before.Status__c, 'The asker waits');
			Assert.isNull(before.Contact_Details__c, 'Nothing shared before accepting (R-ACN2)');
			Assert.areEqual(
				BarnHelp.text('Events', 'Events_App_NothingToAccept'),
				refused,
				'The asker cannot accept'
			);
			Assert.areEqual(
				BarnHelp.text('Events', 'Events_App_Connected'),
				accepted,
				'Ben accepts'
			);
			Attendee_Connection__c anas = rowOf(c.ana.Id);
			Assert.areEqual('Connected', anas.Status__c, 'Both connected');
			Assert.areEqual('Ben on the conference chat', anas.Contact_Details__c, 'Ana sees Ben');
			Assert.areEqual(
				'ana.garcia@example.org',
				rowOf(c.ben.Id).Contact_Details__c,
				'Ben sees Ana'
			);
		}
	}

	@IsTest
	static void declineHidesBothAndAHiddenAttendeeCannotBeAsked() {
		System.runAs(staff()) {
			Conference c = conference();
			EventsPortalExtension app = new EventsPortalExtension();
			app.run(EventAttendeeApp.CONNECT, c.ana.Id, c.benRow.Id);

			Test.startTest();
			String declined = app.run(EventAttendeeApp.DECLINE, c.ben.Id, rowOf(c.ben.Id).Id);
			String again = app.run(EventAttendeeApp.CONNECT, c.ana.Id, c.benRow.Id);
			update as user new Event_Attendee__c(Id = c.anaRow.Id, Networking_Opt_In__c = false);
			String hidden = app.run(EventAttendeeApp.CONNECT, c.ben.Id, c.anaRow.Id);
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Events', 'Events_App_Declined'), declined, 'Declined');
			Assert.areEqual('Declined', rowOf(c.ana.Id).Status__c, 'Both declined');
			Assert.areEqual(
				BarnHelp.text('Events', 'Events_App_AlreadyAsked'),
				again,
				'No new request'
			);
			Assert.areEqual(
				BarnHelp.text('Events', 'Events_App_NotListed'),
				hidden,
				'Only opted-in attendees'
			);
		}
	}

	@IsTest
	static void messagesWaitForTheSettingAndGoOnlyToConnections() {
		System.runAs(staff()) {
			Conference c = conference();
			EventsPortalExtension app = new EventsPortalExtension();
			app.run(EventAttendeeApp.CONNECT, c.ana.Id, c.benRow.Id);
			Attendee_Connection__c anas = rowOf(c.ana.Id);
			update as user new Attendee_Connection__c(Id = anas.Id, Draft_Message__c = 'Coffee?');

			Test.startTest();
			String off = app.run(EventAttendeeApp.SEND_MESSAGE, c.ana.Id, anas.Id);
			setting(Events_Settings__c.Attendee_Messages__c, true);
			String notYet = app.run(EventAttendeeApp.SEND_MESSAGE, c.ana.Id, anas.Id);
			app.run(EventAttendeeApp.ACCEPT, c.ben.Id, rowOf(c.ben.Id).Id);
			String sent = app.run(EventAttendeeApp.SEND_MESSAGE, c.ana.Id, anas.Id);
			Attendee_Message__c received = [
				SELECT Id, Body__c, From_Contact__c
				FROM Attendee_Message__c
				WHERE To_Contact__c = :c.ben.Id
			];
			update as user new Attendee_Message__c(Id = received.Id, Reply__c = 'Yes, at 10');
			String replied = app.run(EventAttendeeApp.SEND_REPLY, c.ben.Id, received.Id);
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text('Events', 'Events_App_MessagesOff'),
				off,
				'Off by default (R-AMS1)'
			);
			Assert.areEqual(
				BarnHelp.text('Events', 'Events_App_NotConnected'),
				notYet,
				'Only to connections'
			);
			Assert.areEqual(
				BarnHelp.text('Events', 'Events_App_MessageSent'),
				sent,
				'Sent once connected'
			);
			Assert.areEqual('Coffee?', received.Body__c, 'The draft was sent');
			Assert.isNull(
				[SELECT Draft_Message__c FROM Attendee_Connection__c WHERE Id = :anas.Id]
				.Draft_Message__c,
				'The draft is cleared'
			);
			Assert.areEqual(
				BarnHelp.text('Events', 'Events_App_MessageSent'),
				replied,
				'Ben replies'
			);
			Assert.areEqual(
				'Yes, at 10',
				[SELECT Body__c FROM Attendee_Message__c WHERE To_Contact__c = :c.ana.Id].Body__c,
				'The reply reaches Ana'
			);
		}
	}

	@IsTest
	static void anAgendaRefusesAFullOrOverlappingSessionUnlessAllowed() {
		System.runAs(staff()) {
			Conference c = conference();
			Event_Session__c keynote = session(c.event, 'Keynote', 0, null);
			Event_Session__c clash = session(c.event, 'Workshop', 0, null);
			Event_Session__c small = session(c.event, 'Roundtable', 2, 1);
			EventsPortalExtension app = new EventsPortalExtension();

			Test.startTest();
			String added = app.run(EventAttendeeApp.ADD_TO_AGENDA, c.ana.Id, keynote.Id);
			String twice = app.run(EventAttendeeApp.ADD_TO_AGENDA, c.ana.Id, keynote.Id);
			String overlap = app.run(EventAttendeeApp.ADD_TO_AGENDA, c.ana.Id, clash.Id);
			app.run(EventAttendeeApp.ADD_TO_AGENDA, c.ben.Id, small.Id);
			String full = app.run(EventAttendeeApp.ADD_TO_AGENDA, c.ana.Id, small.Id);
			setting(Events_Settings__c.Allow_Agenda_Overlaps__c, true);
			String allowed = app.run(EventAttendeeApp.ADD_TO_AGENDA, c.ana.Id, clash.Id);
			Agenda_Item__c item = [
				SELECT Id
				FROM Agenda_Item__c
				WHERE Contact__c = :c.ana.Id AND Event_Session__c = :keynote.Id
			];
			String removed = app.run(EventAttendeeApp.REMOVE_FROM_AGENDA, c.ana.Id, item.Id);
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Events', 'Events_App_Added'), added, 'Added');
			Assert.areEqual(
				BarnHelp.text('Events', 'Events_App_AlreadyPicked'),
				twice,
				'Once per session'
			);
			Assert.areEqual(
				BarnHelp.text('Events', 'Events_App_Overlaps', new List<Object>{ 'Keynote' }),
				overlap,
				'An overlap names the session (R-AGI1)'
			);
			Assert.areEqual(
				BarnHelp.text('Events', 'Events_App_SessionFull'),
				full,
				'A full session is refused'
			);
			Assert.isTrue(
				[SELECT Overlaps__c FROM Agenda_Item__c WHERE Event_Session__c = :clash.Id]
				.Overlaps__c,
				'Allowed overlaps are marked'
			);
			Assert.isTrue(allowed.contains('Keynote'), 'And named');
			Assert.areEqual(BarnHelp.text('Events', 'Events_App_Removed'), removed, 'Removed');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Agenda_Item__c WHERE Id = :item.Id],
				'The pick is gone'
			);
		}
	}

	@IsTest
	static void aRatingIsSentOnceAfterTheSessionStartsAndNamesNoOne() {
		System.runAs(staff()) {
			Conference c = conference();
			// The conference is under way: it began three hours ago.
			c.event.Start__c = Datetime.now().addHours(-3);
			c.event.End__c = c.event.Start__c.addHours(8);
			update as user c.event;
			Event_Session__c started = session(c.event, 'Opening', 0, null);
			Event_Session__c later = session(c.event, 'Closing', 6, null);
			EventsPortalExtension app = new EventsPortalExtension();
			app.run(EventAttendeeApp.ADD_TO_AGENDA, c.ana.Id, started.Id);
			app.run(EventAttendeeApp.ADD_TO_AGENDA, c.ana.Id, later.Id);
			Map<Id, Agenda_Item__c> picks = new Map<Id, Agenda_Item__c>();
			for (Agenda_Item__c pick : [SELECT Id, Event_Session__c FROM Agenda_Item__c]) {
				picks.put(pick.Event_Session__c, pick);
			}

			Test.startTest();
			Database.SaveResult early = Database.update(
				new Agenda_Item__c(Id = picks.get(later.Id).Id, My_Rating__c = '5'),
				false
			);
			update as user new Agenda_Item__c(
				Id = picks.get(started.Id).Id,
				My_Rating__c = '4',
				My_Comment__c = 'Great start'
			);
			Database.SaveResult changed = Database.update(
				new Agenda_Item__c(Id = picks.get(started.Id).Id, My_Rating__c = '1'),
				false
			);
			Test.stopTest();

			Assert.isFalse(early.isSuccess(), 'Not before the session starts (R-AGI2)');
			Assert.isFalse(changed.isSuccess(), 'Sent once');
			Session_Rating__c rating = [
				SELECT Rating__c, Comment__c, Event_Session__c
				FROM Session_Rating__c
			];
			Assert.areEqual(4, rating.Rating__c, 'The rating');
			Assert.areEqual('Great start', rating.Comment__c, 'The comment');
			Assert.areEqual(started.Id, rating.Event_Session__c, 'For the session');
			Assert.isTrue(
				[SELECT Rated__c FROM Agenda_Item__c WHERE Id = :picks.get(started.Id).Id].Rated__c,
				'Marked Rated'
			);
		}
	}
}
