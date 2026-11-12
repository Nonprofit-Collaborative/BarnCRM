/**
 * Event Management's side of Core's form seam (ADR-0175 `0175-forms-module.md`, decision 9;
 * ADR-0182 `0182-event-registrations.md`, decision 4). An event names its registration form by
 * the form's record identifier as text (`Registration_Form_Key__c`); each processed submission
 * filled from an event registers the person Forms matched or created, in the same transaction.
 *
 * Core finds this class by name (`FormAttachmentExtensions.EXTENSION_CLASSES`). Without Forms it
 * is never called and staff register people on the Registrations tab.
 *
 * Answers it reads: `ticketType` (a ticket type's name or record identifier) and `promoCode`.
 */
@NamespaceAccessible
public with sharing class EventFormAttachment implements FormAttachmentExtension {
	public static final String ANSWER_TICKET = 'ticketType';
	public static final String ANSWER_CODE = 'promoCode';

	@NamespaceAccessible
	public EventFormAttachment() {
		// Built by name from Core (FormAttachmentExtensions), so it needs a public constructor.
	}

	public Boolean handles(Schema.SObjectType contextType) {
		return contextType == Event__c.SObjectType ||
			contextType == Event_Attendee__c.SObjectType ||
			contextType == Event_Session__c.SObjectType;
	}

	/**
	 * An attendee's survey link names the person's own record, so it carries a signed claim. A
	 * session's rating link (EV-27) is anonymous and printed by the door, so it carries none.
	 */
	public Boolean signedClaim(Id contextRecordId) {
		return contextRecordId.getSObjectType() == Event_Attendee__c.SObjectType;
	}

	/**
	 * An event's registration form, or, for an attendee (the context of a post-event survey link,
	 * EV-18), the survey form of the attendee's event, or, for a session (EV-27), the rating form
	 * of the session's event.
	 */
	public Id formFor(Id contextRecordId) {
		if (contextRecordId.getSObjectType() == Event_Attendee__c.SObjectType) {
			return EventSurveyService.formForAttendee(contextRecordId);
		}
		if (contextRecordId.getSObjectType() == Event_Session__c.SObjectType) {
			return EventSessionRatings.formForSession(contextRecordId);
		}
		for (Event__c event : [
			SELECT Registration_Form_Key__c
			FROM Event__c
			WHERE Id = :contextRecordId
			WITH USER_MODE
		]) {
			if (String.isNotBlank(event.Registration_Form_Key__c)) {
				try {
					return Id.valueOf(event.Registration_Form_Key__c.trim());
				} catch (StringException notAnId) {
					return null;
				}
			}
		}
		return null;
	}

	/**
	 * Registers the submission's person; a submission with no person registers nobody. A survey
	 * submission (context an attendee) keeps its answers on the attendee instead (EV-18), and a
	 * rating submission (context a session) adds a session rating (EV-27).
	 */
	public void received(FormSubmissionReceipt receipt) {
		if (
			receipt != null &&
			receipt.contextRecordId != null &&
			receipt.contextRecordId.getSObjectType() == Event_Session__c.SObjectType
		) {
			EventSessionRatings.store(receipt);
			return;
		}
		if (
			receipt != null &&
			receipt.contextRecordId != null &&
			receipt.contextRecordId.getSObjectType() == Event_Attendee__c.SObjectType
		) {
			EventSurveyService.store(receipt);
			return;
		}
		if (receipt == null || receipt.personId == null) {
			return;
		}
		EventRegistrationService.Request request = new EventRegistrationService.Request();
		request.eventId = receipt.contextRecordId;
		request.registrant = new EventPersonMatcher.PersonInput();
		request.registrant.contactId = receipt.personId;
		request.ticketType = answer(receipt, ANSWER_TICKET);
		request.promoCode = answer(receipt, ANSWER_CODE);
		request.source = EventRegistrationService.SOURCE_FORM;
		request.formSubmissionKey = receipt.submissionId;
		EventRegistrationService.register(request);
	}

	private static String answer(FormSubmissionReceipt receipt, String key) {
		Object value = receipt.answers == null ? null : receipt.answers.get(key);
		return value == null ? null : String.valueOf(value);
	}
}
