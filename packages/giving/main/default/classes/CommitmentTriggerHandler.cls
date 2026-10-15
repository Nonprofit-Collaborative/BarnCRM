/**
 * Record-level rules for Commitment__c, run by the Core trigger dispatcher through the
 * Automation Registry row `Commitment_Schedule`.
 *
 * Before save it derives the household from the donor, exactly as a gift's is (R-CM1).
 * After insert it generates the schedule, after update it rebuilds the unpaid part of the
 * schedule when the schedule itself changed (R-CM6), and before delete it refuses to
 * remove a commitment that has been paid.
 */
@NamespaceAccessible
public with sharing class CommitmentTriggerHandler extends TriggerHandler {
    @NamespaceAccessible
    public CommitmentTriggerHandler() {
        return;
    }

    public override void beforeInsert() {
        deriveHouseholds((List<Commitment__c>) newRecords(), null);
    }

    public override void beforeUpdate() {
        deriveHouseholds(
            (List<Commitment__c>) newRecords(),
            (Map<Id, Commitment__c>) oldRecordsById()
        );
    }

    public override void afterInsert() {
        onAfterInsert((List<Commitment__c>) newRecords());
    }

    public override void afterUpdate() {
        onAfterUpdate(
            (List<Commitment__c>) newRecords(),
            (Map<Id, Commitment__c>) oldRecordsById()
        );
    }

    public override void beforeDelete() {
        onBeforeDelete((List<Commitment__c>) oldRecords());
    }

    /**
     * Writes the household of every commitment whose donor was set or changed. The
     * household is read through Core's household service, so the same code is right in an
     * org where people are Contacts and in one where they are accounts (ADR-0005).
     */
    @TestVisible
    private void deriveHouseholds(List<Commitment__c> commitments, Map<Id, Commitment__c> oldMap) {
        Set<Id> people = new Set<Id>();
        List<Commitment__c> needHousehold = new List<Commitment__c>();
        for (Commitment__c commitment : commitments) {
            Commitment__c previous = oldMap == null ? null : oldMap.get(commitment.Id);
            Boolean donorChanged =
                previous == null ||
                previous.Donor_Contact__c != commitment.Donor_Contact__c ||
                previous.Donor_Account__c != commitment.Donor_Account__c;
            if (!donorChanged) {
                continue;
            }
            needHousehold.add(commitment);
            if (commitment.Donor_Contact__c != null) {
                people.add(commitment.Donor_Contact__c);
            } else if (commitment.Donor_Account__c != null) {
                people.add(commitment.Donor_Account__c);
            }
        }
        if (needHousehold.isEmpty()) {
            return;
        }
        Map<Id, Id> householdByPerson = people.isEmpty()
            ? new Map<Id, Id>()
            : HouseholdService.getHouseholdIdsFor(people);
        for (Commitment__c commitment : needHousehold) {
            Id person = commitment.Donor_Contact__c != null
                ? commitment.Donor_Contact__c
                : commitment.Donor_Account__c;
            commitment.Household__c = person == null ? null : householdByPerson.get(person);
        }
    }

    @TestVisible
    private void onAfterInsert(List<Commitment__c> commitments) {
        CommitmentService.generateInstallments(new Map<Id, Commitment__c>(commitments).keySet());
    }

    @TestVisible
    private void onAfterUpdate(List<Commitment__c> commitments, Map<Id, Commitment__c> oldMap) {
        Set<Id> rescheduled = new Set<Id>();
        for (Commitment__c commitment : commitments) {
            Commitment__c previous = oldMap.get(commitment.Id);
            if (previous == null) {
                continue;
            }
            Boolean scheduleChanged =
                previous.Amount__c != commitment.Amount__c ||
                previous.Frequency__c != commitment.Frequency__c ||
                previous.Day_of_Month__c != commitment.Day_of_Month__c ||
                previous.End_Date__c != commitment.End_Date__c ||
                previous.Start_Date__c != commitment.Start_Date__c ||
                previous.Expected_Total__c != commitment.Expected_Total__c ||
                previous.Installments_Planned__c != commitment.Installments_Planned__c;
            if (scheduleChanged) {
                rescheduled.add(commitment.Id);
            }
        }
        if (!rescheduled.isEmpty()) {
            CommitmentService.regenerateFutureInstallments(rescheduled);
        }
    }

    @TestVisible
    private void onBeforeDelete(List<Commitment__c> commitments) {
        Set<Id> commitmentIds = new Map<Id, Commitment__c>(commitments).keySet();
        List<Installment__c> installments = new InstallmentSelector()
            .selectByCommitmentIds(commitmentIds);
        if (installments.isEmpty()) {
            return;
        }
        Map<Id, Integer> giftCounts = new InstallmentSelector()
            .countGifts(new Map<Id, Installment__c>(installments).keySet());
        Set<Id> blocked = new Set<Id>();
        for (Installment__c installment : installments) {
            Integer gifts = giftCounts.get(installment.Id);
            Boolean paid =
                (gifts != null && gifts > 0) ||
                (installment.Paid_Amount__c != null &&
                installment.Paid_Amount__c != 0);
            if (paid) {
                blocked.add(installment.Commitment__c);
            }
        }
        for (Commitment__c commitment : commitments) {
            if (blocked.contains(commitment.Id)) {
                commitment.addError(System.Label.Giving_Commitment_DeleteBlocked);
            }
        }
    }
}
