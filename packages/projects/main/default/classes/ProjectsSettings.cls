/**
 * The Project Management settings as the module's code reads them (canonical model 29PM7),
 * through Core's `SettingsService`, which serves an org that never saved them the record its
 * first save would store (ADR-0035). A blank or out of range number reads as its default.
 */
public with sharing class ProjectsSettings {
	public static final String SETTINGS_OBJECT = 'Projects_Settings__c';

	/** Whether Log Time, budgets, utilization and the billable export show. Ships on. */
	public static Boolean timeTracking() {
		Object stored = read('Time_Tracking_Enabled__c');
		return stored == null ? true : Boolean.valueOf(String.valueOf(stored));
	}

	/** Days past due before an open task puts its project At Risk. */
	public static Integer atRiskDays() {
		return number('At_Risk_Days__c', 7, 365);
	}

	/** The share of Budget Hours that, once used, puts a project At Risk. */
	public static Integer budgetWarningPercent() {
		return number('Budget_Warning_Percent__c', 90, 100);
	}

	/** One person's working hours in a week. */
	public static Integer weeklyCapacity() {
		return number('Weekly_Capacity_Hours__c', 40, 168);
	}

	private static Integer number(String key, Integer shipped, Integer max) {
		Object stored = read(key);
		Integer value;
		try {
			value = stored == null ? null : Decimal.valueOf(String.valueOf(stored)).intValue();
		} catch (TypeException unreadable) {
			value = null;
		}
		return value == null || value < 1 || value > max ? shipped : value;
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
