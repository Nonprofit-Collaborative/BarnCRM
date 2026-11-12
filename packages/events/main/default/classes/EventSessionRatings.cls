/**
 * Per-session ratings (EV-27; ADR-0207 `0207-events-paid-registration-proposals-ratings.md`,
 * decisions 14 and 15; canonical model 29EV27, R-SRT1 to R-SRT3). An event names one published
 * public Forms form (`Session_Rating_Form_Key__c`); each session's QR code opens it tied to the
 * session, and each processed submission with a `rating` from 1 to 5 adds one anonymous
 * `Session_Rating__c`. Roll-ups give the session's Ratings and Average Rating.
 *
 * The Agenda tab reaches it through `getSetup` and `saveForm`. Without Forms nothing here is
 * offered and no rating is taken.
 */
public with sharing class EventSessionRatings {
	public static final String ANSWER_RATING = 'rating';
	public static final String ANSWER_COMMENT = 'comment';
	private static final String CONTEXT = 'EventSessionRatings';
	private static final Integer COMMENT_LENGTH = 2000;
	private static final Integer LINK_LIMIT = 200;

	/** What the Session Ratings panel draws. */
	public class Setup {
		@AuraEnabled
		public Boolean available = false;
		@AuraEnabled
		public String formKey;
		@AuraEnabled
		public List<EventSurveyController.Choice> forms = new List<EventSurveyController.Choice>();
		/** Each confirmed session's rating address, by session record identifier. */
		@AuraEnabled
		public Map<String, String> links = new Map<String, String>();
	}

	/**
	 * The forms to choose from, the event's choice and, once chosen, each session's link.
	 *
	 * @param eventId the event
	 */
	@AuraEnabled
	public static Setup getSetup(Id eventId) {
		try {
			Setup result = new Setup();
			result.available = FormCatalogExtensions.isAvailable();
			if (!result.available) {
				return result;
			}
			Id formId = null;
			for (Event__c event : [
				SELECT Session_Rating_Form_Key__c
				FROM Event__c
				WHERE Id = :eventId
				WITH USER_MODE
			]) {
				formId = EventSurveyService.formId(event.Session_Rating_Form_Key__c);
			}
			result.formKey = formId == null ? null : String.valueOf(formId);
			for (FormCatalogEntry entry : FormCatalogExtensions.publicForms()) {
				EventSurveyController.Choice choice = new EventSurveyController.Choice();
				choice.key = entry.key;
				choice.label = entry.label;
				choice.kind = entry.kind;
				result.forms.add(choice);
			}
			if (formId != null) {
				for (Event_Session__c session : [
					SELECT Id
					FROM Event_Session__c
					WHERE Event__c = :eventId AND Status__c = 'Confirmed'
					WITH USER_MODE
					ORDER BY Start__c ASC NULLS LAST, Name
					LIMIT :LINK_LIMIT
				]) {
					String link = FormCatalogExtensions.publicLink(formId, session.Id);
					if (link != null) {
						result.links.put(session.Id, link);
					}
				}
			}
			return result;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getSetup', eventId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Agenda_LoadFailed'));
		}
	}

	/**
	 * Chooses the event's rating form, or clears it; only a published public form is taken.
	 *
	 * @param eventId the event
	 * @param formKey the form's record identifier, or empty for none
	 */
	@AuraEnabled
	public static void saveForm(Id eventId, String formKey) {
		try {
			String chosen = null;
			if (String.isNotBlank(formKey)) {
				Id formId = EventSurveyService.formId(formKey);
				for (FormCatalogEntry entry : FormCatalogExtensions.publicForms()) {
					if (formId != null && entry.key == String.valueOf(formId)) {
						chosen = entry.key;
					}
				}
				if (chosen == null) {
					throw new System.IllegalArgumentException(
						BarnHelp.text('Events', 'Events_Survey_NotPublic')
					);
				}
			}
			update as user new Event__c(Id = eventId, Session_Rating_Form_Key__c = chosen);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.saveForm', eventId);
			throw e instanceof System.IllegalArgumentException
				? UserErrors.message(e.getMessage())
				: UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/** The rating form of the session's event, for a guest opening the session's link. */
	public static Id formForSession(Id sessionId) {
		return new SessionFormReader().formOf(sessionId);
	}

	/**
	 * The one read a rating link's guest makes: which form the session's event names. Without
	 * sharing, as the Site guest user is shared no session; it returns only the form identifier,
	 * never a record value (listed in the without-sharing register beside AttendeeFormReader).
	 */
	private without sharing class SessionFormReader {
		Id formOf(Id sessionId) {
			for (Event_Session__c session : [
				SELECT Event__r.Session_Rating_Form_Key__c
				FROM Event_Session__c
				WHERE Id = :sessionId
				WITH SYSTEM_MODE
			]) {
				return EventSurveyService.formId(session.Event__r.Session_Rating_Form_Key__c);
			}
			return null;
		}
	}

	/**
	 * R-SRT2: keeps a processed submission's rating on its session, once per submission; one with
	 * no whole rating from 1 to 5 adds nothing. Runs as the processing user.
	 */
	public static void store(FormSubmissionReceipt receipt) {
		if (receipt == null || receipt.contextRecordId == null || receipt.answers == null) {
			return;
		}
		Integer rating = ratingOf(receipt.answers.get(ANSWER_RATING));
		if (rating == null) {
			return;
		}
		String key = receipt.submissionId == null ? null : String.valueOf(receipt.submissionId);
		if (key != null) {
			Integer already = [
				SELECT COUNT()
				FROM Session_Rating__c
				WHERE Form_Submission_Key__c = :key
				WITH USER_MODE
			];
			if (already > 0) {
				return;
			}
		}
		Object comment = receipt.answers.get(ANSWER_COMMENT);
		insert as user new Session_Rating__c(
			Event_Session__c = receipt.contextRecordId,
			Rating__c = rating,
			Comment__c = comment == null ? null : String.valueOf(comment).left(COMMENT_LENGTH),
			Form_Submission_Key__c = key
		);
	}

	@TestVisible
	private static Integer ratingOf(Object value) {
		if (value == null) {
			return null;
		}
		try {
			Decimal given = Decimal.valueOf(String.valueOf(value).trim());
			if (given != given.round(System.RoundingMode.DOWN) || given < 1 || given > 5) {
				return null;
			}
			return given.intValue();
		} catch (Exception notANumber) {
			return null;
		}
	}
}
