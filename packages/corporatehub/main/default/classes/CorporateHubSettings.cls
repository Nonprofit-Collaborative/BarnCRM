/**
 * The Corporate Hub settings as the module's code reads them (canonical model 29CH6), through
 * Core's `ModuleSettings` by Setting Definition name (SET-03). A setting never saved reads its
 * shipped default, and a blank or out of range number reads as the default too, the range being
 * its Setting Definition's.
 */
public with sharing class CorporateHubSettings {
	/** Whether the board panel shows seats' age range and gender (CH-15). Ships off. */
	public static Boolean boardDemographics() {
		return ModuleSettings.flag('CorporateHub_Board_Demographics');
	}

	/** Whether the nightly run sends reminders. Ships on. */
	public static Boolean remindersEnabled() {
		return ModuleSettings.flag('CorporateHub_Reminders_Enabled');
	}

	/** Days ahead an owner is reminded, where a record has no Reminder Days of its own. */
	public static Integer reminderDays() {
		return ModuleSettings.integerValue('CorporateHub_Reminder_Days');
	}

	/** Days a person has to acknowledge a policy. */
	public static Integer acknowledgmentDays() {
		return ModuleSettings.integerValue('CorporateHub_Acknowledgment_Days');
	}
}
