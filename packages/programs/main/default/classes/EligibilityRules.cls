/**
 * Eligibility screening rules (P-14, canonical model Section 29ZA, R-EN8): the rules an admin
 * defines for a program, stored as JSON on the program, checked here and applied to an
 * enrollment's intake fields and its person's Contact fields (P-14b, `Contact__r.Birthdate`). Pure logic with no query or save, so it runs in any context. The
 * same rules are evaluated for the preview by the framework-free `eligibilityEngine.js` module in
 * the `eligibilityRules` panel (plan 9.9); the two must agree, and the tests in both carry the
 * same cases.
 *
 * Format (version 1):
 *   { "version": 1, "defaultResult": "Review", "defaultReason": "...",
 *     "rules": [ { "id": "r1", "all": [ { "field": "Referral_Source__c",
 *       "operator": "equals", "value": "Self" } ],
 *       "result": "Eligible|Not Eligible|Review", "reason": "...", "basis": "Income" } ] }
 * Rules are checked in order and the first whose conditions all hold decides; when none does the
 * default result decides.
 */
public with sharing class EligibilityRules {
	public static final String ELIGIBLE = 'Eligible';
	public static final String NOT_ELIGIBLE = 'Not Eligible';
	public static final String REVIEW = 'Review';
	public static final List<String> RESULTS = new List<String>{ ELIGIBLE, NOT_ELIGIBLE, REVIEW };
	public static final List<String> OPERATORS = new List<String>{
		'equals',
		'notEquals',
		'in',
		'notIn',
		'greaterThan',
		'greaterOrEqual',
		'lessThan',
		'lessOrEqual',
		'isBlank',
		'isNotBlank'
	};
	private static final Set<String> LIST_OPERATORS = new Set<String>{ 'in', 'notIn' };
	private static final Set<String> NO_VALUE_OPERATORS = new Set<String>{
		'isBlank',
		'isNotBlank'
	};
	public static final Integer MAX_RULES = 50;
	public static final Integer MAX_CONDITIONS = 10;
	public static final Integer MAX_REASON = 255;
	private static final Pattern NUMBER_PATTERN = Pattern.compile('-?\\d+(\\.\\d+)?');
	private static final Pattern DATE_PATTERN = Pattern.compile('\\d{4}-\\d{2}-\\d{2}');

	/** What screening decided, and why. `ruleId` is empty when the default decided. */
	public class Result {
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String reason;
		@AuraEnabled
		public String basis;
		@AuraEnabled
		public String ruleId;
	}

	/**
	 * The problems in these rules, each a sentence an admin can act on; empty when they are
	 * sound. Blank rules are sound: there is nothing to screen against. `allowedFields` (lower
	 * case API names) limits the fields the conditions may name; null skips that check.
	 */
	public static List<String> validate(String rulesJson, Set<String> allowedFields) {
		List<String> problems = new List<String>();
		if (String.isBlank(rulesJson)) {
			return problems;
		}
		Map<String, Object> root;
		try {
			root = (Map<String, Object>) JSON.deserializeUntyped(rulesJson);
		} catch (Exception notJson) {
			problems.add(BarnHelp.text('Programs', 'Programs_Elig_BadJson'));
			return problems;
		}
		if (root.containsKey('defaultResult') && !RESULTS.contains(text(root, 'defaultResult'))) {
			problems.add(BarnHelp.text('Programs', 'Programs_Elig_BadDefault'));
		}
		List<Object> rules = itemsOf(root, 'rules');
		if (rules.size() > MAX_RULES) {
			problems.add(
				String.format(
					BarnHelp.text('Programs', 'Programs_Elig_TooManyRules'),
					new List<String>{ String.valueOf(MAX_RULES) }
				)
			);
			return problems;
		}
		for (Integer i = 0; i < rules.size(); i++) {
			String position = String.valueOf(i + 1);
			if (!(rules[i] instanceof Map<String, Object>)) {
				problems.add(
					String.format(
						BarnHelp.text('Programs', 'Programs_Elig_BadRule'),
						new List<String>{ position }
					)
				);
				continue;
			}
			Map<String, Object> rule = (Map<String, Object>) rules[i];
			if (!RESULTS.contains(text(rule, 'result'))) {
				problems.add(
					String.format(
						BarnHelp.text('Programs', 'Programs_Elig_BadResult'),
						new List<String>{ position }
					)
				);
			}
			String reason = text(rule, 'reason');
			if (String.isBlank(reason) || reason.length() > MAX_REASON) {
				problems.add(
					String.format(
						BarnHelp.text('Programs', 'Programs_Elig_BadReason'),
						new List<String>{ position }
					)
				);
			}
			List<Object> conditions = itemsOf(rule, 'all');
			if (conditions.isEmpty() || conditions.size() > MAX_CONDITIONS) {
				problems.add(
					String.format(
						BarnHelp.text('Programs', 'Programs_Elig_BadConditions'),
						new List<String>{ position, String.valueOf(MAX_CONDITIONS) }
					)
				);
				continue;
			}
			for (Object item : conditions) {
				String problem = conditionProblem(item, allowedFields);
				if (problem != null) {
					problems.add(String.format(problem, new List<String>{ position }));
				}
			}
		}
		return problems;
	}

	/**
	 * The result of screening these values against these rules, or null when there are no rules
	 * (nothing to decide). `values` maps a field's API name to its plain value: text, a number, a
	 * Boolean, a date as `yyyy-MM-dd`, or null. Assumes the rules are sound.
	 */
	public static Result evaluate(String rulesJson, Map<String, Object> values) {
		if (String.isBlank(rulesJson)) {
			return null;
		}
		Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(rulesJson);
		List<Object> rules = itemsOf(root, 'rules');
		if (rules.isEmpty()) {
			return null;
		}
		Map<String, Object> byName = new Map<String, Object>();
		for (String key : (values == null ? new Map<String, Object>() : values).keySet()) {
			byName.put(key.toLowerCase(), values.get(key));
		}
		for (Object item : rules) {
			Map<String, Object> rule = (Map<String, Object>) item;
			Boolean all = true;
			for (Object condition : itemsOf(rule, 'all')) {
				if (!holds((Map<String, Object>) condition, byName)) {
					all = false;
					break;
				}
			}
			if (all) {
				Result result = new Result();
				result.status = text(rule, 'result');
				result.reason = text(rule, 'reason');
				result.basis = text(rule, 'basis');
				result.ruleId = text(rule, 'id');
				return result;
			}
		}
		Result result = new Result();
		String defaultResult = text(root, 'defaultResult');
		result.status = RESULTS.contains(defaultResult) ? defaultResult : REVIEW;
		String defaultReason = text(root, 'defaultReason');
		result.reason = String.isBlank(defaultReason)
			? BarnHelp.text('Programs', 'Programs_Elig_NoRuleMatched')
			: defaultReason;
		return result;
	}

	private static String conditionProblem(Object item, Set<String> allowedFields) {
		if (!(item instanceof Map<String, Object>)) {
			return BarnHelp.text('Programs', 'Programs_Elig_BadRule');
		}
		Map<String, Object> condition = (Map<String, Object>) item;
		String field = text(condition, 'field');
		if (
			String.isBlank(field) ||
			(allowedFields != null && !allowedFields.contains(field.toLowerCase()))
		) {
			return BarnHelp.text('Programs', 'Programs_Elig_BadField');
		}
		String operator = text(condition, 'operator');
		if (!OPERATORS.contains(operator)) {
			return BarnHelp.text('Programs', 'Programs_Elig_BadOperator');
		}
		if (NO_VALUE_OPERATORS.contains(operator)) {
			return null;
		}
		Object value = condition.get('value');
		if (LIST_OPERATORS.contains(operator)) {
			if (!(value instanceof List<Object>) || ((List<Object>) value).isEmpty()) {
				return BarnHelp.text('Programs', 'Programs_Elig_BadValue');
			}
		} else if (
			value == null ||
			value instanceof List<Object> ||
			value instanceof Map<String, Object> ||
			String.isBlank(String.valueOf(value))
		) {
			return BarnHelp.text('Programs', 'Programs_Elig_BadValue');
		}
		return null;
	}

	private static Boolean holds(Map<String, Object> condition, Map<String, Object> values) {
		String actual = normalized(values.get(text(condition, 'field').toLowerCase()));
		String operator = text(condition, 'operator');
		Object wanted = condition.get('value');
		if (operator == 'isBlank') {
			return actual == '';
		}
		if (operator == 'isNotBlank') {
			return actual != '';
		}
		if (LIST_OPERATORS.contains(operator)) {
			Boolean found = false;
			for (Object option : (List<Object>) wanted) {
				if (same(actual, normalized(option))) {
					found = true;
					break;
				}
			}
			return operator == 'in' ? found : !found;
		}
		String target = normalized(wanted);
		if (operator == 'equals') {
			return same(actual, target);
		}
		if (operator == 'notEquals') {
			return !same(actual, target);
		}
		Integer order = compare(actual, target);
		if (order == null) {
			return false;
		}
		return operator == 'greaterThan'
			? order > 0
			: operator == 'greaterOrEqual'
					? order >= 0
					: operator == 'lessThan' ? order < 0 : order <= 0;
	}

	/** A value as trimmed text; empty for null. Booleans read as true and false. */
	private static String normalized(Object value) {
		return value == null ? '' : String.valueOf(value).trim();
	}

	/** Numbers compare as numbers, anything else as text without regard to case. */
	private static Boolean same(String a, String b) {
		if (NUMBER_PATTERN.matcher(a).matches() && NUMBER_PATTERN.matcher(b).matches()) {
			return Decimal.valueOf(a) == Decimal.valueOf(b);
		}
		return a.toLowerCase() == b.toLowerCase();
	}

	/** Orders two numbers or two dates; null for anything else, which never satisfies an order. */
	private static Integer compare(String a, String b) {
		if (NUMBER_PATTERN.matcher(a).matches() && NUMBER_PATTERN.matcher(b).matches()) {
			Decimal left = Decimal.valueOf(a);
			Decimal right = Decimal.valueOf(b);
			return left == right ? 0 : left > right ? 1 : -1;
		}
		if (DATE_PATTERN.matcher(a).matches() && DATE_PATTERN.matcher(b).matches()) {
			return a == b ? 0 : a > b ? 1 : -1;
		}
		return null;
	}

	private static String text(Map<String, Object> source, String key) {
		Object value = source.get(key);
		return value == null ? null : String.valueOf(value);
	}

	private static List<Object> itemsOf(Map<String, Object> source, String key) {
		Object value = source.get(key);
		return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
	}
}
