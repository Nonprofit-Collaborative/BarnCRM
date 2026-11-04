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
        GiftPostingLock.enforceOnInsert((List<Gift__c>) newRecords());
    }

    public override void afterInsert() {
        GiftPostingLock.enforceOnRestore((List<Gift__c>) newRecords(), false);
    }

    public override void beforeUpdate() {
        GiftPostingLock.enforceOnUpdate(
            (List<Gift__c>) newRecords(),
            (Map<Id, Gift__c>) oldRecordsById()
        );
    }

    public override void beforeDelete() {
        GiftPostingLock.enforceOnDelete((List<Gift__c>) oldRecords());
    }

    public override void afterUndelete() {
        GiftPostingLock.enforceOnRestore((List<Gift__c>) newRecords(), true);
    }
}
