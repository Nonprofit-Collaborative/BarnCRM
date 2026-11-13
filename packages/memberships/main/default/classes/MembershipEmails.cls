/**
 * Emails a membership's contact with a template (R-MEM5 reminders, R-MEM7 payment links), the
 * way Events does (EV-14): the platform composes the mail with the contact as the target and the
 * term as the record, so both sets of merge fields resolve. A stamp field, when given, is set to
 * the term's end date before sending and cleared again when the send fails, so a reminder goes
 * once. No activity is saved: a task per email would need a standard object (plan 4.2).
 */
public with sharing class MembershipEmails {
	private static final String CONTEXT = 'MembershipEmails';

	/** The template's id by its unique name, or null when there is none. */
	public static Id templateId(String developerName) {
		return SetupObjectSelector.emailTemplateId(developerName, true);
	}

	/**
	 * Sends one email per term to its contact. Returns how many were sent. `stampField` is null
	 * or a date field set to the term's end date (blank end dates stamp today).
	 */
	public static Integer send(
		List<Membership_Term__c> terms,
		Id templateId,
		String stampField,
		EmailSender sender
	) {
		if (terms.isEmpty()) {
			return 0;
		}
		if (stampField != null) {
			List<Membership_Term__c> stamps = new List<Membership_Term__c>();
			for (Membership_Term__c term : terms) {
				Membership_Term__c stamp = new Membership_Term__c(Id = term.Id);
				stamp.put(
					stampField,
					term.End_Date__c != null ? term.End_Date__c : MembershipService.today()
				);
				stamps.add(stamp);
			}
			update as system stamps;
		}
		List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
		for (Membership_Term__c term : terms) {
			Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
			message.setTemplateId(templateId);
			message.setTargetObjectId(term.Contact__c);
			message.setWhatId(term.Id);
			message.setTreatTargetObjectAsRecipient(true);
			message.setSaveAsActivity(false);
			messages.add(message);
		}
		List<EmailSendOutcome> outcomes = new List<EmailSendOutcome>();
		String lastFailure = '';
		try {
			outcomes = sender.send(messages);
		} catch (Exception refused) {
			// The whole call was refused (for example the daily limit): every stamp is cleared
			// below so the reminders are retried, not lost.
			lastFailure = refused.getMessage();
		}
		List<Membership_Term__c> unstamp = new List<Membership_Term__c>();
		for (Integer i = 0; i < terms.size(); i++) {
			if (i >= outcomes.size() || !outcomes[i].sent) {
				Membership_Term__c clear = new Membership_Term__c(Id = terms[i].Id);
				if (stampField != null) {
					clear.put(stampField, null);
				}
				unstamp.add(clear);
				lastFailure = i < outcomes.size() &&
					outcomes[i].error != null
					? outcomes[i].error
					: lastFailure;
			}
		}
		if (!unstamp.isEmpty()) {
			if (stampField != null) {
				update as system unstamp;
			}
			ErrorLogger.logMessage(
				BarnHelp.text(
					'Memberships',
					'Memberships_Error_SendFailed',
					new List<Object>{ unstamp.size(), terms.size(), lastFailure }
				),
				CONTEXT,
				ErrorLogger.SEVERITY_WARNING
			);
		}
		return terms.size() - unstamp.size();
	}
}
