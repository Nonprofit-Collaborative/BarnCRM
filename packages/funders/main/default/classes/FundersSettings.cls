/**
 * The Funders settings as the module's code reads them (canonical model 29ZJ), through Core's
 * `ModuleSettings` by Setting Definition name (SET-03). A setting never saved reads its shipped
 * default, and a blank or out of range number reads as the default too, the range being its
 * Setting Definition's (R-FS1), so no caller has to know the defaults.
 */
public with sharing class FundersSettings {
	/** R-GQ3: whether the morning job makes a task for each requirement coming due. Ships on. */
	public static Boolean reminderTasksEnabled() {
		return ModuleSettings.flag('Funders_Reminder_Tasks_Enabled');
	}

	/** R-GQ3: whether the morning job also emails the person reminded. Ships off. */
	public static Boolean reminderEmailsEnabled() {
		return ModuleSettings.flag('Funders_Reminder_Emails_Enabled');
	}

	/** R-FS1: how many days before a requirement is due its reminder goes out, 1 to 90. */
	public static Integer reminderLeadDays() {
		return ModuleSettings.integerValue('Funders_Reminder_Lead_Days');
	}

	/** R-FS2: whether the Grant Finder tab searches Grants.gov. Ships on. */
	public static Boolean grantFinderEnabled() {
		return ModuleSettings.flag('Funders_Grant_Finder_Enabled');
	}

	/** R-FS2: how many days before a renewable award ends its Renewal requirement is due, 1 to 365. */
	public static Integer renewalLeadDays() {
		return ModuleSettings.integerValue('Funders_Renewal_Lead_Days');
	}
}
