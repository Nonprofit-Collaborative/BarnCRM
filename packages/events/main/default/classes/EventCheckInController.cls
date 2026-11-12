/**
 * The Check-In tab of the event page (EV-12): the people who may walk in, checked in with one
 * click, by scanned QR code or by name, and walk-ins added at the door. Thin by design (plan
 * Section 9.9): the browser module `eventCheckInModel` searches, counts and reads a scanned
 * code; this class lists the attendees, moves one between Registered and Attended through
 * `EventRegistrationService`, and registers a walk-in as already attended. A QR code holds the
 * attendee's record identifier, so nothing extra is stored. Reads are user mode.
 */
public with sharing class EventCheckInController {
	private static final String CONTEXT = 'EventCheckInController';
	private static final Integer ROW_LIMIT = 2000;

	/** Everything the tab draws. */
	public class CheckIn {
		@AuraEnabled
		public Boolean canCheckIn = false;
		@AuraEnabled
		public Boolean canWalkIn = false;
		@AuraEnabled
		public Boolean truncated = false;
		@AuraEnabled
		public List<Option> tickets = new List<Option>();
		@AuraEnabled
		public List<Person> attendees = new List<Person>();
	}

	/** One ticket type to choose for a walk-in. */
	public class Option {
		@AuraEnabled
		public String value;
		@AuraEnabled
		public String label;
	}

	/** One attendee who may be checked in. */
	public class Person {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		/** The attendee's Badge Name (EV-26), shown before the name when set. */
		@AuraEnabled
		public String badgeName;
		@AuraEnabled
		public String email;
		@AuraEnabled
		public String ticketName;
		@AuraEnabled
		public String status;
	}

	/**
	 * The attendees holding a seat (Registered, Attended or No-Show) and the event's active tickets.
	 *
	 * @param eventId the event
	 */
	@AuraEnabled
	public static CheckIn getCheckIn(Id eventId) {
		try {
			CheckIn result = new CheckIn();
			result.canCheckIn = Schema.SObjectType.Event_Attendee__c.isUpdateable();
			result.canWalkIn =
				Schema.SObjectType.Event_Registration__c.isCreateable() &&
				Schema.SObjectType.Event_Attendee__c.isCreateable();
			for (Ticket_Type__c ticket : [
				SELECT Id, Name
				FROM Ticket_Type__c
				WHERE Event__c = :eventId AND Active__c = TRUE
				WITH USER_MODE
				ORDER BY Sort_Order__c ASC NULLS LAST, Name
				LIMIT 200
			]) {
				Option option = new Option();
				option.value = ticket.Id;
				option.label = ticket.Name;
				result.tickets.add(option);
			}
			List<Event_Attendee__c> rows = [
				SELECT Id, Name, Badge_Name__c, Contact__r.Email, Ticket_Type__r.Name, Status__c
				FROM Event_Attendee__c
				WHERE
					Event_Registration__r.Event__c = :eventId
					AND Status__c IN :EventRegistrationService.SEATED
				WITH USER_MODE
				ORDER BY Name
				LIMIT :ROW_LIMIT + 1
			];
			result.truncated = rows.size() > ROW_LIMIT;
			for (Integer i = 0; i < Math.min(rows.size(), ROW_LIMIT); i++) {
				Person person = new Person();
				person.id = rows[i].Id;
				person.name = rows[i].Name;
				person.badgeName = rows[i].Badge_Name__c;
				person.email = rows[i].Contact__r?.Email;
				person.ticketName = rows[i].Ticket_Type__r?.Name;
				person.status = rows[i].Status__c;
				result.attendees.add(person);
			}
			return result;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getCheckIn', eventId);
			throw UserErrors.wrapShowingDml(
				e,
				BarnHelp.text('Events', 'Events_CheckIn_LoadFailed')
			);
		}
	}

	/**
	 * Checks an attendee in (Attended), or undoes it (back to Registered).
	 *
	 * @param attendeeId the attendee
	 * @param undo true to take the check-in back
	 * @return the attendee's status now
	 */
	@AuraEnabled
	public static String checkIn(Id attendeeId, Boolean undo) {
		try {
			return EventRegistrationService.setStatus(
				attendeeId,
				undo == true
					? EventRegistrationService.STATUS_REGISTERED
					: EventRegistrationService.STATUS_ATTENDED
			);
		} catch (EventRegistrationService.RegistrationException refused) {
			throw UserErrors.message(refused.getMessage());
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.checkIn', attendeeId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/**
	 * Registers a walk-in as already attended. A walk-in is not held to the event's capacity: the
	 * person is at the door.
	 *
	 * @param requestJson an `EventRegistrationService.Request` as JSON (person and ticket)
	 * @return what was registered
	 */
	@AuraEnabled
	public static EventRegistrationService.Result walkIn(String requestJson) {
		EventRegistrationService.Request request;
		try {
			request = (EventRegistrationService.Request) JSON.deserialize(
				requestJson,
				EventRegistrationService.Request.class
			);
		} catch (Exception unreadable) {
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
		request.attendeeStatus = EventRegistrationService.STATUS_ATTENDED;
		request.registrationValues = new Map<String, Object>();
		request.source = EventRegistrationService.SOURCE_STAFF;
		request.formSubmissionKey = null;
		request.promoCode = null;
		request.guests = new List<EventRegistrationService.GuestInput>();
		try {
			return EventRegistrationService.register(request);
		} catch (EventRegistrationService.RegistrationException refused) {
			throw UserErrors.message(refused.getMessage());
		} catch (EventPersonMatcher.AmbiguousPersonException ambiguous) {
			throw UserErrors.message(ambiguous.getMessage());
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.walkIn', request.eventId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}
}
