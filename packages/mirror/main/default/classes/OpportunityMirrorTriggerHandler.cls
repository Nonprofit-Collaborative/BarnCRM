/**
 * The `Opportunity_Mirror` automation on Gift (feature X-01, R-OM4): copies the gift to its
 * Opportunity before the gift is written, so a new Opportunity's identifier is saved with it.
 * Registered by Mirror in the automation registry after Giving's core rules, so the household
 * the Opportunity's Account is taken from has already been derived. After a delete it reports
 * the Opportunities the deleted gifts leave behind (R-OM9).
 */
@NamespaceAccessible
public with sharing class OpportunityMirrorTriggerHandler extends TriggerHandler {
    @NamespaceAccessible
    public OpportunityMirrorTriggerHandler() {
        return;
    }

    public override String getName() {
        return OpportunityMirrorService.AUTOMATION_NAME;
    }

    public override void beforeInsert() {
        OpportunityMirrorService.syncBeforeSave((List<Gift__c>) Trigger.new, null);
    }

    public override void beforeUpdate() {
        OpportunityMirrorService.syncBeforeSave(
            (List<Gift__c>) Trigger.new,
            (Map<Id, Gift__c>) Trigger.oldMap
        );
    }

    public override void afterDelete() {
        OpportunityMirrorService.warnDeleted((List<Gift__c>) Trigger.old);
    }
}
