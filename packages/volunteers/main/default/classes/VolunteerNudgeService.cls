/**
 * "Still need you" nudges (V-10b): one email, once per shift, to the active volunteers who have
 * helped on the shift's job before, when the shift starts within the lead time and is still short.
 *
 * Sent through the platform's single email call, to the Contact's own address, so the org's
 * email limits apply and nothing outside Salesforce is needed. Nobody with Email Opt Out
 * checked, no address, or a sign-up of any status on the shift is emailed (the selector leaves
 * them out). At most `PER_REMAINING_SLOT` people per open slot, and `MAX_PER_SHIFT` per shift, are
 * written to, most hours on the job first, so an unfilled shift never mails the whole roster. A
 * shift stamped Nudge Sent On is never nudged again; clearing the stamp sends it again.
 */
public with sharing class VolunteerNudgeService {
	private static final String LOG_CONTEXT = 'VolunteerNudgeService';
	private static final String WHEN_FORMAT = 'EEEE, MMMM d, yyyy h:mm a';
	private static final String TIME_FORMAT = 'h:mm a';

	/** People written to per open slot. */
	public static final Integer PER_REMAINING_SLOT = 3;
	/** The most people written to for one shift. */
	public static final Integer MAX_PER_SHIFT = 25;

	/** One `Messaging.sendEmail` call for the chunk, partial success on; a test sends nothing. */
	@TestVisible
	private static EmailSender emailSender = new MessagingEmailSender();

	/** Whether a run should start: the module is on and the setting is on. */
	public static Boolean isActive() {
		return !ShiftScheduleService.isTurnedOff() && VolunteerSettings.nudgesEnabled();
	}

	/** How many people one shift's nudge goes to, from the slots it still needs. */
	public static Integer recipientCap(Decimal slotsRemaining) {
		if (slotsRemaining == null || slotsRemaining <= 0) {
			return 0;
		}
		return Math.min(MAX_PER_SHIFT, (slotsRemaining * PER_REMAINING_SLOT).intValue());
	}

	/**
	 * Stamps this chunk of due shifts, emails the people for the ones whose stamp saved, and
	 * clears the stamp again on a shift none of whose emails went out. Returns how many emails
	 * went out.
	 *
	 * Stamp first: a shift whose stamp cannot be saved is never emailed, because an email
	 * without its stamp would be sent again every morning until the shift.
	 */
	public static Integer nudge(List<Volunteer_Shift__c> shifts) {
		if (shifts == null || shifts.isEmpty() || !isActive()) {
			return 0;
		}
		Datetime now = ShiftScheduleService.now();
		List<Volunteer_Shift__c> stamps = new List<Volunteer_Shift__c>();
		for (Volunteer_Shift__c shift : shifts) {
			stamps.add(new Volunteer_Shift__c(Id = shift.Id, Nudge_Sent_On__c = now));
		}
		List<Database.SaveResult> stamped = Database.update(stamps, false, AccessLevel.SYSTEM_MODE);
		String zone = ShiftScheduleSelector.orgTimeZone();
		List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
		List<Id> messageShiftIds = new List<Id>();
		Integer held = 0;
		String stampFailure;
		for (Integer i = 0; i < shifts.size(); i++) {
			if (!stamped[i].isSuccess()) {
				held++;
				if (stampFailure == null && !stamped[i].getErrors().isEmpty()) {
					stampFailure = stamped[i].getErrors()[0].getMessage();
				}
				continue;
			}
			Volunteer_Shift__c shift = shifts[i];
			for (
				Contact person : VolunteerNudgeSelector.candidates(
					shift.Id,
					shift.Volunteer_Job__c,
					recipientCap(shift.Slots_Remaining__c)
				)
			) {
				messages.add(messageFor(shift, person, zone));
				messageShiftIds.add(shift.Id);
			}
		}
		if (held > 0) {
			ErrorLogger.logMessage(
				BarnHelp.text(
					'Volunteers',
					'Volunteers_Nudges_StampFailed',
					new List<Object>{
						held,
						shifts.size(),
						stampFailure == null ? '' : stampFailure
					}
				),
				LOG_CONTEXT,
				ErrorLogger.SEVERITY_WARNING
			);
		}
		if (messages.isEmpty()) {
			return 0;
		}
		return send(messages, messageShiftIds);
	}

	private static Integer send(List<Messaging.SingleEmailMessage> messages, List<Id> shiftIds) {
		List<EmailSendOutcome> outcomes = emailSender.send(messages);
		Set<Id> reached = new Set<Id>();
		Set<Id> tried = new Set<Id>(shiftIds);
		Integer went = 0;
		Integer notSent = 0;
		String lastFailure;
		for (Integer i = 0; i < messages.size(); i++) {
			if (i < outcomes.size() && outcomes[i].sent) {
				went++;
				reached.add(shiftIds[i]);
			} else {
				notSent++;
				if (i < outcomes.size() && outcomes[i].error != null) {
					lastFailure = outcomes[i].error;
				}
			}
		}
		List<Volunteer_Shift__c> unstamp = new List<Volunteer_Shift__c>();
		for (Id shiftId : tried) {
			if (!reached.contains(shiftId)) {
				// None went out: the stamp goes so tomorrow's run tries again while the shift is ahead.
				unstamp.add(new Volunteer_Shift__c(Id = shiftId, Nudge_Sent_On__c = null));
			}
		}
		if (!unstamp.isEmpty()) {
			Database.update(unstamp, false, AccessLevel.SYSTEM_MODE);
		}
		if (notSent > 0) {
			ErrorLogger.logMessage(
				BarnHelp.text(
					'Volunteers',
					'Volunteers_Nudges_SendFailed',
					new List<Object>{
						notSent,
						messages.size(),
						lastFailure == null ? '' : lastFailure
					}
				),
				LOG_CONTEXT,
				ErrorLogger.SEVERITY_WARNING
			);
		}
		return went;
	}

	/** One nudge, addressed to the person's Contact email. */
	@TestVisible
	private static Messaging.SingleEmailMessage messageFor(
		Volunteer_Shift__c shift,
		Contact person,
		String zone
	) {
		String jobName = shift.Volunteer_Job__r == null ? '' : shift.Volunteer_Job__r.Name;
		String whenText = shift.Start_Time__c.format(WHEN_FORMAT, zone);
		if (shift.End_Time__c != null) {
			whenText += ' - ' + shift.End_Time__c.format(TIME_FORMAT, zone);
		}
		String greeting = String.isBlank(person.FirstName)
			? System.Label.Volunteers_Reminders_GreetingNoName
			: String.format(
					BarnHelp.text('Volunteers', 'Volunteers_Reminders_Greeting'),
					new List<Object>{ person.FirstName }
			  );
		String body =
			greeting +
			'\n\n' +
			BarnHelp.text(
				'Volunteers',
				'Volunteers_Nudges_Body',
				new List<Object>{ jobName, whenText }
			);
		if (String.isNotBlank(shift.Location__c)) {
			body +=
				'\n' +
				String.format(
					BarnHelp.text('Volunteers', 'Volunteers_Reminders_Where'),
					new List<Object>{ shift.Location__c }
				);
		}
		body += '\n\n' + BarnHelp.text('Volunteers', 'Volunteers_Nudges_Closing');

		Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
		message.setToAddresses(new List<String>{ person.Email });
		message.setSubject(
			BarnHelp.text('Volunteers', 'Volunteers_Nudges_Subject', new List<Object>{ jobName })
		);
		message.setPlainTextBody(body);
		message.setSaveAsActivity(false);
		return message;
	}
}
