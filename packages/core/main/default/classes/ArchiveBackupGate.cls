/**
 * The backup before every archive rule run (D-223, ADR-0240 amendment AR-15, canonical model
 * R-SQ18): a run, manual or scheduled, whatever its destination, first saves the records it will
 * archive, with the related records the archive takes with them, to Files as a Backup data job
 * (Backup Sets' export, R-SQ15). Only when that backup is saved in full does its finish start the
 * archive, through the rule's destination as before; otherwise the run is skipped: a Failed
 * Archive job under Recent Runs and an Error Log entry say why.
 *
 * Skip Backup Before Archive (off by default) starts runs without the backup. Who turned it on
 * and when is the newest Setting Change for it, written on the server by the settings save, and
 * each run started without a backup says so in its log.
 *
 * The chain is asynchronous: the backup is a batch, and its finish starts the archive, which
 * queues its own links, so no immediate big object call ever shares a transaction with this DML.
 */
public with sharing class ArchiveBackupGate {
	/** The setting's key on BarnCRM Settings. */
	public static final String SKIP_KEY = 'Skip_Backup_Before_Archive__c';
	/** The Backup job's definition key holding the run to start once the backup is saved. */
	public static final String RUN_KEY = 'beforeArchive';
	/** Records per chunk of the backup: each chunk reads their related records too. */
	public static final Integer SCOPE = 100;
	private static final String CONTEXT = 'ArchiveBackupGate';
	private static final Integer JOBS_READ = 200;

	/** Whether Skip Backup Before Archive is on. */
	public static Boolean skipBackup() {
		return SettingsService.getSettings().Skip_Backup_Before_Archive__c == true;
	}

	/**
	 * Starts a rule's run: its backup, whose finish starts the archive, or, while Skip Backup
	 * Before Archive is on, the archive at once with that said in its log. Returns the job started.
	 */
	public static Import_Batch__c start(ArchiveRun run, String destinationKey) {
		ArchiveDestination destination = ArchiveDestinations.forKey(destinationKey);
		if (skipBackup()) {
			Import_Batch__c started = destination.start(run);
			appendLog(
				started.Id,
				BarnHelp.text('Core', 'Core_ArchiveBackup_LogSkipped', new List<Object>{ turnedOnNote() })
			);
			return started;
		}
		String reason = destination.unavailableReason();
		if (reason != null) {
			throw new ArchiveRules.ArchiveRuleException(reason);
		}
		requireIdle(run.savedQueryId);
		Schema.SObjectType objectType = NamespaceUtil.objectType(run.objectName);
		Datetime now = Datetime.now();
		Import_Batch__c job = new Import_Batch__c(
			Operation__c = BackupSetService.OPERATION_BACKUP,
			Operation_JSON__c = JSON.serialize(
				new Map<String, Object>{
					'version' => 1,
					'name' => run.ruleName,
					'object' => run.objectName,
					'destination' => OffPlatformSendBatch.FILES,
					RUN_KEY => new Map<String, Object>{
						'savedQueryId' => run.savedQueryId,
						'ruleName' => run.ruleName,
						'queryJson' => run.queryJson,
						'objectName' => run.objectName,
						'confirmedCount' => run.confirmedCount,
						'scheduled' => run.scheduled == true,
						'destination' => destinationKey,
						'startedAt' => now.getTime()
					}
				}
			),
			Status__c = ImportBatchService.STATUS_COMMITTING,
			Is_Dry_Run__c = false,
			Row_Count__c = 0,
			Started_At__c = now,
			Committed_By__c = UserInfo.getUserId(),
			Run_Log__c = BarnHelp.text(
					'Core',
					'Core_ArchiveBackup_LogStarted',
					new List<Object>{ UserInfo.getName(), now.format(), run.ruleName, run.confirmedCount.format() }
				) + ArchiveRecordJson.notKeptLine(objectType.getDescribe(SObjectDescribeOptions.DEFERRED))
		);
		// The package's own bookkeeping (ADR-0021); the records are read as the person.
		Database.insert(job, AccessLevel.SYSTEM_MODE);
		FindExportBatch backup = FindExportBatch.forArchiveBackup(
			run.queryJson,
			BulkDeleteService.backupFieldNames(objectType),
			EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(6),
			run.confirmedCount,
			job.Id,
			ArchiveRecordJson.childKinds(objectType.getDescribe(SObjectDescribeOptions.DEFERRED))
		);
		if (System.isBatch() || System.isFuture()) {
			// The nightly step runs rules in a batch's execute, which may not start a batch.
			AsyncStarter.queue(new Starter(backup, job.Id), CONTEXT);
		} else {
			startBackup(backup, job.Id);
		}
		return job;
	}

	/** Starts the backup's export from a queueable, for a run started inside a batch. */
	public with sharing class Starter implements Queueable {
		private final FindExportBatch backup;
		private final Id jobId;

		public Starter(FindExportBatch backup, Id jobId) {
			this.backup = backup;
			this.jobId = jobId;
		}

		public void execute(QueueableContext context) {
			try {
				startBackup(backup, jobId);
			} catch (Exception refused) {
				BackupSetService.afterExport(jobId, true, 0, 0, null, null, false, null);
			}
		}
	}

	private static void startBackup(FindExportBatch backup, Id jobId) {
		Id asyncId = AsyncStarter.batch(backup, SCOPE, CONTEXT);
		Database.update(new Import_Batch__c(Id = jobId, Job_Id__c = asyncId), AccessLevel.SYSTEM_MODE);
	}

	/**
	 * Called by a Backup job's finish (`BackupSetService.afterExport`) when its definition holds a
	 * run: starts the archive when the backup was saved in full and the rule is unchanged since,
	 * with at most the records backed up and none changed since the backup started; otherwise
	 * skips the run with the reason. Never throws.
	 */
	public static void afterBackup(Id jobId, Map<String, Object> definition, Boolean failed, Integer rows) {
		Map<String, Object> pending = (Map<String, Object>) definition.get(RUN_KEY);
		ArchiveRun run = runOf(pending);
		String reason;
		try {
			if (failed) {
				reason = BarnHelp.text('Core', 'Core_ArchiveBackup_NotSaved');
			} else if (rows == null || rows < 1) {
				appendLog(jobId, BarnHelp.text('Core', 'Core_ArchiveBackup_NothingToArchive'));
				return;
			} else if (!unchanged(run)) {
				reason = BarnHelp.text('Core', 'Core_ArchiveBackup_RuleChanged');
			} else {
				run.confirmedCount = Math.min(run.confirmedCount, rows);
				Import_Batch__c started = ArchiveDestinations.forKey((String) pending.get('destination')).start(run);
				appendLog(jobId, BarnHelp.text('Core', 'Core_ArchiveBackup_LogArchiveStarted'));
				appendLog(
					started.Id,
					BarnHelp.text('Core', 'Core_ArchiveBackup_LogBackedUp', new List<Object>{ rows.format() })
				);
				return;
			}
		} catch (Exception refused) {
			reason = refused.getMessage();
		}
		skip(jobId, run, reason);
	}

	/**
	 * Skips a run whose backup did not finish: its Backup job's log and a Failed Archive job under
	 * Recent Runs say why, and so does an Error in the Error Log. Never throws.
	 */
	private static void skip(Id backupJobId, ArchiveRun run, String reason) {
		String line = BarnHelp.text('Core', 'Core_ArchiveBackup_Skipped', new List<Object>{ run.ruleName, reason });
		try {
			appendLog(backupJobId, line);
			Datetime now = Datetime.now();
			Database.insert(
				new Import_Batch__c(
					Operation__c = BigObjectArchiveJob.OPERATION_ARCHIVE,
					Operation_JSON__c = JSON.serialize(
						new Map<String, Object>{
							'version' => 1,
							'action' => 'archive',
							'skipped' => true,
							'savedQueryId' => run.savedQueryId,
							'name' => run.ruleName,
							'object' => run.objectName,
							'scheduled' => run.scheduled == true
						}
					),
					Status__c = ImportBatchService.STATUS_FAILED,
					Is_Dry_Run__c = false,
					Row_Count__c = run.confirmedCount,
					Rows_Created__c = 0,
					Rows_Deleted__c = 0,
					Rows_Rejected__c = 0,
					Started_At__c = now,
					Completed_At__c = now,
					Committed_By__c = UserInfo.getUserId(),
					Run_Log__c = line
				),
				AccessLevel.SYSTEM_MODE
			);
		} catch (Exception notWritten) {
			ErrorLogger.log(notWritten, CONTEXT, backupJobId);
		}
		ErrorLogger.logMessage(line, CONTEXT, ErrorLogger.SEVERITY_ERROR, backupJobId);
	}

	/** Whether the rule still holds the query document that was backed up. */
	private static Boolean unchanged(ArchiveRun run) {
		// The rule's owner may differ from the person running it (a scheduled run): read in
		// system mode only to compare; the records are archived in user mode.
		List<Saved_Query__c> found = [
			SELECT Query_JSON__c
			FROM Saved_Query__c
			WHERE Id = :run.savedQueryId
			WITH SYSTEM_MODE
			LIMIT 1
		];
		return !found.isEmpty() && found[0].Query_JSON__c == run.queryJson;
	}

	private static ArchiveRun runOf(Map<String, Object> pending) {
		ArchiveRun run = new ArchiveRun(
			(Id) pending.get('savedQueryId'),
			(String) pending.get('ruleName'),
			(String) pending.get('queryJson'),
			(String) pending.get('objectName'),
			Integer.valueOf(pending.get('confirmedCount'))
		);
		run.scheduled = pending.get('scheduled') == true;
		run.notChangedAfter = Datetime.newInstance(Long.valueOf(String.valueOf(pending.get('startedAt'))));
		return run;
	}

	/** The rules whose backup is still running. Read in system mode: data job bookkeeping (ADR-0021). */
	public static Set<String> waiting() {
		Set<String> result = new Set<String>();
		for (Import_Batch__c job : [
			SELECT Operation_JSON__c
			FROM Import_Batch__c
			WHERE
				Operation__c = :BackupSetService.OPERATION_BACKUP
				AND Status__c = :ImportBatchService.STATUS_COMMITTING
			WITH SYSTEM_MODE
			LIMIT :JOBS_READ
		]) {
			Object pending = ((Map<String, Object>) JSON.deserializeUntyped(job.Operation_JSON__c)).get(RUN_KEY);
			if (pending instanceof Map<String, Object>) {
				result.add((String) ((Map<String, Object>) pending).get('savedQueryId'));
			}
		}
		return result;
	}

	/** Refuses a rule whose backup is still running, as a run still going is refused (R-SQ18). */
	public static void requireIdle(Id savedQueryId) {
		if (savedQueryId != null && waiting().contains(savedQueryId)) {
			throw new ArchiveRules.ArchiveRuleException(BarnHelp.text('Core', 'Core_ArchiveRules_ErrorRunning'));
		}
	}

	/**
	 * Who turned Skip Backup Before Archive on and when, as a sentence, from the newest Setting
	 * Change for it; null while it is off. Read in system mode: the archiving person's run log
	 * names the administrator who turned it on.
	 */
	public static String turnedOnNote() {
		if (!skipBackup()) {
			return null;
		}
		String settingName = SettingsService.CORE_SETTINGS_OBJECT + '.' + SKIP_KEY;
		List<Setting_Change__c> changes = [
			SELECT New_Value__c, Changed_By__r.Name, Changed_At__c
			FROM Setting_Change__c
			WHERE Setting_Name__c = :settingName
			WITH SYSTEM_MODE
			ORDER BY Changed_At__c DESC, CreatedDate DESC
			LIMIT 1
		];
		if (changes.isEmpty() || changes[0].New_Value__c != 'true' || changes[0].Changed_At__c == null) {
			return BarnHelp.text('Core', 'Core_ArchiveBackup_TurnedOnUnknown');
		}
		return BarnHelp.text(
			'Core',
			'Core_ArchiveBackup_TurnedOnBy',
			new List<Object>{ changes[0].Changed_By__r?.Name, changes[0].Changed_At__c.format() }
		);
	}

	/** Adds a line to a data job's run log. */
	private static void appendLog(Id jobId, String line) {
		Import_Batch__c job = [SELECT Run_Log__c FROM Import_Batch__c WHERE Id = :jobId WITH SYSTEM_MODE LIMIT 1];
		Database.update(
			new Import_Batch__c(Id = jobId, Run_Log__c = (job.Run_Log__c + '\n' + line).right(32768)),
			AccessLevel.SYSTEM_MODE
		);
	}
}
