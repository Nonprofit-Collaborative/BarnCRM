/**
 * Dana opens the gala's Registrations tab, registers a person by hand, marks them attended and
 * cancels another booking; a page cannot set an import's status (EV-02).
 */
@IsTest(testFor='ApexClass:EventRegistrationsController')
private class EventRegistrationsControllerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Events_Admin');
	}

	private static User staff() {
		return TestUsers.adminWith('Events_Admin');
	}

	private static Event__c gala() {
		Datetime start = Datetime.now().addDays(10);
		Event__c record = new Event__c(
			Name = 'Spring Gala',
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(3),
			Capacity__c = 100
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
				'attendeeStatus' => 'Attended',
				'source' => 'Summit Events'
			}
		);
	}

	@IsTest
	static void registersByHandAndListsTheAttendee() {
		System.runAs(staff()) {
			Event__c event = gala();

			Test.startTest();
			EventRegistrationService.Result result = EventRegistrationsController.register(
				requestJson(event.Id, 'Jane', 'Doe')
			);
			EventRegistrationsController.Registrations view = EventRegistrationsController.getRegistrations(
				event.Id
			);
			Test.stopTest();

			Assert.areEqual('Registered', result.status, 'Seat taken');
			Assert.areEqual(1, view.attendees.size(), 'One attendee');
			Assert.areEqual('Registered', view.attendees[0].status, 'Not the import status');
			Assert.areEqual('Staff', view.attendees[0].source, 'A page registers as staff');
			Assert.areEqual('General', view.attendees[0].ticketName, 'The first active ticket');
			Assert.areEqual(1, view.tickets.size(), 'One ticket to choose');
			Assert.isTrue(view.canRegister && view.canChange, 'Staff may register and change');
			Assert.isTrue(view.capacity == 100, 'Capacity shown');
		}
	}

	@IsTest
	static void changesStatusesAndCancels() {
		System.runAs(staff()) {
			Event__c event = gala();
			EventRegistrationService.Result result = EventRegistrationsController.register(
				requestJson(event.Id, 'Jane', 'Doe')
			);
			Id attendeeId = EventRegistrationsController.getRegistrations(event.Id).attendees[0].id;

			Test.startTest();
			String status = EventRegistrationsController.setStatus(attendeeId, 'Attended');
			EventRegistrationsController.cancelRegistration(result.registrationId);
			Boolean refused = false;
			try {
				EventRegistrationsController.setStatus(attendeeId, 'Unknown');
			} catch (AuraHandledException e) {
				refused = true;
			}
			Boolean badJson = false;
			try {
				EventRegistrationsController.register('{not json');
			} catch (AuraHandledException e) {
				badJson = true;
			}
			Test.stopTest();

			Assert.areEqual('Attended', status, 'Marked attended');
			Assert.areEqual(
				'Cancelled',
				[
					SELECT Status__c
					FROM Event_Registration__c
					WHERE Id = :result.registrationId
					WITH USER_MODE
				]
				.Status__c,
				'Cancelled'
			);
			Assert.isTrue(refused, 'Unknown status refused');
			Assert.isTrue(badJson, 'Unreadable request refused');
		}
	}
}
