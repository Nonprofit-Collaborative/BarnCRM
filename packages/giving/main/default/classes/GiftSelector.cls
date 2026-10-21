/**
 * All SOQL against Gift__c. Every query runs in user mode, so a user only ever reads the
 * gifts they are allowed to read (plan Section 4.13).
 */
public with sharing class GiftSelector {
    /**
     * The gifts with the given identifiers.
     */
    public static List<Gift__c> selectById(Set<Id> giftIds) {
        return [
            SELECT
                Id,
                Name,
                Donor_Contact__c,
                Donor_Account__c,
                Household__c,
                Gift_Date__c,
                Amount__c,
                Type__c,
                Status__c,
                Appeal__c,
                Acknowledgment_Status__c,
                Acknowledgment_Date__c,
                Receipt_Number__c,
                External_Id__c,
                Payment_Reference__c,
                Original_Gift__c,
                Refund_Reason__c
            FROM Gift__c
            WHERE Id IN :giftIds
            WITH USER_MODE
        ];
    }

    /**
     * The gifts with the given identifiers, each with its allocations, for the refund and
     * write-off paths that mirror a gift's designation.
     */
    public static List<Gift__c> selectWithAllocations(Set<Id> giftIds) {
        return [
            SELECT
                Id,
                Name,
                Donor_Contact__c,
                Donor_Account__c,
                Household__c,
                Gift_Date__c,
                Amount__c,
                Type__c,
                Status__c,
                Appeal__c,
                Receipt_Number__c,
                Original_Gift__c,
                Refund_Reason__c,
                Commitment__c,
                Installment__c,
                (
                    SELECT Id, Fund__c, Amount__c, Percent__c
                    FROM Gift_Allocations__r
                    ORDER BY Amount__c DESC NULLS LAST
                )
            FROM Gift__c
            WHERE Id IN :giftIds
            WITH USER_MODE
        ];
    }

    /**
     * Amount and status only, keyed by identifier, for the allocation total check.
     */
    public static Map<Id, Gift__c> selectAmountsById(Set<Id> giftIds) {
        return new Map<Id, Gift__c>(
            [SELECT Id, Name, Amount__c, Status__c FROM Gift__c WHERE Id IN :giftIds WITH USER_MODE]
        );
    }

    /**
     * The allocations of the given gifts. It delegates to the allocation selector rather than
     * repeating the query, and it exists here because a caller that has gifts in hand looks for
     * it here first (the gift entry screen, G-03, does).
     */
    public static List<Gift_Allocation__c> selectAllocationsByGiftIds(Set<Id> giftIds) {
        return GiftAllocationSelector.selectByGiftIds(giftIds);
    }

    /**
     * The negative gifts that reverse the given gifts, so a second refund knows what is left.
     */
    public static List<Gift__c> selectReversalsFor(Set<Id> originalGiftIds) {
        return [
            SELECT Id, Amount__c, Original_Gift__c, Status__c
            FROM Gift__c
            WHERE Original_Gift__c IN :originalGiftIds
            WITH USER_MODE
        ];
    }
}
