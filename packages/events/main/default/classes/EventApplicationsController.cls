/**
 * The Applications tab of the event page (EV-06, canonical model 29EV20 and 29EV21): a call for
 * speakers. Proposals per event, reviewers' scores, and accept or decline with an email notice.
 * Thin by design (plan Section 9.9): ranking and wording live in `eventApplicationsModel`.
 * Reads in user mode; writes `AccessLevel.USER_MODE`. Application details are added and edited
 * through the platform's record form.
 */
public with sharing class EventApplicationsController {
	private static final String CONTEXT = 'EventApplicationsController';
	public static final String ACCEPTED = 'Accepted';
	public static final String DECLINED = 'Declined';
	private static final Set<String> UNDECIDED = new Set<String>{ 'Submitted', 'In Review' };

	/** How the notice went; the tab shows the matching sentence from the help catalog. */
	public static final String NOTICE_SENT = 'Sent';
	public static final String NOTICE_OFF = 'NoTemplate';
	public static final String NOTICE_UNKNOWN_TEMPLATE = 'TemplateMissing';
	public static final String NOTICE_NO_EMAIL = 'NoEmail';
	public static final String NOTICE_FAILED = 'SendFailed';
	public static final String NOTICE_NONE = 'None';

	@TestVisible
	private static EmailSender emailSender = new MessagingEmailSender();

	/** Everything the tab draws. */
	public class Applications {
		@AuraEnabled
		public List<ApplicationRow> applications = new List<ApplicationRow>();
		@AuraEnabled
		public Boolean canAdd = false;
		@AuraEnabled
		public Boolean canReview = false;
		@AuraEnabled
		public Boolean canDecide = false;
		/** Field labels by API name, so the tab needs no labels of its own for columns. */
		@AuraEnabled
		public Map<String, String> fieldLabels = new Map<String, String>();
	}

	/** One proposal with its scores. */
	public class ApplicationRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String contactId;
		@AuraEnabled
		public String applicant;
		@AuraEnabled
		public String abstractText;
		@AuraEnabled
		public String track;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String speakerId;
		@AuraEnabled
		public Integer reviewCount = 0;
		@AuraEnabled
		public Decimal averageScore;
		/** The viewing person's own score and note, when they have reviewed it. */
		@AuraEnabled
		public Integer myScore;
		@AuraEnabled
		public String myNotes;
		@AuraEnabled
		public Datetime noticeSent;
		@AuraEnabled
		public String noticeResult;
		@AuraEnabled
		public List<ReviewRow> reviews = new List<ReviewRow>();
	}

	/** One reviewer's score. */
	public class ReviewRow {
		@AuraEnabled
		public String reviewer;
		@AuraEnabled
		public Integer score;
		@AuraEnabled
		public String notes;
	}

	/** The outcome of an accept or decline. */
	public class Decision {
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String speakerId;
		/** One of the NOTICE_ values. */
		@AuraEnabled
		public String notice;
	}

	/**
	 * The event's applications, with their reviews.
	 *
	 * @param eventId the event
	 * @return the tab's applications and what the person may do
	 */
	@AuraEnabled
	public static Applications getApplications(Id eventId) {
		try {
			Applications result = new Applications();
			result.canAdd = Schema.SObjectType.Speaker_Application__c.isCreateable();
			result.canReview = Schema.SObjectType.Speaker_Review__c.isCreateable();
			result.canDecide = Schema.SObjectType.Speaker_Application__c.isUpdateable();
			Map<String, Schema.SObjectField> fields = Schema.SObjectType.Speaker_Application__c.fields.getMap();
			for (
				String name : new List<String>{
					'Name',
					'Contact__c',
					'Track__c',
					'Status__c',
					'Average_Score__c',
					'Abstract__c'
				}
			) {
				result.fieldLabels.put(name, fields.get(name).getDescribe().getLabel());
			}
			Map<String, Schema.SObjectField> reviewFields = Schema.SObjectType.Speaker_Review__c.fields.getMap();
			for (String name : new List<String>{ 'Score__c', 'Notes__c' }) {
				result.fieldLabels.put(name, reviewFields.get(name).getDescribe().getLabel());
			}
			Map<Id, ApplicationRow> byId = new Map<Id, ApplicationRow>();
			for (Speaker_Application__c application : [
				SELECT
					Id,
					Name,
					Contact__c,
					Contact__r.Name,
					Abstract__c,
					Track__r.Name,
					Status__c,
					Event_Speaker__c,
					Review_Count__c,
					Average_Score__c,
					Notice_Sent__c,
					Notice_Result__c
				FROM Speaker_Application__c
				WHERE Event__c = :eventId
				WITH USER_MODE
				ORDER BY Average_Score__c DESC NULLS LAST, Name
				LIMIT 500
			]) {
				ApplicationRow row = new ApplicationRow();
				row.id = application.Id;
				row.name = application.Name;
				row.contactId = application.Contact__c;
				row.applicant = application.Contact__r?.Name;
				row.abstractText = application.Abstract__c;
				row.track = application.Track__r?.Name;
				row.status = application.Status__c;
				row.speakerId = application.Event_Speaker__c;
				row.reviewCount = application.Review_Count__c == null
					? 0
					: Integer.valueOf(application.Review_Count__c);
				row.averageScore = application.Average_Score__c;
				row.noticeSent = application.Notice_Sent__c;
				row.noticeResult = application.Notice_Result__c;
				byId.put(application.Id, row);
				result.applications.add(row);
			}
			Set<Id> applicationIds = byId.keySet();
			for (Speaker_Review__c review : [
				SELECT Speaker_Application__c, Reviewer__c, Reviewer__r.Name, Score__c, Notes__c
				FROM Speaker_Review__c
				WHERE Speaker_Application__c IN :applicationIds
				WITH USER_MODE
				ORDER BY CreatedDate
				LIMIT 2000
			]) {
				ApplicationRow row = byId.get(review.Speaker_Application__c);
				ReviewRow line = new ReviewRow();
				line.reviewer = review.Reviewer__r?.Name;
				line.score = Integer.valueOf(review.Score__c);
				line.notes = review.Notes__c;
				row.reviews.add(line);
				if (review.Reviewer__c == UserInfo.getUserId()) {
					row.myScore = line.score;
					row.myNotes = review.Notes__c;
				}
			}
			return result;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getApplications', eventId);
			throw UserErrors.wrapShowingDml(
				e,
				BarnHelp.text('Events', 'Events_Applications_LoadFailed')
			);
		}
	}

	/**
	 * Saves the viewing person's score for an application: one review per reviewer, so a second
	 * save replaces the first (R-SA3). A first review moves a Submitted application to In Review.
	 *
	 * @param applicationId the application
	 * @param score a whole number from 1 to 5
	 * @param notes why, or empty
	 */
	@AuraEnabled
	public static void saveReview(Id applicationId, Integer score, String notes) {
		try {
			if (score == null || score < 1 || score > 5) {
				throw UserErrors.message(BarnHelp.text('Events', 'Events_Applications_ScoreRange'));
			}
			Speaker_Application__c application = load(applicationId);
			if (!UNDECIDED.contains(application.Status__c)) {
				throw UserErrors.message(BarnHelp.text('Events', 'Events_Applications_Decided'));
			}
			List<Speaker_Review__c> mine = [
				SELECT Id
				FROM Speaker_Review__c
				WHERE
					Speaker_Application__c = :applicationId
					AND Reviewer__c = :UserInfo.getUserId()
				WITH USER_MODE
				LIMIT 1
			];
			Speaker_Review__c review = mine.isEmpty()
				? new Speaker_Review__c(
						Speaker_Application__c = applicationId,
						Reviewer__c = UserInfo.getUserId()
				  )
				: mine[0];
			review.Score__c = score;
			review.Notes__c = notes;
			Database.upsert(review, true, AccessLevel.USER_MODE);
			if (application.Status__c == 'Submitted') {
				Database.update(
					new Speaker_Application__c(Id = applicationId, Status__c = 'In Review'),
					true,
					AccessLevel.USER_MODE
				);
			}
		} catch (AuraHandledException refused) {
			throw refused;
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.saveReview', applicationId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/**
	 * Accepts or declines an undecided application (R-SA4, R-SA5). Accepting makes the person a
	 * speaker at the event, or links the speaker they already are. When `notify` is true the
	 * applicant gets the email template chosen in Events settings; a notice that cannot go out
	 * never undoes the decision, and the application records why.
	 *
	 * @param applicationId the application
	 * @param decision Accepted or Declined
	 * @param notify whether to send the notice
	 * @return the saved status, the speaker and how the notice went
	 */
	@AuraEnabled
	public static Decision decide(Id applicationId, String decision, Boolean notify) {
		Savepoint savepoint = Database.setSavepoint();
		try {
			if (decision != ACCEPTED && decision != DECLINED) {
				throw UserErrors.message(BarnHelp.text('Events', 'Events_Shared_NotSaved'));
			}
			Speaker_Application__c application = load(applicationId);
			if (!UNDECIDED.contains(application.Status__c)) {
				throw UserErrors.message(BarnHelp.text('Events', 'Events_Applications_Decided'));
			}
			Decision result = new Decision();
			result.status = decision;
			result.notice = NOTICE_NONE;
			// A fresh record carries only what changes: the event is not editable on an application.
			Speaker_Application__c change = new Speaker_Application__c(
				Id = applicationId,
				Status__c = decision
			);
			if (decision == ACCEPTED) {
				result.speakerId = speakerFor(application);
				change.Event_Speaker__c = result.speakerId;
			}
			Database.update(change, true, AccessLevel.USER_MODE);
			if (notify == true) {
				result.notice = sendNotice(application, decision);
				stampNotice(application, result.notice);
			}
			return result;
		} catch (AuraHandledException refused) {
			Database.rollback(savepoint);
			throw refused;
		} catch (DmlException e) {
			Database.rollback(savepoint);
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			Database.rollback(savepoint);
			ErrorLogger.log(e, CONTEXT + '.decide', applicationId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/** The applicant as a speaker at the event: the one already there, or a new Invited one. */
	private static Id speakerFor(Speaker_Application__c application) {
		if (application.Contact__c == null) {
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Applications_NoApplicant'));
		}
		List<Event_Speaker__c> existing = [
			SELECT Id
			FROM Event_Speaker__c
			WHERE Event__c = :application.Event__c AND Contact__c = :application.Contact__c
			WITH USER_MODE
			LIMIT 1
		];
		if (!existing.isEmpty()) {
			return existing[0].Id;
		}
		Event_Speaker__c speaker = new Event_Speaker__c(
			Event__c = application.Event__c,
			Contact__c = application.Contact__c
		);
		Database.insert(speaker, true, AccessLevel.USER_MODE);
		return speaker.Id;
	}

	/** One email from the chosen template to the applicant; returns a NOTICE_ value. */
	private static String sendNotice(Speaker_Application__c application, String decision) {
		String developerName = decision == ACCEPTED
			? EventsSettings.acceptNoticeTemplate()
			: EventsSettings.declineNoticeTemplate();
		if (developerName == null) {
			return NOTICE_OFF;
		}
		List<EmailTemplate> templates = [
			SELECT Id
			FROM EmailTemplate
			WHERE DeveloperName = :developerName AND IsActive = TRUE
			WITH SYSTEM_MODE
			LIMIT 1
		];
		if (templates.isEmpty()) {
			return NOTICE_UNKNOWN_TEMPLATE;
		}
		List<Contact> people = [
			SELECT Id, Email
			FROM Contact
			WHERE Id = :application.Contact__c
			WITH USER_MODE
			LIMIT 1
		];
		if (people.isEmpty() || String.isBlank(people[0].Email)) {
			return NOTICE_NO_EMAIL;
		}
		Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
		message.setTemplateId(templates[0].Id);
		message.setTargetObjectId(people[0].Id);
		message.setWhatId(application.Id);
		message.setTreatTargetObjectAsRecipient(true);
		message.setSaveAsActivity(false);
		try {
			List<EmailSendOutcome> outcomes = emailSender.send(
				new List<Messaging.SingleEmailMessage>{ message }
			);
			return !outcomes.isEmpty() && outcomes[0].sent ? NOTICE_SENT : NOTICE_FAILED;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.sendNotice', application.Id);
			return NOTICE_FAILED;
		}
	}

	/** Records on the application when the notice went, or the sentence saying why it did not. */
	private static void stampNotice(Speaker_Application__c application, String notice) {
		Speaker_Application__c change = new Speaker_Application__c(Id = application.Id);
		if (notice == NOTICE_SENT) {
			change.Notice_Sent__c = Datetime.now();
			change.Notice_Result__c = null;
		} else {
			change.Notice_Result__c = noticeText(notice).left(255);
		}
		Database.update(change, true, AccessLevel.USER_MODE);
	}

	/** The sentence for a notice that did not go out. */
	private static String noticeText(String notice) {
		if (notice == NOTICE_OFF) {
			return BarnHelp.text('Events', 'Events_Notice_NoTemplate');
		}
		if (notice == NOTICE_UNKNOWN_TEMPLATE) {
			return BarnHelp.text('Events', 'Events_Notice_TemplateMissing');
		}
		if (notice == NOTICE_NO_EMAIL) {
			return BarnHelp.text('Events', 'Events_Notice_NoEmail');
		}
		return BarnHelp.text('Events', 'Events_Notice_SendFailed');
	}

	private static Speaker_Application__c load(Id applicationId) {
		List<Speaker_Application__c> found = [
			SELECT Id, Event__c, Contact__c, Status__c, Event_Speaker__c
			FROM Speaker_Application__c
			WHERE Id = :applicationId
			WITH USER_MODE
			LIMIT 1
		];
		if (found.isEmpty()) {
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
		return found[0];
	}
}
