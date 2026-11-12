/**
 * Event Management's save-time upkeep for venues and rooms (EV-24; ADR-0215
 * `0215-events-attendee-app-operations-portal-templates.md`, decision 14; canonical model
 * R-EVN1), run by the Core trigger dispatcher through the registry rows `Event_Venue_Fill` and
 * `Session_Room_Fill`.
 *
 * An event with a venue fills its blank Venue Name and Venue Address from the venue. A session
 * whose room record is new or changed copies the room's name into Room, the text the agenda's
 * clash flags, the public page and badges already read, and the room's capacity into a blank
 * Capacity. Reads in user mode: the person saving can read the venue they picked.
 *
 * A new Booth Scan (EV-28, registry row `Sponsor_Lead_Scan`, always runs) is resolved to the
 * scanner's sponsorship and a status, keeping the attendee's details only when they share them
 * (R-SLD1, R-SLD2). An Agenda Item's first rating after its session starts adds one anonymous
 * Session Rating (EV-29, registry row `Agenda_Item_Rating`, always runs; R-AGI2). Both read in
 * system mode in the inner `ScanReader`.
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
		} else if (objectType == Sponsor_Lead__c.SObjectType && oldById == null) {
			new ScanReader().resolve((List<Sponsor_Lead__c>) records);
		} else if (objectType == Agenda_Item__c.SObjectType && oldById != null) {
			new ScanReader().sendRatings((List<Agenda_Item__c>) records, oldById);
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

	/**
	 * The scan and rating rules, read in system mode (Without Sharing Register, Events): a lead
	 * is saved by the sponsor portal's integration user, which has no object access, and must
	 * find the scanned attendee and the scanner's sponsorship whoever saves it; a rating writes
	 * an anonymous Session Rating the person could not read back.
	 */
	@TestVisible
	private without sharing class ScanReader {
		/** R-SLD1 and R-SLD2: the lead's sponsorship, status and, only when Shared, its details. */
		void resolve(List<Sponsor_Lead__c> leads) {
			Set<Id> scanners = new Set<Id>();
			Set<Id> attendeeIds = new Set<Id>();
			for (Sponsor_Lead__c lead : leads) {
				scanners.add(lead.Scanned_By__c);
				Id code = attendeeCode(lead.Badge_Code__c);
				if (code != null) {
					attendeeIds.add(code);
				}
			}
			Map<Id, Event_Attendee__c> attendees = new Map<Id, Event_Attendee__c>(
				[
					SELECT
						Id,
						Contact__r.Email,
						Attendee_Name__c,
						Badge_Name__c,
						Badge_Title__c,
						Badge_Company__c,
						Share_With_Sponsors__c,
						Event_Registration__r.Event__c
					FROM Event_Attendee__c
					WHERE Id IN :attendeeIds
					WITH SYSTEM_MODE
				]
			);
			Map<Id, List<Event_Sponsor__c>> sponsorships = sponsorshipsOf(scanners);
			// A lead staff create for a booth names its sponsorship and may have no scanner.
			Set<Id> namedIds = new Set<Id>();
			for (Sponsor_Lead__c lead : leads) {
				if (lead.Event_Sponsor__c != null) {
					namedIds.add(lead.Event_Sponsor__c);
				}
			}
			Map<Id, Event_Sponsor__c> named = new Map<Id, Event_Sponsor__c>(
				[
					SELECT Id, Event__c, Contact__c
					FROM Event_Sponsor__c
					WHERE Id IN :namedIds
					WITH SYSTEM_MODE
				]
			);
			Set<String> taken = takenKeys(leads, attendees, sponsorships, named.values());
			for (Sponsor_Lead__c lead : leads) {
				Event_Attendee__c attendee = attendees.get(attendeeCode(lead.Badge_Code__c));
				Id eventId = attendee == null ? null : attendee.Event_Registration__r.Event__c;
				Event_Sponsor__c sponsor = sponsorshipAt(
					sponsorships.get(lead.Scanned_By__c),
					eventId
				);
				if (sponsor == null) {
					sponsor = named.get(lead.Event_Sponsor__c);
				}
				if (sponsor == null && lead.Event_Sponsor__c == null) {
					lead.addError(BarnHelp.text('Events', 'Events_Lead_NoSponsorship'));
					continue;
				}
				if (sponsor != null) {
					lead.Event_Sponsor__c = sponsor.Id;
				}
				lead.Event_Attendee__c = null;
				lead.Lead_Key__c = null;
				if (attendee == null || sponsor == null || sponsor.Event__c != eventId) {
					lead.Status__c = 'Not Found';
				} else if (!attendee.Share_With_Sponsors__c) {
					lead.Status__c = 'Not Shared';
					lead.Badge_Code__c = null;
				} else if (!taken.add(leadKey(lead.Event_Sponsor__c, attendee.Id))) {
					lead.Status__c = 'Already Scanned';
				} else {
					lead.Status__c = 'Shared';
					lead.Event_Attendee__c = attendee.Id;
					lead.Lead_Key__c = leadKey(lead.Event_Sponsor__c, attendee.Id);
					lead.Lead_Name__c = String.isBlank(attendee.Badge_Name__c)
						? attendee.Attendee_Name__c
						: attendee.Badge_Name__c;
					lead.Lead_Email__c = attendee.Contact__r?.Email;
					lead.Lead_Title__c = attendee.Badge_Title__c;
					lead.Lead_Company__c = attendee.Badge_Company__c;
				}
			}
		}

		/** A scanner's sponsorships, newest first: as the sponsor's contact or as booth staff. */
		private Map<Id, List<Event_Sponsor__c>> sponsorshipsOf(Set<Id> scanners) {
			Map<Id, Set<Id>> sponsorIdsByScanner = new Map<Id, Set<Id>>();
			Set<Id> sponsorIds = new Set<Id>();
			for (Event_Attendee__c staff : [
				SELECT Contact__c, Sponsor__c
				FROM Event_Attendee__c
				WHERE Contact__c IN :scanners AND Sponsor__c != NULL AND Status__c != 'Cancelled'
				WITH SYSTEM_MODE
			]) {
				if (!sponsorIdsByScanner.containsKey(staff.Contact__c)) {
					sponsorIdsByScanner.put(staff.Contact__c, new Set<Id>());
				}
				sponsorIdsByScanner.get(staff.Contact__c).add(staff.Sponsor__c);
				sponsorIds.add(staff.Sponsor__c);
			}
			Map<Id, List<Event_Sponsor__c>> result = new Map<Id, List<Event_Sponsor__c>>();
			for (Event_Sponsor__c sponsor : [
				SELECT Id, Event__c, Contact__c
				FROM Event_Sponsor__c
				WHERE Contact__c IN :scanners OR Id IN :sponsorIds
				WITH SYSTEM_MODE
				ORDER BY CreatedDate DESC
			]) {
				for (Id scanner : scanners) {
					Set<Id> staffOf = sponsorIdsByScanner.get(scanner);
					if (
						sponsor.Contact__c == scanner ||
						(staffOf != null && staffOf.contains(sponsor.Id))
					) {
						if (!result.containsKey(scanner)) {
							result.put(scanner, new List<Event_Sponsor__c>());
						}
						result.get(scanner).add(sponsor);
					}
				}
			}
			return result;
		}

		/** The scanner's sponsorship at the event, else their newest; null with none. */
		private Event_Sponsor__c sponsorshipAt(List<Event_Sponsor__c> mine, Id eventId) {
			if (mine == null || mine.isEmpty()) {
				return null;
			}
			for (Event_Sponsor__c sponsor : mine) {
				if (sponsor.Event__c == eventId) {
					return sponsor;
				}
			}
			return mine[0];
		}

		/** The lead keys already saved for the sponsorships these scans can reach. */
		private Set<String> takenKeys(
			List<Sponsor_Lead__c> leads,
			Map<Id, Event_Attendee__c> attendees,
			Map<Id, List<Event_Sponsor__c>> sponsorships,
			List<Event_Sponsor__c> named
		) {
			Set<String> keys = new Set<String>();
			for (Event_Sponsor__c sponsor : named) {
				for (Id attendeeId : attendees.keySet()) {
					keys.add(leadKey(sponsor.Id, attendeeId));
				}
			}
			for (List<Event_Sponsor__c> mine : sponsorships.values()) {
				for (Event_Sponsor__c sponsor : mine) {
					for (Id attendeeId : attendees.keySet()) {
						keys.add(leadKey(sponsor.Id, attendeeId));
					}
				}
			}
			Set<String> taken = new Set<String>();
			for (Sponsor_Lead__c saved : [
				SELECT Lead_Key__c
				FROM Sponsor_Lead__c
				WHERE Lead_Key__c IN :keys
				WITH SYSTEM_MODE
			]) {
				taken.add(saved.Lead_Key__c);
			}
			return taken;
		}

		/** R-AGI2: the first rating after the session starts adds one anonymous Session Rating. */
		void sendRatings(List<Agenda_Item__c> items, Map<Id, SObject> oldById) {
			List<Agenda_Item__c> rating = new List<Agenda_Item__c>();
			Set<Id> sessionIds = new Set<Id>();
			for (Agenda_Item__c item : items) {
				Agenda_Item__c old = (Agenda_Item__c) oldById.get(item.Id);
				Boolean changed =
					item.My_Rating__c != old.My_Rating__c ||
					item.My_Comment__c != old.My_Comment__c;
				if (!changed) {
					continue;
				}
				if (old.Rated__c) {
					item.addError(BarnHelp.text('Events', 'Events_Agenda_RatedOnce'));
				} else if (item.My_Rating__c != null) {
					rating.add(item);
					sessionIds.add(item.Event_Session__c);
				}
			}
			if (rating.isEmpty()) {
				return;
			}
			Map<Id, Event_Session__c> sessions = new Map<Id, Event_Session__c>(
				[SELECT Id, Start__c FROM Event_Session__c WHERE Id IN :sessionIds WITH SYSTEM_MODE]
			);
			List<Session_Rating__c> ratings = new List<Session_Rating__c>();
			for (Agenda_Item__c item : rating) {
				Event_Session__c session = sessions.get(item.Event_Session__c);
				if (
					session == null ||
					session.Start__c == null ||
					session.Start__c > Datetime.now()
				) {
					item.addError(BarnHelp.text('Events', 'Events_Agenda_RateAfterStart'));
					continue;
				}
				item.Rated__c = true;
				// Names no person and no agenda item, as EV-27's ratings never do.
				ratings.add(
					new Session_Rating__c(
						Event_Session__c = item.Event_Session__c,
						Rating__c = Integer.valueOf(item.My_Rating__c),
						Comment__c = item.My_Comment__c
					)
				);
			}
			insert as system ratings;
		}

		private Id attendeeCode(String code) {
			if (String.isBlank(code)) {
				return null;
			}
			try {
				Id parsed = Id.valueOf(code.trim());
				return parsed.getSObjectType() == Event_Attendee__c.SObjectType ? parsed : null;
			} catch (Exception notAnId) {
				return null;
			}
		}

		private String leadKey(Id sponsorId, Id attendeeId) {
			return String.valueOf(sponsorId).left(15) + String.valueOf(attendeeId).left(15);
		}
	}
}
