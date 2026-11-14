/**
 * The Corporate Hub settings as the module's code reads them (canonical model 29CH6), through
 * Core's typed `SettingsService` readers, which serve an org that never saved them the record its
 * first save would store (ADR-0035). A blank or out of range number reads as the field's
 * declared default, the range being its Setting Definition's.
 */
public with sharing class CorporateHubSettings {
	public static final String SETTINGS_OBJECT = 'Corporate_Hub_Settings__c';

	/** Whether the board panel shows seats' age range and gender (CH-15). Ships off. */
	public static Boolean boardDemographics() {
		return SettingsService.flag(SETTINGS_OBJECT, 'Board_Demographics__c');
	}

	/** Whether the nightly run sends reminders. Ships on. */
	public static Boolean remindersEnabled() {
		return SettingsService.flag(SETTINGS_OBJECT, 'Reminders_Enabled__c');
	}

	/** Days ahead an owner is reminded, where a record has no Reminder Days of its own. */
	public static Integer reminderDays() {
		return SettingsService.number(SETTINGS_OBJECT, 'Reminder_Days__c').intValue();
	}

	/** Days a person has to acknowledge a policy. */
	public static Integer acknowledgmentDays() {
		return SettingsService.number(SETTINGS_OBJECT, 'Acknowledgment_Days__c').intValue();
	}
}
