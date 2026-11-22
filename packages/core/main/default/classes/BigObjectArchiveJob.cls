/**
 * A big object archive run (canonical model R-ARC3, ADR-0240 archive rules and big object archive):
 * a queueable chain whose links alternate between Copy and Settle, because no immediate big
 * object call may follow ordinary DML in a transaction (the platform refuses it, uncatchably).
 *
 * - Copy (no DML): deletes copies the last Settle could not finish (one retry, then the run log
 *   counts any that stay), reads the next chunk of matching records in user mode, Id order, with
 *   every readable field and their cascade-delete children (the chunk halved until the children
 *   fit `childRows`), and writes them with `insertImmediate`.
 * - Settle (DML only): reads the copies back by full key, reads the originals again, deletes in
 *   user mode those copied and unchanged since the run started, counts them, writes the job, and
 *   queues the next Copy with any copy whose original stayed.
 *
 * Each Copy stamps its rows with a new archive time, so a later Copy never overwrites an earlier
 * one's rows. A link that dies unexpectedly is caught by its finalizer, which deletes that link's
 * copies (a Settle's too, since its deletes roll back) and marks the job Failed.
 */
public with sharing class BigObjectArchiveJob implements Queueable {
	public static final String OPERATION_ARCHIVE = 'Archive';
	/** Records per Copy. */
	public static final Integer CHUNK = 200;
	/** Characters of JSON one Copy writes at most, kept well inside the async heap. */
	public static final Integer JSON_BUDGET = 4000000;
	/** Rows included per org; past it the platform charges, so BarnCRM stops (R-ARC5). */
	public static final Integer CAP = 1000000;
	/** Where the panels start to warn. */
	public static final Integer WARN_AT = 900000;
	/** Cascade-delete child rows one Copy reads at most, for the heap and the query row limit. */
	@TestVisible
	private static Integer childRows = 2000;
	/** Notes written to the Run Log per link; the rest are counted. */
	private static final Integer NOTES_SHOWN = 20;
	private static final String COPY = 'copy';
	private static final String SETTLE = 'settle';
	private static final String CONTEXT = 'BigObjectArchiveJob';
	/** The archived row count's run-state key (R-ARC5), the field name it had on BarnCRM Settings. */
	public static final String COUNT_KEY = 'Archived_Record_Count__c';

	/** Set by tests: links are added here instead of being queued, so a test runs each in turn. */
	@TestVisible
	private static List<Object> queuedForTest;
	/** The last link's finisher, for a test. */
	@TestVisible
	private static Finisher lastFinisher;

	private final Id jobId;
	private final String queryJson;
	private final String objectName;
	private final Id ruleId;
	private final String ruleName;
	private final Datetime notChangedAfter;
	private String phase = COPY;
	private Integer remaining;
	private Id lastId;
	private Datetime copiedAt;
	/** The last Copy's saved rows: record name by Original Id. */
	private Map<String, String> copiedNames = new Map<String, String>();
	private List<String> notes = new List<String>();
	@TestVisible
	private List<ArchiveStore.Key> orphans = new List<ArchiveStore.Key>();
	/** Copies a Copy could not delete, told in the next run log write. */
	private Integer copiesLeft = 0;
	private Boolean done = false;
	private String stopReason;

	public BigObjectArchiveJob(Id jobId, ArchiveRun run, Datetime notChangedAfter) {
		this.jobId = jobId;
		this.queryJson = run.queryJson;
		this.objectName = run.objectName;
		this.ruleId = run.savedQueryId;
		this.ruleName = run.ruleName;
		this.remaining = run.confirmedCount;
		this.notChangedAfter = notChangedAfter;
	}

	public void execute(QueueableContext context) {
		Finisher finisher = new Finisher(jobId, BarnHelp.text('Core', 'Core_ArchiveRules_LogStopped'));
		lastFinisher = finisher;
		if (context != null) {
			System.attachFinalizer(finisher);
		}
		if (phase == COPY) {
			copy(finisher);
			phase = SETTLE;
		} else {
			// A Settle that dies, queuing the next link included, rolls its deletes back: its copies go too.
			for (String one : copiedNames.keySet()) {
				finisher.copied.add(new ArchiveStore.Key(objectName, copiedAt, one));
			}
			settle();
			phase = COPY;
		}
		if (phase == SETTLE || !done || !orphans.isEmpty()) {
			queue(this);
		}
	}

	// -------------------------------------------------------------------------------------
	// Copy: no DML in this transaction
	// -------------------------------------------------------------------------------------

	private void copy(Finisher finisher) {
		copiedNames = new Map<String, String>();
		notes = new List<String>();
		deleteOrphans();
		try {
			if (done || remaining == null || remaining <= 0) {
				done = true;
				return;
			}
			QueryCompiler.Compiled idPage = QueryCompiler.compileIdPage(queryJson, lastId, Math.min(CHUNK, remaining));
			List<SObject> page = Database.queryWithBinds(idPage.soql, idPage.binds, AccessLevel.USER_MODE);
			if (page.isEmpty()) {
				done = true;
				return;
			}
			if (archivedCount() + page.size() > CAP) {
				stopReason = String.format(
					BarnHelp.text('Core', 'Core_ArchiveRules_LogCap'),
					new List<Object>{ CAP.format() }
				);
				done = true;
				return;
			}
			List<Archived_Record__b> rows = rowsFor(page);
			List<Boolean> saved = ArchiveStore.get().insertRows(rows);
			for (Integer i = 0; i < rows.size(); i++) {
				if (saved[i]) {
					copiedNames.put(rows[i].Original_Id__c, rows[i].Record_Name__c);
					finisher.copied.add(new ArchiveStore.Key(objectName, copiedAt, rows[i].Original_Id__c));
				} else {
					notes.add(note(BarnHelp.text('Core', 'Core_ArchiveRules_NoteNotSaved'), rows[i].Record_Name__c));
				}
			}
		} catch (Exception failed) {
			stopReason = failed.getMessage();
			done = true;
		}
	}

	/** Deletes the copies the last Settle kept out, retrying once; the run log counts any that stay. */
	private void deleteOrphans() {
		if (orphans.isEmpty()) {
			return;
		}
		Integer gone = 0;
		for (Integer tries = 0; tries < 2; tries++) {
			try {
				gone = ArchiveStore.get().deleteRows(orphans);
				break;
			} catch (Exception notDeleted) {
				gone = 0;
			}
		}
		copiesLeft += orphans.size() - gone;
		orphans = new List<ArchiveStore.Key>();
	}

	/** The rows for a page of Ids, stopping early at the JSON budget; moves the cursor. */
	@TestVisible
	private List<Archived_Record__b> rowsFor(List<SObject> page) {
		BulkDeleteService.Plan checked = BulkDeleteService.plan(queryJson);
		Schema.DescribeSObjectResult described = checked.objectType.getDescribe(SObjectDescribeOptions.DEFERRED);
		List<ArchiveRecordJson.ChildKind> kinds = ArchiveRecordJson.childKinds(described);
		Set<Id> ids = new Map<Id, SObject>(page).keySet();
		Integer childCount = countChildren(kinds, ids);
		// Too many children to read at once: the first half of the parents, until one is left.
		while (childCount > childRows && page.size() > 1) {
			List<SObject> half = new List<SObject>();
			for (Integer i = 0; i < page.size() / 2; i++) {
				half.add(page[i]);
			}
			page = half;
			ids = new Map<Id, SObject>(page).keySet();
			childCount = countChildren(kinds, ids);
		}
		Boolean tooMany = childCount > childRows;
		Set<String> fields = new Set<String>(BulkDeleteService.backupFieldNames(checked.objectType));
		fields.add('SystemModstamp');
		QueryCompiler.Compiled read = QueryCompiler.compileSelection(queryJson, fields, ids);
		Map<Id, SObject> records = new Map<Id, SObject>(
			Database.queryWithBinds(read.soql, read.binds, AccessLevel.USER_MODE)
		);
		Map<String, String> fieldByObject = new Map<String, String>();
		Map<Id, Map<String, List<SObject>>> children = tooMany
			? new Map<Id, Map<String, List<SObject>>>()
			: childrenOf(kinds, ids, fieldByObject);
		Boolean hasOwner = described.fields.getMap().containsKey('OwnerId');

		copiedAt = Datetime.newInstance((Datetime.now().getTime() / 1000) * 1000);
		List<Archived_Record__b> rows = new List<Archived_Record__b>();
		Integer budget = JSON_BUDGET;
		Integer used = 0;
		for (SObject idOnly : page) {
			SObject record = records.get(idOnly.Id);
			used++;
			lastId = idOnly.Id;
			if (record == null) {
				continue;
			}
			String name = checked.nameOf(record);
			Datetime changed = (Datetime) record.get('SystemModstamp');
			if (changed != null && changed > notChangedAfter) {
				notes.add(note(BarnHelp.text('Core', 'Core_ArchiveRules_NoteChanged'), name));
				continue;
			}
			Map<String, List<SObject>> mine = children.containsKey(record.Id)
				? children.get(record.Id)
				: new Map<String, List<SObject>>();
			String body = tooMany ? null : ArchiveRecordJson.toJson(record, mine, fieldByObject);
			if (body == null || body.length() > ArchiveRecordJson.MAX_JSON) {
				notes.add(note(BarnHelp.text('Core', 'Core_ArchiveRules_NoteTooLarge'), name));
				continue;
			}
			List<SObject> allChildren = new List<SObject>();
			for (List<SObject> kind : mine.values()) {
				allChildren.addAll(kind);
			}
			rows.add(
				new Archived_Record__b(
					Object_Name__c = objectName,
					Archived_At__c = copiedAt,
					Original_Id__c = String.valueOf(record.Id),
					Record_Name__c = name.left(255),
					Owner_Id__c = hasOwner ? (String) record.get('OwnerId') : null,
					Record_JSON__c = body,
					Person_Ids__c = ArchiveRecordJson.peopleOf(record, allChildren),
					Rule_Id__c = ruleId,
					Rule_Name__c = ruleName == null ? null : ruleName.left(80)
				)
			);
			budget -= body.length();
			if (budget <= 0) {
				break;
			}
		}
		remaining -= used;
		return rows;
	}

	/** How many cascade-delete children these records have, counted in user mode. */
	private static Integer countChildren(List<ArchiveRecordJson.ChildKind> kinds, Set<Id> ids) {
		Integer total = 0;
		for (ArchiveRecordJson.ChildKind kind : kinds) {
			total += Database.countQueryWithBinds(
				'SELECT COUNT() FROM ' + kind.objectName + ' WHERE ' + kind.fieldName + ' IN :ids',
				new Map<String, Object>{ 'ids' => ids },
				AccessLevel.USER_MODE
			);
		}
		return total;
	}

	/** Each record's cascade-delete children, by record and child object, read in user mode. */
	private static Map<Id, Map<String, List<SObject>>> childrenOf(
		List<ArchiveRecordJson.ChildKind> kinds,
		Set<Id> ids,
		Map<String, String> fieldByObject
	) {
		Map<Id, Map<String, List<SObject>>> result = new Map<Id, Map<String, List<SObject>>>();
		for (ArchiveRecordJson.ChildKind kind : kinds) {
			fieldByObject.put(kind.objectName, kind.fieldName);
			List<String> childFields = BulkDeleteService.backupFieldNames(NamespaceUtil.objectType(kind.objectName));
			for (
				SObject child : Database.queryWithBinds(
					'SELECT ' +
						String.join(childFields, ', ') +
						' FROM ' +
						kind.objectName +
						' WHERE ' +
						kind.fieldName +
						' IN :ids',
					new Map<String, Object>{ 'ids' => ids },
					AccessLevel.USER_MODE
				)
			) {
				Id parentId = (Id) child.get(kind.fieldName);
				if (!result.containsKey(parentId)) {
					result.put(parentId, new Map<String, List<SObject>>());
				}
				Map<String, List<SObject>> byObject = result.get(parentId);
				if (!byObject.containsKey(kind.objectName)) {
					byObject.put(kind.objectName, new List<SObject>());
				}
				byObject.get(kind.objectName).add(child);
			}
		}
		return result;
	}

	// -------------------------------------------------------------------------------------
	// Settle: DML only
	// -------------------------------------------------------------------------------------

	private void settle() {
		Integer deleted = 0;
		Integer kept = 0;
		try {
			Set<String> present = copiedNames.isEmpty()
				? new Set<String>()
				: ArchiveStore.get().present(objectName, copiedAt, copiedNames.keySet());
			for (String copied : copiedNames.keySet()) {
				if (!present.contains(copied)) {
					notes.add(note(BarnHelp.text('Core', 'Core_ArchiveRules_NoteNotSaved'), copiedNames.get(copied)));
				}
			}
			if (!present.isEmpty()) {
				Integer[] counts = deleteOriginals(present);
				deleted = counts[0];
				kept = counts[1];
			}
			addToCount(deleted + kept);
			writeJob(deleted);
		} catch (Exception failed) {
			ErrorLogger.log(failed, CONTEXT, jobId);
			stopReason = failed.getMessage();
			done = true;
			writeJob(deleted);
		}
	}

	/**
	 * Deletes the originals of rows that were copied, when unchanged since the run started.
	 * Returns the count deleted and the count already gone (their copies are kept and counted).
	 */
	private Integer[] deleteOriginals(Set<String> present) {
		Set<Id> ids = new Set<Id>();
		for (String one : present) {
			ids.add(Id.valueOf(one));
		}
		Map<Id, SObject> originals = new Map<Id, SObject>(
			Database.queryWithBinds(
				'SELECT Id, SystemModstamp FROM ' + objectName + ' WHERE Id IN :ids',
				new Map<String, Object>{ 'ids' => ids },
				AccessLevel.USER_MODE
			)
		);
		Integer gone = 0;
		List<SObject> toDelete = new List<SObject>();
		for (Id one : ids) {
			SObject original = originals.get(one);
			if (original == null) {
				gone++;
			} else if ((Datetime) original.get('SystemModstamp') > notChangedAfter) {
				orphans.add(new ArchiveStore.Key(objectName, copiedAt, String.valueOf(one)));
				notes.add(
					note(BarnHelp.text('Core', 'Core_ArchiveRules_NoteChanged'), copiedNames.get(String.valueOf(one)))
				);
			} else {
				toDelete.add(original);
			}
		}
		Integer deleted = 0;
		List<Database.DeleteResult> results = Database.delete(toDelete, false, AccessLevel.USER_MODE);
		for (Integer i = 0; i < results.size(); i++) {
			if (results[i].isSuccess()) {
				deleted++;
			} else {
				orphans.add(new ArchiveStore.Key(objectName, copiedAt, String.valueOf(toDelete[i].Id)));
				notes.add(
					String.format(
						BarnHelp.text('Core', 'Core_ArchiveRules_NoteNotDeleted'),
						new List<Object>{
							copiedNames.get(String.valueOf(toDelete[i].Id)),
							results[i].getErrors()[0].getMessage()
						}
					)
				);
			}
		}
		return new List<Integer>{ deleted, gone };
	}

	private void writeJob(Integer deleted) {
		Import_Batch__c job = [
			SELECT Id, Run_Log__c, Rows_Deleted__c, Rows_Rejected__c
			FROM Import_Batch__c
			WHERE Id = :jobId
			WITH SYSTEM_MODE
			LIMIT 1
			FOR UPDATE
		];
		List<String> lines = new List<String>{ job.Run_Log__c };
		if (copiesLeft > 0) {
			lines.add(
				BarnHelp.text('Core', 'Core_ArchiveRules_NoteCopiesLeft', new List<Object>{ copiesLeft.format() })
			);
			copiesLeft = 0;
		}
		for (Integer i = 0; i < Math.min(notes.size(), NOTES_SHOWN); i++) {
			lines.add(notes[i]);
		}
		if (notes.size() > NOTES_SHOWN) {
			lines.add(
				String.format(
					BarnHelp.text('Core', 'Core_ArchiveRules_NoteMore'),
					new List<Object>{ (notes.size() - NOTES_SHOWN).format() }
				)
			);
		}
		Integer totalDeleted = DataJobs.intOf(job.Rows_Deleted__c) + deleted;
		Integer rejected = DataJobs.intOf(job.Rows_Rejected__c) + notes.size();
		Boolean finished = done && orphans.isEmpty();
		if (finished) {
			lines.add(
				String.format(
					BarnHelp.text('Core', 'Core_ArchiveRules_LogDone'),
					new List<Object>{ totalDeleted.format(), rejected.format() }
				)
			);
			if (stopReason != null) {
				lines.add(stopReason);
			}
		}
		Database.update(
			new Import_Batch__c(
				Id = jobId,
				Rows_Deleted__c = totalDeleted,
				Rows_Rejected__c = rejected,
				Run_Log__c = String.join(lines, '\n').right(32768),
				Status__c = !finished
					? ImportBatchService.STATUS_COMMITTING
					: (stopReason == null ? ImportBatchService.STATUS_COMPLETE : ImportBatchService.STATUS_FAILED),
				Completed_At__c = finished ? Datetime.now() : null
			),
			AccessLevel.SYSTEM_MODE
		);
		notes = new List<String>();
	}

	// -------------------------------------------------------------------------------------
	// Shared
	// -------------------------------------------------------------------------------------

	/** The rows the big object holds, as Core counts them (R-ARC5). */
	public static Integer archivedCount() {
		return DataJobs.intOf(SettingsState.number(COUNT_KEY));
	}

	/**
	 * Adds to the count (or takes away, with a negative change); never below zero. The count is
	 * run state (SettingsState), locked on its row so parallel links do not lose a change.
	 */
	public static void addToCount(Integer change) {
		if (change == null || change == 0) {
			return;
		}
		Object stored = SettingsState.lockOrCreate(COUNT_KEY);
		Integer now = DataJobs.intOf(SettingsService.toNumber(stored));
		SettingsState.put(new Map<String, Object>{ COUNT_KEY => Math.max(0, now + change) });
	}

	/**
	 * The values under `key` in the definitions (Operation JSON) of the Archive jobs still running
	 * with this `action`: `archive` and `savedQueryId` (R-SQ18), or `restore` and `rowIds`
	 * (R-ARC4). Read in system mode: the package's own bookkeeping (ADR-0021).
	 */
	public static Set<String> running(String action, String key) {
		Set<String> result = new Set<String>();
		for (Import_Batch__c job : [
			SELECT Operation_JSON__c
			FROM Import_Batch__c
			WHERE Operation__c = :OPERATION_ARCHIVE AND Status__c = :ImportBatchService.STATUS_COMMITTING
			WITH SYSTEM_MODE
			LIMIT 200
		]) {
			Map<String, Object> definition = (Map<String, Object>) JSON.deserializeUntyped(job.Operation_JSON__c);
			Object value = action.equals(definition.get('action')) ? definition.get(key) : null;
			for (Object one : value instanceof List<Object> ? (List<Object>) value : new List<Object>{ value }) {
				result.add((String) one);
			}
		}
		return result;
	}

	/** Refuses to start a rule whose last run is still going (R-SQ18). */
	public static void requireIdle(Id savedQueryId) {
		if (savedQueryId != null && running('archive', 'savedQueryId').contains(savedQueryId)) {
			throw new ArchiveRules.ArchiveRuleException(BarnHelp.text('Core', 'Core_ArchiveRules_ErrorRunning'));
		}
	}

	/** Queues the next link, or hands it to a test. */
	public static void queue(Queueable next) {
		if (queuedForTest != null) {
			queuedForTest.add(next);
			return;
		}
		AsyncStarter.queue(next, CONTEXT);
	}

	private static String note(String template, String name) {
		return String.format(template, new List<Object>{ name });
	}

	/**
	 * The finalizer of every archive, restore and erasure link: when a link dies unexpectedly it
	 * deletes that link's copies, so a record is never left both live and archived, then marks the
	 * job Failed with the run log line `line` (a help text), or, with no job (erasure), logs that
	 * line, {0} filled with the reason, as an Error. Runs in its own transaction.
	 */
	public with sharing class Finisher implements Finalizer {
		private final Id jobId;
		private final String line;
		public List<ArchiveStore.Key> copied = new List<ArchiveStore.Key>();

		public Finisher(Id jobId, String line) {
			this.jobId = jobId;
			this.line = line;
		}

		public void execute(FinalizerContext context) {
			if (context != null && context.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
				stopped(context.getException()?.getMessage());
			}
		}

		@TestVisible
		private void stopped(String reason) {
			try {
				ArchiveStore.get().deleteRows(copied);
			} catch (Exception notDeleted) {
				// Logged below with the failure; the copies stay and the log says the run failed.
				copied = new List<ArchiveStore.Key>();
			}
			if (jobId == null) {
				ErrorLogger.logMessages(
					new List<String>{ line.replace('{0}', String.valueOf(reason)) },
					CONTEXT,
					ErrorLogger.SEVERITY_ERROR
				);
			} else {
				fail(jobId, line, reason);
			}
		}
	}

	/** Marks a job Failed with the run log line `line` and a reason, logging any failure to do so. Never throws. */
	public static void fail(Id jobId, String line, String reason) {
		try {
			Import_Batch__c job = DataJobs.forFinish(jobId);
			Database.update(
				new Import_Batch__c(
					Id = jobId,
					Status__c = ImportBatchService.STATUS_FAILED,
					Completed_At__c = Datetime.now(),
					Run_Log__c = (job.Run_Log__c + '\n' + line + (reason == null ? '' : ' ' + reason)).right(32768)
				),
				AccessLevel.SYSTEM_MODE
			);
		} catch (Exception notMarked) {
			ErrorLogger.log(notMarked, CONTEXT, jobId);
		}
	}
}
