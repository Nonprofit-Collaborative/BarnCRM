/**
 * One territory run (canonical model R-TM3, R-TM4; ADR-0205 `0205-territory-management-module.md`,
 * decisions 3 to 5), run as the person who started it.
 *
 * - **One kind at a time.** People, then households, then organizations: each kind with active
 *   rules is its own batch, and each chains the next, carrying the run's totals.
 * - **First match wins.** For each chunk, the kind's active rules of active territories are tried
 *   in priority order through Core's query compiler (R-R2 filters), limited to the chunk's
 *   records, in user mode. A record already in the territory it matches is left alone.
 * - **Preview changes nothing.** It counts what Assign would do and keeps a sample.
 * - **Assign is a Data job.** Every save is `Database.update(records, false, USER_MODE)` and is
 *   journaled, so the run is undone from Data Manager, Data Jobs, like a bulk update (R-BU5).
 *
 * The run record, the job record, the journal and each territory's round robin place are the
 * module's own bookkeeping, written in system mode (ADR-0021).
 */
public with sharing class TerritoryRunBatch implements Database.Batchable<SObject>, Database.Stateful {
	public static final String KIND_PEOPLE = 'People';
	public static final String KIND_HOUSEHOLDS = 'Households';
	public static final String KIND_ORGANIZATIONS = 'Organizations';
	public static final List<String> ALL_KINDS = new List<String>{
		KIND_PEOPLE,
		KIND_HOUSEHOLDS,
		KIND_ORGANIZATIONS
	};
	public static final String MODE_PREVIEW = 'Preview';
	public static final String MODE_ASSIGN = 'Assign';
	public static final String STATUS_QUEUED = 'Queued';
	public static final String STATUS_RUNNING = 'Running';
	public static final String STATUS_DONE = 'Done';
	public static final String STATUS_FAILED = 'Failed';
	/** The most active rules of one kind: each is one query per chunk. */
	public static final Integer MAX_RULES = 50;
	/** One more than the most, so a kind with too many is seen. */
	private static final Integer RULES_READ = MAX_RULES + 1;
	/** Records a chunk reads. */
	public static final Integer CHUNK = 200;
	/** Changes the run keeps to show. */
	public static final Integer SAMPLE_SIZE = 50;
	private static final String CONTEXT = 'TerritoryRunBatch';

	/** One rule, as the run uses it: its territory and its query document. */
	public class Rule {
		public Id territoryId;
		public String name;
		public String queryJson;
	}

	/** What the run carries from one kind to the next. */
	public class Totals {
		public Id runId;
		public Id jobId;
		public String mode;
		public Boolean onlyUnassigned = false;
		public Integer checked = 0;
		public Integer changes = 0;
		public Integer saved = 0;
		public Integer failed = 0;
		public Boolean journalIncomplete = false;
		public String stoppedBecause;
		public Map<Id, Integer> movedIn = new Map<Id, Integer>();
		public Map<Id, TerritoryRouting.Pool> pools;
		public List<Map<String, Object>> sample = new List<Map<String, Object>>();
	}

	private final List<String> kinds;
	private final Integer kindIndex;
	private Totals totals;
	private List<Rule> rules = new List<Rule>();

	public TerritoryRunBatch(List<String> kinds, Integer kindIndex, Totals totals) {
		this.kinds = kinds;
		this.kindIndex = kindIndex;
		this.totals = totals;
	}

	/**
	 * Starts a run of the given kinds: writes the run, and for Assign the Data job, then queues
	 * the first kind. Returns the run's Id.
	 */
	public static Id launch(String mode, Boolean onlyUnassigned, List<String> kinds) {
		Datetime now = Datetime.now();
		Territory_Run__c run = new Territory_Run__c(
			Mode__c = mode,
			Only_Unassigned__c = onlyUnassigned == true,
			Status__c = STATUS_QUEUED,
			Checked__c = 0,
			Changes__c = 0,
			Failed__c = 0
		);
		Database.insert(run, AccessLevel.SYSTEM_MODE);
		Totals totals = new Totals();
		totals.runId = run.Id;
		totals.mode = mode;
		totals.onlyUnassigned = onlyUnassigned == true;
		if (mode == MODE_ASSIGN) {
			Import_Batch__c job = new Import_Batch__c(
				Operation__c = 'Update',
				Operation_JSON__c = JSON.serialize(
					new Map<String, Object>{
						'source' => 'territory',
						'runId' => run.Id,
						'query' => new Map<String, Object>{ 'object' => objectOf(kinds[0]) }
					}
				),
				Status__c = ImportBatchService.STATUS_COMMITTING,
				Is_Dry_Run__c = false,
				Row_Count__c = 0,
				Rows_Created__c = 0,
				Rows_Updated__c = 0,
				Rows_Matched__c = 0,
				Rows_Rejected__c = 0,
				Chunk_Size__c = CHUNK,
				Started_At__c = now,
				Committed_By__c = UserInfo.getUserId(),
				Undo_Deadline__c = now.addDays(ImportBatchService.undoWindowDays()),
				Run_Log__c = BarnHelp.text(
					'Territory',
					'Territory_Log_Started',
					new List<Object>{ UserInfo.getName(), now.format() }
				)
			);
			Database.insert(job, AccessLevel.SYSTEM_MODE);
			totals.jobId = job.Id;
			run.Data_Job_Id__c = job.Id;
			Database.update(run, AccessLevel.SYSTEM_MODE);
		}
		Database.executeBatch(new TerritoryRunBatch(kinds, 0, totals), CHUNK);
		return run.Id;
	}

	/** The object a kind's records are. */
	public static String objectOf(String kind) {
		return kind == KIND_PEOPLE ? 'Contact' : 'Account';
	}

	/**
	 * The clause that keeps a kind's records apart on their object, with its binds added, or
	 * null when the kind has none in this org (no household record type).
	 */
	public static String kindClause(String kind, Map<String, Object> binds) {
		if (kind == KIND_PEOPLE) {
			// A person account's contact is checked as its account; the field exists only there.
			return Schema.SObjectType.Contact.fields.getMap().containsKey('IsPersonContact')
				? 'IsPersonContact = false'
				: '';
		}
		Id household = HouseholdService.householdRecordTypeId();
		if (kind == KIND_HOUSEHOLDS) {
			if (household == null) {
				return null;
			}
			binds.put('territoryKindType', household);
			return 'RecordTypeId = :territoryKindType';
		}
		binds.put('territoryKindType', AccountKinds.organizationRecordTypeId());
		return 'RecordTypeId = :territoryKindType';
	}

	/** The query document of a rule's filter on its kind's object. */
	public static String queryJsonOf(String kind, String filterJson) {
		Map<String, Object> document = new Map<String, Object>{
			'version' => 1,
			'object' => objectOf(kind),
			'fields' => new List<Object>{ 'Id' }
		};
		if (String.isNotBlank(filterJson)) {
			document.put('filter', filterJson);
		}
		return JSON.serialize(document);
	}

	/**
	 * How many records of a kind a filter matches, as the person, counting at most `atMost`.
	 * Throws `QueryCompiler.QueryCompilerException` for a filter that cannot run.
	 */
	public static Integer countMatching(String kind, String filterJson, Integer atMost) {
		QueryCompiler.Compiled compiled = QueryCompiler.compileSelection(
			queryJsonOf(kind, filterJson),
			new Set<String>{ 'Id' },
			null
		);
		Map<String, Object> binds = new Map<String, Object>(compiled.binds);
		String clause = kindClause(kind, binds);
		if (clause == null) {
			return 0;
		}
		binds.put('countLimit', atMost);
		return Database.countQueryWithBinds(
			'SELECT COUNT()' + withClause(compiled.fromWhere, clause) + ' LIMIT :countLimit',
			binds,
			AccessLevel.USER_MODE
		);
	}

	/** The active rules of one kind, of active territories, in the order they are tried. */
	public static List<Territory_Rule__c> activeRules(String kind) {
		return [
			SELECT Id, Name, Territory__c, Filter_JSON__c
			FROM Territory_Rule__c
			WHERE Active__c = TRUE AND Applies_To__c = :kind AND Territory__r.Active__c = TRUE
			WITH USER_MODE
			ORDER BY Territory__r.Priority__c, Territory__r.Name, Name
			LIMIT :RULES_READ
		];
	}

	/** A run that cannot start, in words an administrator can act on. */
	public class TerritoryException extends Exception {
	}

	/**
	 * The kinds with active rules, in run order, after checking each kind has at most
	 * `MAX_RULES` and every rule's filter can run. Throws `TerritoryException` otherwise.
	 */
	public static List<String> kindsToRun() {
		List<String> kinds = new List<String>();
		for (String kind : ALL_KINDS) {
			List<Territory_Rule__c> rules = activeRules(kind);
			if (rules.isEmpty()) {
				continue;
			}
			if (rules.size() > MAX_RULES) {
				throw new TerritoryException(
					BarnHelp.text(
						'Territory',
						'Territory_Error_TooManyRules',
						new List<Object>{ kind, MAX_RULES }
					)
				);
			}
			for (Territory_Rule__c rule : rules) {
				try {
					QueryCompiler.compileSelection(
						queryJsonOf(kind, rule.Filter_JSON__c),
						new Set<String>{ 'Id' },
						null
					);
				} catch (QueryCompiler.QueryCompilerException refused) {
					throw new TerritoryException(
						BarnHelp.text(
							'Territory',
							'Territory_Error_Rule',
							new List<Object>{ rule.Name, refused.getMessage() }
						)
					);
				}
			}
			kinds.add(kind);
		}
		return kinds;
	}

	/**
	 * True while a run is queued or running. A run left unfinished for 12 hours (its job was
	 * stopped) no longer holds the next one back.
	 */
	public static Boolean busy() {
		Datetime since = Datetime.now().addHours(-12);
		return [
				SELECT COUNT()
				FROM Territory_Run__c
				WHERE Status__c IN (:STATUS_QUEUED, :STATUS_RUNNING) AND CreatedDate >= :since
				WITH SYSTEM_MODE
			] > 0;
	}

	private static String withClause(String fromWhere, String clause) {
		if (String.isBlank(clause)) {
			return fromWhere;
		}
		return fromWhere + (fromWhere.contains(' WHERE ') ? ' AND ' : ' WHERE ') + clause;
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		String kind = kinds[kindIndex];
		Map<String, Object> binds = new Map<String, Object>();
		String clause;
		try {
			if (kindIndex == 0) {
				Database.update(
					new Territory_Run__c(Id = totals.runId, Status__c = STATUS_RUNNING),
					AccessLevel.SYSTEM_MODE
				);
			}
			for (Territory_Rule__c row : activeRules(kind)) {
				Rule rule = new Rule();
				rule.territoryId = row.Territory__c;
				rule.name = row.Name;
				rule.queryJson = queryJsonOf(kind, row.Filter_JSON__c);
				rules.add(rule);
			}
			if (totals.pools == null) {
				totals.pools = loadPools();
			}
			clause = kindClause(kind, binds);
		} catch (Exception e) {
			stop(e);
		}
		String query = 'SELECT Id, Name, OwnerId, Territory__c FROM ' + objectOf(kind);
		if (clause == null || rules.isEmpty() || String.isNotBlank(totals.stoppedBecause)) {
			query += ' WHERE Id = NULL';
		} else {
			if (totals.onlyUnassigned) {
				clause = String.isBlank(clause)
					? 'Territory__c = NULL'
					: clause + ' AND Territory__c = NULL';
			}
			query = withClause(query, clause);
		}
		return Database.getQueryLocatorWithBinds(query, binds, AccessLevel.USER_MODE);
	}

	public void execute(Database.BatchableContext context, List<SObject> records) {
		if (String.isNotBlank(totals.stoppedBecause)) {
			return;
		}
		String objectName = objectOf(kinds[kindIndex]);
		try {
			totals.checked += records.size();
			Map<Id, Id> target = firstMatches(new Map<Id, SObject>(records).keySet());
			List<SObject> changed = new List<SObject>();
			List<Map<String, Object>> before = new List<Map<String, Object>>();
			for (SObject record : records) {
				Id territoryId = target.get(record.Id);
				Id current = (Id) record.get('Territory__c');
				if (territoryId == null || territoryId == current) {
					continue;
				}
				SObject change = record.getSObjectType().newSObject(record.Id);
				change.put('Territory__c', territoryId);
				TerritoryRouting.Pool pool = totals.pools.get(territoryId);
				Id owner = pool == null ? null : TerritoryRouting.ownerFor(pool);
				Id oldOwner = (Id) record.get('OwnerId');
				if (owner != null && owner != oldOwner) {
					change.put('OwnerId', owner);
				}
				totals.changes++;
				totals.movedIn.put(
					territoryId,
					(totals.movedIn.containsKey(territoryId)
						? totals.movedIn.get(territoryId)
						: 0) + 1
				);
				if (totals.sample.size() < SAMPLE_SIZE) {
					totals.sample.add(
						new Map<String, Object>{
							'id' => record.Id,
							'name' => record.get('Name'),
							'from' => current,
							'to' => territoryId,
							'owner' => change.get('OwnerId')
						}
					);
				}
				changed.add(change);
				before.add(
					new Map<String, Object>{ 'Territory__c' => current, 'OwnerId' => oldOwner }
				);
			}
			if (totals.mode == MODE_ASSIGN && !changed.isEmpty()) {
				save(objectName, changed, before);
			}
		} catch (QueryCompiler.QueryCompilerException refused) {
			stop(refused);
		} catch (Exception e) {
			stop(e);
		}
	}

	/** Each record's territory: the first rule, in order, whose filter it meets. */
	private Map<Id, Id> firstMatches(Set<Id> ids) {
		Map<Id, Id> target = new Map<Id, Id>();
		Set<Id> left = new Set<Id>(ids);
		for (Rule rule : rules) {
			if (left.isEmpty()) {
				break;
			}
			QueryCompiler.Compiled compiled;
			try {
				compiled = QueryCompiler.compileSelection(
					rule.queryJson,
					new Set<String>{ 'Id' },
					left
				);
			} catch (QueryCompiler.QueryCompilerException refused) {
				throw new QueryCompiler.QueryCompilerException(
					BarnHelp.text(
						'Territory',
						'Territory_Error_Rule',
						new List<Object>{ rule.name, refused.getMessage() }
					)
				);
			}
			for (SObject matched : QueryCompiler.run(compiled)) {
				target.put(matched.Id, rule.territoryId);
				left.remove(matched.Id);
			}
		}
		return target;
	}

	/** Saves a chunk's changes as the person and journals each outcome. */
	private void save(String objectName, List<SObject> changed, List<Map<String, Object>> before) {
		String territoryField = objectName == 'Contact'
			? Schema.SObjectType.Contact.fields.Territory__c.getName()
			: Schema.SObjectType.Account.fields.Territory__c.getName();
		List<Map<String, Object>> journal = new List<Map<String, Object>>();
		List<Database.SaveResult> results = Database.update(changed, false, AccessLevel.USER_MODE);
		for (Integer i = 0; i < results.size(); i++) {
			SObject change = changed[i];
			if (!results[i].isSuccess()) {
				totals.failed++;
				journal.add(
					ImportJournalService.failed(
						objectName,
						change.Id,
						results[i].getErrors()[0].getMessage()
					)
				);
				continue;
			}
			totals.saved++;
			Map<String, Object> was = new Map<String, Object>{
				territoryField => before[i].get('Territory__c')
			};
			Map<String, Object> now = new Map<String, Object>{
				territoryField => change.get('Territory__c')
			};
			if (change.get('OwnerId') != null) {
				was.put('OwnerId', before[i].get('OwnerId'));
				now.put('OwnerId', change.get('OwnerId'));
			}
			journal.add(ImportJournalService.updated(objectName, change.Id, null, was, now));
		}
		if (!ImportJournalService.write(totals.jobId, ImportJournalService.PHASE_COMMIT, journal)) {
			totals.journalIncomplete = true;
		}
	}

	public void finish(Database.BatchableContext context) {
		if (kindIndex + 1 < kinds.size() && String.isBlank(totals.stoppedBecause)) {
			try {
				Database.executeBatch(new TerritoryRunBatch(kinds, kindIndex + 1, totals), CHUNK);
				return;
			} catch (Exception e) {
				stop(e);
			}
		}
		try {
			finishRun();
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.finish', totals.runId);
		}
	}

	private void finishRun() {
		Boolean failed = String.isNotBlank(totals.stoppedBecause);
		if (totals.pools == null) {
			totals.pools = new Map<Id, TerritoryRouting.Pool>();
		}
		Map<Id, Territory__c> territories = new Map<Id, Territory__c>(
			[
				SELECT Id, Name
				FROM Territory__c
				WHERE Id IN :totals.pools.keySet()
				WITH SYSTEM_MODE
			]
		);
		List<Map<String, Object>> byTerritory = new List<Map<String, Object>>();
		List<Territory__c> places = new List<Territory__c>();
		for (Id territoryId : totals.pools.keySet()) {
			TerritoryRouting.Pool pool = totals.pools.get(territoryId);
			Integer moved = totals.movedIn.get(territoryId);
			if (moved == null) {
				continue;
			}
			byTerritory.add(
				new Map<String, Object>{
					'id' => territoryId,
					'name' => territories.containsKey(territoryId)
						? territories.get(territoryId).Name
						: null,
					'changes' => moved,
					'noRoom' => pool.noRoom
				}
			);
			if (totals.mode == MODE_ASSIGN && pool.routing == TerritoryRouting.ROUND_ROBIN) {
				places.add(new Territory__c(Id = territoryId, Next_Member__c = pool.next));
			}
		}
		Set<Id> owners = new Set<Id>();
		for (Map<String, Object> entry : totals.sample) {
			if (entry.get('owner') != null) {
				owners.add((Id) entry.get('owner'));
			}
		}
		Map<Id, User> users = new Map<Id, User>(
			[SELECT Id, Name FROM User WHERE Id IN :owners WITH SYSTEM_MODE]
		);
		for (Map<String, Object> entry : totals.sample) {
			entry.put('fromName', nameOf(territories, entry.get('from')));
			entry.put('toName', nameOf(territories, entry.get('to')));
			User owner = entry.get('owner') == null ? null : users.get((Id) entry.get('owner'));
			entry.put('ownerName', owner?.Name);
		}
		if (!places.isEmpty()) {
			Database.update(places, false, AccessLevel.SYSTEM_MODE);
		}
		String message = failed ? totals.stoppedBecause.left(255) : null;
		Database.update(
			new Territory_Run__c(
				Id = totals.runId,
				Status__c = failed ? STATUS_FAILED : STATUS_DONE,
				Checked__c = totals.checked,
				Changes__c = totals.changes,
				Failed__c = totals.failed,
				Message__c = message,
				Completed_At__c = Datetime.now(),
				Summary_JSON__c = JSON.serialize(
						new Map<String, Object>{
							'territories' => byTerritory,
							'sample' => totals.sample
						}
					)
					.left(131072)
			),
			AccessLevel.SYSTEM_MODE
		);
		if (totals.jobId != null) {
			finishJob(failed);
		}
	}

	private void finishJob(Boolean failed) {
		Import_Batch__c job = [
			SELECT Id, Run_Log__c
			FROM Import_Batch__c
			WHERE Id = :totals.jobId
			WITH SYSTEM_MODE
			LIMIT 1
		];
		List<String> lines = new List<String>();
		if (String.isNotBlank(job.Run_Log__c)) {
			lines.add(job.Run_Log__c);
		}
		if (failed) {
			lines.add(totals.stoppedBecause);
		}
		lines.add(
			BarnHelp.text(
				'Territory',
				'Territory_Log_Finished',
				new List<Object>{
					totals.checked.format(),
					totals.saved.format(),
					totals.failed.format()
				}
			)
		);
		if (totals.journalIncomplete) {
			lines.add(BarnHelp.text('Core', 'Core_BulkUpdate_LogJournalIncomplete'));
		}
		job.Run_Log__c = String.join(lines, '\n').right(32768);
		job.Status__c = failed
			? ImportBatchService.STATUS_FAILED
			: ImportBatchService.STATUS_COMPLETE;
		job.Completed_At__c = Datetime.now();
		job.Row_Count__c = totals.checked;
		job.Rows_Updated__c = totals.saved;
		job.Rows_Matched__c = totals.checked - totals.changes;
		job.Rows_Rejected__c = totals.failed;
		Database.update(job, AccessLevel.SYSTEM_MODE);
	}

	private static Object nameOf(Map<Id, Territory__c> territories, Object territoryId) {
		Territory__c found = territoryId == null ? null : territories.get((Id) territoryId);
		return found == null ? null : found.Name;
	}

	/** Stops the run with a reason a person can act on; anything unexpected is also logged. */
	private void stop(Exception e) {
		if (!(e instanceof QueryCompiler.QueryCompilerException)) {
			ErrorLogger.log(e, CONTEXT, totals.runId);
		}
		if (String.isBlank(totals.stoppedBecause)) {
			totals.stoppedBecause = e.getMessage();
		}
	}

	/**
	 * Every territory's routing, active members in turn order, and, for round robin and
	 * capacity, the records each member already owns there (counted in system mode, so a
	 * member's load is the real one whatever the person can see).
	 */
	@TestVisible
	private static Map<Id, TerritoryRouting.Pool> loadPools() {
		Map<Id, TerritoryRouting.Pool> pools = new Map<Id, TerritoryRouting.Pool>();
		Set<Id> counted = new Set<Id>();
		for (Territory__c territory : [
			SELECT
				Id,
				Routing__c,
				Owner_User__c,
				Next_Member__c,
				(
					SELECT User__c, Capacity__c
					FROM Members__r
					WHERE Active__c = TRUE AND User__r.IsActive = TRUE
					ORDER BY Name
				)
			FROM Territory__c
			WHERE Active__c = TRUE
			WITH SYSTEM_MODE
		]) {
			TerritoryRouting.Pool pool = new TerritoryRouting.Pool();
			pool.routing = String.isBlank(territory.Routing__c)
				? TerritoryRouting.KEEP_OWNER
				: territory.Routing__c;
			pool.territoryOwner = territory.Owner_User__c;
			pool.next = territory.Next_Member__c == null ? 0 : territory.Next_Member__c.intValue();
			for (Territory_Member__c member : territory.Members__r) {
				pool.users.add(member.User__c);
				pool.capacities.add(
					member.Capacity__c == null ? null : member.Capacity__c.intValue()
				);
			}
			pools.put(territory.Id, pool);
			if (pool.needsCounts()) {
				counted.add(territory.Id);
			}
		}
		if (!counted.isEmpty()) {
			addCounts(
				pools,
				[
					SELECT Territory__c, OwnerId, COUNT(Id) held
					FROM Contact
					WHERE Territory__c IN :counted
					WITH SYSTEM_MODE
					GROUP BY Territory__c, OwnerId
				]
			);
			addCounts(
				pools,
				[
					SELECT Territory__c, OwnerId, COUNT(Id) held
					FROM Account
					WHERE Territory__c IN :counted
					WITH SYSTEM_MODE
					GROUP BY Territory__c, OwnerId
				]
			);
		}
		return pools;
	}

	private static void addCounts(
		Map<Id, TerritoryRouting.Pool> pools,
		List<AggregateResult> rows
	) {
		for (AggregateResult row : rows) {
			TerritoryRouting.Pool pool = pools.get((Id) row.get('Territory__c'));
			Id owner = (Id) row.get('OwnerId');
			Integer held = (Integer) row.get('held');
			Integer had = pool.owned.get(owner);
			pool.owned.put(owner, (had == null ? 0 : had) + held);
		}
	}
}
