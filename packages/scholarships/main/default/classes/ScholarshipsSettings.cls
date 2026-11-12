/**
 * The Scholarships settings as the module's code reads them (canonical model 29SG8), through
 * Core's `SettingsService`, which serves an org that never saved them the record its first save
 * would store (ADR-0035). A blank or out of range number reads as the shipped 14.
 */
public with sharing class ScholarshipsSettings {
	public static final String SETTINGS_OBJECT = 'Scholarships_Settings__c';
	public static final Integer DEFAULT_DAYS = 14;

	/** Whether the nightly run sends reminders. Ships on. */
	public static Boolean remindersEnabled() {
		return flag('Reminders_Enabled__c', true);
	}

	/** Whether the nightly run also emails recipients. Ships off. */
	public static Boolean emailRecipients() {
		return flag('Email_Recipients__c', false);
	}

	/** Days ahead the program owner is reminded. */
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

	private static Boolean flag(String key, Boolean shipped) {
		Object stored = read(key);
		return stored == null ? shipped : Boolean.valueOf(String.valueOf(stored));
	}

	/** A setting that cannot be read is treated as never saved: the shipped value applies. */
	private static Object read(String key) {
		try {
			return SettingsService.getValue(SETTINGS_OBJECT, key);
		} catch (SettingsService.SettingsException unreadable) {
			return null;
		}
	}
}
