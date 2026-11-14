/**
 * The morning event email run's work (EV-14; ADR-0182 `0182-event-registrations.md`, decision
 * 6): reminders before an event, follow-ups after it and the No-Show status.
 *
 * Mail is composed by the platform from the template named in Events Settings, with the person
 * as the target (so `{!Contact.FirstName}` resolves) and the attendee as the record (so its own
 * merge fields do), and sent through Core's `EmailSender`. Each attendee is stamped before it is
 * emailed and the stamp is cleared again when the send fails, so an email goes once and a failed
 * one is tried the next morning. Runs in system mode: the nightly run acts for the organization.
 */
public with sharing class EventEmailService {
	public static final String PHASE_REMIND = 'remind';
	public static final String PHASE_FOLLOW_UP = 'followUp';
	public static final String PHASE_NO_SHOW = 'noShow';
	/** How long after an event ends follow-ups go and No-Show is marked. */
	public static final Integer AFTER_DAYS = 7;
	private static final String LOG_CONTEXT = 'EventEmailService';
	private static final String CAN_BE_EMAILED = ' AND Contact__r.Email != NULL AND Contact__r.HasOptedOutOfEmail = FALSE';

	/** One `Messaging.sendEmail` call per chunk, partial success; a test records instead. */
	@TestVisible
	private static EmailSender emailSender = new MessagingEmailSender();

	/** A test sets the clock. */
	@TestVisible
	private static Datetime nowOverride;

	public static Datetime now() {
		return nowOverride != null ? nowOverride : Datetime.now();
	}

	/** Whether the module is on. */
	public static Boolean moduleOn() {
		return !ModuleManagerService.turnedOff()
			.contains(EventsPostInstall.MODULE_KEY.toLowerCase());
	}

	/** Whether a phase has work to do tonight: the module and its setting are on. */
	public static Boolean isActive(String phase) {
		if (!moduleOn()) {
			return false;
		}
		if (phase == PHASE_REMIND) {
			return EventsSettings.remindersEnabled();
		}
		if (phase == PHASE_FOLLOW_UP) {
			return EventsSettings.followUpsEnabled();
		}
		return phase == PHASE_NO_SHOW && EventsSettings.markNoShows();
	}

	/** The first phase at or after this one that is active, or null. */
	public static String nextActive(String after) {
		List<String> phases = new List<String>{ PHASE_REMIND, PHASE_FOLLOW_UP, PHASE_NO_SHOW };
		Integer start = after == null ? 0 : phases.indexOf(after) + 1;
		for (Integer i = start; i < phases.size(); i++) {
			if (isActive(phases[i])) {
				return phases[i];
			}
		}
		return null;
	}

	/** The attendees a phase works on, in system mode. */
	public static Database.QueryLocator locator(String phase) {
		Datetime at = now();
		Map<String, Object> binds = new Map<String, Object>{
			'now' => at,
			'windowEnd' => at.addDays(EventsSettings.reminderLeadDays()),
			'since' => at.addDays(-AFTER_DAYS)
		};
		return Database.getQueryLocatorWithBinds(queryFor(phase), binds, AccessLevel.SYSTEM_MODE);
	}

	@TestVisible
	private static String queryFor(String phase) {
		String base = 'SELECT Id, Contact__c, Status__c FROM Event_Attendee__c WHERE ';
		if (phase == PHASE_REMIND) {
			return base +
				'Status__c = \'Registered\' AND Reminder_Sent_On__c = NULL' +
				' AND Event_Registration__r.Event__r.Status__c IN (\'Open\', \'Closed\')' +
				' AND Event_Registration__r.Event__r.Start__c > :now' +
				' AND Event_Registration__r.Event__r.Start__c <= :windowEnd' +
				CAN_BE_EMAILED;
		}
		if (phase == PHASE_FOLLOW_UP) {
			return base +
				'Status__c = \'Attended\' AND Follow_Up_Sent_On__c = NULL' +
				' AND Event_Registration__r.Event__r.End__c <= :now' +
				' AND Event_Registration__r.Event__r.End__c >= :since' +
				CAN_BE_EMAILED;
		}
		return base +
			'Status__c = \'Registered\'' +
			' AND Event_Registration__r.Event__r.Status__c != \'Cancelled\'' +
			' AND Event_Registration__r.Event__r.End__c <= :now' +
			' AND Event_Registration__r.Event__r.End__c >= :since';
	}

	/** Does one chunk of a phase's work. Returns how many attendees it handled. */
	public static Integer run(String phase, List<Event_Attendee__c> attendees) {
		if (attendees == null || attendees.isEmpty() || !isActive(phase)) {
			return 0;
		}
		if (phase == PHASE_NO_SHOW) {
			return markNoShows(attendees);
		}
		return email(phase, attendees);
	}

	private static Integer markNoShows(List<Event_Attendee__c> attendees) {
		// No-Show holds its seat, so the registration's status and amount stay as they are.
		List<Event_Attendee__c> updates = new List<Event_Attendee__c>();
		for (Event_Attendee__c attendee : [
			SELECT Id
			FROM Event_Attendee__c
			WHERE Id IN :attendees AND Status__c = :EventRegistrationService.STATUS_REGISTERED
			WITH SYSTEM_MODE
		]) {
			updates.add(
				new Event_Attendee__c(
					Id = attendee.Id,
					Status__c = EventRegistrationService.STATUS_NO_SHOW
				)
			);
		}
		Integer marked = 0;
		for (Database.SaveResult saved : Database.update(updates, false, AccessLevel.SYSTEM_MODE)) {
			marked += saved.isSuccess() ? 1 : 0;
		}
		return marked;
	}

	private static Integer email(String phase, List<Event_Attendee__c> attendees) {
		if (phase != PHASE_FOLLOW_UP) {
			return emailGroup(phase, attendees, EventsSettings.reminderTemplate(), null);
		}
		// An attendee of an event with a survey gets the survey template and their own link (EV-18).
		Map<Id, String> links = EventSurveyService.linksFor(attendees);
		List<Event_Attendee__c> withSurvey = new List<Event_Attendee__c>();
		List<Event_Attendee__c> plain = new List<Event_Attendee__c>();
		for (Event_Attendee__c attendee : attendees) {
			(links.containsKey(attendee.Id) ? withSurvey : plain).add(attendee);
		}
		Integer sent = 0;
		if (!withSurvey.isEmpty()) {
			sent += emailGroup(phase, withSurvey, EventsSettings.surveyTemplate(), links);
		}
		if (!plain.isEmpty()) {
			sent += emailGroup(phase, plain, EventsSettings.followUpTemplate(), null);
		}
		return sent;
	}

	/** Stamps and emails one group with one template; survey links, when given, are stamped too. */
	private static Integer emailGroup(
		String phase,
		List<Event_Attendee__c> attendees,
		String templateName,
		Map<Id, String> surveyLinks
	) {
		Boolean remind = phase == PHASE_REMIND;
		Id templateId = templateIdFor(templateName);
		if (templateId == null) {
			ErrorLogger.logMessage(
				BarnHelp.text(
					'Events',
					'Events_Emails_NoTemplate',
					new List<Object>{ templateName }
				),
				LOG_CONTEXT,
				ErrorLogger.SEVERITY_WARNING
			);
			return 0;
		}
		String stampField = remind ? 'Reminder_Sent_On__c' : 'Follow_Up_Sent_On__c';
		Datetime at = now();
		List<Event_Attendee__c> stamps = new List<Event_Attendee__c>();
		for (Event_Attendee__c attendee : attendees) {
			Event_Attendee__c stamp = new Event_Attendee__c(Id = attendee.Id);
			stamp.put(stampField, at);
			if (surveyLinks != null) {
				stamp.Survey_Link__c = surveyLinks.get(attendee.Id);
			}
			stamps.add(stamp);
		}
		List<Database.SaveResult> stamped = Database.update(stamps, false, AccessLevel.SYSTEM_MODE);
		List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
		List<Event_Attendee__c> sentTo = new List<Event_Attendee__c>();
		for (Integer i = 0; i < attendees.size(); i++) {
			if (stamped[i].isSuccess()) {
				messages.add(message(attendees[i], templateId));
				sentTo.add(attendees[i]);
			}
		}
		if (messages.isEmpty()) {
			return 0;
		}
		List<EmailSendOutcome> outcomes = emailSender.send(messages);
		List<Event_Attendee__c> unstamp = new List<Event_Attendee__c>();
		String lastFailure;
		for (Integer i = 0; i < sentTo.size(); i++) {
			if (i >= outcomes.size() || !outcomes[i].sent) {
				Event_Attendee__c clear = new Event_Attendee__c(Id = sentTo[i].Id);
				clear.put(stampField, null);
				unstamp.add(clear);
				if (i < outcomes.size() && outcomes[i].error != null) {
					lastFailure = outcomes[i].error;
				}
			}
		}
		if (!unstamp.isEmpty()) {
			Database.update(unstamp, false, AccessLevel.SYSTEM_MODE);
			ErrorLogger.logMessage(
				BarnHelp.text(
					'Events',
					'Events_Emails_SendFailed',
					new List<Object>{
						unstamp.size(),
						sentTo.size(),
						lastFailure == null ? '' : lastFailure
					}
				),
				LOG_CONTEXT,
				ErrorLogger.SEVERITY_WARNING
			);
		}
		return sentTo.size() - unstamp.size();
	}

	private static Messaging.SingleEmailMessage message(Event_Attendee__c attendee, Id templateId) {
		Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
		message.setTemplateId(templateId);
		message.setTargetObjectId(attendee.Contact__c);
		message.setWhatId(attendee.Id);
		message.setTreatTargetObjectAsRecipient(true);
		// No activity: logging a task per email would depend on a standard object (plan 4.2).
		message.setSaveAsActivity(false);
		return message;
	}

	private static Id templateIdFor(String developerName) {
		return SetupObjectSelector.emailTemplateId(developerName, false);
	}
}
