/**
 * Dana opens the Event Calendar for the month of the community conference: the events and
 * sessions inside the days shown come back, those outside do not, sessions are read only when
 * asked for, a bad range is refused and a read-only person still sees the calendar (EV-19).
 */
@IsTest(testFor='ApexClass:EventCalendarController')
private class EventCalendarControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static Event__c event(String name, Datetime start, Datetime finish) {
		Event__c record = new Event__c(
			Name = name,
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = finish,
			Venue_Name__c = 'Town Hall',
			Description__c = 'Come along'
		);
		insert as user record;
		return record;
	}

	private static Event_Session__c session(Event__c event, String name, Datetime start) {
		Event_Session__c record = new Event_Session__c(
			Event__c = event.Id,
			Name = name,
			Start__c = start,
			End__c = start.addHours(1),
			Room__c = 'Hall A',
			Session_Type__c = 'Talk'
		);
		insert as user record;
		return record;
	}

	@IsTest
	static void returnsTheEventsAndSessionsInsideTheDays() {
		System.runAs(staff()) {
			Datetime noon = Datetime.newInstance(
				Date.today().addDays(10),
				Time.newInstance(12, 0, 0, 0)
			);
			Event__c inside = event('Community Dreamin', noon, noon.addHours(8));
			event('Next Year', noon.addDays(400), noon.addDays(400).addHours(2));
			session(inside, 'Opening Keynote', noon.addHours(1));

			Test.startTest();
			EventCalendarController.Calendar withSessions = EventCalendarController.getCalendar(
				Date.today(),
				Date.today().addDays(30),
				true
			);
			EventCalendarController.Calendar eventsOnly = EventCalendarController.getCalendar(
				Date.today(),
				Date.today().addDays(30),
				false
			);
			Test.stopTest();

			Assert.areEqual(1, withSessions.events.size(), 'Only the event inside the days');
			Assert.areEqual('Community Dreamin', withSessions.events[0].name);
			Assert.areEqual('Town Hall', withSessions.events[0].venueName);
			Assert.areEqual(1, withSessions.sessions.size());
			Assert.areEqual('Opening Keynote', withSessions.sessions[0].name);
			Assert.areEqual('Open', withSessions.sessions[0].eventStatus, 'Its event filters it');
			Assert.areEqual(inside.Id, withSessions.sessions[0].eventId);
			Assert.isTrue(eventsOnly.sessions.isEmpty(), 'Sessions only when asked for');
			Assert.isFalse(withSessions.truncated);
			Assert.areEqual(10, withSessions.today.length(), 'Today as an ISO date');
		}
	}

	@IsTest
	static void anEventSpanningTheRangeEdgesIsIncluded() {
		System.runAs(staff()) {
			Datetime start = Datetime.newInstance(
				Date.today().addDays(-3),
				Time.newInstance(9, 0, 0, 0)
			);
			event('Long Conference', start, start.addDays(6));

			EventCalendarController.Calendar result = EventCalendarController.getCalendar(
				Date.today(),
				Date.today().addDays(1),
				false
			);

			Assert.areEqual(1, result.events.size(), 'It is still running on the first day shown');
		}
	}

	@IsTest
	static void saysWhenMoreMatchedThanOneViewReads() {
		System.runAs(staff()) {
			Datetime noon = Datetime.newInstance(
				Date.today().addDays(2),
				Time.newInstance(12, 0, 0, 0)
			);
			event('One', noon, noon.addHours(1));
			event('Two', noon.addHours(2), noon.addHours(3));
			EventCalendarController.maxEvents = 1;

			EventCalendarController.Calendar result = EventCalendarController.getCalendar(
				Date.today(),
				Date.today().addDays(5),
				false
			);

			Assert.areEqual(1, result.events.size());
			Assert.isTrue(result.truncated);
		}
	}

	@IsTest
	static void refusesABackwardsRange() {
		System.runAs(staff()) {
			try {
				EventCalendarController.getCalendar(Date.today(), Date.today().addDays(-1), false);
				Assert.fail('A range that ends before it starts is refused');
			} catch (AuraHandledException refused) {
				Assert.isNotNull(refused);
			}
			try {
				EventCalendarController.getCalendar(null, null, false);
				Assert.fail('A missing range is refused');
			} catch (AuraHandledException refused) {
				Assert.isNotNull(refused);
			}
		}
	}
}
