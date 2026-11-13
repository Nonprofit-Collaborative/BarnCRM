/**
 * The Speakers tab of the event page (EV-05, canonical model 29EV6 and 29EV7): the event's
 * speakers, each a Core person, with the sessions they are in. Thin by design (plan Section 9.9).
 * Reads in user mode; writes `AccessLevel.USER_MODE`. Speaker details are edited through the
 * platform's record form.
 */
public with sharing class EventSpeakersController {
	private static final String CONTEXT = 'EventSpeakersController';

	/** Everything the tab draws. */
	public class Speakers {
		@AuraEnabled
		public List<SpeakerRow> speakers = new List<SpeakerRow>();
		/** The event's sessions a speaker can be put in. */
		@AuraEnabled
		public List<Option> sessions = new List<Option>();
		/** The roles a speaker can have in a session. */
		@AuraEnabled
		public List<Option> roles = new List<Option>();
		@AuraEnabled
		public Boolean canAdd = false;
		@AuraEnabled
		public Boolean canAssign = false;
		/** Field labels by API name, so the tab needs no labels of its own for columns. */
		@AuraEnabled
		public Map<String, String> fieldLabels = new Map<String, String>();
	}

	/** One speaker and the sessions they are in. */
	public class SpeakerRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String contactId;
		@AuraEnabled
		public String headline;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public List<Assignment> assignments = new List<Assignment>();
		/**
		 * EV-27 (R-SRT3): the average of every rating of the sessions the speaker is in, to one
		 * decimal, and how many there are; null and 0 when none.
		 */
		@AuraEnabled
		public Decimal averageRating;
		@AuraEnabled
		public Decimal ratingCount = 0;
		private Decimal ratingTotal = 0;
		/** EV-25: how many of agreement signed, slides received and dry run done are ticked. */
		@AuraEnabled
		public Integer checklistDone = 0;
	}

	/** A speaker's place in a session. */
	public class Assignment {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String sessionId;
		@AuraEnabled
		public String sessionName;
		@AuraEnabled
		public String role;
	}

	/** A choice in a list. */
	public class Option {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String value;

		Option(String label, String value) {
			this.label = label;
			this.value = value;
		}
	}

	/**
	 * The event's speakers by name, with their sessions, and the sessions they can be put in.
	 *
	 * @param eventId the event
	 * @return the tab's speakers and what the person may do
	 */
	@AuraEnabled
	public static Speakers getSpeakers(Id eventId) {
		try {
			Speakers result = new Speakers();
			result.canAdd = Schema.SObjectType.Event_Speaker__c.isCreateable();
			result.canAssign = Schema.SObjectType.Session_Speaker__c.isCreateable();
			Map<String, Schema.SObjectField> fields = Schema.SObjectType.Event_Speaker__c.fields.getMap();
			for (String name : new List<String>{ 'Name', 'Headline__c', 'Status__c' }) {
				result.fieldLabels.put(
					name,
					NamespaceUtil.field(fields, name).getDescribe().getLabel()
				);
			}
			result.fieldLabels.put(
				'Sessions',
				Schema.SObjectType.Event_Session__c.getLabelPlural()
			);
			Map<String, Schema.SObjectField> links = Schema.SObjectType.Session_Speaker__c.fields.getMap();
			for (String name : new List<String>{ 'Event_Session__c', 'Role__c' }) {
				result.fieldLabels.put(name, links.get(name).getDescribe().getLabel());
			}
			for (
				Schema.PicklistEntry entry : Schema.SObjectType.Session_Speaker__c.fields.Role__c.getPicklistValues()
			) {
				if (entry.isActive()) {
					result.roles.add(new Option(entry.getLabel(), entry.getValue()));
				}
			}
			for (Event_Session__c session : [
				SELECT Id, Name
				FROM Event_Session__c
				WHERE Event__c = :eventId
				WITH USER_MODE
				ORDER BY Start__c ASC NULLS LAST, Name
				LIMIT 500
			]) {
				result.sessions.add(new Option(session.Name, session.Id));
			}
			Map<Id, SpeakerRow> byId = new Map<Id, SpeakerRow>();
			for (Event_Speaker__c speaker : [
				SELECT
					Id,
					Name,
					Contact__c,
					Headline__c,
					Status__c,
					Agreement_Signed__c,
					Slides_Received__c,
					Dry_Run_Done__c
				FROM Event_Speaker__c
				WHERE Event__c = :eventId
				WITH USER_MODE
				ORDER BY Name
				LIMIT 500
			]) {
				SpeakerRow row = new SpeakerRow();
				row.id = speaker.Id;
				row.name = speaker.Name;
				row.contactId = speaker.Contact__c;
				row.headline = speaker.Headline__c;
				row.status = speaker.Status__c;
				row.checklistDone =
					(speaker.Agreement_Signed__c ? 1 : 0) +
					(speaker.Slides_Received__c ? 1 : 0) +
					(speaker.Dry_Run_Done__c ? 1 : 0);
				byId.put(speaker.Id, row);
				result.speakers.add(row);
			}
			Set<Id> speakerIds = byId.keySet();
			for (Session_Speaker__c link : [
				SELECT
					Id,
					Event_Speaker__c,
					Event_Session__c,
					Event_Session__r.Name,
					Event_Session__r.Rating_Count__c,
					Event_Session__r.Rating_Total__c,
					Role__c
				FROM Session_Speaker__c
				WHERE Event_Speaker__c IN :speakerIds
				WITH USER_MODE
				ORDER BY Event_Session__r.Start__c ASC NULLS LAST
				LIMIT 2000
			]) {
				Assignment assignment = new Assignment();
				assignment.id = link.Id;
				assignment.sessionId = link.Event_Session__c;
				assignment.sessionName = link.Event_Session__r.Name;
				assignment.role = link.Role__c;
				SpeakerRow row = byId.get(link.Event_Speaker__c);
				row.assignments.add(assignment);
				Decimal count = link.Event_Session__r.Rating_Count__c;
				if (count != null && count > 0) {
					row.ratingCount += count;
					row.ratingTotal += link.Event_Session__r.Rating_Total__c;
				}
			}
			for (SpeakerRow row : result.speakers) {
				if (row.ratingCount > 0) {
					row.averageRating = (row.ratingTotal / row.ratingCount)
						.setScale(1, System.RoundingMode.HALF_UP);
				}
			}
			return result;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getSpeakers', eventId);
			throw UserErrors.wrapShowingDml(
				e,
				BarnHelp.text('Events', 'Events_Speakers_LoadFailed')
			);
		}
	}

	/**
	 * Adds a person as a speaker at the event, named after them (R-ESP1, R-ESP2).
	 *
	 * @param eventId the event
	 * @param contactId the Core person
	 * @return the new speaker's identifier
	 */
	@AuraEnabled
	public static Id addSpeaker(Id eventId, Id contactId) {
		Event_Speaker__c speaker = new Event_Speaker__c(Event__c = eventId, Contact__c = contactId);
		save(speaker, 'addSpeaker');
		return speaker.Id;
	}

	/**
	 * Puts a speaker in a session of their event with a role (R-SSP1).
	 *
	 * @param sessionId the session
	 * @param speakerId the speaker
	 * @param role Speaker, Moderator or Panelist
	 */
	@AuraEnabled
	public static void assign(Id sessionId, Id speakerId, String role) {
		save(
			new Session_Speaker__c(
				Event_Session__c = sessionId,
				Event_Speaker__c = speakerId,
				Role__c = role
			),
			'assign'
		);
	}

	/**
	 * Removes a speaker and, first, their session assignments (R-ESP3).
	 *
	 * @param speakerId the speaker
	 */
	@AuraEnabled
	public static void removeSpeaker(Id speakerId) {
		Savepoint savepoint = Database.setSavepoint();
		try {
			List<Session_Speaker__c> links = [
				SELECT Id
				FROM Session_Speaker__c
				WHERE Event_Speaker__c = :speakerId
				WITH USER_MODE
			];
			Database.delete(links, true, AccessLevel.USER_MODE);
			Database.delete(new Event_Speaker__c(Id = speakerId), true, AccessLevel.USER_MODE);
		} catch (DmlException e) {
			Database.rollback(savepoint);
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			Database.rollback(savepoint);
			ErrorLogger.log(e, CONTEXT + '.removeSpeaker', speakerId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	private static void save(SObject record, String method) {
		try {
			Database.insert(record, true, AccessLevel.USER_MODE);
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.' + method);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}
}
