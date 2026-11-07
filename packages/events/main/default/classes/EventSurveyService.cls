/**
 * The post-event survey's data work (EV-18; ADR-NEXT `NEXT-event-post-event-survey.md`): which
 * form an attendee's event uses, the attendee's own survey address, and the stored answers.
 *
 * An event names its survey form by the form's record identifier as text
 * (`Survey_Form_Key__c`, ADR-0014), so Events never depends on Forms. The form is filled in from
 * the attendee's link, so the submission's context record is the attendee: the response ties to
 * the attendee, and through the attendee to the event. Addresses are built by Core's
 * `FormCatalogExtensions`; without Forms there are none and nothing here is reached.
 */
public with sharing class EventSurveyService {
	public static final Integer MAX_ANSWERS_LENGTH = 32000;
	private static final Integer CLIPPED_TEXT_LENGTH = 500;

	/** The survey form an event names, or null when none, or the text is not an identifier. */
	public static Id formId(String formKey) {
		if (String.isBlank(formKey)) {
			return null;
		}
		try {
			return Id.valueOf(formKey.trim());
		} catch (StringException notAnId) {
			return null;
		}
	}

	/** The survey form of the attendee's event, in the person's own access; null when none. */
	public static Id formForAttendee(Id attendeeId) {
		for (Event_Attendee__c attendee : [
			SELECT Event_Registration__r.Event__r.Survey_Form_Key__c
			FROM Event_Attendee__c
			WHERE Id = :attendeeId
			WITH USER_MODE
		]) {
			return formId(attendee.Event_Registration__r.Event__r.Survey_Form_Key__c);
		}
		return null;
	}

	/**
	 * Each attendee's survey address, for the attendees whose event has a survey form and for which
	 * Forms can give one. Runs in system mode: the nightly run acts for the organization.
	 */
	public static Map<Id, String> linksFor(List<Event_Attendee__c> attendees) {
		Map<Id, String> links = new Map<Id, String>();
		if (attendees == null || attendees.isEmpty() || !FormCatalogExtensions.isAvailable()) {
			return links;
		}
		for (Event_Attendee__c attendee : [
			SELECT Event_Registration__r.Event__r.Survey_Form_Key__c
			FROM Event_Attendee__c
			WHERE Id IN :attendees
			WITH SYSTEM_MODE
		]) {
			Id formId = formId(attendee.Event_Registration__r.Event__r.Survey_Form_Key__c);
			String link = formId == null
				? null
				: FormCatalogExtensions.publicLink(formId, attendee.Id);
			if (link != null) {
				links.put(attendee.Id, link);
			}
		}
		return links;
	}

	/** Keeps the answers of a processed submission filled in from an attendee's link. */
	public static void store(FormSubmissionReceipt receipt) {
		if (receipt == null || receipt.contextRecordId == null) {
			return;
		}
		Event_Survey_Response__c response = new Event_Survey_Response__c(
			Attendee__c = receipt.contextRecordId
		);
		for (Event_Survey_Response__c existing : [
			SELECT Id
			FROM Event_Survey_Response__c
			WHERE Attendee__c = :receipt.contextRecordId
			WITH USER_MODE
			LIMIT 1
		]) {
			response = new Event_Survey_Response__c(Id = existing.Id);
		}
		response.Answers__c = answersJson(receipt.answers);
		response.Submitted_On__c = Datetime.now();
		response.Form_Submission_Key__c = receipt.submissionId == null
			? null
			: String.valueOf(receipt.submissionId);
		if (response.Id == null) {
			insert as user response;
		} else {
			update as user response;
		}
	}

	/** The answers as JSON that fits the field: long texts are clipped when it would not. */
	@TestVisible
	private static String answersJson(Map<String, Object> answers) {
		Map<String, Object> source = answers == null ? new Map<String, Object>() : answers;
		String text = JSON.serialize(source);
		if (text.length() <= MAX_ANSWERS_LENGTH) {
			return text;
		}
		Map<String, Object> clipped = new Map<String, Object>();
		for (String key : source.keySet()) {
			Object value = source.get(key);
			clipped.put(
				key,
				value instanceof String ? ((String) value).left(CLIPPED_TEXT_LENGTH) : value
			);
		}
		return JSON.serialize(clipped).left(MAX_ANSWERS_LENGTH);
	}
}
