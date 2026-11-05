/**
 * Records a field access change or its undo (C-65, canonical model R-FA1, R-FA6, R-FA7).
 *
 * `ObjectPermissions` and `FieldPermissions` are setup objects: the platform refuses a data
 * job, a journal page or an Error Log entry in the transaction that wrote them (mixed DML). So
 * `FieldAccessService` writes the permission rows and enqueues this job, which writes the data
 * job, its journal pages and any refusals in a transaction of its own, as the same person. The
 * data job and its journal are the package's own bookkeeping, written in system mode
 * (ADR-0021), as a bulk update's are.
 */
public with sharing class FieldAccessRecordJob implements Queueable {
	private static final String LOG_CONTEXT = 'FieldAccessService';

	private Boolean undoing;
	private Id jobId;
	private String definition;
	private Integer setCount;
	private Integer changed;
	private Integer refused;
	private Integer kept;
	private String entriesJson;
	private List<String> failures;
	private Datetime startedAt;
	private String byName;

	private FieldAccessRecordJob(FieldAccessService.Result result) {
		this.changed = result.changed;
		this.refused = result.refused;
		this.kept = result.kept;
		this.entriesJson = JSON.serialize(result.entries);
		this.failures = result.failures;
		this.startedAt = Datetime.now();
		this.byName = UserInfo.getName();
	}

	/** Enqueues the record of an apply: the data job, its Commit journal and refusals. */
	public static void recordApply(
		FieldAccessService.Plan plan,
		Integer confirmedCount,
		FieldAccessService.Result result
	) {
		FieldAccessRecordJob job = new FieldAccessRecordJob(result);
		job.undoing = false;
		job.setCount = plan.setCount;
		job.definition = JSON.serialize(
			new Map<String, Object>{
				'version' => 1,
				'change' => plan.document,
				'confirmedCount' => confirmedCount
			}
		);
		System.enqueueJob(job);
	}

	/** Enqueues the record of an undo: its Undo journal, the job's status and refusals. */
	public static void recordUndo(Id jobId, FieldAccessService.Result result) {
		FieldAccessRecordJob job = new FieldAccessRecordJob(result);
		job.undoing = true;
		job.jobId = jobId;
		System.enqueueJob(job);
	}

	public void execute(QueueableContext context) {
		List<Map<String, Object>> entries = new List<Map<String, Object>>();
		for (Object each : (List<Object>) JSON.deserializeUntyped(entriesJson)) {
			entries.add((Map<String, Object>) each);
		}
		if (undoing) {
			recordUndone(entries);
		} else {
			recordApplied(entries);
		}
		if (!failures.isEmpty()) {
			ErrorLogger.logMessages(failures, LOG_CONTEXT, ErrorLogger.SEVERITY_WARNING);
		}
	}

	private void recordApplied(List<Map<String, Object>> entries) {
		Datetime now = Datetime.now();
		Import_Batch__c job = new Import_Batch__c(
			Operation__c = FieldAccessService.OPERATION_ACCESS,
			Operation_JSON__c = definition,
			Status__c = changed > 0
				? ImportBatchService.STATUS_COMPLETE
				: ImportBatchService.STATUS_FAILED,
			Is_Dry_Run__c = false,
			Row_Count__c = changed + refused,
			Rows_Created__c = 0,
			Rows_Updated__c = changed,
			Rows_Matched__c = 0,
			Rows_Rejected__c = refused,
			Started_At__c = startedAt,
			Completed_At__c = now,
			Committed_By__c = UserInfo.getUserId(),
			Undo_Deadline__c = startedAt.addDays(ImportBatchService.undoWindowDays()),
			Run_Log__c = String.format(
				BarnHelp.text('Core', 'Core_FieldAccess_LogApplied'),
				new List<Object>{
					byName,
					startedAt.format(),
					changed.format(),
					setCount.format(),
					refused.format()
				}
			)
		);
		Database.insert(job, AccessLevel.SYSTEM_MODE);
		ImportJournalService.write(job.Id, ImportJournalService.PHASE_COMMIT, entries);
	}

	private void recordUndone(List<Map<String, Object>> entries) {
		Import_Batch__c job = [
			SELECT Id, Run_Log__c
			FROM Import_Batch__c
			WHERE Id = :jobId
			WITH SYSTEM_MODE
			LIMIT 1
		];
		job.Status__c = changed == 0 &&
			refused > 0
			? ImportBatchService.STATUS_UNDO_FAILED
			: ImportBatchService.STATUS_UNDONE;
		String line = String.format(
			BarnHelp.text('Core', 'Core_FieldAccess_LogUndone'),
			new List<Object>{
				byName,
				startedAt.format(),
				changed.format(),
				kept.format(),
				refused.format()
			}
		);
		job.Run_Log__c = String.isBlank(job.Run_Log__c) ? line : job.Run_Log__c + '\n' + line;
		Database.update(job, AccessLevel.SYSTEM_MODE);
		ImportJournalService.write(job.Id, ImportJournalService.PHASE_UNDO, entries);
	}
}
