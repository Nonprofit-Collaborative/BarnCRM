/**
 * Sends a Backup Set run's or an archive's CSV parts to the off-platform destination (canonical
 * model R-SQ17, ADR-NEXT `NEXT-automatic-backups-and-off-platform-destination.md`): one part per
 * execute (scope 1), so a transaction holds at most one part of about 3 MB under the 12 MB
 * asynchronous heap and the callout size limit. The destination is the installed module's
 * `ArchiveDestination` with key `offPlatform`; Core names no module class.
 *
 * Its finish hands what was sent and what was not to `BackupSetService.afterSent` or
 * `BulkDeleteService.afterArchiveSent`; nothing is deleted here.
 *
 * Without sharing, and in system mode: a retry started by the nightly run sends parts owned by
 * whoever ran the set. Listed in the without-sharing register.
 */
public without sharing class OffPlatformSendBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
	/** The destination key a set or an archive stores. */
	public static final String OFF_PLATFORM = 'offPlatform';
	/** The default: Files only. */
	public static final String FILES = 'files';
	private static final String LOG_CONTEXT = 'OffPlatformSendBatch';

	private final Id jobId;
	private final List<Id> documentIds;
	private final Boolean archive;
	private List<Id> sent = new List<Id>();
	private List<String> failures = new List<String>();

	/** Whether a destination is installed, and when it is not ready or not there, why. */
	public class Status {
		@AuraEnabled
		public Boolean available = false;
		@AuraEnabled
		public String note;
	}

	public OffPlatformSendBatch(Id jobId, List<Id> documentIds, Boolean archive) {
		this.jobId = jobId;
		this.documentIds = documentIds == null ? new List<Id>() : documentIds;
		this.archive = archive == true;
	}

	/** The installed off-platform destination, or null when no module provides one. */
	public static ArchiveDestination destination() {
		for (Object found : ModuleExtensions.all(ArchiveDestination.class)) {
			ArchiveDestination candidate = (ArchiveDestination) found;
			if (candidate.key() == OFF_PLATFORM) {
				return candidate;
			}
		}
		return null;
	}

	/** What the Backup Sets panel and the archive show about the destination. */
	public static Status status() {
		Status result = new Status();
		try {
			ArchiveDestination found = destination();
			result.available = found != null;
			result.note = found == null ? BarnHelp.text('Core', 'Core_OffPlatform_NotInstalled') : found.notReady();
		} catch (Exception e) {
			ErrorLogger.log(e, LOG_CONTEXT);
			result.note = BarnHelp.text('Core', 'Core_OffPlatform_NotInstalled');
		}
		return result;
	}

	/** Starts sending these parts of this job; returns the async job's Id. */
	public static Id start(Id jobId, List<Id> documentIds, Boolean archive) {
		return AsyncStarter.batch(new OffPlatformSendBatch(jobId, documentIds, archive), 1, LOG_CONTEXT);
	}

	public Database.QueryLocator start(Database.BatchableContext context) {
		return Database.getQueryLocatorWithBinds(
			'SELECT Id, ContentDocumentId, Title FROM ContentVersion ' +
			'WHERE ContentDocumentId IN :documents AND IsLatest = TRUE ORDER BY CreatedDate',
			new Map<String, Object>{ 'documents' => documentIds },
			AccessLevel.SYSTEM_MODE
		);
	}

	public void execute(Database.BatchableContext context, List<SObject> scope) {
		for (SObject row : scope) {
			ContentVersion part = (ContentVersion) row;
			String failure;
			try {
				ArchiveDestination found = destination();
				failure = found == null ? BarnHelp.text('Core', 'Core_OffPlatform_NotInstalled') : found.notReady();
				if (failure == null) {
					Blob body = [
						SELECT VersionData
						FROM ContentVersion
						WHERE Id = :part.Id
						WITH SYSTEM_MODE
						LIMIT 1
					]
					.VersionData;
					failure = found.send(part.Title + '.csv', body);
				}
			} catch (Exception e) {
				ErrorLogger.log(e, LOG_CONTEXT, jobId);
				failure = BarnHelp.text('Core', 'Core_OffPlatform_Unexpected', new List<Object>{ e.getTypeName() });
			}
			if (failure == null) {
				sent.add(part.ContentDocumentId);
			} else {
				failures.add(part.Title + ': ' + failure);
			}
		}
	}

	public void finish(Database.BatchableContext context) {
		List<Id> waiting = new List<Id>();
		Set<Id> done = new Set<Id>(sent);
		for (Id documentId : documentIds) {
			if (!done.contains(documentId)) {
				waiting.add(documentId);
			}
		}
		if (!waiting.isEmpty() && failures.isEmpty()) {
			failures.add(BarnHelp.text('Core', 'Core_OffPlatform_FileMissing'));
		}
		if (!failures.isEmpty()) {
			ErrorLogger.logMessage(String.join(failures, '\n').left(30000), LOG_CONTEXT, ErrorLogger.SEVERITY_ERROR, jobId);
		}
		if (archive) {
			BulkDeleteService.afterArchiveSent(jobId, sent, waiting, failures);
		} else {
			BackupSetService.afterSent(jobId, sent, waiting, failures);
		}
	}
}
