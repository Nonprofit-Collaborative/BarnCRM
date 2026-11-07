/**
 * The Events page (EV-01, canonical model 29EV1, ADR-NEXT `NEXT-events-module.md` decision 6):
 * the organization's upcoming or past events, and Repeat Event (R-EV4).
 *
 * Thin by design (plan Section 9.9): it returns plain shapes, and the dates of a series, the date
 * ranges and the status words are worked out in the browser module `eventsModel`. Everything
 * runs as the person: reads in user mode, writes `AccessLevel.USER_MODE`.
 */
public with sharing class EventsHomeController {
	private static final String CONTEXT = 'EventsHomeController';
	/** The most events one view lists. */
	@TestVisible
	private static Integer maxEvents = 200;
	/** The most occurrences one Repeat Event makes (R-EV4). */
	public static final Integer MAX_OCCURRENCES = 52;
	/** The view of events that have ended or were cancelled; anything else is the upcoming view. */
	public static final String VIEW_PAST = 'past';
	private static final String STATUS_DRAFT = 'Draft';
	private static final String STATUS_CANCELLED = 'Cancelled';

	/** Everything the page draws. */
	public class Home {
		@AuraEnabled
		public List<EventRow> events = new List<EventRow>();
		@AuraEnabled
		public Boolean truncated = false;
		@AuraEnabled
		public Boolean canCreate = false;
		/** The field labels the list's columns use, by API name, so the page needs no labels. */
		@AuraEnabled
		public Map<String, String> fieldLabels = new Map<String, String>();
		/** The object's plural label, the page's title. */
		@AuraEnabled
		public String title;
	}

	/** One event in the list. */
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
		public String onlineLink;
		@AuraEnabled
		public Decimal capacity;
		@AuraEnabled
		public String seriesId;
	}

	/**
	 * The upcoming events (not yet ended and not cancelled), soonest first, or the past ones
	 * (ended or cancelled), latest first.
	 *
	 * @param view `past`, or anything else for the upcoming events
	 * @return the page's events and what the person may do
	 */
	@AuraEnabled
	public static Home getEvents(String view) {
		try {
			Home home = new Home();
			home.canCreate = Schema.SObjectType.Event__c.isCreateable();
			home.title = Schema.SObjectType.Event__c.getLabelPlural();
			Map<String, Schema.SObjectField> fields = Schema.SObjectType.Event__c.fields.getMap();
			for (
				String name : new List<String>{ 'Name', 'Status__c', 'Format__c', 'Capacity__c' }
			) {
				home.fieldLabels.put(name, fields.get(name).getDescribe().getLabel());
			}
			Boolean past = view == VIEW_PAST;
			Map<String, Object> binds = new Map<String, Object>{
				'now' => Datetime.now(),
				'cancelled' => STATUS_CANCELLED,
				'maxRows' => maxEvents + 1
			};
			String filter = past
				? ' WHERE End__c < :now OR Status__c = :cancelled ORDER BY Start__c DESC'
				: ' WHERE End__c >= :now AND Status__c != :cancelled ORDER BY Start__c ASC';
			// Access mode: AccessLevel.USER_MODE below.
			List<Event__c> rows = (List<Event__c>) Database.queryWithBinds(
				'SELECT Id, Name, Status__c, Format__c, Start__c, End__c, Venue_Name__c,' +
					' Online_Link__c, Capacity__c, Series__c FROM Event__c' +
					filter +
					' LIMIT :maxRows',
				binds,
				AccessLevel.USER_MODE
			);
			home.truncated = rows.size() > maxEvents;
			for (Integer i = 0; i < rows.size() && i < maxEvents; i++) {
				home.events.add(toRow(rows[i]));
			}
			return home;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getEvents');
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Home_LoadFailed'));
		}
	}

	/**
	 * Repeat Event (R-EV4): one Draft copy of the event for each start given, each as long as the
	 * event, with its registration window moved by the same amount, in the event's series. The
	 * starts come from the browser module `eventsModel`, which works out the pattern.
	 *
	 * @param eventId the event to repeat
	 * @param starts when each new occurrence starts; each after the event's own start
	 * @return how many occurrences were made
	 */
	@AuraEnabled
	public static Integer repeatEvent(Id eventId, List<Datetime> starts) {
		if (!Schema.SObjectType.Event__c.isCreateable()) {
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Repeat_NoPermission'));
		}
		if (
			eventId == null ||
			starts == null ||
			starts.isEmpty() ||
			starts.size() > MAX_OCCURRENCES
		) {
			throw UserErrors.message(
				BarnHelp.text(
					'Events',
					'Events_Repeat_BadCount',
					new List<Object>{ MAX_OCCURRENCES }
				)
			);
		}
		Savepoint savepoint = Database.setSavepoint();
		try {
			Event__c source = [
				SELECT
					Id,
					Name,
					Format__c,
					Start__c,
					End__c,
					Venue_Name__c,
					Venue_Address__c,
					Online_Link__c,
					Capacity__c,
					Registration_Opens__c,
					Registration_Closes__c,
					Description__c,
					Series__c
				FROM Event__c
				WHERE Id = :eventId
				WITH USER_MODE
			];
			List<Event__c> copies = new List<Event__c>();
			for (Datetime start : starts) {
				if (start == null || start <= source.Start__c) {
					throw UserErrors.message(BarnHelp.text('Events', 'Events_Repeat_BadDates'));
				}
				copies.add(copyAt(source, start));
			}
			Database.insert(copies, true, AccessLevel.USER_MODE);
			return copies.size();
		} catch (AuraHandledException e) {
			Database.rollback(savepoint);
			throw e;
		} catch (DmlException e) {
			Database.rollback(savepoint);
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			Database.rollback(savepoint);
			ErrorLogger.log(e, CONTEXT + '.repeatEvent', eventId);
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/** A Draft copy of the event starting at `start`, every time moved by the same amount. */
	@TestVisible
	private static Event__c copyAt(Event__c source, Datetime start) {
		Long shift = start.getTime() - source.Start__c.getTime();
		return new Event__c(
			Name = source.Name,
			Status__c = STATUS_DRAFT,
			Format__c = source.Format__c,
			Start__c = start,
			End__c = moved(source.End__c, shift),
			Venue_Name__c = source.Venue_Name__c,
			Venue_Address__c = source.Venue_Address__c,
			Online_Link__c = source.Online_Link__c,
			Capacity__c = source.Capacity__c,
			Registration_Opens__c = moved(source.Registration_Opens__c, shift),
			Registration_Closes__c = moved(source.Registration_Closes__c, shift),
			Description__c = source.Description__c,
			Series__c = source.Series__c != null ? source.Series__c : source.Id
		);
	}

	private static Datetime moved(Datetime value, Long shift) {
		return value == null ? null : Datetime.newInstance(value.getTime() + shift);
	}

	private static EventRow toRow(Event__c record) {
		EventRow row = new EventRow();
		row.id = record.Id;
		row.name = record.Name;
		row.status = record.Status__c;
		row.format = record.Format__c;
		row.startsAt = record.Start__c;
		row.endsAt = record.End__c;
		row.venueName = record.Venue_Name__c;
		row.onlineLink = record.Online_Link__c;
		row.capacity = record.Capacity__c;
		row.seriesId = record.Series__c;
		return row;
	}
}
