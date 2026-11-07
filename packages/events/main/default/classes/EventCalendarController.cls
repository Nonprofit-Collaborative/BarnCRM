/**
 * The Event Calendar tab (EV-19, ADR-NEXT `NEXT-event-calendar.md`): the organization's events,
 * and optionally their sessions, that fall in the days a month, week or list view shows.
 *
 * Thin by design (plan Section 9.9): it returns plain rows for the days asked for, and the
 * grid, the filters, the day each entry falls on in the person's time zone and the downloadable
 * calendar file are worked out in the browser module `eventCalendarModel`. Everything runs as the
 * person: reads in user mode.
 */
public with sharing class EventCalendarController {
	private static final String CONTEXT = 'EventCalendarController';
	/** The most events and the most sessions one view reads. */
	@TestVisible
	private static Integer maxEvents = 500;
	@TestVisible
	private static Integer maxSessions = 1000;
	/** A day either side of the asked range, so any time zone's day is inside what is read. */
	private static final Integer PADDING_DAYS = 1;
	private static final Integer DESCRIPTION_LENGTH = 1000;

	/** Everything the calendar draws for the days asked for. */
	public class Calendar {
		@AuraEnabled
		public List<EventRow> events = new List<EventRow>();
		@AuraEnabled
		public List<SessionRow> sessions = new List<SessionRow>();
		/** True when more events or sessions matched than one view reads. */
		@AuraEnabled
		public Boolean truncated = false;
		/** Today in the person's time zone, as an ISO date. */
		@AuraEnabled
		public String today;
	}

	/** One event. */
	public class EventRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String format;
		@AuraEnabled
		public Datetime startsAt;
		@AuraEnabled
		public Datetime endsAt;
		@AuraEnabled
		public String venueName;
		@AuraEnabled
		public String venueAddress;
		@AuraEnabled
		public String onlineLink;
		@AuraEnabled
		public String description;
	}

	/** One session, with its event's status and format so the same filters apply. */
	public class SessionRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String sessionType;
		@AuraEnabled
		public String room;
		@AuraEnabled
		public Datetime startsAt;
		@AuraEnabled
		public Datetime endsAt;
		@AuraEnabled
		public String eventId;
		@AuraEnabled
		public String eventName;
		@AuraEnabled
		public String eventStatus;
		@AuraEnabled
		public String eventFormat;
	}

	/**
	 * The events, and when asked the sessions, that overlap the days from `fromDate` to `toDate`.
	 *
	 * @param fromDate the first day shown
	 * @param toDate the last day shown, on or after the first
	 * @param includeSessions whether to read sessions too
	 * @return the rows, soonest first
	 */
	@AuraEnabled
	public static Calendar getCalendar(Date fromDate, Date toDate, Boolean includeSessions) {
		try {
			if (fromDate == null || toDate == null || toDate < fromDate) {
				throw new System.IllegalArgumentException(
					BarnHelp.text('Events', 'Events_Calendar_BadRange')
				);
			}
			Calendar result = new Calendar();
			// Datetime.format uses the person's time zone, so this is their today.
			result.today = Datetime.now().format('yyyy-MM-dd');
			Datetime windowStart = Datetime.newInstance(
				fromDate.addDays(-PADDING_DAYS),
				Time.newInstance(0, 0, 0, 0)
			);
			Datetime windowEnd = Datetime.newInstance(
				toDate.addDays(PADDING_DAYS + 1),
				Time.newInstance(0, 0, 0, 0)
			);
			Integer eventLimit = maxEvents + 1;
			for (Event__c event : [
				SELECT
					Id,
					Name,
					Status__c,
					Format__c,
					Start__c,
					End__c,
					Venue_Name__c,
					Venue_Address__c,
					Online_Link__c,
					Description__c
				FROM Event__c
				WHERE Start__c < :windowEnd AND End__c >= :windowStart
				WITH USER_MODE
				ORDER BY Start__c, Name
				LIMIT :eventLimit
			]) {
				if (result.events.size() == maxEvents) {
					result.truncated = true;
				} else {
					result.events.add(eventRow(event));
				}
			}
			if (includeSessions == true) {
				readSessions(result, windowStart, windowEnd);
			}
			return result;
		} catch (System.IllegalArgumentException e) {
			throw UserErrors.message(e.getMessage());
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getCalendar');
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Calendar_LoadFailed'));
		}
	}

	private static void readSessions(Calendar result, Datetime windowStart, Datetime windowEnd) {
		Integer sessionLimit = maxSessions + 1;
		for (Event_Session__c session : [
			SELECT
				Id,
				Name,
				Status__c,
				Session_Type__c,
				Room__c,
				Start__c,
				End__c,
				Event__c,
				Event__r.Name,
				Event__r.Status__c,
				Event__r.Format__c
			FROM Event_Session__c
			WHERE
				Start__c < :windowEnd
				AND (End__c >= :windowStart
				OR (End__c = NULL
				AND Start__c >= :windowStart))
			WITH USER_MODE
			ORDER BY Start__c, Name
			LIMIT :sessionLimit
		]) {
			if (result.sessions.size() == maxSessions) {
				result.truncated = true;
				continue;
			}
			SessionRow row = new SessionRow();
			row.id = session.Id;
			row.name = session.Name;
			row.status = session.Status__c;
			row.sessionType = session.Session_Type__c;
			row.room = session.Room__c;
			row.startsAt = session.Start__c;
			row.endsAt = session.End__c;
			row.eventId = session.Event__c;
			row.eventName = session.Event__r.Name;
			row.eventStatus = session.Event__r.Status__c;
			row.eventFormat = session.Event__r.Format__c;
			result.sessions.add(row);
		}
	}

	private static EventRow eventRow(Event__c event) {
		EventRow row = new EventRow();
		row.id = event.Id;
		row.name = event.Name;
		row.status = event.Status__c;
		row.format = event.Format__c;
		row.startsAt = event.Start__c;
		row.endsAt = event.End__c;
		row.venueName = event.Venue_Name__c;
		row.venueAddress = event.Venue_Address__c;
		row.onlineLink = event.Online_Link__c;
		row.description = event.Description__c == null
			? null
			: event.Description__c.left(DESCRIPTION_LENGTH);
		return row;
	}
}
