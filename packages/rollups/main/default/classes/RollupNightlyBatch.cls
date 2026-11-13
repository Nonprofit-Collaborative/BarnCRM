/**
 * The nightly rollup run (D-200 P1, ADR-0082 decision 4 as amended): every total over every
 * record once a week, and on the other nights only what can have changed since the last run.
 *
 * `begin` decides the night. A full recalculation of every Every night and Both definition
 * (`RollupFullRecalcBatch`) runs when no run has finished yet, on the night the Night of the
 * Full Recalculation setting names (Sunday unless changed; Every night keeps the old nightly
 * sweep), and after a pause of all automation, which can have let a record move to another
 * parent unseen. On the other nights each definition is planned on its own (`plan`):
 *
 * - **Everywhere tonight**: a Every night definition (no save keeps it), one never calculated,
 *   one that counts deleted records, one whose target filter compares a date with today, a
 *   fiscal year definition on the first night of a fiscal year, and a definition whose filter
 *   says this year or last year on the first night of a year. These go to the full run.
 * - **Only what changed**: every other Both definition. One pass per source entity reads the
 *   source records changed since the last run finished (`SystemModstamp`), deleted ones too,
 *   and, for a condition in the last n days, the records whose date has moved into or out of
 *   the window since then. The engine's own save path (`RollupChanges.forSave`) marks their
 *   targets, and the Rollup Queue recalculates those.
 *
 * Every night also retries the Failed queue entries and releases the held ones, so nothing the
 * queue gave up on waits longer than a night.
 *
 * The run is covered when its last pass finishes with no chunk stopped: the time it started is
 * stored on Rollup Settings (`Nightly_Covered_From__c`), and the next night starts from there.
 * A run that stopped stores nothing, so the next night covers the same changes again.
 *
 * DOCUMENTED EXCEPTION to user mode reads (plan Section 4.13, ADR-0021, as in
 * `RollupFullRecalcBatch`): source records are read and the queue is written in system mode and
 * without sharing, because a total must not depend on who scheduled the run.
 */
public without sharing class RollupNightlyBatch implements Database.Batchable<SObject>, Database.Stateful {
	private static final String LOG_CONTEXT = 'RollupNightlyBatch';

	/** The setting naming the night of the full recalculation. */
	public static final String DAY_SETTING = 'Full_Recalc_Day__c';
	/** The setting value that keeps the full recalculation every night. */
	public static final String EVERY_NIGHT = 'Every_Night';
	/** The night when the setting is blank or holds something else. */
	public static final String DEFAULT_DAY = 'Sunday';
	/** The setting's values, Sunday first, in the order of `weekday`. */
	public static final List<String> DAYS = new List<String>{
		'Sunday',
		'Monday',
		'Tuesday',
		'Wednesday',
		'Thursday',
		'Friday',
		'Saturday'
	};

	/** A known Sunday, to count the day of the week from without the reader's locale. */
	private static final Date A_SUNDAY = Date.newInstance(1900, 1, 7);

	/** Source records a chunk reads; marking them costs a few queries and queue inserts. */
	private static final Integer CHUNK_SIZE = 1000;

	/** Deleted source records read at the end of a pass at most; the rest wait for Sunday. */
	private static final Integer DELETED_ROWS = 10000;

	/** The attributes `HouseholdService.membershipChangeOf` reads on a saved record. */
	private static final Map<String, List<String>> MEMBERSHIP_FIELDS = new Map<String, List<String>>{
		'contact' => new List<String>{ 'accountid' },
		'household_member__c' => new List<String>{ 'household__c', 'contact__c', 'account__c' }
	};

	@TestVisible
	private static Date todayOverride;

	/** One window edge: the records whose date in this field lies between the two values. */
	private class Edge {
		public String field;
		public Object fromValue;
		public Object toValue;
		public Boolean withTime;
	}

	/** One source entity: the definitions read from it, and what the pass selects. */
	@TestVisible
	private class Pass {
		public String source;
		public List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>();
		public Set<String> fields = new Set<String>{ 'id' };
		public Map<String, Edge> edges = new Map<String, Edge>();
	}

	/** The night, carried from pass to pass. */
	@TestVisible
	private class Plan {
		public Datetime since;
		public Datetime startedAt = Datetime.now();
		public List<Rollup_Definition__c> everywhere = new List<Rollup_Definition__c>();
		public List<Pass> passes = new List<Pass>();
		public Integer stopped = 0;
		public Integer marked = 0;
	}

	@TestVisible
	private final Plan plan;
	private final Integer index;

	@TestVisible
	private RollupNightlyBatch(Plan plan, Integer index) {
		this.plan = plan;
		this.index = index;
	}

	// --------------------------------------------------------------------------------- starting

	/**
	 * Starts tonight's run for these definitions (the active Every night and Both ones).
	 *
	 * @return the full run's job when one runs tonight, otherwise the first pass's, or null
	 */
	public static Id begin(List<Rollup_Definition__c> definitions) {
		Datetime since = coveredFrom();
		if (RollupService.isTurnedOff() || AutomationControl.isPaused()) {
			// The full run logs why nothing starts.
			return RollupFullRecalcBatch.begin(definitions, true);
		}
		RollupQueue.releaseHeld();
		RollupQueue.retry(null);
		if (since == null || isFullNight() || pausedSince(since)) {
			return RollupFullRecalcBatch.begin(definitions, true);
		}
		Plan plan = plan(definitions, since);
		Id full = plan.everywhere.isEmpty()
			? null
			: RollupFullRecalcBatch.begin(plan.everywhere, plan.passes.isEmpty());
		if (plan.passes.isEmpty()) {
			return full;
		}
		Id first = Database.executeBatch(new RollupNightlyBatch(plan, 0), CHUNK_SIZE);
		return full == null ? first : full;
	}

	/** When the last covered run started, or null when none has finished. */
	public static Datetime coveredFrom() {
		return Rollup_Settings__c.getOrgDefaults().Nightly_Covered_From__c;
	}

	/** Stores the start of a run that covered every change before it. */
	public static void markCovered(Datetime startedAt) {
		try {
			OrgSettingsSystemWriter.save(
				Rollup_Settings__c.SObjectType,
				new Map<Schema.SObjectField, Object>{
					Rollup_Settings__c.Nightly_Covered_From__c => startedAt
				}
			);
		} catch (Exception notStored) {
			// The next night then covers the same changes again, which costs time, not totals.
			ErrorLogger.log(notStored, LOG_CONTEXT);
		}
	}

	/** The setting's night, or Every_Night; blank or unknown means Sunday. */
	public static String fullRecalcDay() {
		Object stored = SettingsService.getValue(RollupService.SETTINGS_OBJECT, DAY_SETTING);
		String day = stored == null ? null : String.valueOf(stored);
		return day == EVERY_NIGHT || DAYS.contains(day) ? day : DEFAULT_DAY;
	}

	/** True when tonight recalculates every total over every record. */
	public static Boolean isFullNight() {
		String day = fullRecalcDay();
		return day == EVERY_NIGHT || DAYS[Math.mod(A_SUNDAY.daysBetween(today()), 7)] == day;
	}

	private static Date today() {
		return todayOverride == null ? Date.today() : todayOverride;
	}

	/** True when all automation was paused after the last covered run started. */
	private static Boolean pausedSince(Datetime since) {
		return [
				SELECT Id
				FROM Setting_Change__c
				WHERE
					Setting_Name__c = :AutomationControl.PAUSE_SETTING_NAME
					AND CreatedDate >= :since
				WITH SYSTEM_MODE
				LIMIT 1
			]
			.size() > 0;
	}

	// --------------------------------------------------------------------------------- planning

	/** Which definitions run everywhere tonight, and the passes for the rest. */
	@TestVisible
	private static Plan plan(List<Rollup_Definition__c> definitions, Datetime since) {
		Plan plan = new Plan();
		plan.since = since;
		Map<String, Pass> bySource = new Map<String, Pass>();
		for (
			Rollup_Definition__c definition : definitions == null
				? new List<Rollup_Definition__c>()
				: definitions
		) {
			Schema.SObjectType sourceType = SettingsService.typeByName(definition.Source_Object__c);
			List<Edge> edges = sourceType == null
				? null
				: edgesOf(definition, sourceType, since.date());
			if (edges == null) {
				plan.everywhere.add(definition);
				continue;
			}
			String source = String.valueOf(sourceType);
			Pass pass = bySource.get(source);
			if (pass == null) {
				pass = new Pass();
				pass.source = source;
				bySource.put(source, pass);
				plan.passes.add(pass);
			}
			pass.definitions.add(definition);
			Map<String, Schema.SObjectField> fields = RollupChanges.fieldMap(sourceType);
			pass.fields.addAll(
				RollupChanges.localFields(RollupChanges.readsFor(definition), fields)
			);
			List<String> membership = MEMBERSHIP_FIELDS.get(source.toLowerCase());
			for (String field : membership == null ? new List<String>() : membership) {
				if (fields.containsKey(field)) {
					pass.fields.add(field);
				}
			}
			for (Edge edge : edges) {
				pass.edges.put(edge.field + '|' + edge.fromValue + '|' + edge.toValue, edge);
			}
		}
		return plan;
	}

	/**
	 * The window edges a definition's changes since `last` can hide behind, or null when it runs
	 * everywhere tonight.
	 */
	private static List<Edge> edgesOf(
		Rollup_Definition__c definition,
		Schema.SObjectType sourceType,
		Date last
	) {
		Date today = today();
		if (
			definition.Mode__c != RollupService.MODE_BOTH ||
			definition.Last_Calculated__c == null ||
			definition.Include_Deleted__c == true ||
			RollupFilterParser.usesRelativeDate(definition.Target_Filter_JSON__c) ||
			(definition.Fiscal_Year_Aware__c == true &&
			fiscalYearStart(today) > last)
		) {
			return null;
		}
		List<Edge> edges = new List<Edge>();
		for (Map<String, Object> condition : conditionsOf(definition.Filter_JSON__c)) {
			String operator = String.valueOf(condition.get('operator')).toLowerCase().trim();
			if (operator == 'this year' || operator == 'last year') {
				if (last.year() != today.year()) {
					return null;
				}
			} else if (operator == 'last n days') {
				Schema.SObjectField field = RollupChanges.fieldMap(sourceType)
					.get(String.valueOf(condition.get('field')));
				Integer days;
				try {
					days = RollupFilterParser.dayCount(condition.get('value'));
				} catch (Exception unreadable) {
					return null;
				}
				Schema.DisplayType type = field?.getDescribe().getType();
				if (type != Schema.DisplayType.DATE && type != Schema.DisplayType.DATETIME) {
					return null;
				}
				// A day of margin each side covers the time zones and the window's own day.
				edges.add(edgeOf(field, last.addDays(-days - 1), today.addDays(-days + 1)));
				edges.add(edgeOf(field, last.addDays(-1), today.addDays(1)));
			}
		}
		return edges;
	}

	private static Edge edgeOf(Schema.SObjectField field, Date fromDate, Date toDate) {
		Edge edge = new Edge();
		Schema.DescribeFieldResult described = field.getDescribe();
		edge.field = described.getName();
		edge.withTime = described.getType() == Schema.DisplayType.DATETIME;
		edge.fromValue = edge.withTime ? (Object) midnightGmt(fromDate) : fromDate;
		edge.toValue = edge.withTime ? (Object) midnightGmt(toDate.addDays(1)) : toDate;
		return edge;
	}

	private static Datetime midnightGmt(Date day) {
		return Datetime.newInstanceGmt(day, Time.newInstance(0, 0, 0, 0));
	}

	/** The first day of the fiscal year `today` is in. */
	private static Date fiscalYearStart(Date today) {
		Integer month = RollupDateWindow.fiscalYearStartMonth();
		return Date.newInstance(today.month() >= month ? today.year() : today.year() - 1, month, 1);
	}

	/** A filter document's conditions; none when it is blank or cannot be read. */
	private static List<Map<String, Object>> conditionsOf(String filterDocument) {
		List<Map<String, Object>> conditions = new List<Map<String, Object>>();
		if (String.isBlank(filterDocument)) {
			return conditions;
		}
		try {
			Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
				filterDocument
			);
			for (Object condition : (List<Object>) parsed.get('conditions')) {
				Map<String, Object> read = (Map<String, Object>) condition;
				if (read.get('operator') != null && read.get('field') != null) {
					conditions.add(read);
				}
			}
		} catch (Exception unreadable) {
			// A filter that cannot be read stops its definition anyway (R-R10).
			return new List<Map<String, Object>>();
		}
		return conditions;
	}

	// ------------------------------------------------------------------------------- one pass

	private Pass currentPass() {
		return this.plan.passes[this.index];
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		return Database.getQueryLocatorWithBinds(query(''), binds(), AccessLevel.SYSTEM_MODE);
	}

	@TestVisible
	private String query(String suffix) {
		Pass pass = currentPass();
		List<String> changed = new List<String>{ 'SystemModstamp >= :since' };
		Integer i = 0;
		for (Edge edge : pass.edges.values()) {
			changed.add(
				'(' +
					edge.field +
					' >= :from' +
					i +
					' AND ' +
					edge.field +
					(edge.withTime ? ' < :to' : ' <= :to') +
					i +
					')'
			);
			i++;
		}
		return 'SELECT ' +
			String.join(new List<String>(pass.fields), ', ') +
			' FROM ' +
			pass.source +
			' WHERE ' +
			String.join(changed, ' OR ') +
			suffix;
	}

	private Map<String, Object> binds() {
		Map<String, Object> binds = new Map<String, Object>{ 'since' => this.plan.since };
		Integer i = 0;
		for (Edge edge : currentPass().edges.values()) {
			binds.put('from' + i, edge.fromValue);
			binds.put('to' + i, edge.toValue);
			i++;
		}
		return binds;
	}

	/** Marks the targets of these source records and queues them. */
	public void execute(Database.BatchableContext context, List<SObject> records) {
		try {
			queue(
				RollupChanges.forSave(
					currentPass().source,
					records,
					null,
					false,
					currentPass().definitions
				)
			);
		} catch (Exception stopped) {
			ErrorLogger.log(stopped, LOG_CONTEXT);
			this.plan.stopped++;
		}
	}

	private void queue(RollupChanges.Marked marked) {
		Map<String, Set<Id>> idsByTarget = new Map<String, Set<Id>>();
		Map<String, Set<Id>> definitionIdsByTarget = new Map<String, Set<Id>>();
		for (String target : marked.idsByTarget.keySet()) {
			Schema.SObjectType targetType = SettingsService.typeByName(target);
			if (targetType == null) {
				continue;
			}
			String name = String.valueOf(targetType);
			idsByTarget.put(name, marked.idsByTarget.get(target));
			this.plan.marked += marked.idsByTarget.get(target).size();
			List<Rollup_Definition__c> definitions = marked.definitionsFor(target);
			if (definitions != null) {
				Set<Id> ids = new Set<Id>();
				for (Rollup_Definition__c definition : definitions) {
					ids.add(definition.Id);
				}
				definitionIdsByTarget.put(name, ids);
			}
		}
		RollupQueue.add(idsByTarget, definitionIdsByTarget);
	}

	/** Marks the records deleted since the last run, then the next pass, then the end. */
	public void finish(Database.BatchableContext context) {
		this.plan.stopped += stoppedChunks(context);
		try {
			Pass pass = currentPass();
			List<SObject> deleted = Database.queryWithBinds(
				'SELECT ' +
					String.join(new List<String>(pass.fields), ', ') +
					' FROM ' +
					pass.source +
					' WHERE IsDeleted = TRUE AND SystemModstamp >= :since LIMIT ' +
					DELETED_ROWS +
					' ALL ROWS',
				new Map<String, Object>{ 'since' => this.plan.since },
				AccessLevel.SYSTEM_MODE
			);
			if (!deleted.isEmpty()) {
				execute(null, deleted);
			}
		} catch (Exception notRead) {
			ErrorLogger.log(notRead, LOG_CONTEXT);
			this.plan.stopped++;
		}
		if (this.index + 1 < this.plan.passes.size()) {
			RollupNightlyBatch next = new RollupNightlyBatch(this.plan, this.index + 1);
			if (Test.isRunningTest()) {
				// A test cannot chain batch jobs, so the rest of the run happens here.
				next.runInline();
			} else {
				Database.executeBatch(next, CHUNK_SIZE);
			}
			return;
		}
		if (this.plan.stopped == 0) {
			markCovered(this.plan.startedAt);
		}
	}

	/** What a pass does in a test: every chunk, then its finish, in this transaction. */
	@TestVisible
	private void runInline() {
		List<SObject> records = Database.queryWithBinds(
			query(' LIMIT ' + CHUNK_SIZE * 5),
			binds(),
			AccessLevel.SYSTEM_MODE
		);
		for (Integer first = 0; first < records.size(); first += CHUNK_SIZE) {
			List<SObject> chunk = new List<SObject>();
			for (Integer i = first; i < Math.min(first + CHUNK_SIZE, records.size()); i++) {
				chunk.add(records[i]);
			}
			execute(null, chunk);
		}
		finish(null);
	}

	private static Integer stoppedChunks(Database.BatchableContext context) {
		if (context == null) {
			return 0;
		}
		Id jobId = context.getJobId();
		List<AsyncApexJob> jobs = [
			SELECT NumberOfErrors
			FROM AsyncApexJob
			WHERE Id = :jobId
			WITH SYSTEM_MODE
		];
		return jobs.isEmpty() || jobs[0].NumberOfErrors == null ? 0 : jobs[0].NumberOfErrors;
	}
}
