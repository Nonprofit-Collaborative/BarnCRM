/**
 * All SOQL against Gift_Allocation__c.
 */
public with sharing class GiftAllocationSelector {
    /**
     * Every allocation of the given gifts, which is what the total check reads.
     */
    public static List<Gift_Allocation__c> selectByGiftIds(Set<Id> giftIds) {
        return [
            SELECT Id, Name, Gift__c, Fund__c, Amount__c, Percent__c
            FROM Gift_Allocation__c
            WHERE Gift__c IN :giftIds
            WITH USER_MODE
            ORDER BY Amount__c DESC NULLS LAST
        ];
    }

    /**
     * One gift's allocations with their fund names, largest first, for the Gift Allocations card.
     */
    public static List<Gift_Allocation__c> selectWithFundNames(Id giftId) {
        return [
            SELECT Id, Gift__c, Fund__c, Fund__r.Name, Amount__c, Percent__c
            FROM Gift_Allocation__c
            WHERE Gift__c = :giftId
            WITH USER_MODE
            ORDER BY Amount__c DESC NULLS LAST
        ];
    }

    /**
     * The allocations with the given identifiers.
     */
    public static List<Gift_Allocation__c> selectById(Set<Id> allocationIds) {
        return [
            SELECT Id, Name, Gift__c, Fund__c, Amount__c, Percent__c
            FROM Gift_Allocation__c
            WHERE Id IN :allocationIds
            WITH USER_MODE
        ];
    }

    /**
     * How many allocations each of the given funds carries, so a fund that has been used is
     * deactivated rather than deleted (R-F2).
     */
    public static Map<Id, Integer> countByFundIds(Set<Id> fundIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult row : [
            SELECT Fund__c fundId, COUNT(Id) allocationCount
            FROM Gift_Allocation__c
            WHERE Fund__c IN :fundIds
            WITH USER_MODE
            GROUP BY Fund__c
        ]) {
            counts.put((Id) row.get('fundId'), (Integer) row.get('allocationCount'));
        }
        return counts;
    }
}
