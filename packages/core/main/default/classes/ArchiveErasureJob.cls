/**
 * Deletes the archived rows that name an erased person (canonical model R-ARC6, ADR-0240 archive
 * rules and big object archive item 10), queued by `ArchiveErasureExtension`. Links alternate, so
 * no transaction mixes DML with an immediate big object call:
 *
 * - Find (DML, no immediate call): runs only when the person's Erasure record exists, so a
 *   preview or an erasure rolled back does nothing. Settles the rows the last Remove deleted
 *   (`ArchiveCountSettle`: read back by key, the count lowered by those gone), then walks the
 *   archived objects in index order, a page at a time, for rows whose Original Id is one of the
 *   person's records or whose People names one of them. Rows found are saved as pending on the
 *   erasure's own Archive job (made with the first rows found) before a Remove is queued (D-223).
 * - Remove (no DML): `deleteImmediate`s those rows.
 *
 * Big object reads and deletes run in system mode: erasure is the organization's duty, whoever
 * erases, and the person erasing was checked by `PersonErasure`.
 */
public with sharing class ArchiveErasureJob implements Queueable {
	/** Rows read per page. */
	@TestVisible
	private static final Integer PAGE = 200;
	/** Pages read per Find link. */
	@TestVisible
	private static final Integer PAGES_PER_LINK = 10;
	private static final String LOG_CONTEXT = 'ArchiveErasureJob';

	private final Id personId;
	private Set<String> people;
	private Boolean started = false;
	private String objectName;
	private Datetime afterAt;
	private String afterId;
	/** The erasure's Archive job, which holds the pending rows and the count of rows removed. */
	@TestVisible
	private Id jobId;
	/** The rows the next Remove deletes; null in a Find link. */
	@TestVisible
	private List<ArchiveStore.Key> doomed;
	private String removeError;
	private Integer deleted = 0;

	public ArchiveErasureJob(Id personId) {
		this.personId = personId;
	}

	public void execute(QueueableContext context) {
		if (context != null) {
			// A link that dies unexpectedly is logged as an Error naming no record (the person is
			// erased); its finisher settles the count and marks the erasure's job Failed.
			BigObjectArchiveJob.Finisher finisher = new BigObjectArchiveJob.Finisher(
				null,
				BarnHelp.text('Core', 'Core_ArchiveErasure_Stopped')
			);
			finisher.pendingJobId = jobId;
			System.attachFinalizer(finisher);
		}
		if (doomed != null) {
			try {
				ArchiveStore.get().deleteRows(doomed);
			} catch (Exception failed) {
				// Logged by the next Find: an Error Log insert may not share this transaction.
				removeError = failed.getMessage();
			}
			doomed = null;
			BigObjectArchiveJob.queue(this);
			return;
		}
		find();
	}

	private void find() {
		if (jobId != null) {
			// Outside the try: a settle that fails ends the link, and its finisher or the nightly
			// sweep settles the saved rows instead.
			deleted += ArchiveCountSettle.settle(jobId).removed;
		}
		String failure = removeError;
		try {
			if (!started) {
				people = erasedRecords();
				if (people == null) {
					return;
				}
				started = true;
				objectName = ArchiveStore.get().nextObject(null);
			}
			if (failure == null) {
				List<ArchiveStore.Key> found = scan();
				if (!found.isEmpty()) {
					savePending(found);
					doomed = found;
					BigObjectArchiveJob.queue(this);
					return;
				}
				if (objectName != null) {
					BigObjectArchiveJob.queue(this);
					return;
				}
			}
		} catch (Exception failed) {
			failure = failed.getMessage();
		}
		finish(failure);
	}

	/**
	 * The Ids the erasure covers, from the Erasure record: the erased record, and the contact
	 * or person account it names. Null when there is no Erasure record for the person.
	 */
	private Set<String> erasedRecords() {
		String id18 = String.valueOf(personId);
		List<Erasure__c> found = [
			SELECT Erased_Record_Id__c, Contact__c, Person_Account__c
			FROM Erasure__c
			WHERE Erased_Record_Id__c = :id18
			WITH SYSTEM_MODE
			LIMIT 1
		];
		if (found.isEmpty()) {
			return null;
		}
		Set<String> result = new Set<String>{ id18 };
		if (found[0].Contact__c != null) {
			result.add(String.valueOf(found[0].Contact__c));
		}
		if (found[0].Person_Account__c != null) {
			result.add(String.valueOf(found[0].Person_Account__c));
		}
		return result;
	}

	/** Reads up to `PAGES_PER_LINK` pages; returns the keys of the rows naming the person. */
	private List<ArchiveStore.Key> scan() {
		List<ArchiveStore.Key> found = new List<ArchiveStore.Key>();
		// Apex names ignore case: the counter must not be called page, which would hide PAGE.
		for (Integer pagesRead = 0; pagesRead < PAGES_PER_LINK && objectName != null; pagesRead++) {
			List<Archived_Record__b> rows = ArchiveStore.get().scan(objectName, afterAt, afterId, PAGE);
			for (Archived_Record__b row : rows) {
				if (namesPerson(row)) {
					found.add(new ArchiveStore.Key(row.Object_Name__c, row.Archived_At__c, row.Original_Id__c));
				}
			}
			if (rows.size() < PAGE) {
				objectName = ArchiveStore.get().nextObject(objectName);
				afterAt = null;
				afterId = null;
			} else {
				Archived_Record__b last = rows[rows.size() - 1];
				afterAt = last.Archived_At__c;
				afterId = last.Original_Id__c;
			}
		}
		return found;
	}

	private Boolean namesPerson(Archived_Record__b row) {
		if (people.contains(row.Original_Id__c)) {
			return true;
		}
		for (String one : people) {
			if (ArchiveRecordJson.names(row.Person_Ids__c, one)) {
				return true;
			}
		}
		return false;
	}

	/**
	 * Saves the rows the next Remove deletes on the erasure's job, making the job with the first
	 * ones. It names no person: the rows are cleared once settled. Bookkeeping (ADR-0021).
	 */
	private void savePending(List<ArchiveStore.Key> found) {
		List<Object> pending = ArchiveCountSettle.removing(found);
		if (jobId != null) {
			Import_Batch__c job = [SELECT Operation_JSON__c FROM Import_Batch__c WHERE Id = :jobId WITH SYSTEM_MODE];
			Database.update(
				new Import_Batch__c(
					Id = jobId,
					Operation_JSON__c = ArchiveCountSettle.withPending(job.Operation_JSON__c, pending)
				),
				AccessLevel.SYSTEM_MODE
			);
			return;
		}
		Import_Batch__c job = new Import_Batch__c(
			Operation__c = BigObjectArchiveJob.OPERATION_ARCHIVE,
			Operation_JSON__c = JSON.serialize(
				new Map<String, Object>{
					'version' => 1,
					'action' => 'erase',
					'name' => BarnHelp.text('Core', 'Core_ArchiveErasure_RunName'),
					ArchiveCountSettle.PENDING => pending
				}
			),
			Status__c = ImportBatchService.STATUS_COMMITTING,
			Is_Dry_Run__c = false,
			Rows_Created__c = 0,
			Rows_Deleted__c = 0,
			Rows_Rejected__c = 0,
			Started_At__c = Datetime.now(),
			Committed_By__c = UserInfo.getUserId(),
			Run_Log__c = BarnHelp.text('Core', 'Core_ArchiveErasure_RunName')
		);
		Database.insert(job, AccessLevel.SYSTEM_MODE);
		jobId = job.Id;
	}

	/** Logs any failure and finishes the erasure's job, if it has one. */
	private void finish(String failure) {
		if (failure != null) {
			ErrorLogger.logMessages(new List<String>{ failure }, LOG_CONTEXT, ErrorLogger.SEVERITY_ERROR);
		}
		if (jobId == null) {
			return;
		}
		Import_Batch__c job = DataJobs.forFinish(jobId);
		String done = BarnHelp.text('Core', 'Core_ArchiveErasure_LogDone', new List<Object>{ deleted.format() });
		Database.update(
			new Import_Batch__c(
				Id = jobId,
				Rows_Deleted__c = deleted,
				Status__c = failure == null ? ImportBatchService.STATUS_COMPLETE : ImportBatchService.STATUS_FAILED,
				Completed_At__c = Datetime.now(),
				Run_Log__c = (job.Run_Log__c + '\n' + done + (failure == null ? '' : '\n' + failure)).right(32768)
			),
			AccessLevel.SYSTEM_MODE
		);
	}
}
