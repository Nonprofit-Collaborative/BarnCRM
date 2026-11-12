/**
 * Event Management's save-time upkeep for venues and rooms (EV-24; ADR-NEXT
 * `NEXT-events-attendee-app-operations-portal-templates.md`, decision 14; canonical model
 * R-EVN1), run by the Core trigger dispatcher through the registry rows `Event_Venue_Fill` and
 * `Session_Room_Fill`.
 *
 * An event with a venue fills its blank Venue Name and Venue Address from the venue. A session
 * whose room record is new or changed copies the room's name into Room, the text the agenda's
 * clash flags, the public page and badges already read, and the room's capacity into a blank
 * Capacity. Reads in user mode: the person saving can read the venue they picked.
 */
@NamespaceAccessible
public with sharing class EventOperationsHandler extends TriggerHandler {
	private static final Integer NAME_LENGTH = 255;
	private static final Integer ROOM_LENGTH = 80;

	@NamespaceAccessible
	public EventOperationsHandler() {
		return;
	}

	public override String getName() {
		return 'EventOperationsHandler';
	}

	public override void beforeInsert() {
		route(newRecords(), null);
	}

	public override void beforeUpdate() {
		route(newRecords(), oldRecordsById());
	}

	private static void route(List<SObject> records, Map<Id, SObject> oldById) {
		if (records == null || records.isEmpty()) {
			return;
		}
		Schema.SObjectType objectType = records[0].getSObjectType();
		if (objectType == Event__c.SObjectType) {
			fillVenues((List<Event__c>) records);
		} else if (objectType == Event_Session__c.SObjectType) {
			fillRooms((List<Event_Session__c>) records, oldById);
		}
	}

	/** R-EVN1: a blank Venue Name or Venue Address takes the picked venue's. */
	@TestVisible
	private static void fillVenues(List<Event__c> events) {
		Set<Id> venueIds = new Set<Id>();
		for (Event__c record : events) {
			if (
				record.Venue__c != null &&
				(String.isBlank(record.Venue_Name__c) || String.isBlank(record.Venue_Address__c))
			) {
				venueIds.add(record.Venue__c);
			}
		}
		if (venueIds.isEmpty()) {
			return;
		}
		Map<Id, Event_Venue__c> venues = new Map<Id, Event_Venue__c>(
			[
				SELECT Id, Name, Venue_Address__c
				FROM Event_Venue__c
				WHERE Id IN :venueIds
				WITH USER_MODE
			]
		);
		for (Event__c record : events) {
			Event_Venue__c venue = venues.get(record.Venue__c);
			if (venue == null) {
				continue;
			}
			if (String.isBlank(record.Venue_Name__c)) {
				record.Venue_Name__c = venue.Name.left(NAME_LENGTH);
			}
			if (String.isBlank(record.Venue_Address__c)) {
				record.Venue_Address__c = venue.Venue_Address__c;
			}
		}
	}

	/** R-EVN1: a newly picked room names the session's Room and fills a blank Capacity. */
	@TestVisible
	private static void fillRooms(List<Event_Session__c> sessions, Map<Id, SObject> oldById) {
		Set<Id> roomIds = new Set<Id>();
		for (Event_Session__c record : sessions) {
			SObject old = oldById == null ? null : oldById.get(record.Id);
			if (
				record.Venue_Room__c != null &&
				(old == null ||
				old.get('Venue_Room__c') != record.Venue_Room__c)
			) {
				roomIds.add(record.Venue_Room__c);
			}
		}
		if (roomIds.isEmpty()) {
			return;
		}
		Map<Id, Event_Room__c> rooms = new Map<Id, Event_Room__c>(
			[SELECT Id, Name, Capacity__c FROM Event_Room__c WHERE Id IN :roomIds WITH USER_MODE]
		);
		for (Event_Session__c record : sessions) {
			Event_Room__c room = roomIds.contains(record.Venue_Room__c)
				? rooms.get(record.Venue_Room__c)
				: null;
			if (room == null) {
				continue;
			}
			record.Room__c = room.Name.left(ROOM_LENGTH);
			if (record.Capacity__c == null) {
				record.Capacity__c = room.Capacity__c;
			}
		}
	}
}
