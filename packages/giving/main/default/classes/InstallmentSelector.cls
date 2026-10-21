/**
 * Queries for Installment__c and for the gifts paid against an installment.
 */
public with sharing class InstallmentSelector {
    private static final String STATUS_SCHEDULED = 'Scheduled';

    /**
     * Every installment of the commitments named, in schedule order.
     */
    public List<Installment__c> selectByCommitmentIds(Set<Id> commitmentIds) {
        return [
            SELECT
                Id,
                Name,
                Commitment__c,
                Sequence__c,
                Due_Date__c,
                Expected_Amount__c,
                Status__c,
                Paid_Amount__c
            FROM Installment__c
            WHERE Commitment__c IN :commitmentIds
            WITH USER_MODE
            ORDER BY Commitment__c, Sequence__c
        ];
    }

    /**
     * The installments named.
     */
    public List<Installment__c> selectByIds(Set<Id> installmentIds) {
        return [
            SELECT
                Id,
                Name,
                Commitment__c,
                Sequence__c,
                Due_Date__c,
                Expected_Amount__c,
                Status__c,
                Paid_Amount__c
            FROM Installment__c
            WHERE Id IN :installmentIds
            WITH USER_MODE
        ];
    }

    /**
     * The installments still owed by the donors and households named (R-DM2): Scheduled,
     * Overdue or Partially paid, on an Active or Paused commitment whose donor or household is
     * one of them. No date bound: a gift entry screen lists them all for a person to choose
     * from (R-DM8). Earliest due first.
     */
    public List<Installment__c> selectOpenForDonors(
        Set<Id> donorIds,
        Set<Id> householdIds,
        Integer maximum
    ) {
        return [
            SELECT
                Id,
                Name,
                Sequence__c,
                Due_Date__c,
                Expected_Amount__c,
                Status__c,
                Commitment__c,
                Commitment__r.Name,
                Commitment__r.Type__c,
                Commitment__r.Donor_Contact__c,
                Commitment__r.Donor_Account__c,
                Commitment__r.Household__c
            FROM Installment__c
            WHERE
                Status__c IN ('Scheduled', 'Overdue', 'Partially paid')
                AND Commitment__r.Status__c IN ('Active', 'Paused')
                AND (Commitment__r.Donor_Contact__c IN :donorIds
                OR Commitment__r.Donor_Account__c IN :donorIds
                OR Commitment__r.Household__c IN :householdIds)
            WITH USER_MODE
            ORDER BY Due_Date__c, Name
            LIMIT :maximum
        ];
    }

    /**
     * The installments named that are still owed (R-DM2's statuses, on an Active or Paused
     * commitment), with the commitment's donor and household, for checking a choice at save.
     */
    public List<Installment__c> selectOpenByIds(Set<Id> installmentIds) {
        return [
            SELECT
                Id,
                Commitment__c,
                Commitment__r.Donor_Contact__c,
                Commitment__r.Donor_Account__c,
                Commitment__r.Household__c
            FROM Installment__c
            WHERE
                Id IN :installmentIds
                AND Status__c IN ('Scheduled', 'Overdue', 'Partially paid')
                AND Commitment__r.Status__c IN ('Active', 'Paused')
            WITH USER_MODE
        ];
    }

    /**
     * Still-scheduled installments whose due date is on or before the cutoff, for the daily
     * job. Rows already marked Overdue are deliberately outside the query: they already
     * carry the right status, and including them would let a backlog of old overdue rows
     * fill the row cap every night so that a newly overdue payment was never reached.
     */
    public List<Installment__c> selectUnpaidDueBefore(Date cutoff, Integer maximum) {
        return [
            SELECT Id, Commitment__c, Sequence__c, Due_Date__c, Expected_Amount__c, Status__c
            FROM Installment__c
            WHERE Status__c = :STATUS_SCHEDULED AND Due_Date__c <= :cutoff
            WITH USER_MODE
            ORDER BY Due_Date__c
            LIMIT :maximum
        ];
    }

    /**
     * What has been paid against each installment named, by installment: the gifts in
     * `CommitmentService.PAID_GIFT_STATUSES`, net of the negative gifts that refund or write
     * them off.
     */
    public Map<Id, Decimal> sumPaidGifts(Set<Id> installmentIds) {
        Map<Id, Decimal> totals = new Map<Id, Decimal>();
        if (installmentIds == null || installmentIds.isEmpty()) {
            return totals;
        }
        Set<String> paid = CommitmentService.PAID_GIFT_STATUSES;
        for (AggregateResult row : [
            SELECT Installment__c installmentId, SUM(Amount__c) total
            FROM Gift__c
            WHERE Installment__c IN :installmentIds AND Status__c IN :paid
            WITH USER_MODE
            GROUP BY Installment__c
        ]) {
            Decimal total = (Decimal) row.get('total');
            totals.put((Id) row.get('installmentId'), total == null ? 0 : total);
        }
        return totals;
    }

    /**
     * How many gifts of any status are linked to each installment named.
     */
    public Map<Id, Integer> countGifts(Set<Id> installmentIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (installmentIds == null || installmentIds.isEmpty()) {
            return counts;
        }
        for (AggregateResult row : [
            SELECT Installment__c installmentId, COUNT(Id) total
            FROM Gift__c
            WHERE Installment__c IN :installmentIds
            WITH USER_MODE
            GROUP BY Installment__c
        ]) {
            counts.put((Id) row.get('installmentId'), (Integer) row.get('total'));
        }
        return counts;
    }
}
