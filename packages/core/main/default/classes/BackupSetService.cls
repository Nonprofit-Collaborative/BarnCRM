/**
 * Backup Sets (C-66, canonical model R-SQ15, ADR-0213 `0213-backup-sets.md`): saved Find queries
 * whose document carries the `backup` key, run on demand as a Backup data job that writes Archive
 * by Query's file (R-BD9) to the person's Files and deletes nothing.
 *
 * Every read and write of a saved query runs as the person; the job record is written in system
 * mode, as every data job is (ADR-0021). Only people holding Manage BarnCRM Settings and Find and
 * Export Records may use it.
 */
public with sharing class BackupSetService {
	public static final String OPERATION_BACKUP = 'Backup';
	private static final String KEY = 'backup';
	private static final Integer RUNS_SHOWN = 20;
	private static final Integer QUERIES_READ = 500;

	public class BackupSetException extends Exception {
	}

	/** A saved query as the panel lists it. */
	public class SetView {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String objectName;
		@AuraEnabled
		public String ownerName;
		@AuraEnabled
		public Boolean mine;
	}

	/** One run as the panel and Data Jobs list it. */
	public class RunView {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String setName;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Boolean running;
		@AuraEnabled
		public Datetime startedAt;
		@AuraEnabled
		public Integer rows;
		@AuraEnabled
		public String fileId;
		@AuraEnabled
		public String fileName;
		@AuraEnabled
		public String log;
	}

	/** The panel: the Backup Sets, the person's own queries that are not one, and the runs. */
	public class Panel {
		@AuraEnabled
		public List<SetView> sets = new List<SetView>();
		@AuraEnabled
		public List<SetView> candidates = new List<SetView>();
		@AuraEnabled
		public List<RunView> runs = new List<RunView>();
		@AuraEnabled
		public Integer rowLimit;
	}

	/** Whether the running user may use Backup Sets. */
	public static Boolean allowed() {
		return FeatureManagement.checkPermission(DataJobs.EVERYONE_PERMISSION) &&
			FeatureManagement.checkPermission('Find_And_Export_Records');
	}

	public static Panel page() {
		requireAllowed();
		Panel result = new Panel();
		result.rowLimit = FindController.exportLimit();
		Id me = UserInfo.getUserId();
		for (Saved_Query__c query : [
			SELECT Id, Name, Object_Name__c, OwnerId, Owner.Name, Query_JSON__c
			FROM Saved_Query__c
			WITH USER_MODE
			ORDER BY Name
			LIMIT :QUERIES_READ
		]) {
			SetView view = new SetView();
			view.id = query.Id;
			view.name = query.Name;
			view.objectName = query.Object_Name__c;
			view.ownerName = query.Owner?.Name;
			view.mine = query.OwnerId == me;
			if (isBackupSet(query.Query_JSON__c)) {
				result.sets.add(view);
			} else if (view.mine) {
				result.candidates.add(view);
			}
		}
		result.runs = runs();
		return result;
	}

	/** The person's own runs, newest first. */
	public static List<RunView> runs() {
		List<RunView> result = new List<RunView>();
		for (
			Import_Batch__c job : DataJobs.read(
				'Id, Name, Status__c, Started_At__c, Row_Count__c, File_Id__c, File_Name__c, ' +
				'Operation_JSON__c, Run_Log__c',
				OPERATION_BACKUP,
				null,
				RUNS_SHOWN,
				false
			)
		) {
			result.add(runView(job));
		}
		return result;
	}

	/** Adds the `backup` key to one of the person's own saved queries, or takes it off. */
	public static void setBackup(Id queryId, Boolean asSet) {
		requireAllowed();
		Saved_Query__c query = readQuery(queryId);
		if (query.OwnerId != UserInfo.getUserId()) {
			throw new BackupSetException(BarnHelp.text('Core', 'Core_Find_ErrorNotYours'));
		}
		Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(
			query.Query_JSON__c
		);
		document.remove(KEY);
		Database.update(
			new Saved_Query__c(
				Id = query.Id,
				Query_JSON__c = asSet == true
					? marked(query.Query_JSON__c)
					: JSON.serialize(document)
			),
			AccessLevel.USER_MODE
		);
	}

	/** The document with the `backup` key added. */
	public static String marked(String queryJson) {
		Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(queryJson);
		document.put(KEY, new Map<String, Object>{ 'version' => 1 });
		return JSON.serialize(document);
	}

	/** Starts a run of a Backup Set the person may read; returns the job. */
	public static Import_Batch__c run(Id queryId) {
		requireAllowed();
		Saved_Query__c query = readQuery(queryId);
		if (!isBackupSet(query.Query_JSON__c)) {
			throw new BackupSetException(BarnHelp.text('Core', 'Core_BackupSets_ErrorNotSet'));
		}
		QueryCompiler.Compiled compiled = QueryCompiler.compile(query.Query_JSON__c);
		Schema.SObjectType objectType = NamespaceUtil.objectType(compiled.objectName);
		if (objectType == null) {
			// Not an object here: the platform's own error, as before.
			// DEFERRED: no child relationships are read. NOPMD: the rule flags DEFERRED too.
			objectType = Schema.describeSObjects( // NOPMD
					new List<String>{ compiled.objectName },
					Schema.SObjectDescribeOptions.DEFERRED
				)[0]
				.getSObjectType();
		}
		List<String> fields = new List<String>();
		for (Schema.DescribeFieldResult field : BulkDeleteService.backupFields(objectType)) {
			fields.add(field.getName());
		}
		Datetime now = Datetime.now();
		Import_Batch__c job = new Import_Batch__c(
			Operation__c = OPERATION_BACKUP,
			Operation_JSON__c = JSON.serialize(
				new Map<String, Object>{
					'version' => 1,
					'savedQueryId' => query.Id,
					'name' => query.Name,
					'object' => compiled.objectName
				}
			),
			Status__c = ImportBatchService.STATUS_COMMITTING,
			Is_Dry_Run__c = false,
			Row_Count__c = 0,
			Started_At__c = now,
			Committed_By__c = UserInfo.getUserId(),
			Run_Log__c = String.format(
				BarnHelp.text('Core', 'Core_BackupSets_LogStarted'),
				new List<Object>{ UserInfo.getName(), now.format(), query.Name }
			)
		);
		Database.insert(job, AccessLevel.SYSTEM_MODE);
		String tag = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(6);
		job.Job_Id__c = AsyncStarter.batch(
			FindExportBatch.forBackup(
				query.Query_JSON__c,
				fields,
				tag,
				FindController.exportLimit(),
				job.Id
			),
			BulkDeleteService.BACKUP_PAGE_SIZE,
			'BackupSetService'
		);
		Database.update(
			new Import_Batch__c(Id = job.Id, Job_Id__c = job.Job_Id__c),
			AccessLevel.SYSTEM_MODE
		);
		return job;
	}

	/**
	 * Called by the run's export when it finishes: the job is Complete with what was written, or
	 * Failed. `full` says the export stopped at the row limit. Never throws.
	 */
	public static void afterExport(
		Id jobId,
		Boolean failed,
		Integer rows,
		Integer parts,
		Id firstDocumentId,
		String firstTitle,
		Boolean full
	) {
		try {
			Import_Batch__c job = DataJobs.forFinish(jobId);
			List<String> lines = new List<String>{ job.Run_Log__c };
			if (failed) {
				lines.add(BarnHelp.text('Core', 'Core_BackupSets_LogFailed'));
			} else {
				lines.add(
					String.format(
						BarnHelp.text('Core', 'Core_BackupSets_LogSaved'),
						new List<Object>{ rows.format(), parts.format(), firstTitle }
					)
				);
				if (full) {
					lines.add(BarnHelp.text('Core', 'Core_BackupSets_LogFull'));
				}
			}
			Database.update(
				new Import_Batch__c(
					Id = jobId,
					Status__c = failed
						? ImportBatchService.STATUS_FAILED
						: ImportBatchService.STATUS_COMPLETE,
					Completed_At__c = Datetime.now(),
					Row_Count__c = rows,
					File_Id__c = failed ? null : firstDocumentId,
					File_Name__c = failed ? null : firstTitle,
					Run_Log__c = String.join(lines, '\n').right(32768)
				),
				AccessLevel.SYSTEM_MODE
			);
		} catch (Exception e) {
			ErrorLogger.log(e, 'BackupSetService.afterExport', jobId);
		}
	}

	/** Whether a query document carries the `backup` key. */
	public static Boolean isBackupSet(String queryJson) {
		try {
			return String.isNotBlank(queryJson) &&
				((Map<String, Object>) JSON.deserializeUntyped(queryJson)).containsKey(KEY);
		} catch (Exception notJson) {
			return false;
		}
	}

	private static RunView runView(Import_Batch__c job) {
		RunView view = new RunView();
		view.id = job.Id;
		view.name = job.Name;
		view.status = job.Status__c;
		view.running = ImportBatchService.STATUS_COMMITTING.equals(job.Status__c);
		view.startedAt = job.Started_At__c;
		view.rows = DataJobs.intOf(job.Row_Count__c);
		view.fileId = job.File_Id__c;
		view.fileName = job.File_Name__c;
		view.log = job.Run_Log__c;
		try {
			view.setName = (String) ((Map<String, Object>) JSON.deserializeUntyped(
					job.Operation_JSON__c
				))
				.get('name');
		} catch (Exception notJson) {
			view.setName = null;
		}
		return view;
	}

	private static Saved_Query__c readQuery(Id queryId) {
		List<Saved_Query__c> found = [
			SELECT Id, Name, OwnerId, Query_JSON__c
			FROM Saved_Query__c
			WHERE Id = :queryId
			WITH USER_MODE
			LIMIT 1
		];
		if (found.isEmpty()) {
			throw new BackupSetException(BarnHelp.text('Core', 'Core_Find_ErrorNotFound'));
		}
		return found[0];
	}

	private static void requireAllowed() {
		if (!allowed()) {
			throw new BackupSetException(
				BarnHelp.text('Core', 'Core_BackupSets_ErrorNoPermission')
			);
		}
	}
}
