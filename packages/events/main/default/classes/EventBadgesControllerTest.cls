/**
 * Dana opens the gala's Badges tab and sees who to print, with each person's ticket and
 * organization, and the event's sessions (EV-17).
 */
@IsTest(testFor='ApexClass:EventBadgesController, ApexClass:EventCheckInController')
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
			Assert.isNull(result.attendees[0].title, 'No title without an override');
		}
	}

	/** EV-26: Dana sets Jane's badge name, title and company; badges and Check-In use them. */
	@IsTest
	static void badgeOverridesPrintAndShowAtCheckIn() {
		System.runAs(staff()) {
			Datetime start = Datetime.now().addDays(10);
			Event__c event = new Event__c(
				Name = 'Spring Gala',
				Status__c = 'Open',
				Format__c = 'In Person',
				Start__c = start,
				End__c = start.addHours(3)
			);
			insert as user event;
			EventRegistrationService.Request request = new EventRegistrationService.Request();
			request.eventId = event.Id;
			request.registrant = new EventPersonMatcher.PersonInput();
			request.registrant.firstName = 'Jordan';
			request.registrant.lastName = 'Zzbadge';
			EventRegistrationService.register(request);
			Id attendeeId = [SELECT Id FROM Event_Attendee__c WITH USER_MODE LIMIT 1].Id;

			Test.startTest();
			// Edit Badge saves through the platform's record form, as this update does.
			update as user new Event_Attendee__c(
				Id = attendeeId,
				Badge_Name__c = 'Jo',
				Badge_Title__c = 'Chair',
				Badge_Company__c = 'Lake Org'
			);
			EventBadgesController.Badges badges = EventBadgesController.getBadges(event.Id);
			EventCheckInController.CheckIn door = EventCheckInController.getCheckIn(event.Id);
			update as user new Event_Attendee__c(
				Id = attendeeId,
				Badge_Name__c = null,
				Badge_Title__c = null,
				Badge_Company__c = null
			);
			EventBadgesController.Badges cleared = EventBadgesController.getBadges(event.Id);
			Test.stopTest();

			Assert.areEqual('Jo', badges.attendees[0].name, 'Badge name prints');
			Assert.areEqual('Chair', badges.attendees[0].title, 'Badge title prints');
			Assert.areEqual('Lake Org', badges.attendees[0].organization, 'Badge company prints');
			Assert.areEqual('Jo', door.attendees[0].badgeName, 'Check-In has the badge name');
			Assert.areEqual('Jordan Zzbadge', door.attendees[0].name, 'Check-In keeps the name');
			Assert.areEqual('Jordan Zzbadge', cleared.attendees[0].name, 'Cleared: the name again');
			Assert.isNull(cleared.attendees[0].title, 'Cleared: no title');
		}
	}
}
