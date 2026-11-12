/**
 * The engagement score (C-64, canonical model Section 7A, ADR-0212 `0212-engagement-score.md`):
 * the settings, the module signals found by name, and the arithmetic.
 *
 * Each part is a share from 0 to 1 (R-ES2); the score is the weighted shares over the weights of
 * the parts that can be measured, times 100 (R-ES3). Activity is always measured; Gifts, Hours
 * and Events only when their module's signal is installed, so a Core-only org scores on activity
 * alone. A signal that is installed but cannot be built or answer throws, so the caller scores
 * no one rather than scoring people without it (R-ES4).
 */
public with sharing class EngagementScore {
	/** The classes modules register, asked in this order. */
	public static final List<String> SIGNAL_CLASSES = new List<String>{
		'GivingEngagementSignal',
		'VolunteersEngagementSignal',
		'EventsEngagementSignal'
	};

	public static final String ACTIVITY = 'Activity';
	private static final String MONTHS = 'Months';
	@TestVisible
	private static final String DEFAULT_WEIGHTS = 'Gifts 40, Hours 25, Events 20, Activity 15';
	@TestVisible
	private static final String DEFAULT_TARGETS = 'Gifts 1000, Hours 40, Events 4, Activity 90, Months 12';

	/** Injected by tests by class name, since no module is there to resolve. */
	@TestVisible
	private static Map<String, EngagementSignalExtension> overrides = new Map<String, EngagementSignalExtension>();

	/** Set by tests to see the org as having no signal beyond those injected. */
	@TestVisible
	private static Boolean noneForTest = false;

	/** Each class looked up so far this transaction, null when it is not installed. */
	private static Map<String, EngagementSignalExtension> found = new Map<String, EngagementSignalExtension>();

	/** Each part's weight, 0 or more, by part name. */
	public final Map<String, Decimal> weights;

	/** Each part's target, above 0, and Months, by name. */
	public final Map<String, Decimal> targets;

	/** True while the organization has scoring on (R-ES1). */
	public static Boolean isOn() {
		return BarnCRM_Settings__c.getOrgDefaults()?.Engagement_Score_Enabled__c == true;
	}

	/** The score as the organization's settings have it. */
	public EngagementScore() {
		this(
			BarnCRM_Settings__c.getOrgDefaults()?.Engagement_Score_Weights__c,
			BarnCRM_Settings__c.getOrgDefaults()?.Engagement_Score_Targets__c
		);
	}

	/** The score with these settings lines; a part missing or unreadable keeps its default. */
	@TestVisible
	private EngagementScore(String weightLine, String targetLine) {
		weights = read(weightLine, DEFAULT_WEIGHTS, false);
		targets = read(targetLine, DEFAULT_TARGETS, true);
		Integer window = targets.get(MONTHS).intValue();
		targets.put(MONTHS, Math.max(1, Math.min(window, 60)));
	}

	/** The window's first day for a run on this day. */
	public Date since(Date today) {
		return today.addMonths(-targets.get(MONTHS).intValue());
	}

	/**
	 * Each person's score, 0 to 100, on this day. The people need `LastActivityDate`. Throws when
	 * an installed signal cannot answer.
	 */
	public Map<Id, Integer> scores(List<Contact> people, Date today) {
		Map<String, Map<Id, Decimal>> totalsByPart = signalTotals(
			new Map<Id, Contact>(people).keySet(),
			since(today)
		);
		Decimal activityWeight = weights.get(ACTIVITY);
		Map<Id, Integer> scored = new Map<Id, Integer>();
		for (Contact person : people) {
			Decimal earned = activityWeight * activityShare(person.LastActivityDate, today);
			Decimal possible = activityWeight;
			for (String part : totalsByPart.keySet()) {
				Decimal total = totalsByPart.get(part).get(person.Id);
				earned +=
					weights.get(part) *
					Math.min(1, (total == null ? 0 : total) / targets.get(part));
				possible += weights.get(part);
			}
			scored.put(
				person.Id,
				possible == 0
					? 0
					: (earned * 100 / possible).round(System.RoundingMode.HALF_UP).intValue()
			);
		}
		return scored;
	}

	/** 1 on the day of the activity, falling evenly to 0 over the Activity days; 0 with none. */
	@TestVisible
	private Decimal activityShare(Date lastActivity, Date today) {
		if (lastActivity == null) {
			return 0;
		}
		Decimal days = Math.max(0, lastActivity.daysBetween(today));
		return Math.max(0, 1 - days / targets.get(ACTIVITY));
	}

	/** Every installed signal's totals by part, for parts the settings know. */
	private Map<String, Map<Id, Decimal>> signalTotals(Set<Id> contactIds, Date since) {
		Map<String, Map<Id, Decimal>> totalsByPart = new Map<String, Map<Id, Decimal>>();
		for (String className : SIGNAL_CLASSES) {
			EngagementSignalExtension signal = signalFor(className);
			String part = signal == null ? null : signal.key();
			if (part != null && weights.containsKey(part) && part != ACTIVITY) {
				Map<Id, Decimal> totals = signal.totals(new Set<Id>(contactIds), since);
				totalsByPart.put(part, totals == null ? new Map<Id, Decimal>() : totals);
			}
		}
		return totalsByPart;
	}

	private static EngagementSignalExtension signalFor(String className) {
		EngagementSignalExtension signal = overrides.get(className);
		if (signal != null || noneForTest == true) {
			return signal;
		}
		if (!found.containsKey(className)) {
			found.put(className, resolve(className));
		}
		return found.get(className);
	}

	private static EngagementSignalExtension resolve(String className) {
		Type signalType = NamespaceUtil.resolveType(className);
		if (signalType == null) {
			return null;
		}
		Object candidate = signalType.newInstance();
		if (candidate instanceof EngagementSignalExtension) {
			return (EngagementSignalExtension) candidate;
		}
		throw new SignalException(className + ' does not implement EngagementSignalExtension');
	}

	/** Name and number pairs over the defaults; weights 0 or more, targets above 0. */
	private static Map<String, Decimal> read(String line, String defaults, Boolean positive) {
		Map<String, Decimal> values = pairs(defaults);
		Map<String, Decimal> chosen = pairs(line);
		for (String part : chosen.keySet()) {
			Decimal value = chosen.get(part);
			if (values.containsKey(part) && (positive ? value > 0 : value >= 0)) {
				values.put(part, value);
			}
		}
		return values;
	}

	private static Map<String, Decimal> pairs(String line) {
		Map<String, Decimal> values = new Map<String, Decimal>();
		for (String pair : String.isBlank(line) ? new List<String>() : line.split('[,;]')) {
			List<String> words = pair.trim().split('\\s+');
			if (words.size() == 2 && words[1].isNumeric()) {
				values.put(words[0].toLowerCase().capitalize(), Decimal.valueOf(words[1]));
			}
		}
		return values;
	}

	/** An installed signal that cannot be used. */
	public class SignalException extends Exception {
	}
}
