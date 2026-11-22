/**
 * Fundraising's run state: last runs and their summaries, the donor level recalculation time and
 * Books Closed Through (ADR-0238 settings as custom metadata, decisions 6 and 11). Nobody chooses
 * these in BarnCRM Settings, so they are `SettingsState` rows named `Giving.<Name>`, written
 * synchronously in system mode by the run or page that owns each, and never saved as settings.
 * A name is the legacy `Giving_Settings__c` field it replaces, so an org that has not carried
 * its settings over keeps reading the legacy value until then.
 *
 * Every caller carries its own authorization (a run it started, or a page check such as Manage
 * BarnCRM Settings); this class adds no permission of its own.
 */
public with sharing class GivingState {
	private static final String PREFIX = 'Giving';
	private static final Integer SUMMARY_LIMIT = 255;

	public static final String ACKNOWLEDGMENTS_LAST_RUN = 'Acknowledgments_Last_Run__c';
	public static final String ACKNOWLEDGMENTS_SUMMARY = 'Acknowledgments_Last_Run_Summary__c';
	public static final String ASK_REMINDERS_LAST_RUN = 'Ask_Reminders_Last_Run__c';
	public static final String ASK_REMINDERS_SUMMARY = 'Ask_Reminders_Last_Run_Summary__c';
	public static final String BOOKS_CLOSED_THROUGH = 'Books_Closed_Through__c';
	public static final String DONOR_LEVELS_RECALCULATED = 'Donor_Levels_Last_Recalculated__c';
	public static final String GIFT_TRANSACTION_MIRROR_LAST_RUN = 'Gift_Transaction_Mirror_Last_Run__c';
	public static final String GIFT_TRANSACTION_MIRROR_SUMMARY = 'Gift_Transaction_Mirror_Last_Summary__c';
	public static final String INSTALLMENT_OVERDUE_LAST_RUN = 'Installment_Overdue_Last_Run__c';
	public static final String INSTALLMENT_OVERDUE_SUMMARY = 'Installment_Overdue_Last_Run_Summary__c';
	public static final String INSTALLMENT_TOP_UP_LAST_RUN = 'Installment_Top_Up_Last_Run__c';
	public static final String INSTALLMENT_TOP_UP_SUMMARY = 'Installment_Top_Up_Last_Run_Summary__c';
	public static final String OPPORTUNITY_MIRROR_LAST_RUN = 'Opportunity_Mirror_Last_Run__c';
	public static final String OPPORTUNITY_MIRROR_SUMMARY = 'Opportunity_Mirror_Last_Summary__c';
	public static final String PLEDGE_REMINDERS_LAST_RUN = 'Pledge_Reminders_Last_Run__c';
	public static final String PLEDGE_REMINDERS_SUMMARY = 'Pledge_Reminders_Last_Run_Summary__c';

	/** The state row's key for one of the names above. */
	public static String key(String name) {
		return SettingsState.moduleKey(PREFIX, name);
	}

	/** Text held under the name, or null when blank. */
	public static String text(String name) {
		String value = SettingsState.text(key(name));
		return String.isBlank(value) ? null : value;
	}

	/** A date and time held under the name, or null. */
	public static Datetime moment(String name) {
		return SettingsState.moment(key(name));
	}

	/** A date held under the name (`yyyy-MM-dd`, or the legacy field's Date), or null. */
	public static Date dateValue(String name) {
		Object value = SettingsState.get(key(name));
		if (value == null || value instanceof Date) {
			return (Date) value;
		}
		try {
			return Date.valueOf(String.valueOf(value).trim().left(10));
		} catch (Exception unreadable) {
			return null;
		}
	}

	/** Records values by name in one synchronous write; a summary is cut to 255 characters. */
	public static void put(Map<String, Object> valuesByName) {
		Map<String, Object> byKey = new Map<String, Object>();
		for (String name : valuesByName.keySet()) {
			Object value = valuesByName.get(name);
			byKey.put(key(name), value instanceof String ? ((String) value).left(SUMMARY_LIMIT) : value);
		}
		SettingsState.put(byKey);
	}

	/** Records a run's completion time and summary under the two names given. */
	public static void recordRun(String runName, String summaryName, Datetime completedAt, String summary) {
		put(new Map<String, Object>{ runName => completedAt, summaryName => summary });
	}

	/**
	 * Locks the row of the name until this transaction ends and returns its value, creating the
	 * row when it has none (`SettingsState.lockOrCreate`), so two people changing it at once take
	 * turns. A wait that times out throws QueryException.
	 */
	public static Object lock(String name) {
		return SettingsState.lockOrCreate(key(name));
	}
}
