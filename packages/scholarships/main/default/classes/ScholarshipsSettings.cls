/**
 * The Scholarships settings as the module's code reads them (canonical model 29SG8), through
 * Core's `ModuleSettings` by Setting Definition name (SET-03). A setting never saved reads its
 * shipped default, and a blank or out of range number reads as the default too, the range being
 * its Setting Definition's.
 */
public with sharing class ScholarshipsSettings {
	/** Whether the nightly run sends reminders. Ships on. */
	public static Boolean remindersEnabled() {
		return ModuleSettings.flag('Scholarships_Reminders_Enabled');
	}

	/** Whether the nightly run also emails recipients. Ships off. */
	public static Boolean emailRecipients() {
		return ModuleSettings.flag('Scholarships_Email_Recipients');
	}

	/** Days ahead the program owner is reminded, 1 to 365. */
	public static Integer reminderDays() {
		return ModuleSettings.integerValue('Scholarships_Reminder_Days');
	}
}
