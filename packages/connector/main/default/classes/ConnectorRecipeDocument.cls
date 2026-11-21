/**
 * The recipe document (canonical model R-CR1; design `integration-hub-design.md` Sections 3.2
 * and 3.4; security review F1 and F4): reading it, the checks a save makes, and the request
 * rules Call an App holds at save and again at run time. The browser twin is
 * `c/connectorRecipeRules`; this class is the one that counts.
 *
 * Release 1.31 (CN-02) builds the Manual trigger (Run Now and the Flow action) and the steps
 * Find, Create, Update, Create or Update, Call an App, If and Stop; release 1.32 (CN-03) the
 * Schedule and Record Change triggers (`ConnectorTriggers`), CN-09 Load Rows with an Import
 * Template (`ConnectorImportStep`), CN-04 the Webhook trigger and the Send to Webhook step
 * (`ConnectorWebhooks`), and CN-05 For Each, Wait and Change Data (`ConnectorControlSteps`). Any
 * other kind is refused. A step's `fill` lists keys an import left blank (R-CR13): while it holds
 * any, the step is a problem.
 */
public with sharing class ConnectorRecipeDocument {
	public static final Integer MAX_STEPS = 25;
	public static final Integer MAX_DEPTH = 2;
	public static final Integer MAX_LENGTH = 100000;
	public static final Integer MAX_CONDITIONS = 10;
	public static final Set<String> TRIGGERS = new Set<String>{ 'manual', 'schedule', 'record', 'webhook', 'appPoll' };
	public static final Set<String> STEP_KINDS = new Set<String>{
		'find',
		'create',
		'update',
		'upsert',
		'callApp',
		'sendWebhook',
		'if',
		'stop',
		'importRows',
		'forEach',
		'wait',
		'transform'
	};
	public static final Set<String> RECORD_KINDS = new Set<String>{ 'create', 'update', 'upsert' };
	/** The steps that make a request through a connection (F1, F4). */
	public static final Set<String> CALL_KINDS = new Set<String>{ 'callApp', 'sendWebhook' };
	public static final Set<String> METHODS = new Set<String>{ 'GET', 'POST', 'PUT', 'PATCH', 'DELETE' };
	public static final Set<String> OPERATORS = new Set<String>{
		'equals',
		'not equals',
		'contains',
		'does not contain',
		'starts with',
		'greater than',
		'less than',
		'is null',
		'is not null'
	};
	public static final Set<String> OUTCOMES = new Set<String>{ 'Succeeded', 'Skipped', 'Failed' };
	private static final Pattern STEP_ID = Pattern.compile('[A-Za-z0-9_]{1,20}');
	private static final Pattern PILL_PATH = Pattern.compile(
		'(trigger|steps|loop)(\\.[A-Za-z0-9_-]+(\\[[0-9]{1,3}\\])?){0,10}'
	);
	private static final Pattern SLOT_NAME = Pattern.compile('\\{([A-Za-z0-9_]{1,40})\\}');
	private static final Pattern QUERY_NAME = Pattern.compile('[A-Za-z0-9_.\\[\\]-]{1,100}');

	/** A refusal written for a person: shown as it is. */
	public class DocumentException extends Exception {
	}

	/** Reads a document; refuses one that is not JSON, too long or holds `{!` anywhere (F1). */
	public static Map<String, Object> parse(String source) {
		if (String.isBlank(source) || source.length() > MAX_LENGTH) {
			throw new DocumentException(BarnHelp.text('Connector', 'Connector_Recipe_ErrorUnreadable'));
		}
		Object raw;
		try {
			raw = JSON.deserializeUntyped(source);
		} catch (Exception unreadable) {
			raw = null;
		}
		if (!(raw instanceof Map<String, Object>)) {
			throw new DocumentException(BarnHelp.text('Connector', 'Connector_Recipe_ErrorUnreadable'));
		}
		// Serialized again, so a `{!` written with JSON escapes is caught as well.
		if (JSON.serialize(raw).contains('{!')) {
			throw new DocumentException(BarnHelp.text('Connector', 'Connector_Recipe_ErrorMergeField'));
		}
		return (Map<String, Object>) raw;
	}

	/** Every problem a save refuses, in words; empty when the document may be saved. */
	public static List<String> problems(Map<String, Object> document) {
		List<String> found = new List<String>();
		if (document.get('version') != 1) {
			found.add(BarnHelp.text('Connector', 'Connector_Recipe_ErrorUnreadable'));
			return found;
		}
		Map<String, Object> starter = mapOf(document.get('trigger'));
		if (!TRIGGERS.contains(textOf(starter.get('kind')))) {
			found.add(BarnHelp.text('Connector', 'Connector_Recipe_ErrorTrigger'));
		} else if (ConnectorTriggers.problem(starter) != null) {
			found.add(ConnectorTriggers.problem(starter));
		}
		Set<String> ids = new Set<String>();
		Integer count = checkSteps(listOf(document.get('steps')), 1, false, ids, found);
		if (count == 0) {
			found.add(BarnHelp.text('Connector', 'Connector_Recipe_ErrorNoSteps'));
		}
		if (count > MAX_STEPS) {
			found.add(BarnHelp.text('Connector', 'Connector_Recipe_ErrorTooManySteps'));
		}
		return found;
	}

	private static Integer checkSteps(
		List<Object> steps,
		Integer depth,
		Boolean inLoop,
		Set<String> ids,
		List<String> found
	) {
		Integer count = 0;
		for (Object raw : steps) {
			Map<String, Object> step = mapOf(raw);
			count++;
			String id = textOf(step.get('id'));
			String label = String.isBlank(id) ? String.valueOf(count) : id;
			List<Object> at = new List<Object>{ label };
			if (!STEP_ID.matcher(id).matches() || !ids.add(id.toLowerCase())) {
				found.add(BarnHelp.text('Connector', 'Connector_Recipe_ErrorStepId', at));
			}
			String kind = textOf(step.get('kind'));
			if (!STEP_KINDS.contains(kind)) {
				found.add(BarnHelp.text('Connector', 'Connector_Recipe_ErrorStepKind', at));
				continue;
			}
			String problem = CALL_KINDS.contains(kind) ? callProblem(step, at) : stepProblem(kind, step, at);
			if (problem != null) {
				found.add(problem);
			}
			if (!listOf(step.get('fill')).isEmpty()) {
				found.add(BarnHelp.text('Connector', 'Connector_Recipe_ErrorFill', at));
			}
			if (inLoop && ConnectorControlSteps.NOT_IN_LOOP.contains(kind)) {
				found.add(BarnHelp.text('Connector', 'Connector_Recipe_ErrorInLoop', at));
			}
			if (kind == 'if' || kind == 'forEach') {
				// An If or For Each inside another is the deepest allowed (design Section 3.4).
				if (depth > MAX_DEPTH) {
					found.add(BarnHelp.text('Connector', 'Connector_Recipe_ErrorNesting', at));
				}
				Boolean looped = inLoop || kind == 'forEach';
				for (String branch : BRANCHES) {
					count += checkSteps(listOf(step.get(branch)), depth + 1, looped, ids, found);
				}
			}
		}
		return count;
	}

	/** What is wrong with one Find, record, If or Stop step, in words naming it, or null. */
	private static String stepProblem(String kind, Map<String, Object> step, List<Object> at) {
		if (kind == 'importRows') {
			return ConnectorImportStep.problem(step, at);
		}
		if (ConnectorControlSteps.KINDS.contains(kind)) {
			return ConnectorControlSteps.problem(kind, step, at);
		}
		if (kind == 'find') {
			if (mapOf(step.get('query')).get('object') == null) {
				return BarnHelp.text('Connector', 'Connector_Recipe_ErrorFind', at);
			}
			for (Object raw : listOf(step.get('values'))) {
				if (!isPath(textOf(mapOf(raw).get('path')))) {
					return BarnHelp.text('Connector', 'Connector_Recipe_ErrorPath', at);
				}
			}
			return null;
		}
		if (RECORD_KINDS.contains(kind)) {
			if (!isId(textOf(step.get('map')))) {
				return BarnHelp.text('Connector', 'Connector_Recipe_ErrorMap', at);
			}
			if (String.isNotBlank(textOf(step.get('input'))) && !isPath(textOf(step.get('input')))) {
				return BarnHelp.text('Connector', 'Connector_Recipe_ErrorPath', at);
			}
			return kind == 'update' && !isPath(textOf(step.get('recordId')))
				? BarnHelp.text('Connector', 'Connector_Recipe_ErrorRecordId', at)
				: null;
		}
		if (kind == 'if') {
			List<Object> conditions = listOf(step.get('conditions'));
			Boolean bad = conditions.isEmpty() || conditions.size() > MAX_CONDITIONS;
			for (Object raw : conditions) {
				Map<String, Object> condition = mapOf(raw);
				bad |= !isPath(textOf(condition.get('path'))) || !OPERATORS.contains(textOf(condition.get('operator')));
			}
			return bad ? BarnHelp.text('Connector', 'Connector_Recipe_ErrorCondition', at) : null;
		}
		return OUTCOMES.contains(textOf(step.get('outcome'))) && textOf(step.get('message')).length() <= 255
			? null
			: BarnHelp.text('Connector', 'Connector_Recipe_ErrorStop', at);
	}

	/** Call an App's request rules for a request that is not a step: the App Poll trigger's (CN-13). */
	public static String callStepProblem(Map<String, Object> step) {
		return callProblem(step, new List<Object>{ textOf(step.get('id')) });
	}

	/**
	 * Call an App's and Send to Webhook's request rules (F1, F4): connection, method, path or an
	 * address read from the data (`urlFrom`, R-CR11), slots, query, headers, codes.
	 */
	private static String callProblem(Map<String, Object> step, List<Object> at) {
		String connection = textOf(step.get('connection'));
		if (!connection.startsWith(ConnectorConnections.PREFIX) || !Pattern.matches('[A-Za-z0-9_]{1,80}', connection)) {
			return BarnHelp.text('Connector', 'Connector_Recipe_ErrorConnection', at);
		}
		String kind = textOf(step.get('kind'));
		if (kind == 'callApp' && !METHODS.contains(textOf(step.get('method')))) {
			return BarnHelp.text('Connector', 'Connector_Recipe_ErrorMethod', at);
		}
		String path = textOf(step.get('path'));
		String urlFrom = textOf(step.get('urlFrom'));
		Boolean fromData = String.isNotBlank(urlFrom);
		if (
			fromData
				? !isPath(urlFrom) ||
				  String.isNotBlank(path) ||
				  !listOf(step.get('pathValues')).isEmpty() ||
				  !listOf(step.get('query')).isEmpty()
				: requestPathProblem(kind, path)
		) {
			return BarnHelp.text('Connector', 'Connector_Recipe_ErrorRequestPath', at);
		}
		Set<String> slots = new Set<String>();
		Matcher slot = SLOT_NAME.matcher(path);
		while (slot.find()) {
			slots.add(slot.group(1));
		}
		Boolean badSlot = false;
		for (Object raw : listOf(step.get('pathValues'))) {
			Map<String, Object> value = mapOf(raw);
			Boolean blank = String.isBlank(textOf(value.get('path'))) && String.isBlank(textOf(value.get('value')));
			badSlot |= !slots.remove(textOf(value.get('name'))) || blank || !valueOk(value);
		}
		if (badSlot || !slots.isEmpty()) {
			return BarnHelp.text('Connector', 'Connector_Recipe_ErrorSlot', at);
		}
		for (Object raw : listOf(step.get('query'))) {
			Map<String, Object> value = mapOf(raw);
			if (!QUERY_NAME.matcher(textOf(value.get('name'))).matches() || !valueOk(value)) {
				return BarnHelp.text('Connector', 'Connector_Recipe_ErrorQuery', at);
			}
		}
		for (Object raw : listOf(step.get('headers'))) {
			Map<String, Object> header = mapOf(raw);
			if (!headerNameOk(textOf(header.get('name'))) || !valueOk(header)) {
				return BarnHelp.text('Connector', 'Connector_Recipe_ErrorHeader', at);
			}
			if (literalSignIn(header)) {
				return BarnHelp.text(
					'Connector',
					'Connector_Recipe_ErrorSignInHeader',
					new List<Object>{ at[0], header.get('name') }
				);
			}
		}
		for (Object code : listOf(step.get('success'))) {
			if (!(code instanceof Integer) || (Integer) code < 100 || (Integer) code > 599) {
				return BarnHelp.text('Connector', 'Connector_Recipe_ErrorCodes', at);
			}
		}
		String bodyMap = textOf(step.get('bodyMap'));
		String bodyInput = textOf(step.get('bodyInput'));
		if ((String.isNotBlank(bodyMap) && !isId(bodyMap)) || (String.isNotBlank(bodyInput) && !isPath(bodyInput))) {
			return BarnHelp.text('Connector', 'Connector_Recipe_ErrorMap', at);
		}
		return null;
	}

	/**
	 * A header whose name says it signs in with a typed value (R-CR15): a recipe is readable by
	 * every Connector viewer, so such a value is refused at Save, never exported and never
	 * imported. A value read from the data (a path) stays allowed.
	 */
	public static Boolean literalSignIn(Map<String, Object> header) {
		return SIGN_IN_HEADER.matcher(textOf(header.get('name'))).matches() &&
			String.isBlank(textOf(header.get('path'))) &&
			String.isNotBlank(textOf(header.get('value')));
	}

	/** A header name that says it signs in. */
	public static final Pattern SIGN_IN_HEADER = Pattern.compile(
		'(?i).*(key|token|secret|auth|password|signature|session).*'
	);

	/** A header a recipe may set: never `Authorization` or another the auth kind or Salesforce sets (F1). */
	public static Boolean headerNameOk(String name) {
		try {
			ConnectorConnections.checkedHeaderName(name);
			return true;
		} catch (ConnectorConnections.ConnectorException refused) {
			return false;
		}
	}

	/** A name and either a literal value or a path, neither breaking a request line (F1, F4). */
	private static Boolean valueOk(Map<String, Object> entry) {
		String path = textOf(entry.get('path'));
		if (String.isNotBlank(path)) {
			return isPath(path);
		}
		return !unsafeValue(textOf(entry.get('value')));
	}

	/**
	 * True for a path Call an App may not append to `callout:` (F4): it must start with one `/`
	 * and hold no `@`, `\`, `{!`, `?`, `#`, white space, carriage return or line feed.
	 */
	public static Boolean pathProblem(String path) {
		return String.isBlank(path) ||
			path.length() > 1000 ||
			!path.startsWith('/') ||
			path.startsWith('//') ||
			path.contains('@') ||
			path.contains('\\') ||
			path.contains('{!') ||
			path.contains('?') ||
			path.contains('#') ||
			// Any whitespace, CR and LF included (a `.*\s.*` match misses them: `.` stops at a line end).
			path.containsWhitespace();
	}

	/** As `pathProblem`, but Send to Webhook may leave the path blank to post to the connection's own address. */
	public static Boolean requestPathProblem(String kind, String path) {
		return kind == 'sendWebhook' && String.isBlank(path) ? false : pathProblem(path);
	}

	/** True for a value no header, path or query may carry: `{!`, CR or LF (F1, F4). */
	public static Boolean unsafeValue(String value) {
		return value != null && (value.contains('{!') || value.contains('\r') || value.contains('\n'));
	}

	/** A data pill: `trigger` or `steps`, then at most 10 keys, each with an optional `[n]`. */
	public static Boolean isPath(String path) {
		return String.isNotBlank(path) && PILL_PATH.matcher(path).matches();
	}

	public static Set<String> connections(Map<String, Object> document) {
		Set<String> found = new Set<String>();
		// The App Poll trigger's connection (CN-13).
		String polled = textOf(mapOf(document.get('trigger')).get('connection'));
		if (String.isNotBlank(polled)) {
			found.add(polled);
		}
		for (Map<String, Object> step : allSteps(document)) {
			if (String.isNotBlank(textOf(step.get('connection')))) {
				found.add(textOf(step.get('connection')));
			}
		}
		return found;
	}

	/** Every step, nested ones included, in document order. */
	public static List<Map<String, Object>> allSteps(Map<String, Object> document) {
		List<Map<String, Object>> found = new List<Map<String, Object>>();
		collect(listOf(document.get('steps')), found);
		return found;
	}

	/** The keys that hold nested steps: an If's two branches and a For Each's steps. */
	public static final List<String> BRANCHES = new List<String>{ 'then', 'otherwise', 'do' };

	private static void collect(List<Object> steps, List<Map<String, Object>> found) {
		for (Object raw : steps) {
			Map<String, Object> step = mapOf(raw);
			found.add(step);
			for (String branch : BRANCHES) {
				collect(listOf(step.get(branch)), found);
			}
		}
	}

	/** A whole record Id: `instanceof Id` passes an 18 character value whose last 3 do not match. */
	public static Boolean isId(String value) {
		if (String.isBlank(value) || !(value instanceof Id)) {
			return false;
		}
		try {
			return Id.valueOf(value) != null;
		} catch (StringException malformed) {
			return false;
		}
	}

	public static Map<String, Object> mapOf(Object raw) {
		return raw instanceof Map<String, Object> ? (Map<String, Object>) raw : new Map<String, Object>();
	}

	public static List<Object> listOf(Object raw) {
		return raw instanceof List<Object> ? (List<Object>) raw : new List<Object>();
	}

	public static String textOf(Object raw) {
		return raw == null ? '' : String.valueOf(raw);
	}
}
