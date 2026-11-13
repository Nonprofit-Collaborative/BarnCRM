/**
 * The Volunteers settings as the module's code reads them (canonical model Section 29N).
 *
 * Read through Core's typed `SettingsService` readers, which serve an org that has never saved
 * its Volunteer Settings the record its first save would store, so a checkbox that ships on reads
 * as on rather than as the false `getOrgDefaults()` hands back (ADR-0035). A blank or out of
 * range value reads as the field's declared default, the range being its Setting Definition's,
 * so no caller has to know the defaults.
 */
public with sharing class VolunteerSettings {
	public static final String SETTINGS_OBJECT = 'Volunteer_Settings__c';

	/** The milestones a stored list with no usable part falls back to (the field's default). */
	private static final List<Integer> DEFAULT_MILESTONES = new List<Integer>{
		25,
		50,
		100,
		250,
		500,
		1000
	};

	/**
	 * R-VG6: whether a new hours entry waits for a coordinator. On unless an administrator
	 * turned it off: guessing the other way would count hours nobody had checked.
	 */
	public static Boolean hoursRequireApproval() {
		return flag('Hours_Require_Approval__c');
	}

	/** R-VU3: whether marking a sign-up Attended writes the hours for its shift. */
	public static Boolean attendanceCreatesHours() {
		return flag('Attendance_Creates_Hours__c');
	}

	/** V-07: how many weeks ahead recurring schedules keep their shifts, 1 to 26. */
	public static Integer shiftHorizonWeeks() {
		return number('Shift_Horizon_Weeks__c').intValue();
	}

	/** V-10: whether signed-up volunteers get a reminder email before a shift. Off until turned on. */
	public static Boolean remindersEnabled() {
		return flag('Reminders_Enabled__c');
	}

	/** V-10: how many days before a shift its reminder goes out, 1 to 14. */
	public static Integer reminderLeadDays() {
		return number('Reminder_Lead_Days__c').intValue();
	}

	/** V-10b: whether volunteers are emailed about a shift that is still short. Off until turned on. */
	public static Boolean nudgesEnabled() {
		return flag('Nudges_Enabled__c');
	}

	/** V-10b: how many days before an unfilled shift its nudge goes out, 1 to 14. */
	public static Integer nudgeLeadDays() {
		return number('Nudge_Lead_Days__c').intValue();
	}

	/** V-12: the value of one volunteer hour, 0 to 9999.99; 0 hides every value (R-VP5). */
	public static Decimal hourValue() {
		return number('Hour_Value__c');
	}

	/** V-13: whether milestone and anniversary thank-you tasks are created. Off until turned on. */
	public static Boolean recognitionEnabled() {
		return flag('Recognition_Enabled__c');
	}

	/**
	 * V-13: the total hours that earn a thank-you, lowest first. A part that is not a whole
	 * number above 0 is ignored; with none left the shipped list applies.
	 */
	public static List<Integer> hourMilestones() {
		List<Integer> milestones = new List<Integer>();
		for (String part : SettingsService.text(SETTINGS_OBJECT, 'Hour_Milestones__c').split(',')) {
			if (part.trim().isNumeric() && Integer.valueOf(part.trim()) > 0) {
				milestones.add(Integer.valueOf(part.trim()));
			}
		}
		if (milestones.isEmpty()) {
			milestones = DEFAULT_MILESTONES.clone();
		}
		milestones.sort();
		return milestones;
	}

	/** V-14: whether a full shift waitlists new bookings (R-VU8). Off until turned on. */
	public static Boolean waitlistEnabled() {
		return flag('Waitlist_Enabled__c');
	}

	/** V-15: whether a minor's sign-up is flagged and gets a consent step (R-VU11). Off by default. */
	public static Boolean minorConsentRequired() {
		return flag('Minor_Consent_Required__c');
	}

	/** V-15: the age below which a volunteer is a minor, 1 to 21. */
	public static Integer minorAge() {
		return number('Minor_Age__c').intValue();
	}

	/** V-09: the self-service profile form's record identifier, or null when none is set (R-VU10). */
	public static Id profileFormId() {
		try {
			String stored = SettingsService.text(SETTINGS_OBJECT, 'Profile_Form_Key__c');
			return String.isBlank(stored) ? null : Id.valueOf(stored);
		} catch (StringException notAnId) {
			return null;
		}
	}

	private static Decimal number(String key) {
		return SettingsService.number(SETTINGS_OBJECT, key);
	}

	private static Boolean flag(String key) {
		return SettingsService.flag(SETTINGS_OBJECT, key);
	}
}
