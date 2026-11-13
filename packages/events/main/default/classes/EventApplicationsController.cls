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
		/** EV-21: the event's weighted criteria (none: one score per review), and blind review. */
		@AuraEnabled
		public List<EventProposalReview.Criterion> criteria = new List<EventProposalReview.Criterion>();
		@AuraEnabled
		public Boolean blindReview = false;
		@AuraEnabled
		public Boolean canEditEvent = false;
		@AuraEnabled
		public Boolean canAssign = false;
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
		@AuraEnabled
		public Decimal weightedAverage;
		/** The viewing person's own score and note, when they have reviewed it. */
		@AuraEnabled
		public Integer myScore;
		@AuraEnabled
		public String myNotes;
		@AuraEnabled
		public String myCriteriaScores;
		/** EV-21: the viewing person is assigned and has not scored it yet. */
		@AuraEnabled
		public Boolean assignedToMe = false;
		@AuraEnabled
		public List<PresenterRow> presenters = new List<PresenterRow>();
		@AuraEnabled
		public Datetime noticeSent;
		@AuraEnabled
		public String noticeResult;
		@AuraEnabled
		public List<ReviewRow> reviews = new List<ReviewRow>();
	}

	/** One reviewer's score; an assignment has none yet. */
	public class ReviewRow {
		@AuraEnabled
		public String reviewer;
		@AuraEnabled
		public Integer score;
		@AuraEnabled
		public String notes;
		@AuraEnabled
		public Decimal weightedScore;
		/** Scores by criterion label, as JSON, when the event has criteria. */
		@AuraEnabled
		public String criteriaScores;
	}

	/** One more person on a proposal (R-PP1). */
	public class PresenterRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String role;
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
				result.fieldLabels.put(
					name,
					NamespaceUtil.field(fields, name).getDescribe().getLabel()
				);
			}
			Map<String, Schema.SObjectField> reviewFields = Schema.SObjectType.Speaker_Review__c.fields.getMap();
			for (String name : new List<String>{ 'Score__c', 'Notes__c', 'Reviewer__c' }) {
				result.fieldLabels.put(
					name,
					NamespaceUtil.field(reviewFields, name).getDescribe().getLabel()
				);
			}
			result.fieldLabels.put(
				'Weighted_Average__c',
				NamespaceUtil.field(fields, 'Weighted_Average__c').getDescribe().getLabel()
			);
			result.canEditEvent = Schema.SObjectType.Event__c.fields.Review_Criteria__c.isUpdateable();
			result.canAssign = Schema.SObjectType.Speaker_Review__c.fields.Reviewer__c.isCreateable();
			for (Event__c event : [
				SELECT Review_Criteria__c, Blind_Review__c
				FROM Event__c
				WHERE Id = :eventId
				WITH USER_MODE
			]) {
				result.criteria = EventProposalReview.criteriaOf(event.Review_Criteria__c);
				result.blindReview = event.Blind_Review__c == true;
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
					Weighted_Average__c,
					Notice_Sent__c,
					Notice_Result__c
				FROM Speaker_Application__c
				WHERE Event__c = :eventId
				WITH USER_MODE
				ORDER BY Weighted_Average__c DESC NULLS LAST, Average_Score__c DESC NULLS LAST, Name
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
				row.weightedAverage = application.Weighted_Average__c;
				row.noticeSent = application.Notice_Sent__c;
				row.noticeResult = application.Notice_Result__c;
				byId.put(application.Id, row);
				result.applications.add(row);
			}
			Set<Id> applicationIds = byId.keySet();
			for (Speaker_Review__c review : [
				SELECT
					Speaker_Application__c,
					Reviewer__c,
					Reviewer__r.Name,
					Score__c,
					Notes__c,
					Weighted_Score__c,
					Criteria_Scores__c
				FROM Speaker_Review__c
				WHERE Speaker_Application__c IN :applicationIds
				WITH USER_MODE
				ORDER BY CreatedDate
				LIMIT 2000
			]) {
				ApplicationRow row = byId.get(review.Speaker_Application__c);
				ReviewRow line = new ReviewRow();
				line.reviewer = review.Reviewer__r?.Name;
				line.score = review.Score__c == null ? null : Integer.valueOf(review.Score__c);
				line.notes = review.Notes__c;
				line.weightedScore = review.Weighted_Score__c;
				line.criteriaScores = review.Criteria_Scores__c;
				row.reviews.add(line);
				if (review.Reviewer__c == UserInfo.getUserId()) {
					row.myScore = line.score;
					row.myNotes = review.Notes__c;
					row.myCriteriaScores = review.Criteria_Scores__c;
					row.assignedToMe = line.score == null;
				}
			}
			for (Proposal_Presenter__c presenter : [
				SELECT Id, Speaker_Application__c, Contact__r.Name, Role__c
				FROM Proposal_Presenter__c
				WHERE Speaker_Application__c IN :applicationIds
				WITH USER_MODE
				ORDER BY CreatedDate
				LIMIT 2500
			]) {
				PresenterRow line = new PresenterRow();
				line.id = presenter.Id;
				line.name = presenter.Contact__r?.Name;
				line.role = presenter.Role__c;
				byId.get(presenter.Speaker_Application__c).presenters.add(line);
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
	 * With the event's weighted criteria (EV-21, R-SA7) the reviewer scores each from 1 to 5 in
	 * `criteriaScoresJson` (a map by label); the Weighted Score is worked out here and the Score is
	 * it rounded. Without criteria `score` is the one score and the Weighted Score equals it.
	 * Filling an assignment (an unscored review of the person's) scores it.
	 *
	 * @param applicationId the application
	 * @param score a whole number from 1 to 5, when the event has no criteria
	 * @param notes why, or empty
	 * @param criteriaScoresJson each criterion's score by label, when it has
	 */
	@AuraEnabled
	public static void saveReview(
		Id applicationId,
		Integer score,
		String notes,
		String criteriaScoresJson
	) {
		try {
			Speaker_Application__c application = load(applicationId);
			if (!UNDECIDED.contains(application.Status__c)) {
				throw UserErrors.message(BarnHelp.text('Events', 'Events_Applications_Decided'));
			}
			List<EventProposalReview.Criterion> criteria = EventProposalReview.criteriaOf(
				application.Event__r.Review_Criteria__c
			);
			Decimal weighted;
			Map<String, Object> scores = null;
			if (criteria.isEmpty()) {
				if (score == null || score < 1 || score > 5) {
					throw UserErrors.message(
						BarnHelp.text('Events', 'Events_Applications_ScoreRange')
					);
				}
				weighted = score;
			} else {
				try {
					scores = String.isBlank(criteriaScoresJson)
						? new Map<String, Object>()
						: (Map<String, Object>) JSON.deserializeUntyped(criteriaScoresJson);
					weighted = EventProposalReview.weightedScore(criteria, scores);
				} catch (Exception refused) {
					throw UserErrors.message(
						BarnHelp.text('Events', 'Events_Applications_ScoreEach')
					);
				}
				score = weighted.round(System.RoundingMode.HALF_UP).intValue();
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
			review.Weighted_Score__c = weighted;
			review.Criteria_Scores__c = scores == null ? null : JSON.serialize(scores);
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
				result.speakerId = speakerFor(application.Event__c, application.Contact__c);
				change.Event_Speaker__c = result.speakerId;
				// EV-21 (R-PP1): every presenter on the proposal becomes a speaker too.
				for (Id presenter : EventProposalReview.presenterContacts(application.Id)) {
					speakerFor(application.Event__c, presenter);
				}
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

	/** The person as a speaker at the event: the one already there, or a new Invited one. */
	private static Id speakerFor(Id eventId, Id contactId) {
		if (contactId == null) {
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Applications_NoApplicant'));
		}
		List<Event_Speaker__c> existing = [
			SELECT Id
			FROM Event_Speaker__c
			WHERE Event__c = :eventId AND Contact__c = :contactId
			WITH USER_MODE
			LIMIT 1
		];
		if (!existing.isEmpty()) {
			return existing[0].Id;
		}
		Event_Speaker__c speaker = new Event_Speaker__c(Event__c = eventId, Contact__c = contactId);
		Database.insert(speaker, true, AccessLevel.USER_MODE);
		return speaker.Id;
	}

	/** One email from the chosen template to the applicant; returns a NOTICE_ value. */
	private static String sendNotice(Speaker_Application__c application, String decision) {
		String developerName = decision == ACCEPTED
			? EventsSettings.acceptNoticeTemplate()
			: EventsSettings.declineNoticeTemplate();
		String email;
		for (Contact person : [
			SELECT Email
			FROM Contact
			WHERE Id = :application.Contact__c
			WITH USER_MODE
			LIMIT 1
		]) {
			email = person.Email;
		}
		return EventTemplateMail.send(
			emailSender,
			developerName,
			application.Contact__c,
			email,
			application.Id,
			CONTEXT + '.sendNotice'
		);
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
			SELECT
				Id,
				Event__c,
				Event__r.Review_Criteria__c,
				Contact__c,
				Status__c,
				Event_Speaker__c
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
