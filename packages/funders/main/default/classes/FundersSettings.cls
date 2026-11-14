/**
 * The Funders settings as the module's code reads them (canonical model 29ZJ).
 *
 * Read through Core's typed `SettingsService` readers, which serve an org that has never saved
 * its Funders Settings the record its first save would store (ADR-0035). A blank or out of range
 * value reads as the field's declared default, the range being its Setting Definition's (R-FS1),
 * so no caller has to know the defaults.
 */
public with sharing class FundersSettings {
	public static final String SETTINGS_OBJECT = 'Funders_Settings__c';

	/** R-GQ3: whether the morning job makes a task for each requirement coming due. Ships on. */
	public static Boolean reminderTasksEnabled() {
		return SettingsService.flag(SETTINGS_OBJECT, 'Reminder_Tasks_Enabled__c');
	}

	/** R-GQ3: whether the morning job also emails the person reminded. Ships off. */
	public static Boolean reminderEmailsEnabled() {
		return SettingsService.flag(SETTINGS_OBJECT, 'Reminder_Emails_Enabled__c');
	}

	/** R-FS1: how many days before a requirement is due its reminder goes out, 1 to 90. */
	public static Integer reminderLeadDays() {
		return SettingsService.number(SETTINGS_OBJECT, 'Reminder_Lead_Days__c').intValue();
	}

	/** R-FS2: whether the Grant Finder tab searches Grants.gov. Ships on. */
	public static Boolean grantFinderEnabled() {
		return SettingsService.flag(SETTINGS_OBJECT, 'Grant_Finder_Enabled__c');
	}

	/** R-FS2: how many days before a renewable award ends its Renewal requirement is due, 1 to 365. */
	public static Integer renewalLeadDays() {
		return SettingsService.number(SETTINGS_OBJECT, 'Renewal_Lead_Days__c').intValue();
	}
}
