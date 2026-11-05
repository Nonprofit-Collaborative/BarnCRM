/**
 * The `Campaign_Sync` automation on Appeal (feature X-02, R-CS3): copies the appeal to its
 * Campaign before the appeal is written, so a new Campaign's identifier is saved with it.
 * Registered by Mirror in the automation registry, after Giving's hierarchy check, so it
 * never copies an appeal that check has already refused.
 */
@NamespaceAccessible
public with sharing class CampaignSyncTriggerHandler extends TriggerHandler {
	@NamespaceAccessible
	public CampaignSyncTriggerHandler() {
		return;
	}

	public override String getName() {
		return CampaignSyncService.AUTOMATION_NAME;
	}

	public override void beforeInsert() {
		CampaignSyncService.syncBeforeSave((List<Appeal__c>) newRecords(), null);
	}

	public override void beforeUpdate() {
		CampaignSyncService.syncBeforeSave(
			(List<Appeal__c>) newRecords(),
			(Map<Id, Appeal__c>) oldRecordsById()
		);
	}
}
