/**
 * The Survey section of the event page's Details tab (EV-18, ADR-0188
 * `0188-event-post-event-survey.md`): pick the form attendees are sent after the event, and read
 * the answers that came back. The forms live in Forms and are reached only through Core's
 * `FormCatalogExtensions`, so this class never names a Forms object and the section is simply
 * absent (`available` false) when Forms is not installed. Thin by design (plan Section 9.9): the
 * browser module `eventSurveyModel` works out the summary. Everything runs with the person's own
 * access.
 */
public with sharing class EventSurveyController {
	private static final String CONTEXT = 'EventSurveyController';
	private static final Integer RESPONSE_LIMIT = 2000;

	/** Everything the section draws. */
	public class Survey {
		/** Whether a module keeps forms; when false the section shows nothing. */
		@AuraEnabled
		public Boolean available = false;
		/** The survey form chosen for the event, or empty. */
		@AuraEnabled
		public String formKey;
		@AuraEnabled
		public List<Choice> forms = new List<Choice>();
		@AuraEnabled
		public List<Choice> questions = new List<Choice>();
		/** Attendees marked Attended. */
		@AuraEnabled
		public Integer attended = 0;
		/** Attendees who were sent a survey link. */
		@AuraEnabled
		public Integer sent = 0;
		@AuraEnabled
		public List<ResponseRow> responses = new List<ResponseRow>();
	}

	/** A form, or a question of the chosen form. */
	public class Choice {
		@AuraEnabled
		public String key;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String kind;
	}

	/** One attendee's answers. */
	public class ResponseRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String attendeeId;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Datetime submittedOn;
		/** The answers by question key, as JSON. */
		@AuraEnabled
		public String answers;
	}

	/**
	 * The event's survey choice, its questions and its responses, or an unavailable result when no
	 * module keeps forms.
	 *
	 * @param eventId the event
	 * @return what the section draws
	 */
	@AuraEnabled
	public static Survey getSurvey(Id eventId) {
		try {
			Survey result = new Survey();
			result.available = FormCatalogExtensions.isAvailable();
			if (!result.available) {
				return result;
			}
			for (Event__c event : [
				SELECT Survey_Form_Key__c
				FROM Event__c
				WHERE Id = :eventId
				WITH USER_MODE
			]) {
				Id formId = EventSurveyService.formId(event.Survey_Form_Key__c);
				result.formKey = formId == null ? null : String.valueOf(formId);
			}
			for (FormCatalogEntry entry : FormCatalogExtensions.publicForms()) {
				result.forms.add(choice(entry));
			}
			if (result.formKey != null) {
				for (FormCatalogEntry entry : FormCatalogExtensions.questions(result.formKey)) {
					result.questions.add(choice(entry));
				}
			}
			result.attended = [
				SELECT COUNT()
				FROM Event_Attendee__c
				WHERE
					Event_Registration__r.Event__c = :eventId
					AND Status__c = :EventRegistrationService.STATUS_ATTENDED
				WITH USER_MODE
			];
			result.sent = [
				SELECT COUNT()
				FROM Event_Attendee__c
				WHERE Event_Registration__r.Event__c = :eventId AND Survey_Link__c != NULL
				WITH USER_MODE
			];
			for (Event_Survey_Response__c response : [
				SELECT Id, Attendee__c, Attendee__r.Contact__r.Name, Submitted_On__c, Answers__c
				FROM Event_Survey_Response__c
				WHERE Attendee__r.Event_Registration__r.Event__c = :eventId
				WITH USER_MODE
				ORDER BY Submitted_On__c DESC
				LIMIT :RESPONSE_LIMIT
			]) {
				ResponseRow row = new ResponseRow();
				row.id = response.Id;
				row.attendeeId = response.Attendee__c;
				row.name = response.Attendee__r.Contact__r.Name;
				row.submittedOn = response.Submitted_On__c;
				row.answers = response.Answers__c;
				result.responses.add(row);
			}
			return result;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getSurvey', eventId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Survey_LoadFailed'));
		}
	}

	/**
	 * Chooses the form sent to attendees after the event, or clears the choice.
	 *
	 * @param eventId the event
	 * @param formKey the form's record identifier, or empty for no survey
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
			update as user new Event__c(Id = eventId, Survey_Form_Key__c = chosen);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.saveForm', eventId);
			throw e instanceof System.IllegalArgumentException
				? UserErrors.message(e.getMessage())
				: UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Survey_SaveFailed'));
		}
	}

	private static Choice choice(FormCatalogEntry entry) {
		Choice result = new Choice();
		result.key = entry.key;
		result.label = entry.label;
		result.kind = entry.kind;
		return result;
	}
}
