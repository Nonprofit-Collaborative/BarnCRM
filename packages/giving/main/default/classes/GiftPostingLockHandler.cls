/**
 * The posting and closed period lock on gifts (G-20, R-G14), on its own automation so that
 * nothing switches it off: its registry row (`Gift_Posting_Lock`) carries Always Runs, the same
 * as the receipt lock's (ADR-0024). The rules are `GiftPostingLock` methods that take explicit
 * lists and are tested without a trigger context.
 */
@NamespaceAccessible
public with sharing class GiftPostingLockHandler extends TriggerHandler {
    @NamespaceAccessible
    public GiftPostingLockHandler() {
        return;
    }

    public override String getName() {
        return 'GiftPostingLockHandler';
    }

    public override void beforeInsert() {
        GiftPostingLock.enforceOnInsert((List<Gift__c>) Trigger.new);
    }

    public override void afterInsert() {
        GiftPostingLock.enforceOnRestore((List<Gift__c>) Trigger.new, false);
    }

    public override void beforeUpdate() {
        GiftPostingLock.enforceOnUpdate(
            (List<Gift__c>) Trigger.new,
            (Map<Id, Gift__c>) Trigger.oldMap
        );
    }

    public override void beforeDelete() {
        GiftPostingLock.enforceOnDelete((List<Gift__c>) Trigger.old);
    }

    public override void afterUndelete() {
        GiftPostingLock.enforceOnRestore((List<Gift__c>) Trigger.new, true);
    }
}
