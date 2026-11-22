/**
 * The Files destination of an archive rule (canonical model R-SQ18): Archive by Query (R-BD9)
 * unchanged. The records are saved as CSV parts in the running person's Files, then deleted as a
 * bulk delete; the Recycle Bin is left as it is.
 */
@NamespaceAccessible
public with sharing class ArchiveToFiles implements ArchiveDestination {
	@NamespaceAccessible
	public String key() {
		return ArchiveRules.FILES;
	}

	@NamespaceAccessible
	public String unavailableReason() {
		return null;
	}

	@NamespaceAccessible
	public Import_Batch__c start(ArchiveRun run) {
		return BulkDeleteService.startArchive(run.queryJson, run.confirmedCount, null);
	}
}
