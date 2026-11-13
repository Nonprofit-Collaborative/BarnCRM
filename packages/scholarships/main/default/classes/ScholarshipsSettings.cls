/**
 * The Scholarships settings as the module's code reads them (canonical model 29SG8), through
 * Core's typed `SettingsService` readers, which serve an org that never saved them the record its
 * first save would store (ADR-0035). A blank or out of range number reads as the field's declared
 * default, the range being its Setting Definition's.
 */
public with sharing class ScholarshipsSettings {
	public static final String SETTINGS_OBJECT = 'Scholarships_Settings__c';

	/** Whether the nightly run sends reminders. Ships on. */
	public static Boolean remindersEnabled() {
		return SettingsService.flag(SETTINGS_OBJECT, 'Reminders_Enabled__c');
	}

	/** Whether the nightly run also emails recipients. Ships off. */
	public static Boolean emailRecipients() {
		return SettingsService.flag(SETTINGS_OBJECT, 'Email_Recipients__c');
	}

	/** Days ahead the program owner is reminded, 1 to 365. */
	public static Integer reminderDays() {
		return SettingsService.number(SETTINGS_OBJECT, 'Reminder_Days__c').intValue();
	}
}
