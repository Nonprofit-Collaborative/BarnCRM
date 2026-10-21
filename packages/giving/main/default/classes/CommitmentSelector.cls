/**
 * Queries for Commitment__c and for the gifts paid against a commitment.
 *
 * Every SOQL statement in the commitments feature lives here or in
 * InstallmentSelector (plan Section 9.3).
 */
public with sharing class CommitmentSelector {
    private static final String TYPE_RECURRING = 'Recurring';
    private static final String STATUS_ACTIVE = 'Active';
    private static final Set<String> OPEN_STATUSES = new Set<String>{ 'Active', 'Paused' };

    /**
     * The commitments named, with every attribute the schedule builder reads.
     */
    public List<Commitment__c> selectByIds(Set<Id> commitmentIds) {
        return [
            SELECT
                Id,
                Name,
                Type__c,
                Status__c,
                Amount__c,
                Frequency__c,
                Day_of_Month__c,
                Start_Date__c,
                End_Date__c,
                Expected_Total__c,
                Installments_Planned__c,
                Paid_To_Date__c,
                Donor_Contact__c,
                Donor_Account__c,
                Household__c,
                Fund__c,
                Appeal__c
            FROM Commitment__c
            WHERE Id IN :commitmentIds
            WITH USER_MODE
        ];
    }

    /**
     * Every active recurring commitment whose schedule may need extending, as a query the
     * top up batch iterates. A batch is what makes this safe at any size: one capped query
     * would extend the same oldest commitments every night and never reach the rest.
     */
    public Database.QueryLocator activeRecurringLocator() {
        Date today = Date.today();
        return Database.getQueryLocator(
            [
                SELECT
                    Id,
                    Name,
                    Type__c,
                    Status__c,
                    Amount__c,
                    Frequency__c,
                    Day_of_Month__c,
                    Start_Date__c,
                    End_Date__c,
                    Expected_Total__c,
                    Installments_Planned__c
                FROM Commitment__c
                WHERE
                    Type__c = :TYPE_RECURRING
                    AND Status__c = :STATUS_ACTIVE
                    AND (End_Date__c = NULL
                    OR End_Date__c >= :today)
                WITH USER_MODE
                ORDER BY Start_Date__c
            ]
        );
    }

    /**
     * What has been paid against each commitment named, by commitment: the gifts in
     * `CommitmentService.PAID_GIFT_STATUSES`, net of the negative gifts that refund or write
     * them off.
     */
    public Map<Id, Decimal> sumPaidGifts(Set<Id> commitmentIds) {
        Map<Id, Decimal> totals = new Map<Id, Decimal>();
        if (commitmentIds == null || commitmentIds.isEmpty()) {
            return totals;
        }
        Set<String> paid = CommitmentService.PAID_GIFT_STATUSES;
        for (AggregateResult row : [
            SELECT Commitment__c commitmentId, SUM(Amount__c) total
            FROM Gift__c
            WHERE Commitment__c IN :commitmentIds AND Status__c IN :paid
            WITH USER_MODE
            GROUP BY Commitment__c
        ]) {
            Decimal total = (Decimal) row.get('total');
            totals.put((Id) row.get('commitmentId'), total == null ? 0 : total);
        }
        return totals;
    }

    /**
     * The Active and Paused commitments whose donor is one of these records, or whose person
     * donor's account is (deleting that account deletes the person with it). Read in system
     * mode, because the delete guard has to see every such commitment, not only those the
     * person deleting can see.
     */
    public List<Commitment__c> selectOpenNaming(Set<Id> recordIds) {
        return [
            SELECT Id, Donor_Contact__c, Donor_Contact__r.AccountId, Donor_Account__c
            FROM Commitment__c
            WHERE
                Status__c IN :OPEN_STATUSES
                AND (Donor_Contact__c IN :recordIds
                OR Donor_Contact__r.AccountId IN :recordIds
                OR Donor_Account__c IN :recordIds)
            WITH SYSTEM_MODE
        ];
    }
}
