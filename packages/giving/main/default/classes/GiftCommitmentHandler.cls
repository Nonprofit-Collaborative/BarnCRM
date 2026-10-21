/**
 * The Gift__c handler that applies a gift to the commitment and the installment it pays,
 * run by the Core trigger dispatcher through the Automation Registry row
 * `Gift_Commitment_Application` at execution order 20, after the gift's own domain rules.
 */
@NamespaceAccessible
public with sharing class GiftCommitmentHandler extends TriggerHandler {
    @NamespaceAccessible
    public GiftCommitmentHandler() {
        return;
    }

    public override void afterInsert() {
        onAfterInsert((List<Gift__c>) newRecords());
    }

    public override void afterUpdate() {
        onAfterUpdate((List<Gift__c>) newRecords(), (Map<Id, Gift__c>) oldRecordsById());
    }

    public override void afterDelete() {
        onAfterDelete((List<Gift__c>) oldRecords());
    }

    /** A gift restored from the recycle bin pays again, as it did when it was created. */
    public override void afterUndelete() {
        onAfterInsert((List<Gift__c>) newRecords());
    }

    /**
     * A new gift pays what it names. A refund or write-off of a pledge payment (a negative gift
     * carrying the original's commitment and installment, R-G3) takes its amount back off, so
     * a pledge it had completed and that is now short of its total is reopened (R-CM4).
     */
    @TestVisible
    private void onAfterInsert(List<Gift__c> gifts) {
        List<Gift__c> relevant = new List<Gift__c>();
        Map<Id, Decimal> removedByCommitment = new Map<Id, Decimal>();
        for (Gift__c gift : gifts) {
            if (gift.Commitment__c != null || gift.Installment__c != null) {
                relevant.add(gift);
            }
            if (
                gift.Commitment__c != null &&
                gift.Amount__c != null &&
                gift.Amount__c < 0 &&
                CommitmentService.countsAsPaid(gift)
            ) {
                Decimal removed = removedByCommitment.get(gift.Commitment__c);
                removedByCommitment.put(
                    gift.Commitment__c,
                    (removed == null ? 0 : removed) - gift.Amount__c
                );
            }
        }
        CommitmentService.applyGift(relevant);
        CommitmentService.reopenPledgesNoLongerPaid(removedByCommitment);
    }

    /**
     * A gift matters here when its amount or its status changed, because both change what
     * an installment counts as paid, and when its commitment or installment link changed.
     */
    @TestVisible
    private void onAfterUpdate(List<Gift__c> gifts, Map<Id, Gift__c> oldMap) {
        List<Gift__c> relevant = new List<Gift__c>();
        Set<Id> releasedInstallments = new Set<Id>();
        Set<Id> uncancelled = new Set<Id>();
        for (Gift__c gift : gifts) {
            Gift__c previous = oldMap.get(gift.Id);
            if (previous == null) {
                continue;
            }
            if (previous.Status__c == 'Cancelled') {
                uncancelled.add(gift.Id);
            }
            Boolean changed =
                previous.Amount__c != gift.Amount__c ||
                previous.Status__c != gift.Status__c ||
                previous.Commitment__c != gift.Commitment__c ||
                previous.Installment__c != gift.Installment__c;
            if (!changed) {
                continue;
            }
            if (previous.Installment__c != null && previous.Installment__c != gift.Installment__c) {
                releasedInstallments.add(previous.Installment__c);
            }
            if (gift.Commitment__c != null || gift.Installment__c != null) {
                relevant.add(gift);
            }
        }
        // An installment a gift has just left has to be recalculated too.
        CommitmentService.refreshInstallmentStatuses(releasedInstallments);
        CommitmentService.applyGift(relevant, uncancelled);
    }

    /**
     * A deleted gift no longer pays anything (R-CM4): the installment it paid is recalculated
     * from the gifts still linked, and a pledge it had completed is reopened.
     */
    @TestVisible
    private void onAfterDelete(List<Gift__c> gifts) {
        Set<Id> installmentIds = new Set<Id>();
        Map<Id, Decimal> removedByCommitment = new Map<Id, Decimal>();
        for (Gift__c gift : gifts) {
            if (gift.Installment__c != null) {
                installmentIds.add(gift.Installment__c);
            }
            if (gift.Commitment__c != null && CommitmentService.countsAsPaid(gift)) {
                Decimal removed = removedByCommitment.get(gift.Commitment__c);
                removedByCommitment.put(
                    gift.Commitment__c,
                    (removed == null ? 0 : removed) + (gift.Amount__c == null ? 0 : gift.Amount__c)
                );
            }
        }
        CommitmentService.refreshInstallmentStatuses(installmentIds);
        CommitmentService.reopenPledgesNoLongerPaid(removedByCommitment);
    }
}
