/**
 * The `archive` key of a saved query document (canonical model R-SQ18, ADR-0240 archive rules and
 * big object archive): its destination, schedule and Active switch, read, checked, written and
 * asked whether it is due on a day. Pure logic over JSON: no query, no DML.
 */
@NamespaceAccessible
public with sharing class ArchiveRules {
	public static final String KEY = 'archive';
	@NamespaceAccessible
	public static final String FILES = 'Files';
	@NamespaceAccessible
	public static final String BIG_OBJECT = 'BigObject';
	@NamespaceAccessible
	public static final String OFF_PLATFORM = 'OffPlatform';
	/** Every destination, in the order the panel lists them. */
	@NamespaceAccessible
	public static final List<String> DESTINATIONS = new List<String>{ FILES, BIG_OBJECT, OFF_PLATFORM };

	public static final String OFF = 'off';
	public static final String DAILY = 'daily';
	public static final String WEEKLY = 'weekly';
	public static final String MONTHLY = 'monthly';
	private static final Set<String> FREQUENCIES = new Set<String>{ OFF, DAILY, WEEKLY, MONTHLY };
	/** The latest day of the month a monthly rule may name: every month has it. */
	public static final Integer LAST_MONTH_DAY = 28;
	private static final Integer VERSION = 1;

	/** Raised for anything the person can fix; the message is for them. */
	@NamespaceAccessible
	public class ArchiveRuleException extends Exception {
	}

	/** A rule as the document keeps it and the panel edits it. */
	@NamespaceAccessible
	public class Rule {
		@AuraEnabled
		public String destination = FILES;
		@AuraEnabled
		public String frequency = OFF;
		/** 1 (Monday) to 7 (Sunday), for a weekly rule. */
		@AuraEnabled
		public Integer weekday;
		/** 1 to 28, for a monthly rule. */
		@AuraEnabled
		public Integer monthDay;
		@AuraEnabled
		public Boolean active = true;

		/** True when the nightly run may start this rule on some day. */
		@NamespaceAccessible
		public Boolean scheduled() {
			return active == true && frequency != OFF;
		}
	}

	/** The destination a stored value names: an empty or unknown one reads as Files. */
	@NamespaceAccessible
	public static String destinationOf(String value) {
		return DESTINATIONS.contains(value) ? value : FILES;
	}

	/** The rule a query document carries, or null when it is not an archive rule. */
	@NamespaceAccessible
	public static Rule of(String queryJson) {
		Map<String, Object> document = documentOf(queryJson);
		Object raw = document == null ? null : document.get(KEY);
		if (!(raw instanceof Map<String, Object>)) {
			return null;
		}
		Map<String, Object> stored = (Map<String, Object>) raw;
		Rule rule = new Rule();
		rule.destination = destinationOf(stringOf(stored.get('destination')));
		String frequency = stringOf(stored.get('frequency'));
		rule.frequency = FREQUENCIES.contains(frequency) ? frequency : OFF;
		rule.weekday = intOf(stored.get('weekday'));
		rule.monthDay = intOf(stored.get('monthDay'));
		rule.active = stored.get('active') != false;
		return rule;
	}

	/** Whether a query document carries the `archive` key. */
	@NamespaceAccessible
	public static Boolean isRule(String queryJson) {
		return of(queryJson) != null;
	}

	/**
	 * The document with this rule as its `archive` key, checked first; a null rule takes the key
	 * off. Every other key is kept as it was.
	 */
	@NamespaceAccessible
	public static String withRule(String queryJson, Rule rule) {
		Map<String, Object> document = documentOf(queryJson);
		if (document == null) {
			throw new ArchiveRuleException(BarnHelp.text('Core', 'Core_Find_ErrorNotFound'));
		}
		document.remove(KEY);
		if (rule != null) {
			check(rule);
			Map<String, Object> stored = new Map<String, Object>{
				'version' => VERSION,
				'destination' => rule.destination,
				'frequency' => rule.frequency,
				'active' => rule.active == true
			};
			if (rule.frequency == WEEKLY) {
				stored.put('weekday', rule.weekday);
			}
			if (rule.frequency == MONTHLY) {
				stored.put('monthDay', rule.monthDay);
			}
			document.put(KEY, stored);
		}
		return JSON.serialize(document);
	}

	/** Refuses a rule whose destination, frequency or day is not one the rule may hold. */
	@NamespaceAccessible
	public static void check(Rule rule) {
		if (rule == null || !DESTINATIONS.contains(rule.destination) || !FREQUENCIES.contains(rule.frequency)) {
			throw new ArchiveRuleException(BarnHelp.text('Core', 'Core_ArchiveRules_ErrorRule'));
		}
		if (rule.frequency == WEEKLY && (rule.weekday == null || rule.weekday < 1 || rule.weekday > 7)) {
			throw new ArchiveRuleException(BarnHelp.text('Core', 'Core_ArchiveRules_ErrorWeekday'));
		}
		if (rule.frequency == MONTHLY && (rule.monthDay == null || rule.monthDay < 1 || rule.monthDay > LAST_MONTH_DAY)) {
			throw new ArchiveRuleException(BarnHelp.text('Core', 'Core_ArchiveRules_ErrorMonthDay'));
		}
	}

	/** Whether the nightly run starts this rule on `day`: on, and due by its frequency. */
	@NamespaceAccessible
	public static Boolean isDue(Rule rule, Date day) {
		if (rule == null || day == null || !rule.scheduled()) {
			return false;
		}
		if (rule.frequency == DAILY) {
			return true;
		}
		if (rule.frequency == WEEKLY) {
			return weekdayOf(day) == rule.weekday;
		}
		return day.day() == rule.monthDay;
	}

	/** 1 (Monday) to 7 (Sunday). */
	@NamespaceAccessible
	public static Integer weekdayOf(Date day) {
		// Noon in GMT is the same calendar day in every time zone the format could apply.
		return Integer.valueOf(Datetime.newInstanceGmt(day, Time.newInstance(12, 0, 0, 0)).formatGmt('u'));
	}

	/** The next day on or after `fromDay` the rule is due, or null when it is not scheduled. */
	@NamespaceAccessible
	public static Date nextDue(Rule rule, Date fromDay) {
		if (rule == null || fromDay == null || !rule.scheduled()) {
			return null;
		}
		// A monthly rule is due within 31 days; a weekly one within 7.
		for (Integer offset = 0; offset <= 31; offset++) {
			Date candidate = fromDay.addDays(offset);
			if (isDue(rule, candidate)) {
				return candidate;
			}
		}
		return null;
	}

	private static Map<String, Object> documentOf(String queryJson) {
		if (String.isBlank(queryJson)) {
			return null;
		}
		try {
			Object parsed = JSON.deserializeUntyped(queryJson);
			return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : null;
		} catch (Exception notJson) {
			return null;
		}
	}

	private static String stringOf(Object value) {
		return value instanceof String ? (String) value : null;
	}

	private static Integer intOf(Object value) {
		if (value instanceof Integer) {
			return (Integer) value;
		}
		if (value instanceof Decimal) {
			return ((Decimal) value).intValue();
		}
		return null;
	}
}
