/**
 * The clock's triggers (canonical model R-CR1, R-CR6; design Section 3.2): a Schedule recipe's
 * next time, and a Record Change recipe's poll. Polling works on any queryable object, needs no
 * metadata per object and catches imports and bulk updates; it resumes from the recipe's
 * Watermark after an outage. Deletes are not seen.
 *
 * Inherited sharing: the clock polls directly for user-mode recipes, in user mode as the lane's
 * identity, and through `ConnectorRunStore.pollInSystemMode` for a System recipe.
 */
public inherited sharing class ConnectorTriggers {
	public static final Set<String> EVERY = new Set<String>{ '15m', 'hour', 'day', 'week' };
	public static final List<String> DAYS = new List<String>{ 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN' };
	public static final Set<String> STAMPS = new Set<String>{ 'created', 'changed' };
	public static final Set<String> MODES = new Set<String>{ 'each', 'batch' };
	public static final Integer MAX_POLLED = 200;
	/** A batch run's input stays well under the 131,072 a run's Input holds. */
	private static final Integer BATCH_TEXT = 120000;
	private static final Pattern AT = Pattern.compile('([01][0-9]|2[0-3]):[0-5][0-9]');
	/** 1 January 1900 was a Monday. */
	private static final Date A_MONDAY = Date.newInstance(1900, 1, 1);
	private static TimeZone zone;

	private Connector_Recipe__c recipe;
	private Map<String, Object> starter;
	private Set<Id> identities;

	public ConnectorTriggers(Connector_Recipe__c recipe, Map<String, Object> starter, Set<Id> identities) {
		this.recipe = recipe;
		this.starter = starter;
		this.identities = identities;
	}

	/** What is wrong with a `schedule` or `record` trigger, in words, or null (R-CR1). */
	public static String problem(Map<String, Object> starter) {
		String kind = text(starter.get('kind'));
		if (kind == 'schedule') {
			String every = text(starter.get('every'));
			Boolean timed = every == 'day' || every == 'week';
			if (
				!EVERY.contains(every) ||
				(timed && !AT.matcher(text(starter.get('at'))).matches()) ||
				(every == 'week' && !DAYS.contains(text(starter.get('day'))))
			) {
				return BarnHelp.text('Connector', 'Connector_Recipe_ErrorSchedule');
			}
		} else if (kind == 'record') {
			Map<String, Object> query = ConnectorRecipeDocument.mapOf(starter.get('query'));
			Object most = starter.get('limit');
			if (
				String.isBlank(text(query.get('object'))) ||
				!STAMPS.contains(text(starter.get('on'))) ||
				(starter.get('mode') != null && !MODES.contains(text(starter.get('mode')))) ||
				(most != null && !(most instanceof Integer && (Integer) most >= 1 && (Integer) most <= MAX_POLLED))
			) {
				return BarnHelp.text('Connector', 'Connector_Recipe_ErrorRecordTrigger');
			}
		}
		return null;
	}

	/** Publish's check of a `record` trigger (R-CR2): its query compiles and has its stamp. */
	public static String publishProblem(Map<String, Object> starter) {
		try {
			QueryCompiler.Compiled compiled = QueryCompiler.compile(JSON.serialize(starter.get('query')));
			Schema.SObjectType type = NamespaceUtil.globalDescribe().get(compiled.objectName.toLowerCase());
			if (type == null || !type.getDescribe().fields.getMap().containsKey(stampOf(starter).toLowerCase())) {
				return BarnHelp.text('Connector', 'Connector_Publish_NoStamp', new List<Object>{ compiled.objectName });
			}
			return null;
		} catch (Exception refused) {
			return refused.getMessage();
		}
	}

	/** The next time a schedule is due after `after`, in the org's time zone (R-CR6). */
	public static Datetime nextAt(Map<String, Object> starter, Datetime after) {
		String every = text(starter.get('every'));
		if (every == '15m') {
			return after.addMinutes(15);
		}
		if (every == 'hour') {
			return after.addHours(1);
		}
		List<String> parts = text(starter.get('at')).split(':');
		Time at = Time.newInstance(Integer.valueOf(parts[0]), Integer.valueOf(parts[1]), 0, 0);
		TimeZone local = orgZone();
		Date today = after.addSeconds(local.getOffset(after) / 1000).dateGmt();
		for (Integer i = 0; i <= 7; i++) {
			Date day = today.addDays(i);
			if (every == 'week' && DAYS[Math.mod(A_MONDAY.daysBetween(day), 7)] != text(starter.get('day'))) {
				continue;
			}
			Datetime wall = Datetime.newInstanceGmt(day, at);
			Datetime instant = wall.addSeconds(-local.getOffset(wall) / 1000);
			if (instant > after) {
				return instant;
			}
		}
		return after.addDays(1);
	}

	private static TimeZone orgZone() {
		if (zone == null) {
			zone = TimeZone.getTimeZone(
				[SELECT TimeZoneSidKey FROM Organization WITH SYSTEM_MODE LIMIT 1].TimeZoneSidKey
			);
		}
		return zone;
	}

	/** A Queued run of the recipe's published version, as the clock starts it. */
	public static Connector_Run__c newRun(Connector_Recipe__c recipe, String startedBy, String inputJson) {
		return new Connector_Run__c(
			Recipe__c = recipe.Id,
			Status__c = ConnectorRunStore.QUEUED,
			Started_By__c = startedBy,
			Ran_As__c = recipe.Run_As__c,
			Recipe_Version__c = recipe.Version__c == null ? 0 : recipe.Version__c,
			Input_JSON__c = inputJson,
			Is_Test__c = false
		);
	}

	/** The Watermark a recipe starts from: now, so a first poll does not run the whole history. */
	public static String watermark(Datetime stamp, Id lastId) {
		return stamp.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') +
			'|' +
			(lastId == null ? '' : String.valueOf(lastId));
	}

	private static String stampOf(Map<String, Object> starter) {
		return text(starter.get('on')) == 'created' ? 'CreatedDate' : 'SystemModstamp';
	}

	/**
	 * The records changed (or created) after the Watermark, oldest first, at most the trigger's
	 * limit, as Queued runs: one per record, or one for the batch. Moves the Watermark to the last
	 * record read. Records last changed by a recipe identity are skipped when Ignore Own Changes
	 * is on (the loop guard).
	 */
	public List<Connector_Run__c> poll() {
		AccessLevel access = recipe.Run_As__c == ConnectorRecipes.RUN_AS_SYSTEM
			? AccessLevel.SYSTEM_MODE
			: AccessLevel.USER_MODE;
		Map<String, Object> query = ConnectorRecipeDocument.mapOf(starter.get('query'));
		QueryCompiler.Compiled compiled = QueryCompiler.compile(JSON.serialize(query));
		String stamp = stampOf(starter);
		Map<String, String> fields = new Map<String, String>{ 'id' => 'Id', stamp.toLowerCase() => stamp };
		for (Object field : ConnectorRecipeDocument.listOf(query.get('fields'))) {
			fields.put(String.valueOf(field).toLowerCase(), String.valueOf(field));
		}
		Map<String, Object> binds = new Map<String, Object>(compiled.binds);
		List<String> mark = String.isBlank(recipe.Watermark__c)
			? new List<String>{ watermark(Datetime.now(), null) }
			: recipe.Watermark__c.split('\\|');
		binds.put('cnStamp', (Datetime) JSON.deserialize('"' + mark[0] + '"', Datetime.class));
		String after = '(' + stamp + ' > :cnStamp';
		if (mark.size() > 1 && ConnectorRecipeDocument.isId(mark[1])) {
			binds.put('cnId', Id.valueOf(mark[1]));
			after += ' OR (' + stamp + ' = :cnStamp AND Id > :cnId)';
		}
		after += ')';
		if (recipe.Ignore_Own_Changes__c != false && !identities.isEmpty()) {
			binds.put('cnSkip', identities);
			after += ' AND LastModifiedById NOT IN :cnSkip';
		}
		Object most = starter.get('limit');
		binds.put('cnMost', most instanceof Integer ? (Integer) most : MAX_POLLED);
		String soql =
			'SELECT ' +
			String.join(fields.values(), ', ') +
			compiled.fromWhere +
			(compiled.fromWhere.contains(' WHERE ') ? ' AND ' : ' WHERE ') +
			after +
			' ORDER BY ' +
			stamp +
			', Id LIMIT :cnMost';
		List<SObject> rows = Database.queryWithBinds(soql, binds, access);
		if (rows.isEmpty()) {
			return new List<Connector_Run__c>();
		}
		SObject last = rows[rows.size() - 1];
		recipe.Watermark__c = watermark((Datetime) last.get(stamp), last.Id);
		return runsFor(rows);
	}

	private List<Connector_Run__c> runsFor(List<SObject> rows) {
		List<Connector_Run__c> runs = new List<Connector_Run__c>();
		List<Object> records = (List<Object>) JSON.deserializeUntyped(JSON.serialize(rows));
		if (text(starter.get('mode')) != 'batch') {
			for (Object raw : records) {
				Object record = ConnectorStepRunner.withoutAttributes(raw);
				runs.add(
					newRun(
						recipe,
						'RecordChange',
						JSON.serialize(
							new Map<String, Object>{
								'recordId' => ConnectorRecipeDocument.mapOf(record).get('Id'),
								'record' => record
							}
						)
					)
				);
			}
			return runs;
		}
		List<Object> chunk = new List<Object>();
		Integer size = 0;
		for (Object raw : records) {
			Object record = ConnectorStepRunner.withoutAttributes(raw);
			Integer length = JSON.serialize(record).length();
			if (!chunk.isEmpty() && size + length > BATCH_TEXT) {
				runs.add(batchRun(chunk));
				chunk = new List<Object>();
				size = 0;
			}
			chunk.add(record);
			size += length;
		}
		runs.add(batchRun(chunk));
		return runs;
	}

	private Connector_Run__c batchRun(List<Object> chunk) {
		List<Object> ids = new List<Object>();
		for (Object record : chunk) {
			ids.add(ConnectorRecipeDocument.mapOf(record).get('Id'));
		}
		return newRun(
			recipe,
			'RecordChange',
			JSON.serialize(new Map<String, Object>{ 'recordIds' => ids, 'records' => chunk })
		);
	}

	private static String text(Object value) {
		return ConnectorRecipeDocument.textOf(value);
	}
}
