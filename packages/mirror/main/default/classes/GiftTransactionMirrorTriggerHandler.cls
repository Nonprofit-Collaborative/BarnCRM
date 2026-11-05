/**
 * The `Gift_Transaction_Mirror` automation on Gift (feature X-07, canonical model Section 29C1).
 * It copies nothing, since the Gift Transaction mirror works only in runs (R-GT6): before a gift
 * is written it checks a typed or changed Gift Transaction ID (R-GT9), and after a delete it
 * reports the Gift Transactions the deleted gifts leave behind (R-GT8). Its switch on the
 * Automation page also stops the runs.
 */
@NamespaceAccessible
public with sharing class GiftTransactionMirrorTriggerHandler extends TriggerHandler {
	@NamespaceAccessible
	public GiftTransactionMirrorTriggerHandler() {
		return;
	}

	public override String getName() {
		return GiftTransactionMirrorService.AUTOMATION_NAME;
	}

	public override void beforeInsert() {
		GiftTransactionMirrorService.checkLinks((List<Gift__c>) newRecords(), null);
	}

	public override void beforeUpdate() {
		GiftTransactionMirrorService.checkLinks(
			(List<Gift__c>) newRecords(),
			(Map<Id, Gift__c>) oldRecordsById()
		);
	}

	public override void afterDelete() {
		GiftTransactionMirrorService.warnDeleted((List<Gift__c>) oldRecords());
	}
}
