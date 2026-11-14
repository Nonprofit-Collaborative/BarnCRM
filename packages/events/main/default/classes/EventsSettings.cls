/**
 * The Event Management settings as the module's code reads them (canonical model 29EV25).
 *
 * Read through Core's typed `SettingsService` readers, which serve an org that has never saved
 * its Events Settings the record its first save would store (ADR-0035). A blank or out of range
 * value reads as the field's declared default, the range being its Setting Definition's, so no
 * caller has to know the defaults. That includes the two speaker notice templates, which ship as
 * BarnCRM_Speaker_Accepted and BarnCRM_Speaker_Declined (R-ES1).
 */
public with sharing class EventsSettings {
	public static final String SETTINGS_OBJECT = 'Events_Settings__c';

	/** EV-20: whether a form registration that owes money waits for an online payment. Ships off. */
	public static Boolean onlinePayments() {
		return flag('Online_Payments__c');
	}

	/** EV-20: the payment link email template's unique name. */
	public static String paymentLinkTemplate() {
		return text('Payment_Link_Template__c');
	}

	/** R-SA5: the unique name of the email template for an accepted application. */
	public static String acceptNoticeTemplate() {
		return text('Accept_Notice_Template__c');
	}

	/** R-SA5: the unique name of the email template for a declined application. */
	public static String declineNoticeTemplate() {
		return text('Decline_Notice_Template__c');
	}

	/** Whether the morning run emails reminders. Ships off. */
	public static Boolean remindersEnabled() {
		return flag('Reminders_Enabled__c');
	}

	/** Whether the morning run emails follow-ups to those who attended. Ships off. */
	public static Boolean followUpsEnabled() {
		return flag('Follow_Ups_Enabled__c');
	}

	/** Whether the morning run marks people still Registered after an event as No-Show. Ships off. */
	public static Boolean markNoShows() {
		return flag('Mark_No_Shows__c');
	}

	/** R-AMS1: whether connected attendees may message each other in the attendee app. Ships off. */
	public static Boolean attendeeMessages() {
		return flag('Attendee_Messages__c');
	}

	/** R-AGI1: whether an overlapping agenda pick is let through and marked. Ships off. */
	public static Boolean allowAgendaOverlaps() {
		return flag('Allow_Agenda_Overlaps__c');
	}

	/** How many days before an event its reminder goes out, 1 to 30. */
	public static Integer reminderLeadDays() {
		return SettingsService.number(SETTINGS_OBJECT, 'Reminder_Lead_Days__c').intValue();
	}

	/** The reminder template's unique name. */
	public static String reminderTemplate() {
		return text('Reminder_Template__c');
	}

	/** The follow-up template's unique name. */
	public static String followUpTemplate() {
		return text('Follow_Up_Template__c');
	}

	/** The template a follow-up uses when the event has a survey (EV-18). */
	public static String surveyTemplate() {
		return text('Survey_Template__c');
	}

	/** The note shown beside a priced ticket on a public event page (EV-16); never blank. */
	public static String publicPaymentNote() {
		String note = text('Public_Payment_Note__c');
		return String.isBlank(note)
			? BarnHelp.text('Events', 'Events_Public_PaymentNoteDefault')
			: note;
	}

	private static String text(String key) {
		return SettingsService.text(SETTINGS_OBJECT, key);
	}

	private static Boolean flag(String key) {
		return SettingsService.flag(SETTINGS_OBJECT, key);
	}
}
