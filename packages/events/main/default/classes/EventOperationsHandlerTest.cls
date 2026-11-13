/**
 * Dana keeps the conference center as a venue with its rooms, picks it on a batch of events and
 * picks rooms on sessions (EV-24, R-EVN1).
 */
@IsTest(
	testFor='ApexClass:EventOperationsHandler, ApexTrigger:EventTrigger, ApexTrigger:EventSessionTrigger'
)
private class EventOperationsHandlerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Events_Admin');
	}

	private static User staff() {
		return TestUsers.adminWith('Events_Admin');
	}

	private static Event__c event(String name, Id venueId) {
		Datetime start = Datetime.now().addDays(20);
		return new Event__c(
			Name = name,
			Status__c = 'Open',
			Format__c = 'In Person',
			Start__c = start,
			End__c = start.addHours(8),
			Venue__c = venueId
		);
	}

	@IsTest
	static void fillsBlankVenueFieldsForABatchAndKeepsTypedOnes() {
		System.runAs(staff()) {
			Event_Venue__c venue = new Event_Venue__c(
				Name = 'Riverside Center',
				Venue_Address__c = '1 Main St'
			);
			insert as user venue;
			List<Event__c> events = new List<Event__c>();
			for (Integer i = 0; i < 200; i++) {
				events.add(event('Class ' + i, venue.Id));
			}
			Event__c typed = event('Gala', venue.Id);
			typed.Venue_Name__c = 'Main Hall';
			events.add(typed);
			Test.startTest();
			insert as user events;
			Test.stopTest();
			Event__c first = [
				SELECT Venue_Name__c, Venue_Address__c
				FROM Event__c
				WHERE Id = :events[0].Id
				WITH USER_MODE
			];
			Assert.areEqual('Riverside Center', first.Venue_Name__c, 'A blank name fills');
			Assert.areEqual('1 Main St', first.Venue_Address__c, 'A blank address fills');
			Integer filled = [
				SELECT COUNT()
				FROM Event__c
				WHERE Venue_Name__c = 'Riverside Center'
				WITH USER_MODE
			];
			Assert.areEqual(200, filled, 'Every event in the batch fills');
			Event__c kept = [
				SELECT Venue_Name__c, Venue_Address__c
				FROM Event__c
				WHERE Id = :typed.Id
				WITH USER_MODE
			];
			Assert.areEqual('Main Hall', kept.Venue_Name__c, 'A typed name is kept');
			Assert.areEqual('1 Main St', kept.Venue_Address__c, 'Only the blank one fills');
		}
	}

	@IsTest
	static void aPickedRoomNamesTheSessionAndFillsABlankCapacity() {
		System.runAs(staff()) {
			Event_Venue__c venue = new Event_Venue__c(Name = 'Riverside Center');
			insert as user venue;
			Event_Room__c roomA = new Event_Room__c(
				Venue__c = venue.Id,
				Name = 'Room A',
				Capacity__c = 40
			);
			Event_Room__c roomB = new Event_Room__c(
				Venue__c = venue.Id,
				Name = 'Room B',
				Capacity__c = 90
			);
			insert as user new List<Event_Room__c>{ roomA, roomB };
			Event__c record = event('Summit', venue.Id);
			insert as user record;
			Event_Session__c open = new Event_Session__c(
				Event__c = record.Id,
				Name = 'Opening',
				Session_Type__c = 'Lightning Talk',
				Status__c = 'Draft',
				Venue_Room__c = roomA.Id
			);
			Event_Session__c sized = new Event_Session__c(
				Event__c = record.Id,
				Name = 'Workshop',
				Session_Type__c = 'Workshop',
				Status__c = 'Draft',
				Capacity__c = 12,
				Venue_Room__c = roomA.Id
			);
			Test.startTest();
			insert as user new List<Event_Session__c>{ open, sized };
			update as user new Event_Session__c(Id = open.Id, Room__c = 'Typed Room');
			Event_Session__c kept = [
				SELECT Room__c
				FROM Event_Session__c
				WHERE Id = :open.Id
				WITH USER_MODE
			];
			update as user new Event_Session__c(Id = open.Id, Venue_Room__c = roomB.Id);
			Test.stopTest();
			Assert.areEqual(
				'Typed Room',
				kept.Room__c,
				'An unchanged room record keeps typed text'
			);
			Map<Id, Event_Session__c> saved = new Map<Id, Event_Session__c>(
				[
					SELECT Room__c, Capacity__c
					FROM Event_Session__c
					WHERE Event__c = :record.Id
					WITH USER_MODE
				]
			);
			Assert.areEqual('Room B', saved.get(open.Id).Room__c, 'A changed room renames it');
			Assert.areEqual(40, saved.get(open.Id).Capacity__c, 'A filled capacity is kept');
			Assert.areEqual('Room A', saved.get(sized.Id).Room__c, 'The room name is copied');
			Assert.areEqual(12, saved.get(sized.Id).Capacity__c, 'A typed capacity is kept');
		}
	}
}
