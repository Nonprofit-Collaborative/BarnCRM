/**
 * The Corporate Hub settings as the module's code reads them (canonical model 29CH6), through
 * Core's `SettingsService`, which serves an org that never saved them the record its first save
 * would store (ADR-0035). A blank or out of range number reads as the shipped 30.
 */
public with sharing class CorporateHubSettings {
	public static final String SETTINGS_OBJECT = 'Corporate_Hub_Settings__c';
	public static final Integer DEFAULT_DAYS = 30;

	/** Whether the nightly run sends reminders. Ships on. */
	public static Boolean remindersEnabled() {
		Object stored = read('Reminders_Enabled__c');
		return stored == null || Boolean.valueOf(String.valueOf(stored));
	}

	/** Days ahead an owner is reminded, where a record has no Reminder Days of its own. */
	public static Integer reminderDays() {
		return days('Reminder_Days__c');
	}

	/** Days a person has to acknowledge a policy. */
	public static Integer acknowledgmentDays() {
		return days('Acknowledgment_Days__c');
	}

	private static Integer days(String key) {
		Object stored = read(key);
		Integer value;
		try {
			value = stored == null ? null : Decimal.valueOf(String.valueOf(stored)).intValue();
		} catch (TypeException unreadable) {
			value = null;
		}
		return value == null || value < 1 || value > 365 ? DEFAULT_DAYS : value;
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
