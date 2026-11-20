/**
 * Runs one Connector Run's steps (canonical model R-CR1, R-CR5, R-RUN3, R-RUN4; design Sections
 * 3.4, 3.7, 4 and 5; security review F1, F4, F7). Steps already in the run's State are skipped,
 * so a continued or retried run never repeats one. Before a callout that would follow a record
 * write in this transaction, or when the transaction nears its limits, the run stops at that
 * step and is queued again (`CheckpointException`).
 *
 * Call an App builds every request from the recipe and data, never from typed addresses: the
 * endpoint is always `callout:<connection>` plus a checked path; any header, path, query or body
 * value carrying `{!` fails the step (F1); path and query values are URL-encoded (F4). No
 * header is kept, and only a failed step's response, trimmed to 2,000 characters, is logged.
 *
 * Inherited sharing: the runner calls it directly for user-mode recipes and through
 * `ConnectorRunStore.runInSystemMode` for a System recipe.
 */
public inherited sharing class ConnectorStepRunner {
	public static final Integer MAX_FOUND = 200;
	public static final Integer MAX_RESPONSE = 4000000;
	public static final Integer TRIMMED = 2000;
	public static final Integer TIMEOUT_MS = 30000;

	/** Stop this run here and continue it in a new transaction. */
	public class CheckpointException extends Exception {
	}

	/** Look again later: the run waits its minutes, keeping this step's progress (Load Rows, R-CR9). */
	public class WaitException extends Exception {
		public Map<String, Object> progress;
		public Integer minutes;
	}

	/** A Stop step's end. */
	public class StoppedException extends Exception {
		public String outcome;
	}

	/** A step that failed, in plain words, with the app's status and trimmed answer if any. */
	public class StepFailureException extends Exception {
		public Integer status;
		public String response;
		/** True for a failure that may pass: no answer, or 408, 429, 500, 502, 503, 504 (R-CR7). */
		public Boolean passing = false;
		/** The app's `Retry-After`, in seconds, when it sent one. */
		public Integer retryAfter;
	}

	/** HTTP statuses a later try may get past (R-CR7). */
	public static final Set<Integer> PASSING = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };

	/** Set when the run failed on a step a later try may get past, for the runner's retry. */
	public StepFailureException passingFailure;

	/** What one transaction has spent across runs (design Section 4). */
	public class Budget {
		public Long calloutMs = 0;
		public Boolean wrote = false;

		public Boolean low() {
			return Limits.getCallouts() >= 90 ||
				calloutMs >= 100000 ||
				Limits.getCpuTime() >= 45000 ||
				Limits.getQueries() >= 180 ||
				Limits.getDmlStatements() >= 140;
		}
	}

	private Connector_Run__c run;
	private Budget budget;
	private AccessLevel access;
	private Boolean isTest;
	private Boolean sendForReal = false;
	private Set<String> done = new Set<String>();
	private Map<String, Object> outputs = new Map<String, Object>();
	private Map<String, Object> data = new Map<String, Object>();
	private List<Object> log = new List<Object>();
	private Integer written = 0;
	/** Above 0 inside a For Each: steps there log only failures (R-CR12). */
	private Integer looping = 0;

	public ConnectorStepRunner(Connector_Run__c run, Budget budget) {
		this.run = run;
		this.budget = budget;
		this.access = run.Ran_As__c == ConnectorRecipes.RUN_AS_SYSTEM ? AccessLevel.SYSTEM_MODE : AccessLevel.USER_MODE;
		this.isTest = run.Is_Test__c == true;
	}

	/** Runs what is left of the run and sets its status, state, log and times; never throws. */
	public Connector_Run__c execute() {
		if (run.Started_At__c == null) {
			run.Started_At__c = Datetime.now();
		}
		Map<String, Object> state = ConnectorRecipeDocument.mapOf(parsed(run.State_JSON__c));
		for (Object id : ConnectorRecipeDocument.listOf(state.get('done'))) {
			done.add(String.valueOf(id));
		}
		outputs = ConnectorRecipeDocument.mapOf(state.get('steps'));
		log = ConnectorRecipeDocument.listOf(parsed(run.Step_Log_JSON__c));
		written = run.Records_Written__c == null ? 0 : run.Records_Written__c.intValue();
		Object input = parsed(run.Input_JSON__c);
		if (isTest && input instanceof Map<String, Object>) {
			Map<String, Object> wrapper = (Map<String, Object>) input;
			sendForReal = wrapper.get('sendForReal') == true;
			input = wrapper.get('sample');
		}
		data.put('trigger', input == null ? new Map<String, Object>() : input);
		data.put('steps', outputs);
		String status = ConnectorRunStore.SUCCEEDED;
		try {
			String source = isTest ? run.Recipe__r.Draft_JSON__c : run.Recipe__r.Definition_JSON__c;
			if (String.isBlank(source)) {
				throw failure(BarnHelp.text('Connector', 'Connector_Run_ErrorNoDefinition'));
			}
			walk(ConnectorRecipeDocument.listOf(ConnectorRecipeDocument.parse(source).get('steps')));
		} catch (CheckpointException paused) {
			status = ConnectorRunStore.QUEUED;
		} catch (WaitException waiting) {
			status = ConnectorRunStore.WAITING;
			run.Next_Attempt_At__c = Datetime.now().addMinutes(waiting.minutes);
		} catch (StoppedException stop) {
			status = stop.outcome;
			run.Error_Message__c = String.isBlank(stop.getMessage()) ? null : stop.getMessage().left(1000);
		} catch (StepFailureException failed) {
			status = ConnectorRunStore.FAILED;
			run.Error_Message__c = failed.getMessage().left(1000);
			passingFailure = failed.passing ? failed : null;
		} catch (ConnectorRecipeDocument.DocumentException refused) {
			status = ConnectorRunStore.FAILED;
			run.Error_Message__c = refused.getMessage().left(1000);
		}
		run.Status__c = status;
		run.Records_Written__c = written;
		Map<String, Object> saved = new Map<String, Object>{ 'done' => new List<String>(done), 'steps' => outputs };
		run.State_JSON__c = JSON.serialize(saved);
		run.Step_Log_JSON__c = JSON.serialize(log);
		if (
			run.State_JSON__c.length() > ConnectorRunStore.MAX_TEXT ||
			run.Step_Log_JSON__c.length() > ConnectorRunStore.MAX_TEXT
		) {
			run.State_JSON__c = null;
			run.Step_Log_JSON__c = run.Step_Log_JSON__c.left(ConnectorRunStore.MAX_TEXT);
			run.Status__c = ConnectorRunStore.FAILED;
			run.Error_Message__c = BarnHelp.text('Connector', 'Connector_Run_ErrorTooLarge');
		}
		if (run.Status__c != ConnectorRunStore.QUEUED && run.Status__c != ConnectorRunStore.WAITING) {
			run.Finished_At__c = Datetime.now();
		}
		return run;
	}

	/** Each step of a list in order, skipping the done ones; an If walks its chosen branch. */
	private void walk(List<Object> steps) {
		for (Object raw : steps) {
			Map<String, Object> step = ConnectorRecipeDocument.mapOf(raw);
			String id = ConnectorRecipeDocument.textOf(step.get('id'));
			if (done.contains(id)) {
				continue;
			}
			String kind = ConnectorRecipeDocument.textOf(step.get('kind'));
			if (kind == 'forEach') {
				loop(step, id);
				continue;
			}
			if (kind == 'if') {
				Map<String, Object> chosen = ConnectorRecipeDocument.mapOf(outputs.get(id));
				if (chosen.isEmpty()) {
					chosen = new Map<String, Object>{ 'branch' => holds(step) ? 'then' : 'otherwise' };
					outputs.put(id, chosen);
					entry(id, kind, 'succeeded', 0, null);
				}
				walk(ConnectorRecipeDocument.listOf(step.get(String.valueOf(chosen.get('branch')))));
				done.add(id);
				continue;
			}
			if (budget.low() || (ConnectorRecipeDocument.CALL_KINDS.contains(kind) && budget.wrote)) {
				throw new CheckpointException();
			}
			Long started = System.currentTimeMillis();
			try {
				outputs.put(id, perform(kind, step));
			} catch (StoppedException stop) {
				done.add(id);
				entry(id, kind, 'succeeded', 0, null);
				throw stop;
			} catch (CheckpointException paused) {
				throw paused;
			} catch (WaitException waiting) {
				outputs.put(id, waiting.progress);
				throw waiting;
			} catch (Exception problem) {
				// A failed step starts again from nothing on Retry.
				outputs.remove(id);
				StepFailureException failed = problem instanceof StepFailureException
					? (StepFailureException) problem
					: failure(plain(problem));
				run.Failed_Step__c = id;
				Map<String, Object> logged = entry(
					id,
					kind,
					'failed',
					System.currentTimeMillis() - started,
					failed.getMessage()
				);
				logged.put('status', failed.status);
				logged.put('response', failed.response == null ? null : failed.response.left(TRIMMED));
				throw failed;
			}
			done.add(id);
			Map<String, Object> logged = entry(
				id,
				kind,
				isTest ? 'tested' : 'succeeded',
				System.currentTimeMillis() - started,
				null
			);
			Map<String, Object> result = ConnectorRecipeDocument.mapOf(outputs.get(id));
			if (result.containsKey('id') && result.get('id') != null) {
				logged.put('ids', new List<Object>{ result.get('id') });
			}
			logged.put('status', result.get('status'));
			logged.put('mapVersion', result.remove('mapVersion'));
			if (result.containsKey('summary')) {
				logged.put('message', result.get('summary'));
			}
		}
	}

	private Map<String, Object> entry(String id, String kind, String outcome, Long ms, String message) {
		Map<String, Object> logged = new Map<String, Object>{
			'step' => id,
			'kind' => kind,
			'outcome' => outcome,
			'ms' => ms,
			'message' => message
		};
		if (looping == 0 || isTest || outcome == 'failed') {
			log.add(logged);
		}
		return logged;
	}

	/**
	 * For Each (R-CR12): its steps once per item, with `loop.item` and `loop.index`. The next
	 * item is kept as the step's progress before each item, so a checkpoint or a retry carries on
	 * there; finished items' step results are cleared, so the next item runs them afresh. Every
	 * 200 items, or near the limits, the run continues in a new transaction. A Test runs the
	 * first item only and keeps its results.
	 */
	private void loop(Map<String, Object> step, String id) {
		List<Object> inside = ConnectorRecipeDocument.listOf(step.get('do'));
		Set<String> innerIds = new Set<String>();
		for (
			Map<String, Object> each : ConnectorRecipeDocument.allSteps(new Map<String, Object>{ 'steps' => inside })
		) {
			innerIds.add(ConnectorRecipeDocument.textOf(each.get('id')));
		}
		List<Object> items;
		try {
			items = ConnectorControlSteps.itemsOf(pill(step.get('items')));
		} catch (StepFailureException failed) {
			run.Failed_Step__c = id;
			entry(id, 'forEach', 'failed', 0, failed.getMessage());
			throw failed;
		}
		if (isTest && items.size() > 1) {
			items = new List<Object>{ items[0] };
		}
		Object next = ConnectorRecipeDocument.mapOf(outputs.get(id)).get('next');
		Integer index = next == null ? 0 : Integer.valueOf(next);
		Integer pass = 0;
		looping++;
		try {
			while (index < items.size()) {
				outputs.put(id, new Map<String, Object>{ 'next' => index });
				data.put('loop', new Map<String, Object>{ 'item' => items[index], 'index' => index });
				walk(inside);
				index++;
				pass++;
				if (!isTest) {
					done.removeAll(innerIds);
					for (String each : innerIds) {
						outputs.remove(each);
					}
				}
				if (index < items.size() && (pass >= ConnectorControlSteps.CHECKPOINT_ITEMS || budget.low())) {
					outputs.put(id, new Map<String, Object>{ 'next' => index });
					throw new CheckpointException();
				}
			}
		} finally {
			looping--;
			data.remove('loop');
		}
		outputs.put(id, new Map<String, Object>{ 'count' => items.size() });
		done.add(id);
		entry(
			id,
			'forEach',
			isTest ? 'tested' : 'succeeded',
			0,
			BarnHelp.text('Connector', 'Connector_Run_ForEachDone', new List<Object>{ items.size() })
		);
	}

	private Object perform(String kind, Map<String, Object> step) {
		if (kind == 'find') {
			return find(step);
		}
		if (ConnectorRecipeDocument.RECORD_KINDS.contains(kind)) {
			return saveRecord(kind, step);
		}
		if (ConnectorRecipeDocument.CALL_KINDS.contains(kind)) {
			return callApp(kind, step);
		}
		if (kind == 'importRows') {
			Map<String, Object> loaded = ConnectorImportStep.perform(
				step,
				pill(step.get('rows')),
				ConnectorRecipeDocument.mapOf(outputs.get(ConnectorRecipeDocument.textOf(step.get('id')))),
				run,
				budget
			);
			written += ConnectorImportStep.written(loaded);
			return loaded;
		}
		if (kind == 'wait') {
			return ConnectorControlSteps.waitFor(
				step,
				ConnectorRecipeDocument.mapOf(outputs.get(ConnectorRecipeDocument.textOf(step.get('id')))),
				isTest
			);
		}
		if (kind == 'transform') {
			String input = ConnectorRecipeDocument.textOf(step.get('input'));
			return ConnectorControlSteps.transform(step, pill(String.isBlank(input) ? 'trigger' : input), access);
		}
		StoppedException stop = new StoppedException(ConnectorRecipeDocument.textOf(step.get('message')));
		stop.outcome = ConnectorRecipeDocument.textOf(step.get('outcome'));
		throw stop;
	}

	// ---------------------------------------------------------------------------------------
	// Find Records
	// ---------------------------------------------------------------------------------------

	/** The step's query document with values from earlier steps, run in the run's access mode. */
	private Object find(Map<String, Object> step) {
		Map<String, Object> query = ConnectorRecipeDocument.mapOf(
			JSON.deserializeUntyped(JSON.serialize(step.get('query')))
		);
		Map<String, Object> filter = ConnectorRecipeDocument.mapOf(query.get('filter'));
		for (Object raw : ConnectorRecipeDocument.listOf(step.get('values'))) {
			Map<String, Object> value = ConnectorRecipeDocument.mapOf(raw);
			for (Object condition : ConnectorRecipeDocument.listOf(filter.get('conditions'))) {
				Map<String, Object> each = ConnectorRecipeDocument.mapOf(condition);
				if (String.valueOf(each.get('id')) == String.valueOf(value.get('condition'))) {
					each.put('value', ConnectorMapRuntime.text(pill(value.get('path'))));
				}
			}
		}
		Object most = query.get('limit');
		query.put('limit', most instanceof Integer && (Integer) most < MAX_FOUND ? most : MAX_FOUND);
		QueryCompiler.Compiled compiled = QueryCompiler.compile(JSON.serialize(query));
		List<SObject> rows;
		if (access == AccessLevel.USER_MODE) {
			rows = QueryCompiler.run(compiled);
		} else {
			List<String> fields = new List<String>{ 'Id' };
			for (Object field : ConnectorRecipeDocument.listOf(query.get('fields'))) {
				if (String.valueOf(field).toLowerCase() != 'id') {
					fields.add(String.valueOf(field));
				}
			}
			Map<String, Object> binds = new Map<String, Object>(compiled.binds);
			binds.put('connectorMost', query.get('limit'));
			rows = Database.queryWithBinds(
				'SELECT ' + String.join(fields, ', ') + compiled.fromWhere + ' LIMIT :connectorMost',
				binds,
				AccessLevel.SYSTEM_MODE
			);
		}
		List<Object> records = new List<Object>();
		for (Object row : (List<Object>) JSON.deserializeUntyped(JSON.serialize(rows))) {
			records.add(withoutAttributes(row));
		}
		if (records.isEmpty() && step.get('stopIfNone') == true) {
			StoppedException stop = new StoppedException(BarnHelp.text('Connector', 'Connector_Run_NoneFound'));
			stop.outcome = ConnectorRunStore.SKIPPED;
			throw stop;
		}
		return new Map<String, Object>{ 'count' => records.size(), 'records' => records };
	}

	/** A record as untyped JSON without Salesforce's `attributes`; also the clock's polled rows. */
	public static Object withoutAttributes(Object raw) {
		if (raw instanceof Map<String, Object>) {
			Map<String, Object> row = (Map<String, Object>) raw;
			row.remove('attributes');
			for (String key : new List<String>(row.keySet())) {
				row.put(key, withoutAttributes(row.get(key)));
			}
		}
		return raw;
	}

	// ---------------------------------------------------------------------------------------
	// Create, Update, Create or Update
	// ---------------------------------------------------------------------------------------

	private Object saveRecord(String kind, Map<String, Object> step) {
		ConnectorMapRuntime.SavedMap saved = ConnectorMapRuntime.load(
			ConnectorRecipeDocument.textOf(step.get('map')),
			access
		);
		Object input = pill(
			String.isBlank(ConnectorRecipeDocument.textOf(step.get('input'))) ? 'trigger' : step.get('input')
		);
		Id recordId;
		if (kind == 'update') {
			String text = ConnectorMapRuntime.text(pill(step.get('recordId')));
			recordId = ConnectorRecipeDocument.isId(text) ? Id.valueOf(text) : null;
		}
		String owner = run.Recipe__r.Record_Owner_Id__c;
		ConnectorMapRuntime.Saved result = ConnectorMapRuntime.save(
			kind,
			saved.document,
			input,
			recordId,
			ConnectorRecipeDocument.isId(owner) ? Id.valueOf(owner) : null,
			access,
			isTest
		);
		Map<String, Object> output = new Map<String, Object>{
			'id' => result.recordId,
			'action' => result.action,
			'mapVersion' => saved.version
		};
		if (isTest) {
			output.put('wouldWrite', result.fields);
		} else if (result.action != 'skipped') {
			written++;
			budget.wrote = true;
		}
		return output;
	}

	// ---------------------------------------------------------------------------------------
	// Call an App (F1, F4)
	// ---------------------------------------------------------------------------------------

	/**
	 * Call an App, and Send to Webhook (always POST, R-CR11). An address read from the data
	 * (`urlFrom`: fetch back, or a callback) is held to the connection's host and only its path
	 * and query are used (F4).
	 */
	private Object callApp(String kind, Map<String, Object> step) {
		String connection = ConnectorRecipeDocument.textOf(step.get('connection'));
		String method = kind == 'sendWebhook' ? 'POST' : ConnectorRecipeDocument.textOf(step.get('method'));
		String path = ConnectorRecipeDocument.textOf(step.get('path'));
		String urlFrom = ConnectorRecipeDocument.textOf(step.get('urlFrom'));
		if (
			!connection.startsWith(ConnectorConnections.PREFIX) ||
			(String.isBlank(urlFrom) && ConnectorRecipeDocument.requestPathProblem(kind, path))
		) {
			throw failure(BarnHelp.text('Connector', 'Connector_Run_ErrorRequest'));
		}
		String address;
		if (String.isNotBlank(urlFrom)) {
			address = ConnectorWebhooks.calloutAddress(ConnectorMapRuntime.text(pill(urlFrom)), connection);
		} else {
			for (Object raw : ConnectorRecipeDocument.listOf(step.get('pathValues'))) {
				Map<String, Object> slot = ConnectorRecipeDocument.mapOf(raw);
				path = path.replace('{' + slot.get('name') + '}', encoded(valueOf(slot)));
			}
			List<String> pairs = new List<String>();
			for (Object raw : ConnectorRecipeDocument.listOf(step.get('query'))) {
				Map<String, Object> pair = ConnectorRecipeDocument.mapOf(raw);
				pairs.add(encoded(ConnectorRecipeDocument.textOf(pair.get('name'))) + '=' + encoded(valueOf(pair)));
			}
			address = path + (pairs.isEmpty() ? '' : '?' + String.join(pairs, '&'));
		}
		HttpRequest request = new HttpRequest();
		request.setEndpoint('callout:' + connection + address);
		request.setMethod(method);
		request.setTimeout(TIMEOUT_MS);
		List<String> headerNames = new List<String>();
		for (Object raw : ConnectorRecipeDocument.listOf(step.get('headers'))) {
			Map<String, Object> header = ConnectorRecipeDocument.mapOf(raw);
			String name = ConnectorRecipeDocument.textOf(header.get('name'));
			if (!ConnectorRecipeDocument.headerNameOk(name)) {
				throw failure(BarnHelp.text('Connector', 'Connector_Run_ErrorRequest'));
			}
			request.setHeader(name, valueOf(header));
			headerNames.add(name);
		}
		String body;
		if (String.isNotBlank(ConnectorRecipeDocument.textOf(step.get('bodyMap')))) {
			ConnectorMapRuntime.SavedMap saved = ConnectorMapRuntime.load(
				ConnectorRecipeDocument.textOf(step.get('bodyMap')),
				access
			);
			Object input = pill(
				String.isBlank(ConnectorRecipeDocument.textOf(step.get('bodyInput')))
					? 'trigger'
					: step.get('bodyInput')
			);
			body = JSON.serialize(ConnectorMapRuntime.buildJson(saved.document, input));
			guard(body);
			request.setHeader('Content-Type', 'application/json');
			request.setBody(body);
		}
		if (isTest && method != 'GET' && !sendForReal) {
			return new Map<String, Object>{
				'request' => new Map<String, Object>{
					'method' => method,
					'path' => address,
					'headers' => headerNames,
					'body' => body
				}
			};
		}
		Long started = System.currentTimeMillis();
		HttpResponse response;
		try {
			response = new Http().send(request);
		} catch (CalloutException unreachable) {
			StepFailureException failed = failure(
				BarnHelp.text(
					'Connector',
					'Connector_Run_ErrorUnreachable',
					new List<Object>{ unreachable.getTypeName() }
				)
			);
			failed.passing = true;
			throw failed;
		} finally {
			budget.calloutMs += System.currentTimeMillis() - started;
		}
		return answer(step, response);
	}

	/** The app's answer as the step's result, or a failure in plain words. */
	private Object answer(Map<String, Object> step, HttpResponse response) {
		Integer status = response.getStatusCode();
		String text = response.getBody();
		if (text != null && text.length() > MAX_RESPONSE) {
			throw failure(BarnHelp.text('Connector', 'Connector_Run_ErrorResponseTooLarge'));
		}
		List<Object> codes = ConnectorRecipeDocument.listOf(step.get('success'));
		Boolean ok = codes.isEmpty() ? status >= 200 && status < 300 : codes.contains(status);
		if (status == 404 && step.get('notFoundOk') == true) {
			return new Map<String, Object>{ 'status' => status, 'body' => null };
		}
		if (!ok) {
			String message;
			if (status == 401 || status == 403) {
				message = BarnHelp.text('Connector', 'Connector_Run_ErrorRefused', new List<Object>{ status });
			} else if (status == 404) {
				message = BarnHelp.text('Connector', 'Connector_Run_ErrorNotFound');
			} else if (status == 429) {
				message = BarnHelp.text('Connector', 'Connector_Run_ErrorTooMany');
			} else if (status >= 500) {
				message = BarnHelp.text('Connector', 'Connector_Run_ErrorAppDown', new List<Object>{ status });
			} else {
				message = BarnHelp.text('Connector', 'Connector_Run_ErrorStatus', new List<Object>{ status });
			}
			StepFailureException failed = failure(message);
			failed.status = status;
			failed.response = text;
			failed.passing = PASSING.contains(status);
			String wait = response.getHeader('Retry-After');
			failed.retryAfter = String.isNotBlank(wait) &&
				wait.trim().isNumeric() &&
				wait.trim().length() < 7
				? Integer.valueOf(wait.trim())
				: null;
			throw failed;
		}
		Object parsedBody = text;
		if (String.isNotBlank(text) && (text.trim().startsWith('{') || text.trim().startsWith('['))) {
			try {
				parsedBody = JSON.deserializeUntyped(text);
			} catch (Exception notJson) {
				parsedBody = text;
			}
		}
		return new Map<String, Object>{ 'status' => status, 'body' => parsedBody };
	}

	/** A literal value or a path's value as text, refused when it carries `{!`, CR or LF (F1, F4). */
	private String valueOf(Map<String, Object> entry) {
		String path = ConnectorRecipeDocument.textOf(entry.get('path'));
		String value = String.isBlank(path)
			? ConnectorRecipeDocument.textOf(entry.get('value'))
			: ConnectorMapRuntime.text(pill(path));
		value = value == null ? '' : value;
		guard(value);
		return value;
	}

	/** Fails the step when text that came from a recipe, a payload, an app or a record holds `{!` (F1). */
	private static void guard(String value) {
		if (ConnectorRecipeDocument.unsafeValue(value)) {
			throw failure(BarnHelp.text('Connector', 'Connector_Run_ErrorMergeField'));
		}
	}

	/** URL-encoded for a path or query (F4): `%20` for a space, so nothing can end the segment. */
	private static String encoded(String value) {
		return EncodingUtil.urlEncode(value, 'UTF-8').replace('+', '%20');
	}

	// ---------------------------------------------------------------------------------------
	// If
	// ---------------------------------------------------------------------------------------

	/** Whether an If's conditions hold: all of them, or any when `match` is `any`. */
	private Boolean holds(Map<String, Object> step) {
		Boolean anyMatch = step.get('match') == 'any';
		for (Object raw : ConnectorRecipeDocument.listOf(step.get('conditions'))) {
			Map<String, Object> condition = ConnectorRecipeDocument.mapOf(raw);
			Boolean met = compare(
				ConnectorMapRuntime.text(pill(condition.get('path'))),
				ConnectorRecipeDocument.textOf(condition.get('operator')),
				ConnectorRecipeDocument.textOf(condition.get('value'))
			);
			if (anyMatch && met) {
				return true;
			}
			if (!anyMatch && !met) {
				return false;
			}
		}
		return !anyMatch;
	}

	/** One R-R2 comparison of text, ignoring capitals; numbers compare as numbers. */
	@TestVisible
	private static Boolean compare(String actual, String operator, String expected) {
		String left = actual == null ? '' : actual.trim().toLowerCase();
		String right = expected == null ? '' : expected.trim().toLowerCase();
		switch on operator {
			when 'is null' {
				return String.isBlank(left);
			}
			when 'is not null' {
				return String.isNotBlank(left);
			}
			when 'equals' {
				return left == right;
			}
			when 'not equals' {
				return left != right;
			}
			when 'contains' {
				return left.contains(right);
			}
			when 'does not contain' {
				return !left.contains(right);
			}
			when 'starts with' {
				return left.startsWith(right);
			}
		}
		Integer order;
		try {
			order = Decimal.valueOf(left) < Decimal.valueOf(right)
				? -1
				: (Decimal.valueOf(left) == Decimal.valueOf(right) ? 0 : 1);
		} catch (Exception notNumbers) {
			order = left.compareTo(right);
		}
		return operator == 'greater than' ? order > 0 : order < 0;
	}

	// ---------------------------------------------------------------------------------------
	// Helpers
	// ---------------------------------------------------------------------------------------

	private Object pill(Object path) {
		return ConnectorMapRuntime.read(data, ConnectorRecipeDocument.textOf(path));
	}

	private static Object parsed(String source) {
		if (String.isBlank(source)) {
			return null;
		}
		try {
			return JSON.deserializeUntyped(source);
		} catch (Exception unreadable) {
			return null;
		}
	}

	private static StepFailureException failure(String message) {
		return new StepFailureException(message);
	}

	/**
	 * An exception as words for the run: messages written for a person as they are, a save's
	 * first error, and otherwise a fixed message naming only the exception type (F7: no raw
	 * message, which could echo a request).
	 */
	@TestVisible
	private static String plain(Exception problem) {
		if (
			problem instanceof ConnectorMapRuntime.MapException ||
			problem instanceof QueryCompiler.QueryCompilerException ||
			problem instanceof ConnectorRecipeDocument.DocumentException
		) {
			return problem.getMessage();
		}
		if (problem instanceof DmlException) {
			return BarnHelp.text(
				'Connector',
				'Connector_Run_ErrorSave',
				new List<Object>{ ((DmlException) problem).getDmlMessage(0) }
			);
		}
		if (problem instanceof QueryException || problem instanceof NoAccessException) {
			return BarnHelp.text('Connector', 'Connector_Run_ErrorAccess');
		}
		return BarnHelp.text('Connector', 'Connector_Run_ErrorUnexpected', new List<Object>{ problem.getTypeName() });
	}
}
