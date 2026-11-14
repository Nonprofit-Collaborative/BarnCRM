/**
 * The form's rules on the server, which decides what counts (canonical model R-FS1; ADR-0175
 * `0175-forms-module.md`, decision 5): conditions, which questions show, answer checks and the
 * answers that count. The same rules as the framework-free `c/formRules` module the pages use,
 * held to the same cases (`formRules/__tests__/data/formVectors.json`, `FormRulesTest`).
 *
 * A definition is the parsed JSON (R-FM1) as untyped maps and lists, so nothing here depends on
 * Salesforce types and a definition the page saved is read exactly as it was written.
 */
public with sharing class FormRules {
	private static final Pattern EMAIL = Pattern.compile('^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$');
	private static final Pattern PHONE = Pattern.compile('^[+()0-9\\s.\\-x]+$');
	private static final Pattern DATE_TEXT = Pattern.compile('^\\d{4}-\\d{2}-\\d{2}$');
	private static final Integer MIN_PHONE_DIGITS = 7;
	/** The kinds of file a file question takes (C-42c): documents and pictures, nothing a browser runs. */
	public static final Set<String> FILE_TYPES = new Set<String>{
		'pdf',
		'jpg',
		'jpeg',
		'png',
		'gif',
		'heic',
		'doc',
		'docx',
		'xls',
		'xlsx',
		'csv',
		'txt',
		'rtf',
		'odt'
	};
	private static final Map<String, Integer> DEFAULT_MAX_LENGTH = new Map<String, Integer>{
		'text' => 255,
		'textarea' => 32768
	};

	/** Thrown for text that is not a definition. */
	public class DefinitionException extends Exception {
	}

	/** Reads a definition's JSON into maps and lists. */
	public static Map<String, Object> parse(String definitionJson) {
		Object parsed;
		try {
			parsed = JSON.deserializeUntyped(definitionJson);
		} catch (JSONException notJson) {
			parsed = null;
		}
		if (parsed instanceof Map<String, Object>) {
			return (Map<String, Object>) parsed;
		}
		throw new DefinitionException(BarnHelp.text('Forms', 'Forms_Definition_NotJson'));
	}

	/** A JSON object sent by a page or caller, such as answers, as a map: empty when it is not one. */
	public static Map<String, Object> jsonMap(String text) {
		Object parsed;
		try {
			parsed = String.isBlank(text) ? null : JSON.deserializeUntyped(text);
		} catch (JSONException notJson) {
			parsed = null;
		}
		return parsed instanceof Map<String, Object>
			? (Map<String, Object>) parsed
			: new Map<String, Object>();
	}

	/** The definition's steps, never null. */
	public static List<Map<String, Object>> steps(Map<String, Object> definition) {
		return maps(definition == null ? null : definition.get('steps'));
	}

	/** A step's fields, never null. */
	public static List<Map<String, Object>> fields(Map<String, Object> step) {
		return maps(step == null ? null : step.get('fields'));
	}

	/** Every field of the definition, in order. */
	public static List<Map<String, Object>> allFields(Map<String, Object> definition) {
		List<Map<String, Object>> found = new List<Map<String, Object>>();
		for (Map<String, Object> step : steps(definition)) {
			found.addAll(fields(step));
		}
		return found;
	}

	/** The definition's record entries, never null. */
	public static List<Map<String, Object>> records(Map<String, Object> definition) {
		return maps(definition == null ? null : definition.get('records'));
	}

	/** A list of JSON objects, skipping anything else in it. */
	public static List<Map<String, Object>> maps(Object value) {
		List<Map<String, Object>> found = new List<Map<String, Object>>();
		if (value instanceof List<Object>) {
			for (Object item : (List<Object>) value) {
				if (item instanceof Map<String, Object>) {
					found.add((Map<String, Object>) item);
				}
			}
		}
		return found;
	}

	/** Whether an answer counts as not given: missing, or only spaces. False is an answer. */
	public static Boolean isBlank(Object value) {
		return value == null || String.isBlank(String.valueOf(value));
	}

	private static String comparable(Object value) {
		if (value instanceof Boolean) {
			return String.valueOf(value);
		}
		return isBlank(value) ? '' : String.valueOf(value).trim().toLowerCase();
	}

	private static Decimal asNumber(Object value) {
		return isBlank(value) || value instanceof Boolean ? null : SettingsService.toNumber(value);
	}

	/** -1, 0 or 1 for numbers or dates, null for anything else. */
	private static Integer compare(Object left, Object right) {
		Decimal a = asNumber(left);
		Decimal b = asNumber(right);
		if (a != null && b != null) {
			return a == b ? 0 : (a < b ? -1 : 1);
		}
		String x = isBlank(left) ? '' : String.valueOf(left).trim();
		String y = isBlank(right) ? '' : String.valueOf(right).trim();
		if (DATE_TEXT.matcher(x).matches() && DATE_TEXT.matcher(y).matches()) {
			return x == y ? 0 : (x < y ? -1 : 1);
		}
		return null;
	}

	/** Whether a condition holds for these answers; no condition always holds. */
	public static Boolean evaluate(Object condition, Map<String, Object> answers) {
		if (!(condition instanceof Map<String, Object>)) {
			return condition == null;
		}
		Map<String, Object> test = (Map<String, Object>) condition;
		if (test.get('all') instanceof List<Object>) {
			for (Object part : (List<Object>) test.get('all')) {
				if (!evaluate(part, answers)) {
					return false;
				}
			}
			return true;
		}
		if (test.get('any') instanceof List<Object>) {
			for (Object part : (List<Object>) test.get('any')) {
				if (evaluate(part, answers)) {
					return true;
				}
			}
			return false;
		}
		Object value = answers == null ? null : answers.get(String.valueOf(test.get('field')));
		Object expected = test.get('value');
		switch on String.valueOf(test.get('op')) {
			when 'isBlank' {
				return isBlank(value);
			}
			when 'isNotBlank' {
				return !isBlank(value);
			}
			when 'equals' {
				return comparable(value) == comparable(expected);
			}
			when 'notEquals' {
				return comparable(value) != comparable(expected);
			}
			when 'contains' {
				return comparable(value).contains(comparable(expected));
			}
			when 'greaterThan' {
				return compare(value, expected) == 1;
			}
			when 'lessThan' {
				return compare(value, expected) == -1;
			}
			when else {
				return false;
			}
		}
	}

	/**
	 * Which questions show, by key: a question shows when its step does and its condition
	 * holds, reading a hidden question's answer as not given.
	 */
	public static Map<String, Boolean> visibility(
		Map<String, Object> definition,
		Map<String, Object> answers
	) {
		Map<String, Boolean> shown = new Map<String, Boolean>();
		Map<String, Object> counted = new Map<String, Object>();
		for (Map<String, Object> step : steps(definition)) {
			Boolean stepShows = evaluate(step.get('showWhen'), counted);
			for (Map<String, Object> field : fields(step)) {
				String key = String.valueOf(field.get('key'));
				Boolean fieldShows = stepShows && evaluate(field.get('showWhen'), counted);
				shown.put(key, fieldShows);
				if (fieldShows && answers != null) {
					counted.put(key, answers.get(key));
				}
			}
		}
		return shown;
	}

	/** The code of what is wrong with one answer, or null when nothing is. */
	public static String checkAnswer(Map<String, Object> field, Object value) {
		String type = String.valueOf(field.get('type'));
		Boolean required = field.get('required') == true;
		if (type == 'checkbox') {
			return required && !isTrue(value) ? 'mustTick' : null;
		}
		if (isBlank(value)) {
			return required ? 'required' : null;
		}
		String text = String.valueOf(value).trim();
		switch on type {
			when 'email' {
				return EMAIL.matcher(text).matches() ? null : 'badEmail';
			}
			when 'phone' {
				Boolean digits = text.replaceAll('[^0-9]', '').length() >= MIN_PHONE_DIGITS;
				return PHONE.matcher(text).matches() && digits ? null : 'badPhone';
			}
			when 'number' {
				return checkNumber(field, text);
			}
			when 'date' {
				return isDate(text) ? null : 'badDate';
			}
			when 'file' {
				// The answer is the file's name; the file itself is checked by FormFiles.
				String kind = text.substringAfterLast('.').toLowerCase();
				return FILE_TYPES.contains(kind) && text.length() <= 255 ? null : 'badFileType';
			}
			when 'picklist' {
				for (Map<String, Object> option : maps(field.get('options'))) {
					if (String.valueOf(option.get('value')) == text) {
						return null;
					}
				}
				return 'notAnOption';
			}
			when else {
				Decimal limitGiven = asNumber(field.get('maxLength'));
				Integer limitOf = limitGiven != null
					? limitGiven.intValue()
					: (DEFAULT_MAX_LENGTH.containsKey(type) ? DEFAULT_MAX_LENGTH.get(type) : 255);
				return text.length() > limitOf ? 'tooLong' : null;
			}
		}
	}

	private static String checkNumber(Map<String, Object> field, String text) {
		Decimal given = asNumber(text);
		if (given == null) {
			return 'badNumber';
		}
		Decimal min = asNumber(field.get('min'));
		Decimal max = asNumber(field.get('max'));
		if (min != null && given < min) {
			return 'belowMin';
		}
		if (max != null && given > max) {
			return 'aboveMax';
		}
		return null;
	}

	/** A real calendar date written YYYY-MM-DD. */
	public static Boolean isDate(String text) {
		if (text == null || !DATE_TEXT.matcher(text).matches()) {
			return false;
		}
		Integer year = Integer.valueOf(text.left(4));
		Integer month = Integer.valueOf(text.mid(5, 2));
		Integer day = Integer.valueOf(text.right(2));
		if (month < 1 || month > 12 || day < 1) {
			return false;
		}
		return day <= Date.daysInMonth(year, month);
	}

	private static Boolean isTrue(Object value) {
		return value == true || String.valueOf(value) == 'true';
	}

	/** The problem codes of every showing question, by field key. Empty when it can be sent. */
	public static Map<String, String> checkAll(
		Map<String, Object> definition,
		Map<String, Object> answers
	) {
		Map<String, Boolean> shown = visibility(definition, answers);
		Map<String, String> problems = new Map<String, String>();
		for (Map<String, Object> field : allFields(definition)) {
			String key = String.valueOf(field.get('key'));
			if (shown.get(key) == true) {
				String found = checkAnswer(field, answers == null ? null : answers.get(key));
				if (found != null) {
					problems.put(key, found);
				}
			}
		}
		return problems;
	}

	/**
	 * The answers that count: showing questions only, keys the form has only, text trimmed,
	 * numbers as numbers, a checkbox always true or false, blanks left out.
	 */
	public static Map<String, Object> countedAnswers(
		Map<String, Object> definition,
		Map<String, Object> answers
	) {
		Map<String, Boolean> shown = visibility(definition, answers);
		Map<String, Object> counted = new Map<String, Object>();
		for (Map<String, Object> field : allFields(definition)) {
			String key = String.valueOf(field.get('key'));
			if (shown.get(key) != true) {
				continue;
			}
			Object value = answers == null ? null : answers.get(key);
			String type = String.valueOf(field.get('type'));
			if (type == 'checkbox') {
				counted.put(key, isTrue(value));
			} else if (!isBlank(value)) {
				String text = String.valueOf(value).trim();
				Decimal numeric = type == 'number' ? asNumber(text) : null;
				counted.put(key, numeric != null ? (Object) numeric : (Object) text);
			}
		}
		return counted;
	}
}
