/**
 * The Event Management settings as the module's code reads them (canonical model 29EV25).
 *
 * Read through Core's `SettingsService`. A blank value reads as null, which every caller takes
 * as "send no email".
 */
public with sharing class EventsSettings {
	public static final String SETTINGS_OBJECT = 'Events_Settings__c';

	/** R-SA5: the developer name of the email template for an accepted application, or null. */
	public static String acceptNoticeTemplate() {
		return read('Accept_Notice_Template__c');
	}

	/** R-SA5: the developer name of the email template for a declined application, or null. */
	public static String declineNoticeTemplate() {
		return read('Decline_Notice_Template__c');
	}

	/** A setting that cannot be read is treated as never saved: no template. */
	private static String read(String key) {
		try {
			Object stored = SettingsService.getValue(SETTINGS_OBJECT, key);
			String value = stored == null ? null : String.valueOf(stored).trim();
			return String.isBlank(value) ? null : value;
		} catch (SettingsService.SettingsException unreadable) {
			return null;
		}
	}
}
