/**
 * The delete guard on people and organizations that Giving records name as donor.
 *
 * A gift's or a commitment's Donor Contact and Donor Account are cleared by the platform when the
 * record they name is deleted, and no gift or commitment trigger runs when that happens. So a
 * Contact or Account is not deleted when a locked gift names it (G-20, R-G15, ADR-0053), or when
 * it is the donor of an Active or Paused commitment, which could then never be saved again
 * (R-CM1). Registered on both objects, run by Core's own triggers, with Always Runs (ADR-0024). A
 * merge still works: the refusal is made after delete, where a merged record carries its
 * MasterRecordId.
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
        CommitmentService.noteDonorsWithOpenCommitments(Trigger.old);
    }

    public override void afterDelete() {
        GiftPostingLock.enforceOnDonorDelete(Trigger.old);
        CommitmentService.refuseDeletingOpenCommitmentDonors(Trigger.old);
    }
}
