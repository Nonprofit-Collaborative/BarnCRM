/**
 * Restoring archived rows (canonical model R-ARC4, ADR-0240 archive rules and big object archive): a
 * queueable chain whose links alternate, so no transaction mixes ordinary DML with an immediate
 * big object call (the platform refuses that, uncatchably).
 *
 * - Write (DML only): first settles the rows the last Remove deleted (reads them back by key and
 *   subtracts those gone from `Archived_Record_Count__c`), then inserts the next chunk of records
 *   in user mode with only the fields the person may create, a lookup only when its target exists,
 *   and their saved children with the new parent Id. A record whose child could not be created is
 *   deleted again and its row stays archived. Logs each old Id with its new Id and what was left
 *   out on the job, then queues a Remove, or finishes the job when nothing is left.
 * - Remove (no DML): `deleteImmediate`s the rows whose record was created.
 *
 * A row that failed to restore stays archived and is named in the log. A link that dies
 * unexpectedly is caught by its finalizer, which marks the job Failed.
 */
public with sharing class ArchiveRestoreJob implements Queueable {
	/** Rows inserted per Write: each holds at most 131,072 characters of JSON. */
	public static final Integer ROWS_PER_WRITE = 25;
	private static final String WRITE = 'write';
	private static final String REMOVE = 'remove';
	private static final String CONTEXT = 'ArchiveRestoreJob';

	private final Id jobId;
	private final String objectName;
	private List<String> pending;
	private String phase = WRITE;
	/** Row ids whose record this chain created and whose row the next Remove deletes. */
	private List<String> restoredRows = new List<String>();
	private String removeError;

	public ArchiveRestoreJob(Id jobId, String objectName, List<String> rowIds) {
		this.jobId = jobId;
		this.objectName = objectName;
		this.pending = new List<String>(rowIds);
	}

	public void execute(QueueableContext context) {
		if (context != null) {
			System.attachFinalizer(new Finisher(jobId, phase == REMOVE));
		}
		if (phase == REMOVE) {
			remove();
			phase = WRITE;
			BigObjectArchiveJob.queue(this);
			return;
		}
		write();
		if (!restoredRows.isEmpty()) {
			phase = REMOVE;
			BigObjectArchiveJob.queue(this);
		} else if (!pending.isEmpty()) {
			BigObjectArchiveJob.queue(this);
		}
	}

	// -------------------------------------------------------------------------------------
	// Remove: no DML in this transaction
	// -------------------------------------------------------------------------------------

	private void remove() {
		removeError = null;
		try {
			ArchiveStore.get().deleteRows(keysOf(restoredRows));
		} catch (Exception failed) {
			removeError = failed.getMessage();
		}
	}

	// -------------------------------------------------------------------------------------
	// Write: DML only
	// -------------------------------------------------------------------------------------

	private void write() {
		Outcome outcome = new Outcome();
		Savepoint beforeInsert;
		Integer linesBefore = 0;
		Integer chunkSize = 0;
		try {
			settleRemoved(outcome);
			restoredRows = new List<String>();
			if (!pending.isEmpty()) {
				List<String> chunk = new List<String>();
				while (!pending.isEmpty() && chunk.size() < ROWS_PER_WRITE) {
					chunk.add(pending.remove(0));
				}
				chunkSize = chunk.size();
				linesBefore = outcome.lines.size();
				beforeInsert = Database.setSavepoint();
				insertChunk(chunk, outcome);
			}
		} catch (Exception failed) {
			// Nothing this chunk created stays, so no record is both live and archived: every row
			// of the chunk, and every row not yet tried, stays archived.
			if (beforeInsert != null) {
				Database.rollback(beforeInsert);
				while (outcome.lines.size() > linesBefore) {
					outcome.lines.remove(outcome.lines.size() - 1);
				}
				outcome.failed = chunkSize;
			}
			outcome.failed += pending.size();
			outcome.restored = 0;
			ErrorLogger.log(failed, CONTEXT, jobId);
			outcome.stopReason = failed.getMessage();
			pending = new List<String>();
			restoredRows = new List<String>();
		}
		writeJob(outcome);
	}

	/** Reads back the rows the last Remove deleted and counts those gone. */
	private void settleRemoved(Outcome outcome) {
		if (restoredRows.isEmpty()) {
			return;
		}
		Set<String> kept = new Set<String>();
		Map<Datetime, Set<String>> byTime = groupByTime(restoredRows);
		for (Datetime at : byTime.keySet()) {
			for (String originalId : ArchiveStore.get().present(objectName, at, byTime.get(at))) {
				kept.add(at.getTime() + '|' + originalId);
			}
		}
		for (String rowId : kept) {
			outcome.lines.add(
				BarnHelp.text('Core', 'Core_ArchiveViewer_NoteCopyKept', new List<Object>{ rowId.substringAfter('|') })
			);
		}
		if (removeError != null) {
			outcome.lines.add(removeError);
		}
		outcome.removed = restoredRows.size() - kept.size();
		BigObjectArchiveJob.addToCount(-outcome.removed);
	}

	/** Inserts one chunk's records and their children in user mode. */
	private void insertChunk(List<String> chunk, Outcome outcome) {
		Map<String, Archived_Record__b> rowById = new Map<String, Archived_Record__b>();
		Map<Datetime, Set<String>> byTime = groupByTime(chunk);
		for (Datetime at : byTime.keySet()) {
			for (Archived_Record__b row : ArchiveStore.get().rows(objectName, at, byTime.get(at))) {
				rowById.put(row.Archived_At__c.getTime() + '|' + row.Original_Id__c, row);
			}
		}
		Set<Id> lookups = new Set<Id>();
		for (Archived_Record__b row : rowById.values()) {
			if (String.isNotBlank(row.Record_JSON__c)) {
				lookups.addAll(ArchiveRecordJson.lookupsOf(row.Record_JSON__c));
			}
		}
		Set<Id> existing = existingOf(lookups);

		List<String> tried = new List<String>();
		List<ArchiveRecordJson.Restored> made = new List<ArchiveRecordJson.Restored>();
		List<SObject> parents = new List<SObject>();
		for (String rowId : chunk) {
			Archived_Record__b row = rowById.get(rowId);
			String originalId = rowId.substringAfter('|');
			if (row == null || String.isBlank(row.Record_JSON__c)) {
				outcome.fail(BarnHelp.text('Core', 'Core_ArchiveViewer_NoteGone', new List<Object>{ originalId }));
				continue;
			}
			ArchiveRecordJson.Restored restored = ArchiveRecordJson.restore(row.Record_JSON__c, existing);
			if (restored.record == null) {
				outcome.fail(
					BarnHelp.text('Core', 'Core_ArchiveViewer_NoteCannotCreate', new List<Object>{ originalId })
				);
				continue;
			}
			tried.add(rowId);
			made.add(restored);
			parents.add(restored.record);
		}
		List<Database.SaveResult> saved = Database.insert(parents, false, AccessLevel.USER_MODE);

		// Children of the records created, by child object, with the row each belongs to.
		Map<String, List<SObject>> childrenByObject = new Map<String, List<SObject>>();
		Map<String, List<Integer>> ownerByObject = new Map<String, List<Integer>>();
		for (Integer i = 0; i < tried.size(); i++) {
			if (!saved[i].isSuccess()) {
				outcome.fail(
					String.format(
						BarnHelp.text('Core', 'Core_ArchiveViewer_NoteNotCreated'),
						new List<Object>{ tried[i].substringAfter('|'), saved[i].getErrors()[0].getMessage() }
					)
				);
				continue;
			}
			ArchiveRecordJson.Restored restored = made[i];
			for (String childObject : restored.childrenByObject.keySet()) {
				String parentField = restored.parentFieldByObject.get(childObject);
				if (!childrenByObject.containsKey(childObject)) {
					childrenByObject.put(childObject, new List<SObject>());
					ownerByObject.put(childObject, new List<Integer>());
				}
				for (SObject child : restored.childrenByObject.get(childObject)) {
					child.put(parentField, saved[i].getId());
					childrenByObject.get(childObject).add(child);
					ownerByObject.get(childObject).add(i);
				}
			}
		}
		Map<Integer, String> childFailure = new Map<Integer, String>();
		for (String childObject : childrenByObject.keySet()) {
			List<Database.SaveResult> childSaved = Database.insert(
				childrenByObject.get(childObject),
				false,
				AccessLevel.USER_MODE
			);
			for (Integer c = 0; c < childSaved.size(); c++) {
				Integer owner = ownerByObject.get(childObject)[c];
				if (!childSaved[c].isSuccess() && !childFailure.containsKey(owner)) {
					childFailure.put(owner, childObject + ': ' + childSaved[c].getErrors()[0].getMessage());
				}
			}
		}
		// A record whose child failed is taken back out, so its row stays archived whole.
		List<SObject> undo = new List<SObject>();
		for (Integer owner : childFailure.keySet()) {
			undo.add(parents[owner]);
			outcome.fail(
				String.format(
					BarnHelp.text('Core', 'Core_ArchiveViewer_NoteChildFailed'),
					new List<Object>{ tried[owner].substringAfter('|'), childFailure.get(owner) }
				)
			);
		}
		Database.delete(undo, false, AccessLevel.USER_MODE);

		for (Integer i = 0; i < tried.size(); i++) {
			if (!saved[i].isSuccess() || childFailure.containsKey(i)) {
				continue;
			}
			restoredRows.add(tried[i]);
			outcome.restored++;
			outcome.lines.add(
				String.format(
					BarnHelp.text('Core', 'Core_ArchiveViewer_NoteRestored'),
					new List<Object>{ tried[i].substringAfter('|'), saved[i].getId() }
				)
			);
			if (!made[i].dropped.isEmpty()) {
				outcome.lines.add(
					String.format(
						BarnHelp.text('Core', 'Core_ArchiveViewer_NoteDropped'),
						new List<Object>{ tried[i].substringAfter('|'), String.join(made[i].dropped, ', ') }
					)
				);
			}
		}
	}

	/**
	 * Which of these lookup targets the person can still see; an inactive user is not a target,
	 * since a record cannot be owned by or point at one on insert.
	 */
	@TestVisible
	private static Set<Id> existingOf(Set<Id> lookups) {
		Map<Schema.SObjectType, Set<Id>> byType = new Map<Schema.SObjectType, Set<Id>>();
		for (Id one : lookups) {
			Schema.SObjectType type = one.getSObjectType();
			if (!byType.containsKey(type)) {
				byType.put(type, new Set<Id>());
			}
			byType.get(type).add(one);
		}
		Set<Id> result = new Set<Id>();
		for (Schema.SObjectType type : byType.keySet()) {
			Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
			if (!described.isAccessible() || !described.isQueryable()) {
				continue;
			}
			String soql =
				'SELECT Id FROM ' +
				described.getName() +
				' WHERE Id IN :ids' +
				(type == User.SObjectType ? ' AND IsActive = true' : '');
			try {
				for (
					SObject found : Database.queryWithBinds(
						soql,
						new Map<String, Object>{ 'ids' => byType.get(type) },
						AccessLevel.USER_MODE
					)
				) {
					result.add(found.Id);
				}
			} catch (Exception notReadable) {
				// An object that cannot be queried this way: its lookups are left out, and logged as such.
				continue;
			}
		}
		return result;
	}

	private void writeJob(Outcome outcome) {
		Import_Batch__c job = [
			SELECT Id, Run_Log__c, Rows_Created__c, Rows_Deleted__c, Rows_Rejected__c
			FROM Import_Batch__c
			WHERE Id = :jobId
			WITH SYSTEM_MODE
			LIMIT 1
			FOR UPDATE
		];
		List<String> lines = new List<String>{ job.Run_Log__c };
		lines.addAll(outcome.lines);
		Integer created = DataJobs.intOf(job.Rows_Created__c) + outcome.restored;
		Integer removed = DataJobs.intOf(job.Rows_Deleted__c) + outcome.removed;
		Integer rejected = DataJobs.intOf(job.Rows_Rejected__c) + outcome.failed;
		Boolean finished = pending.isEmpty() && restoredRows.isEmpty();
		if (finished) {
			lines.add(
				String.format(
					BarnHelp.text('Core', 'Core_ArchiveViewer_LogDone'),
					new List<Object>{ removed.format(), rejected.format() }
				)
			);
			if (outcome.stopReason != null) {
				lines.add(outcome.stopReason);
			}
		}
		Database.update(
			new Import_Batch__c(
				Id = jobId,
				Rows_Created__c = created,
				Rows_Deleted__c = removed,
				Rows_Rejected__c = rejected,
				Run_Log__c = String.join(lines, '\n').right(32768),
				Status__c = !finished
					? ImportBatchService.STATUS_COMMITTING
					: (outcome.stopReason == null
							? ImportBatchService.STATUS_COMPLETE
							: ImportBatchService.STATUS_FAILED),
				Completed_At__c = finished ? Datetime.now() : null
			),
			AccessLevel.SYSTEM_MODE
		);
	}

	// -------------------------------------------------------------------------------------
	// Shared
	// -------------------------------------------------------------------------------------

	private List<ArchiveStore.Key> keysOf(List<String> rowIds) {
		List<ArchiveStore.Key> keys = new List<ArchiveStore.Key>();
		for (String rowId : rowIds) {
			keys.add(ArchiveViewerService.keyOf(objectName, rowId));
		}
		return keys;
	}

	private Map<Datetime, Set<String>> groupByTime(List<String> rowIds) {
		Map<Datetime, Set<String>> result = new Map<Datetime, Set<String>>();
		for (ArchiveStore.Key key : keysOf(rowIds)) {
			if (!result.containsKey(key.archivedAt)) {
				result.put(key.archivedAt, new Set<String>());
			}
			result.get(key.archivedAt).add(key.originalId);
		}
		return result;
	}

	/** What one Write did. */
	private class Outcome {
		Integer restored = 0;
		Integer removed = 0;
		Integer failed = 0;
		String stopReason;
		List<String> lines = new List<String>();

		void fail(String line) {
			failed++;
			lines.add(line);
		}
	}

	/**
	 * Marks the job Failed when a link dies unexpectedly. A Write rolls back, so nothing it
	 * created stays; a Remove that dies leaves restored records whose rows are still archived,
	 * which the log says. Runs in its own transaction.
	 */
	public with sharing class Finisher implements Finalizer {
		private final Id jobId;
		private final Boolean removing;

		public Finisher(Id jobId, Boolean removing) {
			this.jobId = jobId;
			this.removing = removing;
		}

		public void execute(FinalizerContext context) {
			if (context == null || context.getResult() != ParentJobResult.UNHANDLED_EXCEPTION) {
				return;
			}
			String reason = context.getException()?.getMessage();
			if (removing) {
				reason =
					BarnHelp.text('Core', 'Core_ArchiveViewer_LogRemoveStopped') + (reason == null ? '' : ' ' + reason);
			}
			BigObjectArchiveJob.fail(jobId, reason);
		}
	}
}
