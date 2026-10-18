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
        Object stored = read('Shift_Horizon_Weeks__c');
        if (stored == null) {
            return DEFAULT_SHIFT_HORIZON_WEEKS;
        }
        Integer weeks;
        try {
            weeks = Decimal.valueOf(String.valueOf(stored)).intValue();
        } catch (TypeException unreadable) {
            return DEFAULT_SHIFT_HORIZON_WEEKS;
        }
        if (weeks < MIN_SHIFT_HORIZON_WEEKS || weeks > MAX_SHIFT_HORIZON_WEEKS) {
            return DEFAULT_SHIFT_HORIZON_WEEKS;
        }
        return weeks;
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
