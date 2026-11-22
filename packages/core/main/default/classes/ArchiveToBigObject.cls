/**
 * The Big Object destination of an archive rule (canonical model R-SQ16 and R-ARC3, ADR-NEXT archive
 * rules and big object archive): an Archive data job and the first Copy of `BigObjectArchiveJob`.
 * Refused for a person without the BarnCRM Admin grant on the big object, and at the cap.
 */
@NamespaceAccessible
public with sharing class ArchiveToBigObject implements ArchiveDestination {
	@NamespaceAccessible
	public String key() {
		return ArchiveRules.BIG_OBJECT;
	}

	@NamespaceAccessible
	public String unavailableReason() {
		if (!Schema.SObjectType.Archived_Record__b.isCreateable()) {
			return BarnHelp.text('Core', 'Core_ArchiveRules_BigObjectNoAccess');
		}
		if (BigObjectArchiveJob.archivedCount() >= BigObjectArchiveJob.CAP) {
			return String.format(
				BarnHelp.text('Core', 'Core_ArchiveRules_LogCap'),
				new List<Object>{ BigObjectArchiveJob.CAP.format() }
			);
		}
		return null;
	}

	@NamespaceAccessible
	public Import_Batch__c start(ArchiveRun run) {
		String reason = unavailableReason();
		if (reason != null) {
			throw new ArchiveRules.ArchiveRuleException(reason);
		}
		Datetime now = Datetime.now();
		Import_Batch__c job = new Import_Batch__c(
			Operation__c = BigObjectArchiveJob.OPERATION_ARCHIVE,
			Operation_JSON__c = JSON.serialize(
				new Map<String, Object>{
					'version' => 1,
					'action' => 'archive',
					'savedQueryId' => run.savedQueryId,
					'name' => run.ruleName,
					'object' => run.objectName,
					'notChangedAfter' => now,
					'scheduled' => run.scheduled == true
				}
			),
			Status__c = ImportBatchService.STATUS_COMMITTING,
			Is_Dry_Run__c = false,
			Row_Count__c = run.confirmedCount,
			Rows_Created__c = 0,
			Rows_Deleted__c = 0,
			Rows_Rejected__c = 0,
			Started_At__c = now,
			Committed_By__c = UserInfo.getUserId(),
			Run_Log__c = String.format(
				BarnHelp.text('Core', 'Core_ArchiveRules_LogStarted'),
				new List<Object>{ UserInfo.getName(), now.format(), run.ruleName, run.confirmedCount.format() }
			)
		);
		// The package's own bookkeeping (ADR-0021); the records are read and deleted as the person.
		Database.insert(job, AccessLevel.SYSTEM_MODE);
		BigObjectArchiveJob.queue(new BigObjectArchiveJob(job.Id, run, now));
		return job;
	}
}
