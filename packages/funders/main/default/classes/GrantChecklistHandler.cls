/**
 * R-GQ7 for Grant__c, run by the Core trigger dispatcher through the registry row
 * `Grant_Checklist`, switchable from the Automation page (ADR-0017): a grant created at, or moved
 * to, a stage gets that stage's active checklist items as tasks. It does work for the user, so an
 * import of past grants can turn it off.
 */
@NamespaceAccessible
public with sharing class GrantChecklistHandler extends TriggerHandler {
	@NamespaceAccessible
	public GrantChecklistHandler() {
		return;
	}

	public override String getName() {
		return 'GrantChecklistHandler';
	}

	public override void afterInsert() {
		GrantManagementService.addTasksOnStageChange((List<Grant__c>) newRecords(), null);
	}

	public override void afterUpdate() {
		GrantManagementService.addTasksOnStageChange(
			(List<Grant__c>) newRecords(),
			(Map<Id, Grant__c>) oldRecordsById()
		);
	}
}
