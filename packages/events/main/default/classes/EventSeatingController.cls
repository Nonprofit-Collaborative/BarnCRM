/**
 * The Seating tab of the event page (EV-13, canonical model 29EV26): the event's tables with
 * capacity, host and optional sponsor, and the people who may be seated (attendees Registered or
 * Attended), each with the table they sit at and their dietary and access needs. Thin by design
 * (plan Section 9.9): counts, over-capacity warnings, the keep-a-party-together suggestion and the
 * CSV live in `eventSeatingModel`. A party is the people on one registration. Seating more people
 * than a table holds is allowed; the tab warns. Reads are user mode and writes use
 * `AccessLevel.USER_MODE`.
 */
public with sharing class EventSeatingController {
	private static final String CONTEXT = 'EventSeatingController';
	private static final Integer ROW_LIMIT = 2000;
	private static final Set<String> SEATABLE = new Set<String>{
		EventRegistrationService.STATUS_REGISTERED,
		EventRegistrationService.STATUS_ATTENDED
	};

	/** Everything the tab draws. */
	public class Seating {
		@AuraEnabled
		public Boolean canEdit = false;
		@AuraEnabled
		public Boolean canAddTable = false;
		@AuraEnabled
		public Boolean truncated = false;
		@AuraEnabled
		public List<TableRow> tables = new List<TableRow>();
		@AuraEnabled
		public List<Guest> guests = new List<Guest>();
		@AuraEnabled
		public List<Option> sponsors = new List<Option>();
	}

	/** One sponsor to choose for a sponsor table. */
	public class Option {
		@AuraEnabled
		public String value;
		@AuraEnabled
		public String label;
	}

	/** One table. */
	public class TableRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Integer capacity;
		@AuraEnabled
		public String hostId;
		@AuraEnabled
		public String hostName;
		@AuraEnabled
		public String sponsorId;
		@AuraEnabled
		public String sponsorName;
	}

	/** One person who may be seated. */
	public class Guest {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String partyId;
		@AuraEnabled
		public String tableId;
		@AuraEnabled
		public String ticketName;
		@AuraEnabled
		public String organization;
		@AuraEnabled
		public String dietary;
		@AuraEnabled
		public String access;
	}

	/** A table to save: with an identifier it is changed, without one it is added. */
	public class TableInput {
		public String id;
		public String eventId;
		public String name;
		public Integer capacity;
		public String hostId;
		public String sponsorId;
	}

	/** One seat to set: a null table takes the person off their table. */
	public class SeatInput {
		public String attendeeId;
		public String tableId;
	}

	/**
	 * The tables, the guests and the sponsors of the event.
	 *
	 * @param eventId the event
	 */
	@AuraEnabled
	public static Seating getSeating(Id eventId) {
		try {
			Seating result = new Seating();
			result.canEdit = Schema.SObjectType.Event_Attendee__c.isUpdateable();
			result.canAddTable = Schema.SObjectType.Event_Table__c.isCreateable();
			for (Event_Table__c row : [
				SELECT
					Id,
					Name,
					Capacity__c,
					Host__c,
					Host__r.Name,
					Event_Sponsor__c,
					Event_Sponsor__r.Name
				FROM Event_Table__c
				WHERE Event__c = :eventId
				WITH USER_MODE
				ORDER BY Name
				LIMIT 500
			]) {
				TableRow table = new TableRow();
				table.id = row.Id;
				table.name = row.Name;
				table.capacity = row.Capacity__c == null ? 0 : row.Capacity__c.intValue();
				table.hostId = row.Host__c;
				table.hostName = row.Host__r?.Name;
				table.sponsorId = row.Event_Sponsor__c;
				table.sponsorName = row.Event_Sponsor__r?.Name;
				result.tables.add(table);
			}
			for (Event_Sponsor__c sponsor : [
				SELECT Id, Name
				FROM Event_Sponsor__c
				WHERE Event__c = :eventId AND Status__c != 'Declined'
				WITH USER_MODE
				ORDER BY Name
				LIMIT 200
			]) {
				Option option = new Option();
				option.value = sponsor.Id;
				option.label = sponsor.Name;
				result.sponsors.add(option);
			}
			List<Event_Attendee__c> rows = [
				SELECT
					Id,
					Name,
					Event_Registration__c,
					Event_Table__c,
					Ticket_Type__r.Name,
					Contact__r.Account.Name,
					Dietary_Needs__c,
					Access_Needs__c
				FROM Event_Attendee__c
				WHERE Event_Registration__r.Event__c = :eventId AND Status__c IN :SEATABLE
				WITH USER_MODE
				ORDER BY Event_Registration__c, Name
				LIMIT :ROW_LIMIT + 1
			];
			result.truncated = rows.size() > ROW_LIMIT;
			for (Integer i = 0; i < Math.min(rows.size(), ROW_LIMIT); i++) {
				Guest guest = new Guest();
				guest.id = rows[i].Id;
				guest.name = rows[i].Name;
				guest.partyId = rows[i].Event_Registration__c;
				guest.tableId = rows[i].Event_Table__c;
				guest.ticketName = rows[i].Ticket_Type__r?.Name;
				guest.organization = rows[i].Contact__r?.Account?.Name;
				guest.dietary = rows[i].Dietary_Needs__c;
				guest.access = rows[i].Access_Needs__c;
				result.guests.add(guest);
			}
			return result;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getSeating', eventId);
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Seating_LoadFailed'));
		}
	}

	/**
	 * Adds a table or changes one.
	 *
	 * @param inputJson a `TableInput` as JSON
	 * @return the table's identifier
	 */
	@AuraEnabled
	public static String saveTable(String inputJson) {
		TableInput input;
		try {
			input = (TableInput) JSON.deserialize(inputJson, TableInput.class);
		} catch (Exception unreadable) {
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
		if (String.isBlank(input.name) || input.capacity == null || input.capacity < 1) {
			throw UserErrors.message(
				BarnHelp.text('Events', 'Events_Seating_TableNeedsNameAndSeats')
			);
		}
		try {
			Event_Table__c table = new Event_Table__c(
				Name = input.name.trim().left(80),
				Capacity__c = input.capacity,
				Host__c = String.isBlank(input.hostId) ? null : (Id) input.hostId,
				Event_Sponsor__c = String.isBlank(input.sponsorId) ? null : (Id) input.sponsorId
			);
			if (String.isBlank(input.id)) {
				table.Event__c = input.eventId;
				Database.insert(table, true, AccessLevel.USER_MODE);
			} else {
				table.Id = input.id;
				Database.update(table, true, AccessLevel.USER_MODE);
			}
			return table.Id;
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.saveTable', input.eventId);
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/**
	 * Removes a table. The people seated at it stay registered and have no table.
	 *
	 * @param tableId the table
	 */
	@AuraEnabled
	public static void deleteTable(Id tableId) {
		try {
			Database.delete(new Event_Table__c(Id = tableId), true, AccessLevel.USER_MODE);
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.deleteTable', tableId);
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/**
	 * Seats people: sets each person's table, or takes them off a table. A table is never refused
	 * for being full; the tab warns first. Every person and table must belong to the event.
	 *
	 * @param eventId the event
	 * @param seatsJson a list of `SeatInput` as JSON
	 * @return how many people were moved
	 */
	@AuraEnabled
	public static Integer assignSeats(Id eventId, String seatsJson) {
		List<SeatInput> seats;
		try {
			seats = (List<SeatInput>) JSON.deserialize(seatsJson, List<SeatInput>.class);
		} catch (Exception unreadable) {
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
		Set<Id> attendeeIds = new Set<Id>();
		Set<Id> tableIds = new Set<Id>();
		for (SeatInput seat : seats) {
			attendeeIds.add(seat.attendeeId);
			if (String.isNotBlank(seat.tableId)) {
				tableIds.add(seat.tableId);
			}
		}
		try {
			Map<Id, Event_Attendee__c> attendees = new Map<Id, Event_Attendee__c>(
				[
					SELECT Id
					FROM Event_Attendee__c
					WHERE
						Id IN :attendeeIds
						AND Event_Registration__r.Event__c = :eventId
						AND Status__c IN :SEATABLE
					WITH USER_MODE
				]
			);
			Map<Id, Event_Table__c> tables = new Map<Id, Event_Table__c>(
				[
					SELECT Id
					FROM Event_Table__c
					WHERE Id IN :tableIds AND Event__c = :eventId
					WITH USER_MODE
				]
			);
			if (attendees.size() != attendeeIds.size() || tables.size() != tableIds.size()) {
				throw UserErrors.message(BarnHelp.text('Events', 'Events_Seating_OtherEvent'));
			}
			List<Event_Attendee__c> changes = new List<Event_Attendee__c>();
			for (SeatInput seat : seats) {
				changes.add(
					new Event_Attendee__c(
						Id = seat.attendeeId,
						Event_Table__c = String.isBlank(seat.tableId) ? null : (Id) seat.tableId
					)
				);
			}
			Database.update(changes, true, AccessLevel.USER_MODE);
			return changes.size();
		} catch (AuraHandledException refused) {
			throw refused;
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.assignSeats', eventId);
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/**
	 * Saves an attendee's dietary and access needs.
	 *
	 * @param attendeeId the attendee
	 * @param dietary dietary needs, blank for none
	 * @param access access needs, blank for none
	 */
	@AuraEnabled
	public static void saveNeeds(Id attendeeId, String dietary, String access) {
		try {
			Database.update(
				new Event_Attendee__c(
					Id = attendeeId,
					Dietary_Needs__c = String.isBlank(dietary) ? null : dietary.trim(),
					Access_Needs__c = String.isBlank(access) ? null : access.trim()
				),
				true,
				AccessLevel.USER_MODE
			);
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.saveNeeds', attendeeId);
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}
}
