/**
 * The Memberships settings as the module's code reads them (canonical model 29MEM4), through
 * Core's typed `SettingsService` readers; a setting never saved, blank, out of range or unreadable
 * reads as the field's declared default.
 */
public with sharing class MembershipsSettings {
	public static final String SETTINGS_OBJECT = 'Memberships_Settings__c';
	public static final String PAYMENT_LINK_TEMPLATE = 'BarnCRM_Membership_Payment_Link';

	/** Whether the nightly run emails renewal reminders. Ships off. */
	public static Boolean remindersEnabled() {
		return SettingsService.flag(SETTINGS_OBJECT, 'Reminders_Enabled__c');
	}

	/** Whether gifts to a level's fund pay memberships. Ships on. */
	public static Boolean renewFromGifts() {
		return SettingsService.flag(SETTINGS_OBJECT, 'Renew_From_Gifts__c');
	}

	/** Days before the end a reminder goes, 1 to 365. */
	public static Integer reminderDays() {
		return SettingsService.number(SETTINGS_OBJECT, 'Reminder_Days__c').intValue();
	}

	/** The reminder template's unique name. */
	public static String reminderTemplate() {
		return SettingsService.text(SETTINGS_OBJECT, 'Reminder_Template__c');
	}
}
