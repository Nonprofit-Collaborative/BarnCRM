/**
 * The attendee app's actions (EV-22, EV-29; ADR-NEXT
 * `NEXT-events-attendee-app-operations-portal-templates.md`, decisions 6 to 8 and 11; canonical
 * model R-ACN1, R-ACN2, R-AMS1, R-AGI1): connect with another attendee, accept or decline,
 * message a connection and reply, and add a session to or remove it from the person's agenda.
 * Reached only through `EventsPortalExtension`, after Portal Builder has checked the record is on
 * the verified person's page (a scoped catalog or their own related rows).
 *
 * `without sharing` and system mode (Without Sharing Register, Portal): the portal's integration
 * user has no object access. Every read is re-filtered by the verified person, and every write
 * names only that person and the other side of their own connection. Expected refusals are
 * answers in the person's words, not errors.
 */
public without sharing class EventAttendeeApp {
	public static final String CONNECT = 'Events.Connect';
	public static final String ACCEPT = 'Events.AcceptConnection';
	public static final String DECLINE = 'Events.DeclineConnection';
	public static final String SEND_MESSAGE = 'Events.SendMessage';
	public static final String SEND_REPLY = 'Events.SendReply';
	public static final String ADD_TO_AGENDA = 'Events.AddToAgenda';
	public static final String REMOVE_FROM_AGENDA = 'Events.RemoveFromAgenda';
	/** R-AMS1: messages one person may send in a day. */
	@TestVisible
	private static final Integer DAILY_MESSAGES = 50;
	private static final String REQUESTED = 'Requested';
	private static final String WANTS = 'Wants to Connect';
	private static final String CONNECTED = 'Connected';
	private static final String DECLINED = 'Declined';
	private static final String CANCELLED = 'Cancelled';

	/** The action names this class answers. */
	public static Set<String> actionNames() {
		return new Set<String>{
			CONNECT,
			ACCEPT,
			DECLINE,
			SEND_MESSAGE,
			SEND_REPLY,
			ADD_TO_AGENDA,
			REMOVE_FROM_AGENDA
		};
	}

	/** Runs one action for the verified person on one record; returns what to tell them. */
	public static String run(String actionName, Id personId, Id recordId) {
		switch on actionName {
			when 'Events.Connect' {
				return connect(personId, recordId);
			}
			when 'Events.AcceptConnection' {
				return answer(personId, recordId, true);
			}
			when 'Events.DeclineConnection' {
				return answer(personId, recordId, false);
			}
			when 'Events.SendMessage' {
				return sendMessage(personId, recordId);
			}
			when 'Events.SendReply' {
				return sendReply(personId, recordId);
			}
			when 'Events.AddToAgenda' {
				return addToAgenda(personId, recordId);
			}
			when 'Events.RemoveFromAgenda' {
				return removeFromAgenda(personId, recordId);
			}
			when else {
				throw new System.IllegalArgumentException('Unknown action ' + actionName);
			}
		}
	}

	// ---- Connections (R-ACN1, R-ACN2) ------------------------------------------------------

	private static String connect(Id personId, Id attendeeId) {
		List<Event_Attendee__c> found = [
			SELECT Id, Contact__c, Event_Registration__r.Event__c, Networking_Opt_In__c, Status__c
			FROM Event_Attendee__c
			WHERE Id = :attendeeId
			WITH SYSTEM_MODE
		];
		if (found.isEmpty() || !found[0].Networking_Opt_In__c || found[0].Status__c == CANCELLED) {
			return BarnHelp.text('Events', 'Events_App_NotListed');
		}
		Event_Attendee__c other = found[0];
		if (other.Contact__c == personId) {
			return BarnHelp.text('Events', 'Events_App_NotYou');
		}
		Id eventId = other.Event_Registration__r.Event__c;
		Event_Attendee__c mine = attendeeAt(personId, eventId);
		if (mine == null) {
			return BarnHelp.text('Events', 'Events_App_NotAttending');
		}
		Integer existing = [
			SELECT COUNT()
			FROM Attendee_Connection__c
			WHERE
				Pair_Key__c IN :new List<String>{
					pairKey(eventId, personId, other.Contact__c),
					pairKey(eventId, other.Contact__c, personId)
				}
			WITH SYSTEM_MODE
		];
		if (existing > 0) {
			// A declined pair reads the same, so a request never learns it was declined.
			return BarnHelp.text('Events', 'Events_App_AlreadyAsked');
		}
		insert as system new List<Attendee_Connection__c>{
			side(eventId, personId, other.Contact__c, other.Id, REQUESTED),
			side(eventId, other.Contact__c, personId, mine.Id, WANTS)
		};
		return BarnHelp.text('Events', 'Events_App_RequestSent');
	}

	private static Attendee_Connection__c side(
		Id eventId,
		Id personId,
		Id otherId,
		Id otherAttendeeId,
		String status
	) {
		return new Attendee_Connection__c(
			Event__c = eventId,
			Contact__c = personId,
			Other_Contact__c = otherId,
			Other_Attendee__c = otherAttendeeId,
			Status__c = status,
			Pair_Key__c = pairKey(eventId, personId, otherId)
		);
	}

	/** Accept marks both rows Connected and copies each How to Reach Me across; decline hides both. */
	private static String answer(Id personId, Id connectionId, Boolean accept) {
		Attendee_Connection__c mine = ownConnection(personId, connectionId);
		if (mine == null || mine.Status__c == DECLINED || (accept && mine.Status__c != WANTS)) {
			return BarnHelp.text('Events', 'Events_App_NothingToAccept');
		}
		List<Attendee_Connection__c> theirs = [
			SELECT Id
			FROM Attendee_Connection__c
			WHERE Pair_Key__c = :pairKey(mine.Event__c, mine.Other_Contact__c, personId)
			WITH SYSTEM_MODE
		];
		List<Attendee_Connection__c> changes = new List<Attendee_Connection__c>();
		Attendee_Connection__c mineChange = new Attendee_Connection__c(Id = mine.Id);
		Attendee_Connection__c theirChange = theirs.isEmpty()
			? null
			: new Attendee_Connection__c(Id = theirs[0].Id);
		if (accept) {
			mineChange.Status__c = CONNECTED;
			mineChange.Contact_Details__c = reachOf(mine.Other_Contact__c, mine.Event__c);
			if (theirChange != null) {
				theirChange.Status__c = CONNECTED;
				theirChange.Contact_Details__c = reachOf(personId, mine.Event__c);
			}
		} else {
			mineChange.Status__c = DECLINED;
			mineChange.Contact_Details__c = null;
			if (theirChange != null) {
				theirChange.Status__c = DECLINED;
				theirChange.Contact_Details__c = null;
			}
		}
		changes.add(mineChange);
		if (theirChange != null) {
			changes.add(theirChange);
		}
		update as system changes;
		return accept
			? BarnHelp.text('Events', 'Events_App_Connected')
			: BarnHelp.text('Events', 'Events_App_Declined');
	}

	private static String reachOf(Id personId, Id eventId) {
		Event_Attendee__c row = attendeeAt(personId, eventId);
		return row == null ? null : row.Networking_Contact__c;
	}

	// ---- Messages (R-AMS1) -----------------------------------------------------------------

	private static String sendMessage(Id personId, Id connectionId) {
		if (!EventsSettings.attendeeMessages()) {
			return BarnHelp.text('Events', 'Events_App_MessagesOff');
		}
		Attendee_Connection__c mine = ownConnection(personId, connectionId);
		if (mine == null || mine.Status__c != CONNECTED) {
			return BarnHelp.text('Events', 'Events_App_NotConnected');
		}
		if (String.isBlank(mine.Draft_Message__c)) {
			return BarnHelp.text('Events', 'Events_App_NothingToSend');
		}
		if (sentToday(personId) >= DAILY_MESSAGES) {
			return BarnHelp.text('Events', 'Events_App_TooMany');
		}
		insert as system message(
			mine.Event__c,
			personId,
			mine.Other_Contact__c,
			mine.Draft_Message__c
		);
		update as system new Attendee_Connection__c(Id = mine.Id, Draft_Message__c = null);
		return BarnHelp.text('Events', 'Events_App_MessageSent');
	}

	private static String sendReply(Id personId, Id messageId) {
		if (!EventsSettings.attendeeMessages()) {
			return BarnHelp.text('Events', 'Events_App_MessagesOff');
		}
		List<Attendee_Message__c> found = [
			SELECT Id, Event__c, From_Contact__c, Reply__c
			FROM Attendee_Message__c
			WHERE Id = :messageId AND To_Contact__c = :personId
			WITH SYSTEM_MODE
		];
		if (found.isEmpty() || String.isBlank(found[0].Reply__c)) {
			return BarnHelp.text('Events', 'Events_App_NothingToSend');
		}
		Attendee_Message__c received = found[0];
		Integer connected = [
			SELECT COUNT()
			FROM Attendee_Connection__c
			WHERE
				Pair_Key__c = :pairKey(received.Event__c, personId, received.From_Contact__c)
				AND Status__c = :CONNECTED
			WITH SYSTEM_MODE
		];
		if (connected == 0) {
			return BarnHelp.text('Events', 'Events_App_NotConnected');
		}
		if (sentToday(personId) >= DAILY_MESSAGES) {
			return BarnHelp.text('Events', 'Events_App_TooMany');
		}
		insert as system message(
			received.Event__c,
			personId,
			received.From_Contact__c,
			received.Reply__c
		);
		update as system new Attendee_Message__c(Id = received.Id, Reply__c = null);
		return BarnHelp.text('Events', 'Events_App_MessageSent');
	}

	private static Attendee_Message__c message(Id eventId, Id fromId, Id toId, String body) {
		return new Attendee_Message__c(
			Event__c = eventId,
			From_Contact__c = fromId,
			To_Contact__c = toId,
			Body__c = body,
			Sent_At__c = Datetime.now()
		);
	}

	private static Integer sentToday(Id personId) {
		return [
			SELECT COUNT()
			FROM Attendee_Message__c
			WHERE From_Contact__c = :personId AND Sent_At__c = TODAY
			WITH SYSTEM_MODE
		];
	}

	// ---- Agenda (R-AGI1) -------------------------------------------------------------------

	private static String addToAgenda(Id personId, Id sessionId) {
		List<Event_Session__c> found = [
			SELECT Id, Name, Event__c, Start__c, End__c, Capacity__c, Agenda_Picks__c, Status__c
			FROM Event_Session__c
			WHERE Id = :sessionId
			WITH SYSTEM_MODE
		];
		if (found.isEmpty() || found[0].Status__c == CANCELLED) {
			return BarnHelp.text('Events', 'Events_App_NotAttending');
		}
		Event_Session__c session = found[0];
		if (attendeeAt(personId, session.Event__c) == null) {
			return BarnHelp.text('Events', 'Events_App_NotAttending');
		}
		String key = pickKey(sessionId, personId);
		if ([SELECT COUNT() FROM Agenda_Item__c WHERE Pick_Key__c = :key WITH SYSTEM_MODE] > 0) {
			return BarnHelp.text('Events', 'Events_App_AlreadyPicked');
		}
		if (
			session.Capacity__c != null &&
			session.Agenda_Picks__c != null &&
			session.Agenda_Picks__c >= session.Capacity__c
		) {
			return BarnHelp.text('Events', 'Events_App_SessionFull');
		}
		String clash = overlapping(personId, session);
		if (clash != null && !EventsSettings.allowAgendaOverlaps()) {
			return BarnHelp.text('Events', 'Events_App_Overlaps', new List<Object>{ clash });
		}
		insert as system new Agenda_Item__c(
			Event_Session__c = sessionId,
			Contact__c = personId,
			Overlaps__c = clash != null,
			Pick_Key__c = key
		);
		return clash == null
			? BarnHelp.text('Events', 'Events_App_Added')
			: BarnHelp.text('Events', 'Events_App_AddedOverlap', new List<Object>{ clash });
	}

	/** The name of a session already on the person's agenda that overlaps this one, or null. */
	private static String overlapping(Id personId, Event_Session__c session) {
		if (session.Start__c == null || session.End__c == null) {
			return null;
		}
		for (Agenda_Item__c item : [
			SELECT Event_Session__r.Name
			FROM Agenda_Item__c
			WHERE
				Contact__c = :personId
				AND Event_Session__r.Event__c = :session.Event__c
				AND Event_Session__r.Start__c < :session.End__c
				AND Event_Session__r.End__c > :session.Start__c
			WITH SYSTEM_MODE
			LIMIT 1
		]) {
			return item.Event_Session__r.Name;
		}
		return null;
	}

	private static String removeFromAgenda(Id personId, Id itemId) {
		List<Agenda_Item__c> found = [
			SELECT Id
			FROM Agenda_Item__c
			WHERE Id = :itemId AND Contact__c = :personId
			WITH SYSTEM_MODE
		];
		if (!found.isEmpty()) {
			delete as system found;
		}
		return BarnHelp.text('Events', 'Events_App_Removed');
	}

	// ---- Shared ----------------------------------------------------------------------------

	/** The person's own attendee row at an event, not Cancelled, or null. */
	private static Event_Attendee__c attendeeAt(Id personId, Id eventId) {
		for (Event_Attendee__c row : [
			SELECT Id, Networking_Contact__c
			FROM Event_Attendee__c
			WHERE
				Contact__c = :personId
				AND Event_Registration__r.Event__c = :eventId
				AND Status__c != :CANCELLED
			WITH SYSTEM_MODE
			ORDER BY CreatedDate
			LIMIT 1
		]) {
			return row;
		}
		return null;
	}

	private static Attendee_Connection__c ownConnection(Id personId, Id connectionId) {
		for (Attendee_Connection__c row : [
			SELECT Id, Event__c, Other_Contact__c, Status__c, Draft_Message__c
			FROM Attendee_Connection__c
			WHERE Id = :connectionId AND Contact__c = :personId
			WITH SYSTEM_MODE
		]) {
			return row;
		}
		return null;
	}

	/** R-ACN1: one row per event, person and other person. */
	@TestVisible
	private static String pairKey(Id eventId, Id personId, Id otherId) {
		return String.valueOf(eventId).left(15) +
			String.valueOf(personId).left(15) +
			String.valueOf(otherId).left(15);
	}

	/** R-AGI1: a person picks a session once. */
	@TestVisible
	private static String pickKey(Id sessionId, Id personId) {
		return String.valueOf(sessionId) + String.valueOf(personId).left(15);
	}
}
