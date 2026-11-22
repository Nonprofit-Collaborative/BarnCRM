/**
 * The Off Platform destination of an archive rule (canonical model R-SQ18 and R-SQ17, ADR-NEXT
 * archive rules and big object archive): Archive by Query (R-BD9) with its file sent to the
 * installed backup destination (`OffPlatformDestination`, from a module such as BarnCRM Connector)
 * before anything is deleted. Usable only while a destination is installed and ready for the
 * running user.
 */
@NamespaceAccessible
public with sharing class OffPlatformArchiveDestination implements ArchiveDestination {
	@NamespaceAccessible
	public String key() {
		return ArchiveRules.OFF_PLATFORM;
	}

	@NamespaceAccessible
	public String unavailableReason() {
		OffPlatformSendBatch.Status status = OffPlatformSendBatch.status();
		return status.available ? status.note : BarnHelp.text('Core', 'Core_ArchiveRules_OffPlatformMissing');
	}

	@NamespaceAccessible
	public Import_Batch__c start(ArchiveRun run) {
		String reason = unavailableReason();
		if (reason != null) {
			throw new ArchiveRules.ArchiveRuleException(reason);
		}
		return BulkDeleteService.startArchive(
			run.queryJson,
			run.confirmedCount,
			null,
			OffPlatformSendBatch.OFF_PLATFORM
		);
	}
}
