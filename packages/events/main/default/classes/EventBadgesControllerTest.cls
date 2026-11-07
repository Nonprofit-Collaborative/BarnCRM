/**
 * Dana opens the gala's Badges tab and sees who to print, with each person's ticket and
 * organization, and the event's sessions (EV-17).
 */
@IsTest(testFor='ApexClass:EventBadgesController')
private class EventBadgesControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	@IsTest
	static void listsPrintablePeopleAndSessions() {
		System.runAs(staff()) {
			Datetime start = Datetime.now().addDays(10);
			Event__c event = new Event__c(
				Name = 'Spring Gala',
				Status__c = 'Open',
				Format__c = 'In Person',
				Start__c = start,
				End__c = start.addHours(3),
				Venue_Name__c = 'Grand Hall'
			);
			insert as user event;
			insert as user new Ticket_Type__c(
				Event__c = event.Id,
				Name = 'VIP',
				Price__c = 100,
				Active__c = true
			);
			insert as user new Event_Session__c(
				Event__c = event.Id,
				Name = 'Keynote',
				Start__c = start,
				End__c = start.addHours(1),
				Room__c = 'Main Stage'
			);
			EventRegistrationService.Request request = new EventRegistrationService.Request();
			request.eventId = event.Id;
			request.registrant = new EventPersonMatcher.PersonInput();
			request.registrant.firstName = 'Jane';
			request.registrant.lastName = 'Doe';
			EventRegistrationService.register(request);

			Test.startTest();
			EventBadgesController.Badges result = EventBadgesController.getBadges(event.Id);
			Boolean refused = false;
			try {
				EventBadgesController.getBadges(null);
			} catch (AuraHandledException e) {
				refused = true;
			}
			Test.stopTest();

			Assert.areEqual('Spring Gala', result.eventName, 'Event named');
			Assert.areEqual('Grand Hall', result.venue, 'Venue shown');
			Assert.areEqual(1, result.attendees.size(), 'One person to print');
			Assert.areEqual('Jane Doe', result.attendees[0].name, 'Name shown');
			Assert.areEqual(1, result.sessions.size(), 'One session');
			Assert.areEqual('Keynote', result.sessions[0].name, 'Session named');
			Assert.isTrue(refused, 'A missing event is refused');
		}
	}
}
