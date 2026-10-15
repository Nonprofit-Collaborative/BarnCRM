/**
 * The receipt lock, on its own automation so that nothing switches it off.
 *
 * ADR-0024: enforcing receipt immutability is not a convenience, so it does not belong in the
 * switchable handler that fills in households, dates and default allocations. Its registry row
 * (`Gift_Receipt_Lock`) carries `Always_Runs__c`, so the dispatcher runs it whatever the bypass,
 * the pause and the switch say, and the console shows its switch off and disabled with a reason.
 *
 * The handler is the same three-line wrapper every other one is: the rules themselves are
 * `GiftService` methods that take explicit lists and are unit tested without a trigger context.
 */
@NamespaceAccessible
public with sharing class GiftReceiptLockHandler extends TriggerHandler {
    @NamespaceAccessible
    public GiftReceiptLockHandler() {
        return;
    }

    public override String getName() {
        return 'GiftReceiptLockHandler';
    }

    public override void beforeInsert() {
        GiftService.enforceReceiptNumberOnInsert((List<Gift__c>) Trigger.new);
    }

    public override void afterInsert() {
        GiftService.recordReceiptNumberOverridesOnInsert((List<Gift__c>) Trigger.new);
    }

    public override void beforeUpdate() {
        GiftService.enforceReceiptLock(
            (List<Gift__c>) Trigger.new,
            (Map<Id, Gift__c>) Trigger.oldMap
        );
    }

    public override void beforeDelete() {
        GiftService.preventLossOfHistory((List<Gift__c>) Trigger.old);
    }
}
