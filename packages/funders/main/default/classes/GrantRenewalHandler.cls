/**
 * R-GN12 for Grant__c, run by the Core trigger dispatcher through the registry row
 * `Grant_Renewal`, switchable from the Automation page (ADR-0017): an awarded, renewable grant
 * with an award end date keeps one open Renewal requirement, which the requirement reminders
 * remind. It does work for the user, so an import of past grants can turn it off.
 */
@NamespaceAccessible
public with sharing class GrantRenewalHandler extends TriggerHandler {
	@NamespaceAccessible
	public GrantRenewalHandler() {
		return;
	}

	public override String getName() {
		return 'GrantRenewalHandler';
	}

	public override void afterInsert() {
		GrantManagementService.syncRenewals((List<Grant__c>) newRecords(), null);
	}

	public override void afterUpdate() {
		GrantManagementService.syncRenewals(
			(List<Grant__c>) newRecords(),
			(Map<Id, Grant__c>) oldRecordsById()
		);
	}
}
