/**
 * The Event Management settings as the module's code reads them (canonical model 29EV25).
 *
 * Read through Core's `SettingsService`, which serves an org that has never saved its Events
 * Settings the record its first save would store (ADR-0035). A blank or out of range value reads
 * as the shipped one here, so no caller has to know the defaults. That includes the two speaker
 * notice templates, which ship as BarnCRM_Speaker_Accepted and BarnCRM_Speaker_Declined (R-ES1).
 */
public with sharing class EventsSettings {
	public static final String SETTINGS_OBJECT = 'Events_Settings__c';
	public static final Integer DEFAULT_REMINDER_LEAD_DAYS = 2;
	public static final Integer MIN_REMINDER_LEAD_DAYS = 1;
	public static final Integer MAX_REMINDER_LEAD_DAYS = 30;
	public static final String DEFAULT_REMINDER_TEMPLATE = 'BarnCRM_Event_Reminder';
	public static final String DEFAULT_FOLLOW_UP_TEMPLATE = 'BarnCRM_Event_Follow_Up';
	public static final String DEFAULT_ACCEPT_NOTICE_TEMPLATE = 'BarnCRM_Speaker_Accepted';
	public static final String DEFAULT_DECLINE_NOTICE_TEMPLATE = 'BarnCRM_Speaker_Declined';

	/** R-SA5: the unique name of the email template for an accepted application. */
	public static String acceptNoticeTemplate() {
		return textOr('Accept_Notice_Template__c', DEFAULT_ACCEPT_NOTICE_TEMPLATE);
	}

	/** R-SA5: the unique name of the email template for a declined application. */
	public static String declineNoticeTemplate() {
		return textOr('Decline_Notice_Template__c', DEFAULT_DECLINE_NOTICE_TEMPLATE);
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

	/** How many days before an event its reminder goes out, 1 to 30. */
	public static Integer reminderLeadDays() {
		Object stored = read('Reminder_Lead_Days__c');
		Integer days;
		try {
			days = stored == null ? null : Decimal.valueOf(String.valueOf(stored)).intValue();
		} catch (TypeException unreadable) {
			days = null;
		}
		if (days == null || days < MIN_REMINDER_LEAD_DAYS || days > MAX_REMINDER_LEAD_DAYS) {
			return DEFAULT_REMINDER_LEAD_DAYS;
		}
		return days;
	}

	/** The reminder template's unique name. */
	public static String reminderTemplate() {
		return textOr('Reminder_Template__c', DEFAULT_REMINDER_TEMPLATE);
	}

	/** The follow-up template's unique name. */
	public static String followUpTemplate() {
		return textOr('Follow_Up_Template__c', DEFAULT_FOLLOW_UP_TEMPLATE);
	}

	private static String textOr(String key, String shipped) {
		String value = textOrNull(key);
		return value == null ? shipped : value;
	}

	private static String textOrNull(String key) {
		Object stored = read(key);
		String value = stored == null ? null : String.valueOf(stored).trim();
		return String.isBlank(value) ? null : value;
	}

	private static Boolean flag(String key) {
		Object stored = read(key);
		if (stored == null) {
			return false;
		}
		if (stored instanceof Boolean) {
			return (Boolean) stored;
		}
		return Boolean.valueOf(String.valueOf(stored));
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
