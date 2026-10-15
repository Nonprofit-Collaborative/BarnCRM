/**
 * Record-level rules for Installment__c, run by the Core trigger dispatcher through the
 * Automation Registry row `Installment_Protection`.
 *
 * An installment a gift has been received against is part of the giving history, so it is
 * not deleted. Staff mark it Skipped instead (R-IN2).
 */
@NamespaceAccessible
public with sharing class InstallmentTriggerHandler extends TriggerHandler {
    @NamespaceAccessible
    public InstallmentTriggerHandler() {
        return;
    }

    public override void beforeDelete() {
        onBeforeDelete((List<Installment__c>) oldRecords());
    }

    @TestVisible
    private void onBeforeDelete(List<Installment__c> installments) {
        Map<Id, Integer> giftCounts = new InstallmentSelector()
            .countGifts(new Map<Id, Installment__c>(installments).keySet());
        for (Installment__c installment : installments) {
            Integer gifts = giftCounts.get(installment.Id);
            Boolean paid =
                (gifts != null && gifts > 0) ||
                (installment.Paid_Amount__c != null &&
                installment.Paid_Amount__c != 0);
            if (paid) {
                installment.addError(System.Label.Giving_Installment_DeleteBlocked);
            }
        }
    }
}
