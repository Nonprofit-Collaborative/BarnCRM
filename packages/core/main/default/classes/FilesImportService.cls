/**
 * Import Files (C-70, canonical model 29FI, R-FI1 to R-FI5; ADR-0214 `0214-files-import.md`):
 * documents from a zip, read in the browser, saved to Files as the person, each linked to its
 * record, journaled and undone as a data job (Operation Files).
 *
 * The browser reads the zip and the manifest and sends the files in small groups; this checks
 * the records, saves each group, and keeps the job's counts and journal. Everything about a
 * file is done as the person: they own the document and can only link it to a record they can
 * see. The job and its journal are the package's own bookkeeping, written in system mode
 * (ADR-0021).
 */
public with sharing class FilesImportService {
	public static final String OPERATION_FILES = 'Files';
	/** The most files one zip may load (R-FI1); also what one synchronous undo deletes. */
	public static final Integer MAX_FILES = 2000;
	/**
	 * The largest file, and the most one group may carry: 2 MB is about 2.7 MB as base64,
	 * inside the Lightning request limit and, with each file's text released once decoded,
	 * the 6 MB heap (R-FI2, R-FI3).
	 */
	public static final Integer MAX_FILE_BYTES = 2097152;
	public static final Integer MAX_GROUP_BYTES = 2097152;
	public static final Integer MAX_GROUP_FILES = 20;
	public static final Integer JOBS_SHOWN = 20;
	/** Object types one record check may query; SOQL allows 100 queries a transaction. */
	private static final Integer MAX_TYPES_CHECKED = 80;
	private static final String DOCUMENT = 'ContentDocument';
	private static final String JOB_FIELDS =
		'Id, Name, Status__c, File_Name__c, Started_At__c, Completed_At__c, Undo_Deadline__c, ' +
		'Row_Count__c, Rows_Created__c, Rows_Rejected__c, Rows_Deleted__c, Run_Log__c, ' +
		'Is_Dry_Run__c, Job_Id__c, Committed_By__c';

	public class FilesImportException extends Exception {
	}

	/** One file of a group, as the page sends it. */
	public class IncomingFile {
		@AuraEnabled
		public Integer row { get; set; }
		@AuraEnabled
		public String recordId { get; set; }
		@AuraEnabled
		public String fileName { get; set; }
		@AuraEnabled
		public String title { get; set; }
		@AuraEnabled
		public String description { get; set; }
		/** The file's bytes as base64. */
		@AuraEnabled
		public String data { get; set; }
	}

	/** A file the platform refused, with its manifest row and the platform's reason. */
	public class Refusal {
		@AuraEnabled
		public Integer row;
		@AuraEnabled
		public String reason;
	}

	/** What one group saved and refused. */
	public class GroupResult {
		@AuraEnabled
		public Integer saved = 0;
		@AuraEnabled
		public List<Refusal> refusals = new List<Refusal>();
	}

	/** One files job, for the panel's Recent Loads and Data Jobs. */
	public class JobView {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String fileName;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Datetime startedAt;
		@AuraEnabled
		public Datetime undoDeadline;
		@AuraEnabled
		public Integer rows;
		@AuraEnabled
		public Integer saved;
		@AuraEnabled
		public Integer refused;
		@AuraEnabled
		public Integer deleted;
		@AuraEnabled
		public Boolean canUndo = false;
		@AuraEnabled
		public String log;
	}

	/** Whether the person may import files: Manage BarnCRM Settings, as every import (R-FI5). */
	public static Boolean allowed() {
		return FeatureManagement.checkPermission(DataJobs.EVERYONE_PERMISSION);
	}

	/**
	 * The Ids among `recordIds` that name no record the person can see, as given (R-FI2). An
	 * Id that is not an Id at all is in the list too.
	 */
	public static List<String> unseen(List<String> recordIds) {
		requireAllowed();
		if (recordIds == null || recordIds.size() > MAX_FILES) {
			throw new FilesImportException(tooMany());
		}
		Map<Schema.SObjectType, Set<Id>> byType = new Map<Schema.SObjectType, Set<Id>>();
		Set<String> missing = new Set<String>();
		for (String text : recordIds) {
			Id parsed = idOf(text);
			if (parsed == null) {
				missing.add(text);
				continue;
			}
			Schema.SObjectType objectType = parsed.getSObjectType();
			if (!byType.containsKey(objectType)) {
				byType.put(objectType, new Set<Id>());
			}
			byType.get(objectType).add(parsed);
		}
		if (byType.size() > MAX_TYPES_CHECKED) {
			throw new FilesImportException(
				BarnHelp.text('Core', 'Core_FilesImport_ErrorTooManyKinds')
			);
		}
		Set<Id> seen = new Set<Id>();
		for (Schema.SObjectType objectType : byType.keySet()) {
			Set<Id> ids = byType.get(objectType);
			try {
				for (
					SObject found : Database.queryWithBinds(
						'SELECT Id FROM ' + objectType + ' WHERE Id IN :ids',
						new Map<String, Object>{ 'ids' => ids },
						AccessLevel.USER_MODE
					)
				) {
					seen.add(found.Id);
				}
			} catch (Exception notReadable) {
				// An object the person cannot read, or one that cannot be queried: none seen.
				continue;
			}
		}
		for (String text : recordIds) {
			Id parsed = idOf(text);
			if (parsed != null && !seen.contains(parsed)) {
				missing.add(text);
			}
		}
		return new List<String>(missing);
	}

	/** Starts a load of `rowCount` files from the zip `fileName` (R-FI3); returns the job. */
	public static Import_Batch__c start(String fileName, Integer rowCount) {
		requireAllowed();
		if (rowCount == null || rowCount < 1 || rowCount > MAX_FILES) {
			throw new FilesImportException(tooMany());
		}
		Datetime now = Datetime.now();
		String zipName = String.isBlank(fileName) ? '' : fileName.abbreviate(255);
		Import_Batch__c job = new Import_Batch__c(
			Operation__c = OPERATION_FILES,
			Status__c = ImportBatchService.STATUS_COMMITTING,
			Is_Dry_Run__c = false,
			File_Name__c = zipName,
			Row_Count__c = rowCount,
			Rows_Created__c = 0,
			Rows_Rejected__c = 0,
			Started_At__c = now,
			Committed_By__c = UserInfo.getUserId(),
			Undo_Deadline__c = now.addDays(ImportBatchService.undoWindowDays()),
			Run_Log__c = String.format(
				BarnHelp.text('Core', 'Core_FilesImport_LogStarted'),
				new List<Object>{ UserInfo.getName(), zipName, now.format() }
			)
		);
		Database.insert(job, AccessLevel.SYSTEM_MODE);
		return job;
	}

	/**
	 * Saves one group of files as the person, each linked to its record, and journals it: a
	 * Created entry per document, a Failed entry per refusal (R-FI3).
	 */
	public static GroupResult addFiles(Id jobId, List<IncomingFile> files) {
		requireAllowed();
		Import_Batch__c job = loading(jobId);
		if (files == null || files.isEmpty()) {
			return new GroupResult();
		}
		if (files.size() > MAX_GROUP_FILES) {
			throw new FilesImportException(
				String.format(
					BarnHelp.text('Core', 'Core_FilesImport_ErrorGroup'),
					new List<Object>{ MAX_GROUP_FILES }
				)
			);
		}
		GroupResult result = new GroupResult();
		List<Map<String, Object>> entries = new List<Map<String, Object>>();
		List<ContentVersion> versions = new List<ContentVersion>();
		List<IncomingFile> sent = new List<IncomingFile>();
		Integer groupBytes = 0;
		for (IncomingFile file : files) {
			Blob data = String.isBlank(file.data) ? null : EncodingUtil.base64Decode(file.data);
			// Released as soon as it is decoded, so the group's text and bytes are not both held.
			file.data = null;
			String reason = refusalOf(file, data);
			if (reason == null) {
				groupBytes += data.size();
				if (groupBytes > MAX_GROUP_BYTES) {
					reason = BarnHelp.text('Core', 'Core_FilesImport_ErrorFileTooLarge');
				}
			}
			if (reason != null) {
				refuse(result, entries, file, reason);
				continue;
			}
			versions.add(
				new ContentVersion(
					Title = String.isBlank(file.title)
						? titleOf(file.fileName)
						: file.title.abbreviate(255),
					Description = String.isBlank(file.description)
						? null
						: file.description.abbreviate(1000),
					PathOnClient = file.fileName.substringAfterLast('/').length() > 0
						? file.fileName.substringAfterLast('/')
						: file.fileName,
					VersionData = data,
					FirstPublishLocationId = idOf(file.recordId)
				)
			);
			sent.add(file);
		}
		List<Database.SaveResult> saves = Database.insert(versions, false, AccessLevel.USER_MODE);
		Map<Id, Id> documentOf = new Map<Id, Id>();
		Set<Id> savedVersions = new Set<Id>();
		for (Database.SaveResult save : saves) {
			if (save.isSuccess()) {
				savedVersions.add(save.getId());
			}
		}
		for (ContentVersion saved : [
			SELECT Id, ContentDocumentId
			FROM ContentVersion
			WHERE Id IN :savedVersions
			WITH USER_MODE
		]) {
			documentOf.put(saved.Id, saved.ContentDocumentId);
		}
		for (Integer i = 0; i < saves.size(); i++) {
			IncomingFile file = sent[i];
			Database.SaveResult save = saves[i];
			if (save.isSuccess()) {
				Map<String, Object> entry = ImportJournalService.created(
					DOCUMENT,
					documentOf.get(save.getId()),
					file.row
				);
				entry.put('versionId', String.valueOf(save.getId()));
				entry.put('recordId', file.recordId);
				entries.add(entry);
				result.saved++;
			} else {
				refuse(result, entries, file, save.getErrors()[0].getMessage());
			}
		}
		ImportJournalService.write(job.Id, ImportJournalService.PHASE_COMMIT, entries);
		Database.update(
			new Import_Batch__c(
				Id = job.Id,
				Rows_Created__c = DataJobs.intOf(job.Rows_Created__c) + result.saved,
				Rows_Rejected__c = DataJobs.intOf(job.Rows_Rejected__c) + result.refusals.size()
			),
			AccessLevel.SYSTEM_MODE
		);
		return result;
	}

	/** Ends a load: Complete, with a Run Log summary (R-FI3). */
	public static JobView finish(Id jobId) {
		requireAllowed();
		Import_Batch__c job = loading(jobId);
		job.Status__c = ImportBatchService.STATUS_COMPLETE;
		job.Completed_At__c = Datetime.now();
		job.Run_Log__c = appended(
			job.Run_Log__c,
			String.format(
				BarnHelp.text('Core', 'Core_FilesImport_LogFinished'),
				new List<Object>{
					DataJobs.intOf(job.Rows_Created__c).format(),
					DataJobs.intOf(job.Rows_Rejected__c).format()
				}
			)
		);
		Database.update(job, AccessLevel.SYSTEM_MODE);
		return view(job);
	}

	/**
	 * Undoes a load (R-FI4): deletes, as the person, every document the journal lists, except
	 * one whose latest version is not the one the load saved. `confirmed` is the count of files
	 * the person was shown; a different count is refused.
	 */
	public static JobView undo(Id jobId, Integer confirmed) {
		requireAllowed();
		Import_Batch__c job = locked(jobId);
		String reason = ImportUndoService.refusal(job);
		if (reason != null) {
			throw new FilesImportException(reason);
		}
		Integer saved = DataJobs.intOf(job.Rows_Created__c);
		if (confirmed != saved) {
			throw new FilesImportException(
				String.format(
					BarnHelp.text('Core', 'Core_Import_UndoErrorCountChanged'),
					new List<String>{
						String.valueOf(confirmed == null ? 0 : confirmed),
						String.valueOf(saved)
					}
				)
			);
		}
		Map<Id, Id> versionOf = journaledDocuments(job.Id);
		List<ContentDocument> deletable = new List<ContentDocument>();
		Integer kept = 0;
		for (ContentDocument document : [
			SELECT Id, LatestPublishedVersionId
			FROM ContentDocument
			WHERE Id IN :versionOf.keySet()
			WITH USER_MODE
		]) {
			if (document.LatestPublishedVersionId == versionOf.get(document.Id)) {
				deletable.add(document);
			} else {
				kept++;
			}
		}
		Integer deleted = 0;
		for (
			Database.DeleteResult result : Database.delete(deletable, false, AccessLevel.USER_MODE)
		) {
			if (result.isSuccess()) {
				deleted++;
			} else {
				kept++;
			}
		}
		job.Status__c = ImportBatchService.STATUS_UNDONE;
		job.Rows_Deleted__c = deleted;
		job.Run_Log__c = appended(
			job.Run_Log__c,
			String.format(
				BarnHelp.text('Core', 'Core_FilesImport_LogUndone'),
				new List<Object>{ UserInfo.getName(), deleted.format(), kept.format() }
			)
		);
		Database.update(job, AccessLevel.SYSTEM_MODE);
		return view(job);
	}

	/** The newest files jobs, everyone's: all who may import files manage BarnCRM Settings. */
	public static List<JobView> jobs() {
		requireAllowed();
		List<JobView> result = new List<JobView>();
		for (
			Import_Batch__c job : DataJobs.read(JOB_FIELDS, OPERATION_FILES, null, JOBS_SHOWN, true)
		) {
			result.add(view(job));
		}
		return result;
	}

	// -------------------------------------------------------------------------------------

	private static JobView view(Import_Batch__c job) {
		JobView result = new JobView();
		result.id = job.Id;
		result.name = job.Name;
		result.fileName = job.File_Name__c;
		result.status = job.Status__c;
		result.startedAt = job.Started_At__c;
		result.undoDeadline = job.Undo_Deadline__c;
		result.rows = DataJobs.intOf(job.Row_Count__c);
		result.saved = DataJobs.intOf(job.Rows_Created__c);
		result.refused = DataJobs.intOf(job.Rows_Rejected__c);
		result.deleted = DataJobs.intOf(job.Rows_Deleted__c);
		result.canUndo = result.saved > 0 && ImportUndoService.refusal(job) == null;
		result.log = job.Run_Log__c;
		return result;
	}

	/** Why one file is refused before it is saved, or null (R-FI2). */
	private static String refusalOf(IncomingFile file, Blob data) {
		if (idOf(file.recordId) == null) {
			return BarnHelp.text('Core', 'Core_FilesImport_ErrorRecordId');
		}
		if (String.isBlank(file.fileName)) {
			return BarnHelp.text('Core', 'Core_FilesImport_ErrorNoData');
		}
		if (data == null || data.size() == 0) {
			return BarnHelp.text('Core', 'Core_FilesImport_ErrorNoData');
		}
		if (data.size() > MAX_FILE_BYTES) {
			return BarnHelp.text('Core', 'Core_FilesImport_ErrorFileTooLarge');
		}
		return null;
	}

	private static void refuse(
		GroupResult result,
		List<Map<String, Object>> entries,
		IncomingFile file,
		String reason
	) {
		Refusal refusal = new Refusal();
		refusal.row = file.row;
		refusal.reason = reason;
		result.refusals.add(refusal);
		Map<String, Object> entry = ImportJournalService.failed(
			DOCUMENT,
			idOf(file.recordId),
			reason
		);
		entry.put('row', file.row);
		entries.add(entry);
	}

	/** Every document the load's journal lists as created, with the version it saved. */
	private static Map<Id, Id> journaledDocuments(Id jobId) {
		Map<Id, Id> versionOf = new Map<Id, Id>();
		for (
			Import_Journal__c page : ImportJournalService.pages(
				jobId,
				ImportJournalService.PHASE_COMMIT,
				ImportJournalService.MAX_PAGES_READ
			)
		) {
			for (Map<String, Object> entry : ImportJournalService.entries(page)) {
				Id documentId = idOf((String) entry.get('id'));
				Id versionId = idOf((String) entry.get('versionId'));
				if (
					ImportJournalService.ACTION_CREATED.equals(entry.get('action')) &&
					documentId != null &&
					versionId != null
				) {
					versionOf.put(documentId, versionId);
				}
			}
		}
		return versionOf;
	}

	/** The person's own load that is still running, locked; anything else is refused. */
	private static Import_Batch__c loading(Id jobId) {
		Id me = UserInfo.getUserId();
		for (Import_Batch__c job : [
			SELECT Id, Status__c, Rows_Created__c, Rows_Rejected__c, Run_Log__c
			FROM Import_Batch__c
			WHERE
				Id = :jobId
				AND Operation__c = :OPERATION_FILES
				AND Committed_By__c = :me
				AND Status__c = :ImportBatchService.STATUS_COMMITTING
			WITH SYSTEM_MODE
			LIMIT 1
			FOR UPDATE
		]) {
			return job;
		}
		throw new FilesImportException(BarnHelp.text('Core', 'Core_FilesImport_ErrorJobGone'));
	}

	/** A files job the person may see, locked so two undos make one undo and one refusal. */
	private static Import_Batch__c locked(Id jobId) {
		if (DataJobs.find('Id', OPERATION_FILES, jobId) == null) {
			throw new FilesImportException(BarnHelp.text('Core', 'Core_Import_ErrorBatchGone'));
		}
		return Database.queryWithBinds(
			'SELECT ' + JOB_FIELDS + ' FROM Import_Batch__c WHERE Id = :jobId LIMIT 1 FOR UPDATE',
			new Map<String, Object>{ 'jobId' => jobId },
			AccessLevel.SYSTEM_MODE
		)[0];
	}

	private static String titleOf(String fileName) {
		String name = fileName.contains('/') ? fileName.substringAfterLast('/') : fileName;
		String bare = name.contains('.') ? name.substringBeforeLast('.') : name;
		return (String.isBlank(bare) ? name : bare).abbreviate(255);
	}

	private static String appended(String log, String line) {
		String text = String.isBlank(log) ? line : log + '\n' + line;
		return text.length() > 32768 ? text.right(32768) : text;
	}

	private static Id idOf(String text) {
		if (String.isBlank(text) || !(text.length() == 15 || text.length() == 18)) {
			return null;
		}
		try {
			return Id.valueOf(text);
		} catch (Exception notAnId) {
			return null;
		}
	}

	private static String tooMany() {
		return String.format(
			BarnHelp.text('Core', 'Core_FilesImport_ErrorTooMany'),
			new List<Object>{ MAX_FILES.format() }
		);
	}

	private static void requireAllowed() {
		if (!allowed()) {
			throw new FilesImportException(
				BarnHelp.text('Core', 'Core_FilesImport_ErrorNoPermission')
			);
		}
	}
}
