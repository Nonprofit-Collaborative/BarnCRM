/**
 * The Events part of the engagement score counts the events each person attended in the window
 * (C-64, canonical model R-ES2), and Core finds it by name.
 */
@IsTest(testFor='ApexClass:EventsEngagementSignal')
private class EventsEngagementSignalTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Events_Admin');
	}

	private static Id registerJane(Datetime start) {
		Event__c event = new Event__c(
			Name = 'Gala ' + start.format('yyyy'),
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(3)
		);
		insert as user event;
		EventRegistrationService.Request request = new EventRegistrationService.Request();
		request.eventId = event.Id;
		request.registrant = new EventPersonMatcher.PersonInput();
		request.registrant.firstName = 'Jane';
		request.registrant.lastName = 'Doe';
		request.registrant.email = 'jane.doe@example.org';
		EventRegistrationService.register(request);
		return event.Id;
	}

	@IsTest
	static void countsAttendedEventsInTheWindowOnly() {
		System.runAs(TestUsers.adminWith('Events_Admin')) {
			registerJane(Datetime.now().addDays(-20));
			registerJane(Datetime.now().addYears(-2));
			List<Event_Attendee__c> attendees = [
				SELECT Id, Contact__c
				FROM Event_Attendee__c
				WITH SYSTEM_MODE
			];
			for (Event_Attendee__c attendee : attendees) {
				attendee.Status__c = 'Attended';
			}
			Database.update(attendees, AccessLevel.SYSTEM_MODE);
			Id jane = attendees[0].Contact__c;

			Test.startTest();
			EngagementSignalExtension signal = (EngagementSignalExtension) NamespaceUtil.resolveType(
					'EventsEngagementSignal'
				)
				.newInstance();
			Map<Id, Decimal> totals = signal.totals(
				new Set<Id>{ jane },
				Date.today().addMonths(-12)
			);
			Test.stopTest();

			Assert.areEqual(2, attendees.size(), 'Jane was registered for both events');
			Assert.areEqual(
				attendees[0].Contact__c,
				attendees[1].Contact__c,
				'Matched as one person'
			);
			Assert.areEqual('Events', signal.key(), 'The Events part');
			Assert.areEqual(1, totals.get(jane), 'Only the event in the window counts');
		}
	}
}
