/**
 * The Memberships settings as the module's code reads them (canonical model 29MEM4), through
 * Core's `SettingsService`; a setting never saved, blank or unreadable reads as its shipped value.
 */
public with sharing class MembershipsSettings {
	public static final String SETTINGS_OBJECT = 'Memberships_Settings__c';
	public static final Integer DEFAULT_DAYS = 30;
	public static final String DEFAULT_TEMPLATE = 'BarnCRM_Membership_Renewal';
	public static final String PAYMENT_LINK_TEMPLATE = 'BarnCRM_Membership_Payment_Link';

	/** Whether the nightly run emails renewal reminders. Ships off. */
	public static Boolean remindersEnabled() {
		Object stored = read('Reminders_Enabled__c');
		return stored != null && Boolean.valueOf(String.valueOf(stored));
	}

	/** Whether gifts to a level's fund pay memberships. Ships on. */
	public static Boolean renewFromGifts() {
		Object stored = read('Renew_From_Gifts__c');
		return stored == null || Boolean.valueOf(String.valueOf(stored));
	}

	/** Days before the end a reminder goes, 1 to 365. */
	public static Integer reminderDays() {
		Object stored = read('Reminder_Days__c');
		Integer value;
		try {
			value = stored == null ? null : Decimal.valueOf(String.valueOf(stored)).intValue();
		} catch (TypeException unreadable) {
			value = null;
		}
		return value == null || value < 1 || value > 365 ? DEFAULT_DAYS : value;
	}

	/** The reminder template's unique name. */
	public static String reminderTemplate() {
		Object stored = read('Reminder_Template__c');
		return stored == null || String.isBlank(String.valueOf(stored))
			? DEFAULT_TEMPLATE
			: String.valueOf(stored).trim();
	}

	private static Object read(String key) {
		try {
			return SettingsService.getValue(SETTINGS_OBJECT, key);
		} catch (SettingsService.SettingsException unreadable) {
			return null;
		}
	}
}
