/**
 * The Badges tab of the event page (EV-17): the people holding a seat (Registered or Attended)
 * and the event's sessions, for printing name badges and sign-in sheets. Thin by design (plan
 * Section 9.9): the layouts and the print pages are built in the browser by `eventBadgesModel`
 * and printed there, so nothing goes to an outside service. A badge's QR code holds the
 * attendee's record identifier, the same code the Check-In tab reads. Reads are user mode.
 */
public with sharing class EventBadgesController {
	private static final String CONTEXT = 'EventBadgesController';
	private static final Integer ROW_LIMIT = 2000;
	private static final Set<String> PRINTABLE = new Set<String>{
		EventRegistrationService.STATUS_REGISTERED,
		EventRegistrationService.STATUS_ATTENDED
	};

	/** Everything the tab draws. */
	public class Badges {
		@AuraEnabled
		public String eventName;
		@AuraEnabled
		public Datetime eventStart;
		@AuraEnabled
		public String venue;
		@AuraEnabled
		public Boolean truncated = false;
		@AuraEnabled
		public List<Person> attendees = new List<Person>();
		@AuraEnabled
		public List<Slot> sessions = new List<Slot>();
	}

	/** One person to print. */
	public class Person {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String organization;
		/** The attendee's Badge Title (EV-26), blank when none is set. */
		@AuraEnabled
		public String title;
		@AuraEnabled
		public String ticketName;
	}

	/** One session, for a sign-in sheet of its own. */
	public class Slot {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Datetime startsAt;
		@AuraEnabled
		public String room;
	}

	/**
	 * The event's name, date and venue, the people to print and the sessions.
	 *
	 * @param eventId the event
	 */
	@AuraEnabled
	public static Badges getBadges(Id eventId) {
		try {
			Badges result = new Badges();
			Event__c event = [
				SELECT Id, Name, Start__c, Venue_Name__c
				FROM Event__c
				WHERE Id = :eventId
				WITH USER_MODE
				LIMIT 1
			];
			result.eventName = event.Name;
			result.eventStart = event.Start__c;
			result.venue = event.Venue_Name__c;
			List<Event_Attendee__c> rows = [
				SELECT
					Id,
					Name,
					Badge_Name__c,
					Badge_Title__c,
					Badge_Company__c,
					Ticket_Type__r.Name,
					Contact__r.Account.Name
				FROM Event_Attendee__c
				WHERE Event_Registration__r.Event__c = :eventId AND Status__c IN :PRINTABLE
				WITH USER_MODE
				ORDER BY Name
				LIMIT :ROW_LIMIT + 1
			];
			result.truncated = rows.size() > ROW_LIMIT;
			for (Integer i = 0; i < Math.min(rows.size(), ROW_LIMIT); i++) {
				Person person = new Person();
				person.id = rows[i].Id;
				// EV-26: the badge overrides win when set (ADR-NEXT decision 13).
				person.name = String.isNotBlank(rows[i].Badge_Name__c)
					? rows[i].Badge_Name__c
					: rows[i].Name;
				person.title = rows[i].Badge_Title__c;
				person.ticketName = rows[i].Ticket_Type__r?.Name;
				person.organization = String.isNotBlank(rows[i].Badge_Company__c)
					? rows[i].Badge_Company__c
					: rows[i].Contact__r?.Account?.Name;
				result.attendees.add(person);
			}
			for (Event_Session__c session : [
				SELECT Id, Name, Start__c, Room__c
				FROM Event_Session__c
				WHERE Event__c = :eventId
				WITH USER_MODE
				ORDER BY Start__c ASC NULLS LAST, Name
				LIMIT 500
			]) {
				Slot slot = new Slot();
				slot.id = session.Id;
				slot.name = session.Name;
				slot.startsAt = session.Start__c;
				slot.room = session.Room__c;
				result.sessions.add(slot);
			}
			return result;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getBadges', eventId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Badges_LoadFailed'));
		}
	}
}
