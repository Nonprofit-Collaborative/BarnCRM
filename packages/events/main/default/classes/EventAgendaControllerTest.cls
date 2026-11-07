/**
 * Dana builds the community conference's agenda: Admin and Developer tracks, a keynote in no
 * track, and a talk she moves from one track to another (EV-04, R-ESN1 to R-ESN3, R-ESN5).
 */
@IsTest(testFor='ApexClass:EventAgendaController')
private class EventAgendaControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static Event__c conference(Datetime start) {
		Event__c record = new Event__c(
			Name = 'Community Dreamin',
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(8)
		);
		insert as user record;
		return record;
	}

	private static Event_Session__c session(Event__c event, String name, Datetime start) {
		return new Event_Session__c(
			Event__c = event.Id,
			Name = name,
			Start__c = start,
			End__c = start == null ? null : start.addHours(1),
			Room__c = 'Hall A'
		);
	}

	@IsTest
	static void listsTracksInOrderAndSessionsByTime() {
		System.runAs(staff()) {
			Datetime start = Datetime.now().addDays(30);
			Event__c event = conference(start);
			Event_Track__c developers = new Event_Track__c(
				Event__c = event.Id,
				Name = 'Developers',
				Sort_Order__c = 2
			);
			Event_Track__c admins = new Event_Track__c(
				Event__c = event.Id,
				Name = 'Admins',
				Sort_Order__c = 1
			);
			insert as user new List<Event_Track__c>{ developers, admins };
			Event_Session__c talk = session(event, 'Flows 101', start.addHours(2));
			talk.Track__c = admins.Id;
			insert as user new List<Event_Session__c>{
				talk,
				session(event, 'Keynote', start),
				session(event, 'Lightning Talks', null)
			};

			Test.startTest();
			EventAgendaController.Agenda agenda = EventAgendaController.getAgenda(event.Id);
			Test.stopTest();

			Assert.areEqual('Admins', agenda.tracks[0].name, 'By sort order');
			Assert.areEqual(3, agenda.sessions.size(), 'Every session');
			Assert.areEqual('Keynote', agenda.sessions[0].name, 'By start time');
			Assert.areEqual(admins.Id, agenda.sessions[1].trackId, 'With its track');
			Assert.isNull(agenda.sessions[2].startsAt, 'Unscheduled last');
			Assert.isTrue(agenda.canMove && agenda.canAddSession, 'Staff may build it');
		}
	}

	@IsTest
	static void moveChangesOnlyTheTrack() {
		System.runAs(staff()) {
			Datetime start = Datetime.now().addDays(30);
			Event__c event = conference(start);
			Event_Track__c admins = new Event_Track__c(Event__c = event.Id, Name = 'Admins');
			insert as user admins;
			Event_Session__c talk = session(event, 'Flows 101', start.addHours(1));
			insert as user talk;

			Test.startTest();
			EventAgendaController.moveSession(talk.Id, admins.Id);
			Test.stopTest();

			Event_Session__c saved = [
				SELECT Track__c, Room__c, Start__c
				FROM Event_Session__c
				WHERE Id = :talk.Id
				WITH USER_MODE
			];
			Assert.areEqual(admins.Id, saved.Track__c, 'Moved to Admins');
			Assert.areEqual('Hall A', saved.Room__c, 'Room unchanged');
			Assert.areEqual(start.addHours(1), saved.Start__c, 'Time unchanged');
		}
	}

	@IsTest
	static void refusesAnotherEventsTrackAndTimesOutsideTheEvent() {
		System.runAs(staff()) {
			Datetime start = Datetime.now().addDays(30);
			Event__c event = conference(start);
			Event__c other = conference(start.addDays(60));
			Event_Track__c foreign = new Event_Track__c(Event__c = other.Id, Name = 'Elsewhere');
			insert as user foreign;
			Event_Session__c talk = session(event, 'Flows 101', start.addHours(1));
			insert as user talk;
			Event_Session__c late = session(event, 'After Hours', start.addHours(9));
			Event_Session__c half = session(event, 'Half', start.addHours(1));
			half.End__c = null;

			Test.startTest();
			Boolean refused = false;
			try {
				EventAgendaController.moveSession(talk.Id, foreign.Id);
			} catch (AuraHandledException e) {
				refused = true;
			}
			List<Database.SaveResult> results = Database.insert(
				new List<Event_Session__c>{ late, half },
				false,
				AccessLevel.USER_MODE
			);
			Test.stopTest();

			Assert.isTrue(refused, 'R-ESN3: a track of another event is refused');
			Assert.isFalse(results[0].isSuccess(), 'R-ESN2: inside the event');
			Assert.isFalse(results[1].isSuccess(), 'R-ESN1: start and end together');
		}
	}

	@IsTest
	static void deletingATrackKeepsItsSessions() {
		System.runAs(staff()) {
			Datetime start = Datetime.now().addDays(30);
			Event__c event = conference(start);
			Event_Track__c admins = new Event_Track__c(Event__c = event.Id, Name = 'Admins');
			insert as user admins;
			Event_Session__c talk = session(event, 'Flows 101', start.addHours(1));
			talk.Track__c = admins.Id;
			insert as user talk;

			Test.startTest();
			delete as user admins;
			Test.stopTest();

			Event_Session__c saved = [
				SELECT Track__c
				FROM Event_Session__c
				WHERE Id = :talk.Id
				WITH USER_MODE
			];
			Assert.isNull(saved.Track__c, 'R-ETR1: the session stays, with no track');
		}
	}
}
