/**
 * The Funders settings as the module's code reads them (canonical model 29ZJ).
 *
 * Read through Core's `SettingsService`, which serves an org that has never saved its Funders
 * Settings the record its first save would store, so a checkbox that ships on reads as on rather
 * than as the false `getOrgDefaults()` hands back (ADR-0035). A blank or out of range value reads
 * as the shipped one here (R-FS1), so no caller has to know the defaults.
 */
public with sharing class FundersSettings {
    public static final String SETTINGS_OBJECT = 'Funders_Settings__c';
    public static final Integer DEFAULT_REMINDER_LEAD_DAYS = 14;
    public static final Integer MIN_REMINDER_LEAD_DAYS = 1;
    public static final Integer MAX_REMINDER_LEAD_DAYS = 90;

    /** R-GQ3: whether the morning job makes a task for each requirement coming due. Ships on. */
    public static Boolean reminderTasksEnabled() {
        return flag('Reminder_Tasks_Enabled__c', true);
    }

    /** R-GQ3: whether the morning job also emails the person reminded. Ships on. */
    public static Boolean reminderEmailsEnabled() {
        return flag('Reminder_Emails_Enabled__c', true);
    }

    /** R-FS1: how many days before a requirement is due its reminder goes out, 1 to 90. */
    public static Integer reminderLeadDays() {
        Object stored = read('Reminder_Lead_Days__c');
        if (stored == null) {
            return DEFAULT_REMINDER_LEAD_DAYS;
        }
        Integer days;
        try {
            days = Decimal.valueOf(String.valueOf(stored)).intValue();
        } catch (TypeException unreadable) {
            return DEFAULT_REMINDER_LEAD_DAYS;
        }
        if (days < MIN_REMINDER_LEAD_DAYS || days > MAX_REMINDER_LEAD_DAYS) {
            return DEFAULT_REMINDER_LEAD_DAYS;
        }
        return days;
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
