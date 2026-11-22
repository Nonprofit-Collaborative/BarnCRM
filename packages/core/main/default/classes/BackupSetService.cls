/**
 * Backup Sets (C-66, canonical model R-SQ15 and R-SQ16, ADR-0213 `0213-backup-sets.md` as amended
 * by ADR-NEXT `NEXT-automatic-backups-and-off-platform-destination.md`): saved Find queries whose
 * document carries the `backup` key, run on demand or on their schedule by the nightly run
 * (`BackupSetSchedule`) as a Backup data job that writes Archive by Query's file (R-BD9) to Files.
 * Nothing is changed or deleted except, for a scheduled set, the files of runs past the number of
 * runs kept.
 *
 * Every read and write of a saved query from the panel runs as the person; the job record is
 * written in system mode, as every data job is (ADR-0021). Only people holding Manage BarnCRM
 * Settings and Find and Export Records may use it.
 */
@NamespaceAccessible
public with sharing class BackupSetService {
	public static final String OPERATION_BACKUP = 'Backup';
	private static final String KEY = 'backup';
	private static final Integer RUNS_SHOWN = 20;
	private static final Integer QUERIES_READ = 500;

	/** The schedule frequencies a set may have (R-SQ16); a set without a schedule is `off`. */
	public static final String OFF = 'off';
	public static final String DAILY = 'daily';
	public static final String WEEKLY = 'weekly';
	public static final String MONTHLY = 'monthly';
	private static final Set<String> FREQUENCIES = new Set<String>{ OFF, DAILY, WEEKLY, MONTHLY };

	/** Runs kept per scheduled set while the setting is empty (R-SQ16). */
	public static final Integer DEFAULT_RUNS_KEPT = 7;
	public static final Integer MAX_RUNS_KEPT = 365;

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
		/** `off`, `daily`, `weekly` or `monthly` (R-SQ16). */
		@AuraEnabled
		public String frequency = OFF;
		/** Weekly: 1 (Monday) to 7 (Sunday). */
		@AuraEnabled
		public Integer weekday;
		/** Monthly: the day of the month, 1 to 28. */
		@AuraEnabled
		public Integer day;
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
		/** Runs kept per scheduled set (R-SQ16). */
		@AuraEnabled
		public Integer runsKept;
		/** True when the nightly run is scheduled and its Backup Sets step is on. */
		@AuraEnabled
		public Boolean nightlyOn;
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
		result.runsKept = runsKept();
		result.nightlyOn =
			NightlyJobs.isScheduled() && NightlyJobs.isSwitchedOn(BackupSetSchedule.STEP_KEY, true);
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
				Map<String, Object> schedule = scheduleOf(query.Query_JSON__c);
				view.frequency = frequencyOf(schedule);
				view.weekday = view.frequency == WEEKLY ? numberOf(schedule.get('weekday')) : null;
				view.day = view.frequency == MONTHLY ? numberOf(schedule.get('day')) : null;
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
		Saved_Query__c query = readOwnQuery(queryId);
		Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(query.Query_JSON__c);
		document.remove(KEY);
		Database.update(
			new Saved_Query__c(
				Id = query.Id,
				Query_JSON__c = asSet == true ? marked(query.Query_JSON__c) : JSON.serialize(document)
			),
			AccessLevel.USER_MODE
		);
	}

	/**
	 * Sets the schedule of one of the person's own Backup Sets (R-SQ16): `off`, `daily`, `weekly`
	 * on `weekday` (1 Monday to 7 Sunday) or `monthly` on `day` (1 to 28).
	 */
	public static void setSchedule(Id queryId, String frequency, Integer weekday, Integer day) {
		requireAllowed();
		Saved_Query__c query = readOwnQuery(queryId);
		if (!isBackupSet(query.Query_JSON__c)) {
			throw new BackupSetException(BarnHelp.text('Core', 'Core_BackupSets_ErrorNotSet'));
		}
		String chosen = String.isBlank(frequency) ? OFF : frequency.trim().toLowerCase();
		Boolean valid =
			FREQUENCIES.contains(chosen) &&
			(chosen != WEEKLY || (weekday != null && weekday >= 1 && weekday <= 7)) &&
			(chosen != MONTHLY || (day != null && day >= 1 && day <= 28));
		if (!valid) {
			throw new BackupSetException(BarnHelp.text('Core', 'Core_BackupSets_ErrorSchedule'));
		}
		Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(query.Query_JSON__c);
		Map<String, Object> backup = backupOf(document);
		if (chosen == OFF) {
			backup.remove('schedule');
		} else {
			Map<String, Object> schedule = new Map<String, Object>{ 'frequency' => chosen };
			if (chosen == WEEKLY) {
				schedule.put('weekday', weekday);
			}
			if (chosen == MONTHLY) {
				schedule.put('day', day);
			}
			backup.put('schedule', schedule);
		}
		document.put(KEY, backup);
		Database.update(
			new Saved_Query__c(Id = query.Id, Query_JSON__c = JSON.serialize(document)),
			AccessLevel.USER_MODE
		);
	}

	/** The document with the `backup` key added. */
	public static String marked(String queryJson) {
		Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(queryJson);
		document.put(KEY, new Map<String, Object>{ 'version' => 1 });
		return JSON.serialize(document);
	}

	/** The document with the stored document's `backup` key kept, schedule and all. */
	public static String marked(String queryJson, String storedJson) {
		Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(queryJson);
		Map<String, Object> stored = (Map<String, Object>) JSON.deserializeUntyped(storedJson);
		document.put(KEY, backupOf(stored));
		return JSON.serialize(document);
	}

	/** Starts a run of a Backup Set the person may read; returns the job. */
	public static Import_Batch__c run(Id queryId) {
		requireAllowed();
		return start(readQuery(queryId), null);
	}

	/**
	 * Starts a run of this Backup Set as the running user, who must be allowed. `scheduled` names
	 * the schedule that started it, for the log; null for Run Now.
	 */
	public static Import_Batch__c start(Saved_Query__c query, String scheduled) {
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
		String started = String.format(
			BarnHelp.text('Core', 'Core_BackupSets_LogStarted'),
			new List<Object>{ UserInfo.getName(), now.format(), query.Name }
		);
		if (scheduled != null) {
			started += ' ' + BarnHelp.text('Core', 'Core_BackupSets_LogScheduled', new List<Object>{ scheduled });
		}
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
			Run_Log__c = started
		);
		Database.insert(job, AccessLevel.SYSTEM_MODE);
		String tag = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(6);
		job.Job_Id__c = AsyncStarter.batch(
			FindExportBatch.forBackup(query.Query_JSON__c, fields, tag, FindController.exportLimit(), job.Id),
			BulkDeleteService.BACKUP_PAGE_SIZE,
			'BackupSetService'
		);
		Database.update(new Import_Batch__c(Id = job.Id, Job_Id__c = job.Job_Id__c), AccessLevel.SYSTEM_MODE);
		return job;
	}

	/**
	 * Called by the run's export when it finishes: the job is Complete with what was written, or
	 * Failed. `full` says the export stopped at the row limit; `documentIds` are its parts, kept
	 * in the definition so the files can be found again (R-SQ16). A complete run of a scheduled
	 * set then removes the files of its runs past the number kept. Never throws.
	 */
	public static void afterExport(
		Id jobId,
		Boolean failed,
		Integer rows,
		Integer parts,
		Id firstDocumentId,
		String firstTitle,
		Boolean full,
		List<Id> documentIds
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
			Map<String, Object> definition = definitionOf(jobId);
			if (!failed && documentIds != null) {
				definition.put('documents', documentIds);
			}
			Database.update(
				new Import_Batch__c(
					Id = jobId,
					Status__c = failed ? ImportBatchService.STATUS_FAILED : ImportBatchService.STATUS_COMPLETE,
					Completed_At__c = Datetime.now(),
					Row_Count__c = rows,
					File_Id__c = failed ? null : firstDocumentId,
					File_Name__c = failed ? null : firstTitle,
					Operation_JSON__c = JSON.serialize(definition),
					Run_Log__c = String.join(lines, '\n').right(32768)
				),
				AccessLevel.SYSTEM_MODE
			);
			if (!failed) {
				BackupSetSchedule.keepNewest((Id) definition.get('savedQueryId'));
			}
		} catch (Exception e) {
			ErrorLogger.log(e, 'BackupSetService.afterExport', jobId);
		}
	}

	/** Whether a query document carries the `backup` key. */
	@NamespaceAccessible
	public static Boolean isBackupSet(String queryJson) {
		try {
			return String.isNotBlank(queryJson) &&
				((Map<String, Object>) JSON.deserializeUntyped(queryJson)).containsKey(KEY);
		} catch (Exception notJson) {
			return false;
		}
	}

	/** The set's schedule (R-SQ16), or an empty map for a set run only on demand. */
	public static Map<String, Object> scheduleOf(String queryJson) {
		try {
			Object schedule = backupOf((Map<String, Object>) JSON.deserializeUntyped(queryJson)).get('schedule');
			return schedule instanceof Map<String, Object>
				? (Map<String, Object>) schedule
				: new Map<String, Object>();
		} catch (Exception notJson) {
			return new Map<String, Object>();
		}
	}

	/**
	 * Whether a set with this schedule runs on `day` (R-SQ16): daily, weekly on its weekday or
	 * monthly on its day of the month. An unreadable schedule never runs.
	 */
	public static Boolean isDue(Map<String, Object> schedule, Date day) {
		String frequency = frequencyOf(schedule);
		if (frequency == DAILY) {
			return true;
		}
		if (frequency == WEEKLY) {
			return numberOf(schedule.get('weekday')) == weekdayOf(day);
		}
		if (frequency == MONTHLY) {
			return numberOf(schedule.get('day')) == day.day();
		}
		return false;
	}

	/** 1 (Monday) to 7 (Sunday): 7 January 1900 was a Sunday. */
	public static Integer weekdayOf(Date day) {
		Integer fromSunday = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(day), 7);
		return fromSunday == 0 ? 7 : fromSunday;
	}

	/** Runs kept per scheduled set (Backup Runs Kept, R-SQ16), 1 to 365, 7 when empty. */
	public static Integer runsKept() {
		return DataJobs.wholeNumberSetting('Backup_Runs_Kept__c', DEFAULT_RUNS_KEPT, 1, MAX_RUNS_KEPT);
	}

	/** A job's definition, or an empty map when it cannot be read. */
	private static Map<String, Object> definitionOf(Id jobId) {
		for (Import_Batch__c job : [
			SELECT Operation_JSON__c
			FROM Import_Batch__c
			WHERE Id = :jobId
			WITH SYSTEM_MODE
			LIMIT 1
		]) {
			try {
				return (Map<String, Object>) JSON.deserializeUntyped(job.Operation_JSON__c);
			} catch (Exception notJson) {
				return new Map<String, Object>();
			}
		}
		return new Map<String, Object>();
	}

	private static String frequencyOf(Map<String, Object> schedule) {
		Object value = schedule == null ? null : schedule.get('frequency');
		return value instanceof String && FREQUENCIES.contains((String) value) ? (String) value : OFF;
	}

	private static Integer numberOf(Object value) {
		return value instanceof Decimal ? ((Decimal) value).intValue() : (value instanceof Integer ? (Integer) value : null);
	}

	private static Map<String, Object> backupOf(Map<String, Object> document) {
		Object backup = document.get(KEY);
		Map<String, Object> result = backup instanceof Map<String, Object>
			? (Map<String, Object>) backup
			: new Map<String, Object>();
		result.put('version', 1);
		return result;
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
			view.setName = (String) ((Map<String, Object>) JSON.deserializeUntyped(job.Operation_JSON__c)).get('name');
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

	/** Only a query's owner changes its `backup` key (R-SQ15). */
	private static Saved_Query__c readOwnQuery(Id queryId) {
		Saved_Query__c query = readQuery(queryId);
		if (query.OwnerId != UserInfo.getUserId()) {
			throw new BackupSetException(BarnHelp.text('Core', 'Core_Find_ErrorNotYours'));
		}
		return query;
	}

	private static void requireAllowed() {
		if (!allowed()) {
			throw new BackupSetException(BarnHelp.text('Core', 'Core_BackupSets_ErrorNoPermission'));
		}
	}
}
