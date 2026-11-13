/**
 * Dana lays out the gala's tables, seats a party together, takes a person off a table, records a
 * dietary need, and removes a table (EV-13).
 */
@IsTest(testFor='ApexClass:EventSeatingController')
private class EventSeatingControllerTest {
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
			End__c = start.addHours(3)
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

	private static void register(Id eventId, String last, Integer guests) {
		EventRegistrationService.Request request = new EventRegistrationService.Request();
		request.eventId = eventId;
		request.registrant = new EventPersonMatcher.PersonInput();
		request.registrant.firstName = 'Pat';
		request.registrant.lastName = last;
		request.guests = new List<EventRegistrationService.GuestInput>();
		for (Integer i = 0; i < guests; i++) {
			EventRegistrationService.GuestInput guest = new EventRegistrationService.GuestInput();
			guest.person = new EventPersonMatcher.PersonInput();
			guest.person.firstName = 'Guest' + i;
			guest.person.lastName = last;
			request.guests.add(guest);
		}
		EventRegistrationService.register(request);
	}

	private static String tableJson(Id eventId, String id, String name, Integer capacity) {
		return JSON.serialize(
			new Map<String, Object>{
				'id' => id,
				'eventId' => eventId,
				'name' => name,
				'capacity' => capacity
			}
		);
	}

	@IsTest
	static void seatsAPartyAndTakesOneOff() {
		System.runAs(staff()) {
			Event__c event = gala();
			register(event.Id, 'Rivera', 1);
			Account sponsorAccount = TestDataFactory.organization(new Account(Name = 'Acme Co'));
			insert as user sponsorAccount;
			Id sponsorId = EventSponsorsController.addSponsor(event.Id, sponsorAccount.Id, null);
			Test.startTest();
			Id tableId = EventSeatingController.saveTable(tableJson(event.Id, null, 'Table 1', 2));
			EventSeatingController.saveTable(
				JSON.serialize(
					new Map<String, Object>{
						'id' => tableId,
						'eventId' => event.Id,
						'name' => 'Table One',
						'capacity' => 2,
						'sponsorId' => sponsorId
					}
				)
			);
			EventSeatingController.Seating before = EventSeatingController.getSeating(event.Id);
			List<Map<String, Object>> seats = new List<Map<String, Object>>();
			for (EventSeatingController.Guest guest : before.guests) {
				seats.add(
					new Map<String, Object>{ 'attendeeId' => guest.id, 'tableId' => tableId }
				);
			}
			Integer moved = EventSeatingController.assignSeats(event.Id, JSON.serialize(seats));
			EventSeatingController.Seating seated = EventSeatingController.getSeating(event.Id);
			EventSeatingController.saveNeeds(seated.guests[0].id, 'Vegetarian ', 'Wheelchair');
			EventSeatingController.assignSeats(
				event.Id,
				JSON.serialize(
					new List<Map<String, Object>>{
						new Map<String, Object>{
							'attendeeId' => seated.guests[0].id,
							'tableId' => null
						}
					}
				)
			);
			EventSeatingController.Seating after = EventSeatingController.getSeating(event.Id);
			Test.stopTest();

			Assert.areEqual(1, before.tables.size(), 'One table');
			Assert.areEqual('Table One', before.tables[0].name, 'Renamed');
			Assert.areEqual('Acme Co', before.tables[0].sponsorName, 'A sponsor table');
			Assert.areEqual(1, before.sponsors.size(), 'The sponsor can be chosen');
			Assert.areEqual(2, before.guests.size(), 'The registrant and the guest');
			Assert.areEqual(before.guests[0].partyId, before.guests[1].partyId, 'One party');
			Assert.areEqual(2, moved, 'The party moved together');
			Assert.areEqual(tableId, seated.guests[0].tableId, 'Seated');
			Assert.areEqual('Vegetarian', after.guests[0].dietary, 'Dietary saved and trimmed');
			Assert.areEqual('Wheelchair', after.guests[0].access, 'Access saved');
			Assert.isNull(after.guests[0].tableId, 'Taken off the table');
			Assert.isTrue(before.canEdit && before.canAddTable, 'Staff may edit');
		}
	}

	@IsTest
	static void refusesOtherEventsAndBadInput() {
		System.runAs(staff()) {
			Event__c event = gala();
			Event__c other = gala();
			register(event.Id, 'Rivera', 0);
			Id otherTable = EventSeatingController.saveTable(tableJson(other.Id, null, 'Far', 4));
			EventSeatingController.Seating seating = EventSeatingController.getSeating(event.Id);
			Integer refusals = 0;
			Test.startTest();
			try {
				EventSeatingController.assignSeats(
					event.Id,
					JSON.serialize(
						new List<Map<String, Object>>{
							new Map<String, Object>{
								'attendeeId' => seating.guests[0].id,
								'tableId' => otherTable
							}
						}
					)
				);
			} catch (AuraHandledException e) {
				refusals++;
			}
			try {
				EventSeatingController.saveTable(tableJson(event.Id, null, '', 4));
			} catch (AuraHandledException e) {
				refusals++;
			}
			try {
				EventSeatingController.saveTable('{not json');
			} catch (AuraHandledException e) {
				refusals++;
			}
			try {
				EventSeatingController.assignSeats(event.Id, '{not json');
			} catch (AuraHandledException e) {
				refusals++;
			}
			Test.stopTest();
			Assert.areEqual(4, refusals, 'Each bad call is refused');
		}
	}

	@IsTest
	static void removingATableLeavesGuestsRegistered() {
		System.runAs(staff()) {
			Event__c event = gala();
			register(event.Id, 'Rivera', 0);
			Id tableId = EventSeatingController.saveTable(tableJson(event.Id, null, 'Table 1', 2));
			EventSeatingController.Seating seating = EventSeatingController.getSeating(event.Id);
			EventSeatingController.assignSeats(
				event.Id,
				JSON.serialize(
					new List<Map<String, Object>>{
						new Map<String, Object>{
							'attendeeId' => seating.guests[0].id,
							'tableId' => tableId
						}
					}
				)
			);
			Test.startTest();
			EventSeatingController.deleteTable(tableId);
			Test.stopTest();
			EventSeatingController.Seating after = EventSeatingController.getSeating(event.Id);
			Assert.areEqual(0, after.tables.size(), 'Table gone');
			Assert.areEqual(1, after.guests.size(), 'The guest is still registered');
			Assert.isNull(after.guests[0].tableId, 'No table');
		}
	}
}
