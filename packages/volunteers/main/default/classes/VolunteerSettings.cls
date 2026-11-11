/**
 * The Volunteers settings as the module's code reads them (canonical model Section 29N).
 *
 * Read through Core's `SettingsService`, which serves an org that has never saved its
 * Volunteer Settings the record its first save would store, so a checkbox that ships on reads
 * as on rather than as the false `getOrgDefaults()` hands back (ADR-0035). A blank or out of
 * range value reads as the shipped one here, so no caller has to know the defaults.
 */
public with sharing class VolunteerSettings {
	public static final String SETTINGS_OBJECT = 'Volunteer_Settings__c';
	public static final Integer DEFAULT_SHIFT_HORIZON_WEEKS = 8;
	public static final Integer MIN_SHIFT_HORIZON_WEEKS = 1;
	public static final Integer MAX_SHIFT_HORIZON_WEEKS = 26;
	public static final Integer DEFAULT_REMINDER_LEAD_DAYS = 1;
	public static final Integer MIN_REMINDER_LEAD_DAYS = 1;
	public static final Integer MAX_REMINDER_LEAD_DAYS = 14;
	public static final Integer DEFAULT_NUDGE_LEAD_DAYS = 3;
	public static final Decimal DEFAULT_HOUR_VALUE = 34.79;
	public static final Integer DEFAULT_MINOR_AGE = 18;
	public static final List<Integer> DEFAULT_MILESTONES = new List<Integer>{
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
		return flag('Hours_Require_Approval__c', true);
	}

	/** R-VU3: whether marking a sign-up Attended writes the hours for its shift. */
	public static Boolean attendanceCreatesHours() {
		return flag('Attendance_Creates_Hours__c', true);
	}

	/** V-07: how many weeks ahead recurring schedules keep their shifts, 1 to 26. */
	public static Integer shiftHorizonWeeks() {
		return bounded(
				'Shift_Horizon_Weeks__c',
				DEFAULT_SHIFT_HORIZON_WEEKS,
				MIN_SHIFT_HORIZON_WEEKS,
				MAX_SHIFT_HORIZON_WEEKS
			)
			.intValue();
	}

	/** V-10: whether signed-up volunteers get a reminder email before a shift. Off until turned on. */
	public static Boolean remindersEnabled() {
		return flag('Reminders_Enabled__c', false);
	}

	/** V-10: how many days before a shift its reminder goes out, 1 to 14. */
	public static Integer reminderLeadDays() {
		return bounded(
				'Reminder_Lead_Days__c',
				DEFAULT_REMINDER_LEAD_DAYS,
				MIN_REMINDER_LEAD_DAYS,
				MAX_REMINDER_LEAD_DAYS
			)
			.intValue();
	}

	/** V-10b: whether volunteers are emailed about a shift that is still short. Off until turned on. */
	public static Boolean nudgesEnabled() {
		return flag('Nudges_Enabled__c', false);
	}

	/** V-10b: how many days before an unfilled shift its nudge goes out, 1 to 14. */
	public static Integer nudgeLeadDays() {
		return bounded(
				'Nudge_Lead_Days__c',
				DEFAULT_NUDGE_LEAD_DAYS,
				MIN_REMINDER_LEAD_DAYS,
				MAX_REMINDER_LEAD_DAYS
			)
			.intValue();
	}

	/** V-12: the value of one volunteer hour, 0 to 9999.99; 0 hides every value (R-VP5). */
	public static Decimal hourValue() {
		return bounded('Hour_Value__c', DEFAULT_HOUR_VALUE, 0, 9999.99);
	}

	/** V-13: whether milestone and anniversary thank-you tasks are created. Off until turned on. */
	public static Boolean recognitionEnabled() {
		return flag('Recognition_Enabled__c', false);
	}

	/**
	 * V-13: the total hours that earn a thank-you, lowest first. A part that is not a whole
	 * number above 0 is ignored; with none left the shipped list applies.
	 */
	public static List<Integer> hourMilestones() {
		Object stored = read('Hour_Milestones__c');
		List<Integer> milestones = new List<Integer>();
		for (String part : String.valueOf(stored == null ? '' : stored).split(',')) {
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
		return flag('Waitlist_Enabled__c', false);
	}

	/** V-15: whether a minor's sign-up is flagged and gets a consent step (R-VU11). Off by default. */
	public static Boolean minorConsentRequired() {
		return flag('Minor_Consent_Required__c', false);
	}

	/** V-15: the age below which a volunteer is a minor, 1 to 21. */
	public static Integer minorAge() {
		return bounded('Minor_Age__c', DEFAULT_MINOR_AGE, 1, 21).intValue();
	}

	/** V-09: the self-service profile form's record identifier, or null when none is set (R-VU10). */
	public static Id profileFormId() {
		Object stored = read('Profile_Form_Key__c');
		try {
			return stored == null ? null : Id.valueOf(String.valueOf(stored).trim());
		} catch (StringException notAnId) {
			return null;
		}
	}

	/** A number setting, or the shipped value when blank, unreadable or out of range. */
	private static Decimal bounded(String key, Decimal shipped, Decimal min, Decimal max) {
		Object stored = read(key);
		Decimal value;
		try {
			value = stored == null ? null : Decimal.valueOf(String.valueOf(stored));
		} catch (TypeException unreadable) {
			return shipped;
		}
		return value == null || value < min || value > max ? shipped : value;
	}

	private static Boolean flag(String key, Boolean shipped) {
		Object stored = read(key);
		if (stored == null) {
			return shipped;
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
