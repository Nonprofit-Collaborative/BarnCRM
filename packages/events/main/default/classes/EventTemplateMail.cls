/**
 * One email from an email template named in Events settings to one Core person: the speaker
 * notices (R-SA5) and the payment link (EV-20, R-ERG5). The template is found by unique name
 * (ADR-0032), the person is the recipient and the record is merged. Returns how it went as one of
 * the outcome words below, which the tabs turn into sentences; it never throws for a send.
 */
public with sharing class EventTemplateMail {
	public static final String SENT = 'Sent';
	public static final String NO_TEMPLATE = 'NoTemplate';
	public static final String TEMPLATE_MISSING = 'TemplateMissing';
	public static final String NO_EMAIL = 'NoEmail';
	public static final String SEND_FAILED = 'SendFailed';

	/**
	 * Sends the template to the person.
	 *
	 * @param sender the sender (a test passes a fake)
	 * @param developerName the template's unique name, or null for no email
	 * @param personId the recipient
	 * @param email the recipient's address, read by the caller with the access it has
	 * @param whatId the record merged
	 * @param context where to log a failed send
	 */
	public static String send(
		EmailSender sender,
		String developerName,
		Id personId,
		String email,
		Id whatId,
		String context
	) {
		if (developerName == null) {
			return NO_TEMPLATE;
		}
		Id templateId = SetupObjectSelector.emailTemplateId(developerName, true);
		if (templateId == null) {
			return TEMPLATE_MISSING;
		}
		if (personId == null || String.isBlank(email)) {
			return NO_EMAIL;
		}
		Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
		message.setTemplateId(templateId);
		message.setTargetObjectId(personId);
		message.setWhatId(whatId);
		message.setTreatTargetObjectAsRecipient(true);
		message.setSaveAsActivity(false);
		try {
			List<EmailSendOutcome> outcomes = sender.send(
				new List<Messaging.SingleEmailMessage>{ message }
			);
			return !outcomes.isEmpty() && outcomes[0].sent ? SENT : SEND_FAILED;
		} catch (Exception e) {
			ErrorLogger.log(e, context, whatId);
			return SEND_FAILED;
		}
	}
}
