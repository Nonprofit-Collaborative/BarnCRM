/**
 * The Agenda tab of the event page (EV-04, canonical model 29EV4 and 29EV5): the event's tracks
 * and sessions, and moving a session to another track (R-ESN5). Thin by design (plan Section
 * 9.9): days, columns and clash flags are worked out in the browser module `eventAgendaModel`.
 * Reads in user mode; the move writes `AccessLevel.USER_MODE`. Tracks and sessions are added and
 * edited through the platform's record forms.
 */
public with sharing class EventAgendaController {
	private static final String CONTEXT = 'EventAgendaController';
	/** The most sessions one agenda shows; a conference this size is well past it. */
	@TestVisible
	private static Integer maxSessions = 500;

	/** Everything the tab draws. */
	public class Agenda {
		@AuraEnabled
		public List<TrackRow> tracks = new List<TrackRow>();
		@AuraEnabled
		public List<SessionRow> sessions = new List<SessionRow>();
		@AuraEnabled
		public Boolean truncated = false;
		@AuraEnabled
		public Boolean canMove = false;
		@AuraEnabled
		public Boolean canAddTrack = false;
		@AuraEnabled
		public Boolean canAddSession = false;
		/** The track object's plural label, the heading of the tracks list. */
		@AuraEnabled
		public String tracksTitle;
	}

	/** One track. */
	public class TrackRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
	}

	/** One session. */
	public class SessionRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String trackId;
		@AuraEnabled
		public Datetime startsAt;
		@AuraEnabled
		public Datetime endsAt;
		@AuraEnabled
		public String room;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String sessionType;
		/** The event speakers in the session, for the speaker clash check. */
		@AuraEnabled
		public List<String> speakerIds = new List<String>();
	}

	/**
	 * The event's tracks (by sort order, then name) and sessions.
	 *
	 * @param eventId the event
	 * @return the tab's tracks, sessions and what the person may do
	 */
	@AuraEnabled
	public static Agenda getAgenda(Id eventId) {
		try {
			Agenda agenda = new Agenda();
			agenda.canMove =
				Schema.SObjectType.Event_Session__c.isUpdateable() &&
				Schema.SObjectType.Event_Session__c.fields.Track__c.isUpdateable();
			agenda.canAddTrack = Schema.SObjectType.Event_Track__c.isCreateable();
			agenda.canAddSession = Schema.SObjectType.Event_Session__c.isCreateable();
			agenda.tracksTitle = Schema.SObjectType.Event_Track__c.getLabelPlural();
			for (Event_Track__c track : [
				SELECT Id, Name
				FROM Event_Track__c
				WHERE Event__c = :eventId
				WITH USER_MODE
				ORDER BY Sort_Order__c ASC NULLS LAST, Name
				LIMIT 50
			]) {
				TrackRow row = new TrackRow();
				row.id = track.Id;
				row.name = track.Name;
				agenda.tracks.add(row);
			}
			Integer maxRows = maxSessions + 1;
			List<Event_Session__c> sessions = [
				SELECT Id, Name, Track__c, Start__c, End__c, Room__c, Status__c, Session_Type__c
				FROM Event_Session__c
				WHERE Event__c = :eventId
				WITH USER_MODE
				ORDER BY Start__c ASC NULLS LAST, Name
				LIMIT :maxRows
			];
			agenda.truncated = sessions.size() > maxSessions;
			for (Integer i = 0; i < sessions.size() && i < maxSessions; i++) {
				agenda.sessions.add(toRow(sessions[i]));
			}
			return agenda;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getAgenda', eventId);
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Agenda_LoadFailed'));
		}
	}

	/**
	 * Moves a session to another track of its event, or to no track (R-ESN5): only its Track
	 * changes. The lookup filter keeps the track in the session's own event.
	 *
	 * @param sessionId the session
	 * @param trackId the track, or null for no track
	 */
	@AuraEnabled
	public static void moveSession(Id sessionId, Id trackId) {
		try {
			Database.update(
				new Event_Session__c(Id = sessionId, Track__c = trackId),
				true,
				AccessLevel.USER_MODE
			);
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.moveSession', sessionId);
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	private static SessionRow toRow(Event_Session__c record) {
		SessionRow row = new SessionRow();
		row.id = record.Id;
		row.name = record.Name;
		row.trackId = record.Track__c;
		row.startsAt = record.Start__c;
		row.endsAt = record.End__c;
		row.room = record.Room__c;
		row.status = record.Status__c;
		row.sessionType = record.Session_Type__c;
		return row;
	}
}
