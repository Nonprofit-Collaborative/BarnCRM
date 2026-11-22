/**
 * Scheduled Backup Sets (canonical model R-SQ16, ADR-NEXT
 * `NEXT-automatic-backups-and-off-platform-destination.md`): the Backup Sets step of the nightly
 * run (ADR-0166), with its own switch, starts every set whose schedule falls today, and a
 * complete run of a scheduled set removes the files of that set's runs past Backup Runs Kept.
 *
 * Without sharing, and in system mode: saved queries are private to their owners, and the run
 * belongs to the user the nightly run runs as, so the schedule must see every set; a run's files
 * may be owned by whoever ran it. What a run reads of the records is still read as the running
 * user (`FindExportBatch`, user mode). Listed in the without-sharing register.
 */
public without sharing class BackupSetSchedule implements Schedulable {
	/** The step's key and its row on `Nightly_Job__c`. */
	public static final String STEP_KEY = 'BarnCRM Backup Sets';
	private static final String CONTEXT = 'BackupSetSchedule';
	private static final Integer QUERIES_READ = 500;
	private static final Integer JOBS_READ = 1000;

	/**
	 * Two in the morning, after Record Cleanup; shipped on, as nothing runs without a schedule.
	 * Run Now is safe: it starts today's due sets once more.
	 */
	public static NightlyStep step() {
		return new NightlyStep(
				STEP_KEY,
				BarnHelp.text('Core', 'Core_NightlyJobs_BackupSets'),
				2,
				0,
				new BackupSetSchedule()
			)
			.withSwitch(true)
			.runnableNow();
	}

	public void execute(SchedulableContext context) {
		startDue(Date.today());
	}

	/**
	 * Starts each Backup Set whose schedule falls on `day`, as the running user; returns how many
	 * started. A set that cannot start is logged and the rest still start.
	 */
	public static Integer startDue(Date day) {
		if (!BackupSetService.allowed()) {
			ErrorLogger.logMessage(
				BarnHelp.text('Core', 'Core_BackupSets_ErrorScheduleUser'),
				CONTEXT,
				ErrorLogger.SEVERITY_WARNING
			);
			return 0;
		}
		Integer started = 0;
		for (Saved_Query__c query : [
			SELECT Id, Name, OwnerId, Query_JSON__c
			FROM Saved_Query__c
			WITH SYSTEM_MODE
			ORDER BY Name
			LIMIT :QUERIES_READ
		]) {
			if (!BackupSetService.isBackupSet(query.Query_JSON__c)) {
				continue;
			}
			Map<String, Object> schedule = BackupSetService.scheduleOf(query.Query_JSON__c);
			if (!BackupSetService.isDue(schedule, day)) {
				continue;
			}
			try {
				BackupSetService.start(query, String.valueOf(schedule.get('frequency')));
				started++;
			} catch (Exception e) {
				ErrorLogger.log(e, CONTEXT, query.Id);
			}
		}
		return started;
	}

	/**
	 * Removes the files of a scheduled set's complete runs past the newest Backup Runs Kept
	 * (R-SQ16), and says so on each run. A set run only on demand keeps every file. Never throws.
	 */
	public static void keepNewest(Id savedQueryId) {
		try {
			if (savedQueryId == null || !isScheduled(savedQueryId)) {
				return;
			}
			Integer kept = BackupSetService.runsKept();
			Integer seen = 0;
			List<Import_Batch__c> trimmed = new List<Import_Batch__c>();
			Set<Id> documents = new Set<Id>();
			for (Import_Batch__c job : [
				SELECT Id, File_Id__c, File_Name__c, Operation_JSON__c, Committed_By__c, Run_Log__c
				FROM Import_Batch__c
				WHERE
					Operation__c = :BackupSetService.OPERATION_BACKUP
					AND Status__c = :ImportBatchService.STATUS_COMPLETE
					AND File_Id__c != NULL
				WITH SYSTEM_MODE
				ORDER BY Started_At__c DESC
				LIMIT :JOBS_READ
			]) {
				Map<String, Object> definition = definitionOf(job);
				if (String.valueOf(definition.get('savedQueryId')) != String.valueOf(savedQueryId)) {
					continue;
				}
				seen++;
				if (seen <= kept) {
					continue;
				}
				documents.addAll(documentsOf(job, definition));
				trimmed.add(
					new Import_Batch__c(
						Id = job.Id,
						File_Id__c = null,
						File_Name__c = null,
						Run_Log__c = (job.Run_Log__c +
							'\n' +
							BarnHelp.text('Core', 'Core_BackupSets_LogRemoved', new List<Object>{ kept }))
							.right(32768)
					)
				);
			}
			if (trimmed.isEmpty()) {
				return;
			}
			List<String> failures = new List<String>();
			List<ContentDocument> doomed = new List<ContentDocument>();
			for (Id documentId : documents) {
				doomed.add(new ContentDocument(Id = documentId));
			}
			for (Database.DeleteResult result : Database.delete(doomed, false, AccessLevel.SYSTEM_MODE)) {
				if (!result.isSuccess()) {
					failures.add(result.getId() + ': ' + result.getErrors()[0].getMessage());
				}
			}
			if (!failures.isEmpty()) {
				ErrorLogger.logMessage(String.join(failures, '\n').left(30000), CONTEXT, ErrorLogger.SEVERITY_WARNING);
			}
			Database.update(trimmed, false, AccessLevel.SYSTEM_MODE);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT, savedQueryId);
		}
	}

	private static Boolean isScheduled(Id savedQueryId) {
		for (Saved_Query__c query : [
			SELECT Query_JSON__c
			FROM Saved_Query__c
			WHERE Id = :savedQueryId
			WITH SYSTEM_MODE
			LIMIT 1
		]) {
			return BackupSetService.scheduleOf(query.Query_JSON__c).get('frequency') != null;
		}
		return false;
	}

	/**
	 * A run's parts: the documents its finish kept, or, for a run saved before they were kept,
	 * its first file and every file its runner owns titled as its other parts.
	 */
	private static Set<Id> documentsOf(Import_Batch__c job, Map<String, Object> definition) {
		Set<Id> result = new Set<Id>();
		Object kept = definition.get('documents');
		if (kept instanceof List<Object> && !((List<Object>) kept).isEmpty()) {
			for (Object documentId : (List<Object>) kept) {
				result.add(Id.valueOf(String.valueOf(documentId)));
			}
			return result;
		}
		result.add(job.File_Id__c);
		if (String.isNotBlank(job.File_Name__c) && job.File_Name__c.endsWith('-part-1')) {
			String prefix = job.File_Name__c.removeEnd('1') + '%';
			for (ContentDocument part : [
				SELECT Id
				FROM ContentDocument
				WHERE Title LIKE :prefix AND OwnerId = :job.Committed_By__c
				WITH SYSTEM_MODE
				LIMIT 200
			]) {
				result.add(part.Id);
			}
		}
		return result;
	}

	private static Map<String, Object> definitionOf(Import_Batch__c job) {
		try {
			return (Map<String, Object>) JSON.deserializeUntyped(job.Operation_JSON__c);
		} catch (Exception notJson) {
			return new Map<String, Object>();
		}
	}
}
