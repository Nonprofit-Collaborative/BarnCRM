/**
 * The delete guard on people and organizations for the posting lock (G-20, R-G15, ADR-0053).
 *
 * A locked gift's Donor Contact and Donor Account are cleared by the platform when the record
 * they name is deleted, and no gift trigger runs when that happens. So a Contact or Account that
 * a locked gift names is not deleted. Registered on both objects, run by Core's own triggers,
 * with Always Runs (ADR-0024). A merge still works: the refusal is made after delete, where a
 * merged record carries its MasterRecordId.
 */
@NamespaceAccessible
public with sharing class GiftDonorDeleteGuardHandler extends TriggerHandler {
    @NamespaceAccessible
    public GiftDonorDeleteGuardHandler() {
        return;
    }

    public override String getName() {
        return 'GiftDonorDeleteGuardHandler';
    }

    public override void beforeDelete() {
        GiftPostingLock.noteDonorsNamed(Trigger.old);
    }

    public override void afterDelete() {
        GiftPostingLock.enforceOnDonorDelete(Trigger.old);
    }
}
