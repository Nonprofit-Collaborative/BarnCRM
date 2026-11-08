/**
 * Registers people for an event and changes their attendance (EV-02; ADR-0182
 * `0182-event-registrations.md`, decisions 2, 3 and 5; canonical model 29EV8 and 29EV9).
 *
 * One registration names a registrant and its attendees: the registrant (unless they only book
 * for others) and any guests. People are found or created by `EventPersonMatcher` (Core's
 * matchers, household-aware). Ticket types, promo codes, the event's capacity and each ticket's
 * quantity are applied; an attendee with no seat left is Waitlisted. Everything is written in
 * user mode under one savepoint.
 *
 * Seats and code uses are counted in system mode: a count discloses nobody, and a person who may
 * register people must not oversell an event because some registrations are not shared with them.
 */
public with sharing class EventRegistrationService {
	public static final String STATUS_REGISTERED = 'Registered';
	public static final String STATUS_WAITLISTED = 'Waitlisted';
	public static final String STATUS_CANCELLED = 'Cancelled';
	public static final String STATUS_ATTENDED = 'Attended';
	public static final String STATUS_NO_SHOW = 'No-Show';
	public static final String SOURCE_STAFF = 'Staff';
	public static final String SOURCE_FORM = 'Form';
	public static final String SOURCE_SUMMIT = 'Summit Events';

	/** Attendee statuses that hold a seat (R-EAT1). */
	public static final Set<String> SEATED = new Set<String>{
		STATUS_REGISTERED,
		STATUS_ATTENDED,
		STATUS_NO_SHOW
	};
	private static final Set<String> ATTENDEE_STATUSES = new Set<String>{
		STATUS_REGISTERED,
		STATUS_WAITLISTED,
		STATUS_CANCELLED,
		STATUS_ATTENDED,
		STATUS_NO_SHOW
	};
	private static final Integer NAME_LENGTH = 80;

	/** A registration that cannot be made, in words for the person making it. */
	public class RegistrationException extends Exception {
	}

	/** One guest: a person and the ticket they hold (empty for the registrant's). */
	public class GuestInput {
		@AuraEnabled
		public EventPersonMatcher.PersonInput person;
		@AuraEnabled
		public String ticketTypeId;
	}

	/** What to register. */
	public class Request {
		@AuraEnabled
		public String eventId;
		@AuraEnabled
		public EventPersonMatcher.PersonInput registrant;
		/** The registrant's ticket type, by identifier or name; empty for the first active. */
		@AuraEnabled
		public String ticketType;
		/** False when the registrant books only for their guests. */
		@AuraEnabled
		public Boolean registrantAttends = true;
		@AuraEnabled
		public List<GuestInput> guests = new List<GuestInput>();
		@AuraEnabled
		public String promoCode;
		@AuraEnabled
		public String source = SOURCE_STAFF;
		@AuraEnabled
		public String formSubmissionKey;
		/** A status every attendee takes instead of the seat count (an import, such as Summit). */
		public String attendeeStatus;
		/** The record a sync keys the registration by; set by an adapter, never by a page. */
		public Map<String, Object> registrationValues = new Map<String, Object>();
	}

	/** What was registered. */
	public class Result {
		@AuraEnabled
		public String registrationId;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Integer registered = 0;
		@AuraEnabled
		public Integer waitlisted = 0;
		@AuraEnabled
		public Decimal amountOwed = 0;
		/** People already on the event, left out (R-EAT2). */
		@AuraEnabled
		public List<String> alreadyRegistered = new List<String>();
		@AuraEnabled
		public String registrantId;
	}

	private class Seat {
		Id personId;
		Ticket_Type__c ticket;
	}

	/**
	 * Registers the request's people for its event.
	 *
	 * @param request what to register
	 * @return what was registered
	 * @throws RegistrationException when nothing can be registered, with the reason
	 */
	public static Result register(Request request) {
		if (request == null || String.isBlank(request.eventId)) {
			throw new RegistrationException(BarnHelp.text('Events', 'Events_Register_NoEvent'));
		}
		System.Savepoint before = Database.setSavepoint();
		try {
			return registerNow(request);
		} catch (Exception failed) {
			Database.rollback(before);
			throw failed;
		}
	}

	private static Result registerNow(Request request) {
		Event__c event = lockEvent(Id.valueOf(request.eventId));
		if (event.Status__c == STATUS_CANCELLED) {
			throw new RegistrationException(
				BarnHelp.text('Events', 'Events_Register_EventCancelled')
			);
		}
		List<Ticket_Type__c> tickets = activeTickets(event.Id);
		Datetime now = Datetime.now();
		Promo_Code__c code = promoCode(event.Id, request.promoCode, now);

		Result result = new Result();
		Id registrantId = EventPersonMatcher.resolve(request.registrant, null);
		result.registrantId = registrantId;
		Id householdId = EventPersonMatcher.householdOf(registrantId);

		List<Seat> wanted = new List<Seat>();
		if (request.registrantAttends != false) {
			wanted.add(newSeat(registrantId, ticketFor(tickets, request.ticketType)));
		}
		for (GuestInput guest : request.guests == null ? new List<GuestInput>() : request.guests) {
			if (guest == null || guest.person == null) {
				continue;
			}
			wanted.add(
				newSeat(
					EventPersonMatcher.resolve(guest.person, householdId),
					ticketFor(tickets, guest.ticketTypeId)
				)
			);
		}
		Map<Id, String> names = personNames(wanted);
		List<Seat> fresh = withoutRegistered(event.Id, wanted, names, result);
		if (fresh.isEmpty()) {
			throw new RegistrationException(
				BarnHelp.text(
					'Events',
					'Events_Register_AllRegistered',
					new List<Object>{ String.join(result.alreadyRegistered, ', ') }
				)
			);
		}
		if (code != null && !appliesToAny(code, fresh, now)) {
			throw new RegistrationException(
				BarnHelp.text('Events', 'Events_Register_CodeNotForTicket')
			);
		}

		Event_Registration__c registration = new Event_Registration__c(
			Event__c = event.Id,
			Contact__c = registrantId,
			Promo_Code__c = code == null ? null : code.Id,
			Source__c = String.isBlank(request.source) ? SOURCE_STAFF : request.source,
			Form_Submission_Key__c = request.formSubmissionKey,
			Status__c = STATUS_REGISTERED
		);
		for (String fieldName : request.registrationValues.keySet()) {
			registration.put(fieldName, request.registrationValues.get(fieldName));
		}
		insert as user registration;

		SeatCounter counter = new SeatCounter(event, tickets);
		List<Event_Attendee__c> attendees = new List<Event_Attendee__c>();
		for (Seat item : fresh) {
			Id ticketId = item.ticket == null ? null : item.ticket.Id;
			String status = String.isNotBlank(request.attendeeStatus)
				? request.attendeeStatus
				: (counter.take(ticketId) ? STATUS_REGISTERED : STATUS_WAITLISTED);
			attendees.add(
				new Event_Attendee__c(
					Event_Registration__c = registration.Id,
					Name = names.get(item.personId).left(NAME_LENGTH),
					Contact__c = item.personId,
					Ticket_Type__c = ticketId,
					Price__c = item.ticket == null
						? 0
						: EventPricing.priceWithCode(item.ticket.Price__c, code, ticketId, now),
					Status__c = status
				)
			);
			if (status == STATUS_WAITLISTED) {
				result.waitlisted++;
			} else if (SEATED.contains(status)) {
				result.registered++;
			}
		}
		insert as user attendees;
		Event_Registration__c totals = settle(registration.Id, attendees);
		update as user totals;

		result.registrationId = registration.Id;
		result.status = totals.Status__c;
		result.amountOwed = totals.Amount_Owed__c;
		return result;
	}

	/**
	 * Changes one attendee's status (R-EAT1). Moving a waitlisted or cancelled attendee back to
	 * Registered needs a free seat; the registration's status and amount follow.
	 *
	 * @return the attendee's status now
	 */
	public static String setStatus(Id attendeeId, String status) {
		if (!ATTENDEE_STATUSES.contains(status)) {
			throw new RegistrationException(BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
		System.Savepoint before = Database.setSavepoint();
		try {
			Event_Attendee__c attendee = [
				SELECT
					Id,
					Status__c,
					Ticket_Type__c,
					Event_Registration__c,
					Event_Registration__r.Event__c
				FROM Event_Attendee__c
				WHERE Id = :attendeeId
				WITH USER_MODE
			];
			Boolean needsSeat = !SEATED.contains(attendee.Status__c) && SEATED.contains(status);
			if (needsSeat) {
				Event__c event = lockEvent(attendee.Event_Registration__r.Event__c);
				SeatCounter counter = new SeatCounter(event, activeTickets(event.Id));
				if (!counter.take(attendee.Ticket_Type__c)) {
					throw new RegistrationException(
						BarnHelp.text('Events', 'Events_Register_NoSeat')
					);
				}
			}
			update as user new Event_Attendee__c(Id = attendee.Id, Status__c = status);
			resettle(new Set<Id>{ attendee.Event_Registration__c });
			return status;
		} catch (Exception failed) {
			Database.rollback(before);
			throw failed;
		}
	}

	/** Cancels a registration and every attendee on it. */
	public static void cancelRegistration(Id registrationId) {
		List<Event_Attendee__c> attendees = new List<Event_Attendee__c>();
		for (Event_Attendee__c attendee : [
			SELECT Id
			FROM Event_Attendee__c
			WHERE Event_Registration__c = :registrationId
			WITH USER_MODE
		]) {
			attendees.add(new Event_Attendee__c(Id = attendee.Id, Status__c = STATUS_CANCELLED));
		}
		update as user attendees;
		update as user new Event_Registration__c(
			Id = registrationId,
			Status__c = STATUS_CANCELLED,
			Amount_Owed__c = 0
		);
	}

	/** Sets each registration's status and amount owed from its attendees as they are now. */
	public static void resettle(Set<Id> registrationIds) {
		Map<Id, List<Event_Attendee__c>> byRegistration = new Map<Id, List<Event_Attendee__c>>();
		for (Id registrationId : registrationIds) {
			byRegistration.put(registrationId, new List<Event_Attendee__c>());
		}
		for (Event_Attendee__c attendee : [
			SELECT Event_Registration__c, Status__c, Price__c
			FROM Event_Attendee__c
			WHERE Event_Registration__c IN :registrationIds
			WITH SYSTEM_MODE
		]) {
			byRegistration.get(attendee.Event_Registration__c).add(attendee);
		}
		List<Event_Registration__c> updates = new List<Event_Registration__c>();
		for (Id registrationId : byRegistration.keySet()) {
			updates.add(settle(registrationId, byRegistration.get(registrationId)));
		}
		update as user updates;
	}

	/** Registered while any attendee holds a seat, Waitlisted while all wait, else Cancelled. */
	private static Event_Registration__c settle(
		Id registrationId,
		List<Event_Attendee__c> attendees
	) {
		Decimal owed = 0;
		Boolean holdsSeat = false;
		Boolean waiting = false;
		for (Event_Attendee__c attendee : attendees) {
			if (SEATED.contains(attendee.Status__c)) {
				holdsSeat = true;
				owed += attendee.Price__c == null ? 0 : attendee.Price__c;
			} else if (attendee.Status__c == STATUS_WAITLISTED) {
				waiting = true;
			}
		}
		return new Event_Registration__c(
			Id = registrationId,
			Amount_Owed__c = owed,
			Status__c = holdsSeat
				? STATUS_REGISTERED
				: (waiting ? STATUS_WAITLISTED : STATUS_CANCELLED)
		);
	}

	/** The event, locked so two registrations never take its last seat twice. */
	private static Event__c lockEvent(Id eventId) {
		List<Event__c> events = [
			SELECT Id, Name, Status__c, Capacity__c
			FROM Event__c
			WHERE Id = :eventId
			WITH USER_MODE
			FOR UPDATE
		];
		if (events.isEmpty()) {
			throw new RegistrationException(BarnHelp.text('Events', 'Events_Register_NoEvent'));
		}
		return events[0];
	}

	private static List<Ticket_Type__c> activeTickets(Id eventId) {
		return [
			SELECT Id, Name, Price__c, Quantity__c
			FROM Ticket_Type__c
			WHERE Event__c = :eventId AND Active__c = TRUE
			WITH USER_MODE
			ORDER BY Sort_Order__c ASC NULLS LAST, Name
			LIMIT 200
		];
	}

	/** The ticket named by identifier or name; blank means the first active one, or none. */
	private static Ticket_Type__c ticketFor(List<Ticket_Type__c> tickets, String wanted) {
		if (String.isBlank(wanted)) {
			return tickets.isEmpty() ? null : tickets[0];
		}
		for (Ticket_Type__c ticket : tickets) {
			if (
				String.valueOf(ticket.Id) == wanted.trim() ||
				ticket.Name.equalsIgnoreCase(wanted.trim())
			) {
				return ticket;
			}
		}
		throw new RegistrationException(
			BarnHelp.text('Events', 'Events_Register_UnknownTicket', new List<Object>{ wanted })
		);
	}

	/** The event's code by its text, refused unless usable now and under its limit (R-ERG2). */
	private static Promo_Code__c promoCode(Id eventId, String text, Datetime now) {
		if (String.isBlank(text)) {
			return null;
		}
		String typed = text.trim();
		List<Promo_Code__c> codes = [
			SELECT
				Id,
				Name,
				Active__c,
				Discount_Type__c,
				Discount_Value__c,
				Ticket_Type__c,
				Max_Uses__c,
				Valid_From__c,
				Valid_Until__c
			FROM Promo_Code__c
			WHERE Event__c = :eventId AND Name = :typed
			WITH USER_MODE
			LIMIT 1
		];
		if (codes.isEmpty() || EventPricing.codeState(codes[0], now) != EventPricing.ACTIVE) {
			throw new RegistrationException(
				BarnHelp.text('Events', 'Events_Register_BadCode', new List<Object>{ typed })
			);
		}
		Promo_Code__c code = codes[0];
		if (code.Max_Uses__c != null) {
			Integer used = [
				SELECT COUNT()
				FROM Event_Registration__c
				WHERE Promo_Code__c = :code.Id AND Status__c != :STATUS_CANCELLED
				WITH SYSTEM_MODE
			];
			if (used >= code.Max_Uses__c) {
				throw new RegistrationException(
					BarnHelp.text('Events', 'Events_Register_CodeUsedUp', new List<Object>{ typed })
				);
			}
		}
		return code;
	}

	private static Boolean appliesToAny(Promo_Code__c code, List<Seat> seats, Datetime now) {
		for (Seat item : seats) {
			if (EventPricing.codeApplies(code, item.ticket == null ? null : item.ticket.Id, now)) {
				return true;
			}
		}
		return false;
	}

	private static Seat newSeat(Id personId, Ticket_Type__c ticket) {
		Seat item = new Seat();
		item.personId = personId;
		item.ticket = ticket;
		return item;
	}

	private static Map<Id, String> personNames(List<Seat> seats) {
		Set<Id> ids = new Set<Id>();
		for (Seat item : seats) {
			ids.add(item.personId);
		}
		Map<Id, String> names = new Map<Id, String>();
		for (Contact person : [SELECT Id, Name FROM Contact WHERE Id IN :ids WITH USER_MODE]) {
			names.put(person.Id, person.Name);
		}
		for (Id personId : ids) {
			if (!names.containsKey(personId)) {
				throw new RegistrationException(
					BarnHelp.text('Events', 'Events_Register_NoPerson')
				);
			}
		}
		return names;
	}

	/** The seats wanted less anyone already on the event or named twice (R-EAT2). */
	private static List<Seat> withoutRegistered(
		Id eventId,
		List<Seat> wanted,
		Map<Id, String> names,
		Result result
	) {
		Set<Id> taken = new Set<Id>();
		for (Event_Attendee__c attendee : [
			SELECT Contact__c
			FROM Event_Attendee__c
			WHERE
				Event_Registration__r.Event__c = :eventId
				AND Contact__c IN :names.keySet()
				AND Status__c != :STATUS_CANCELLED
			WITH SYSTEM_MODE
		]) {
			taken.add(attendee.Contact__c);
		}
		List<Seat> fresh = new List<Seat>();
		for (Seat item : wanted) {
			if (taken.contains(item.personId)) {
				result.alreadyRegistered.add(names.get(item.personId));
				continue;
			}
			taken.add(item.personId);
			fresh.add(item);
		}
		return fresh;
	}

	/**
	 * Seats left for each ticket, the fewer of the event's and the ticket's, never below zero;
	 * a ticket with no limit on either is left out (R-EAT1). Counts only, never an attendee row:
	 * the public event page shows this (ADR-NEXT public event pages, decision 3).
	 */
	public static Map<Id, Integer> seatsLeft(Event__c event, List<Ticket_Type__c> tickets) {
		SeatCounter counter = new SeatCounter(event, tickets);
		Map<Id, Integer> left = new Map<Id, Integer>();
		for (Ticket_Type__c ticket : tickets) {
			Integer ticketLeft = counter.ticketLeft.get(ticket.Id);
			Integer seats = counter.eventLeft == null
				? ticketLeft
				: (ticketLeft == null
						? counter.eventLeft
						: Math.min(ticketLeft, counter.eventLeft));
			if (seats != null) {
				left.put(ticket.Id, Math.max(seats, 0));
			}
		}
		return left;
	}

	/** Free seats on the event's capacity and each ticket's quantity (R-EAT1). */
	private inherited sharing class SeatCounter {
		private Integer eventLeft;
		private Map<Id, Integer> ticketLeft = new Map<Id, Integer>();

		SeatCounter(Event__c event, List<Ticket_Type__c> tickets) {
			Integer total = 0;
			Map<Id, Integer> byTicket = new Map<Id, Integer>();
			for (AggregateResult row : [
				SELECT Ticket_Type__c ticket, COUNT(Id) seats
				FROM Event_Attendee__c
				WHERE Event_Registration__r.Event__c = :event.Id AND Status__c IN :SEATED
				WITH SYSTEM_MODE
				GROUP BY Ticket_Type__c
			]) {
				Integer seats = (Integer) row.get('seats');
				total += seats;
				byTicket.put((Id) row.get('ticket'), seats);
			}
			eventLeft = event.Capacity__c == null ? null : event.Capacity__c.intValue() - total;
			for (Ticket_Type__c ticket : tickets) {
				if (ticket.Quantity__c != null) {
					Integer sold = byTicket.containsKey(ticket.Id) ? byTicket.get(ticket.Id) : 0;
					ticketLeft.put(ticket.Id, ticket.Quantity__c.intValue() - sold);
				}
			}
		}

		/** Takes a seat when one is free on both, and says whether it did. */
		Boolean take(Id ticketId) {
			Boolean ticketFree =
				ticketId == null ||
				!ticketLeft.containsKey(ticketId) ||
				ticketLeft.get(ticketId) > 0;
			if ((eventLeft != null && eventLeft <= 0) || !ticketFree) {
				return false;
			}
			if (eventLeft != null) {
				eventLeft--;
			}
			if (ticketId != null && ticketLeft.containsKey(ticketId)) {
				ticketLeft.put(ticketId, ticketLeft.get(ticketId) - 1);
			}
			return true;
		}
	}
}
