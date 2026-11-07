/**
 * Dana opens the gala's Check-In tab, checks a guest in and takes it back, and adds a walk-in at
 * the door who is already attended (EV-12).
 */
@IsTest(testFor='ApexClass:EventCheckInController')
private class EventCheckInControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static User staff() {
		return TestUsers.adminWith(EventsAccessSync.ADMIN_SET);
	}

	private static Event__c gala() {
		Datetime start = Datetime.now().addDays(10);
		Event__c record = new Event__c(
			Name = 'Spring Gala',
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(3),
			Capacity__c = 1
		);
		insert as user record;
		insert as user new Ticket_Type__c(
			Event__c = record.Id,
			Name = 'General',
			Price__c = 20,
			Active__c = true
		);
		return record;
	}

	private static String requestJson(Id eventId, String first, String last) {
		return JSON.serialize(
			new Map<String, Object>{
				'eventId' => eventId,
				'registrant' => new Map<String, Object>{ 'firstName' => first, 'lastName' => last },
				'attendeeStatus' => 'Cancelled',
				'promoCode' => 'IGNORED'
			}
		);
	}

	@IsTest
	static void checksInAndUndoes() {
		System.runAs(staff()) {
			Event__c event = gala();
			EventRegistrationService.Request request = new EventRegistrationService.Request();
			request.eventId = event.Id;
			request.registrant = new EventPersonMatcher.PersonInput();
			request.registrant.firstName = 'Jane';
			request.registrant.lastName = 'Doe';
			EventRegistrationService.register(request);

			Test.startTest();
			EventCheckInController.CheckIn before = EventCheckInController.getCheckIn(event.Id);
			String attended = EventCheckInController.checkIn(before.attendees[0].id, false);
			EventCheckInController.CheckIn during = EventCheckInController.getCheckIn(event.Id);
			String undone = EventCheckInController.checkIn(before.attendees[0].id, true);
			Boolean refused = false;
			try {
				EventCheckInController.checkIn(null, false);
			} catch (AuraHandledException e) {
				refused = true;
			}
			Test.stopTest();

			Assert.areEqual(1, before.attendees.size(), 'One guest holds a seat');
			Assert.areEqual('Registered', before.attendees[0].status, 'Not yet in');
			Assert.areEqual('General', before.attendees[0].ticketName, 'Ticket shown');
			Assert.areEqual(1, before.tickets.size(), 'One ticket to choose');
			Assert.isTrue(before.canCheckIn && before.canWalkIn, 'Staff may check in');
			Assert.areEqual('Attended', attended, 'Checked in');
			Assert.areEqual('Attended', during.attendees[0].status, 'Listed as in');
			Assert.areEqual('Registered', undone, 'Taken back');
			Assert.isTrue(refused, 'A missing attendee is refused');
		}
	}

	@IsTest
	static void addsAWalkInPastCapacityAsAttended() {
		System.runAs(staff()) {
			Event__c event = gala();
			EventRegistrationService.Request first = new EventRegistrationService.Request();
			first.eventId = event.Id;
			first.registrant = new EventPersonMatcher.PersonInput();
			first.registrant.lastName = 'Full';
			EventRegistrationService.register(first);

			Test.startTest();
			EventRegistrationService.Result result = EventCheckInController.walkIn(
				requestJson(event.Id, 'Walt', 'Door')
			);
			Boolean badJson = false;
			try {
				EventCheckInController.walkIn('{not json');
			} catch (AuraHandledException e) {
				badJson = true;
			}
			Test.stopTest();

			Event_Attendee__c walkIn = [
				SELECT Status__c, Event_Registration__r.Source__c
				FROM Event_Attendee__c
				WHERE Name LIKE '%Door%'
				WITH USER_MODE
			];
			Assert.areEqual(1, result.registered, 'Counted as in');
			Assert.areEqual('Attended', walkIn.Status__c, 'The page sets Attended, not the request');
			Assert.areEqual('Staff', walkIn.Event_Registration__r.Source__c, 'Staff source');
			Assert.isTrue(badJson, 'Unreadable request refused');
		}
	}
}
