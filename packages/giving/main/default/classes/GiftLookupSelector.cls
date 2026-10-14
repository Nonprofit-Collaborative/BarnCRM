/**
 * The gift queries that recognition needs: soft credit maintenance and matching gift linkage.
 *
 * The gift feature's own queries live in its own selector. This one exists so that G-08, G-09 and
 * G-10 read gifts without reaching into another feature's class, and so that every query they make
 * is in one file (plan Section 9.3).
 *
 * Two access levels, deliberately. Automation reads in system mode, because the credits BarnCRM
 * maintains must be right whatever the saving user can see; anything a person asked for
 * reads in user mode, so the screen shows them only their own access.
 */
public with sharing class GiftLookupSelector {
    /**
     * Gifts as automatic soft credit maintenance needs them.
     */
    public static List<Gift__c> selectForRecognition(Set<Id> giftIds) {
        if (giftIds == null || giftIds.isEmpty()) {
            return new List<Gift__c>();
        }
        return [
            SELECT Id, Amount__c, Status__c, Donor_Contact__c, Donor_Account__c, Household__c
            FROM Gift__c
            WHERE Id IN :giftIds
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
    }

    /**
     * The gifts of these households, most recent first, as automatic soft credit maintenance
     * needs them after a change of household membership (R-SC3).
     *
     * System mode and a caller supplied cap, for the same reason as the query above: the credits
     * have to be right whatever the person who moved somebody between households can see, and a
     * household's giving history has no natural bound.
     */
    public static List<Gift__c> selectForHouseholds(Set<Id> householdIds, Integer maxRows) {
        if (householdIds == null || householdIds.isEmpty() || maxRows == null || maxRows <= 0) {
            return new List<Gift__c>();
        }
        Integer rowCap = Math.min(maxRows, 10000);
        return [
            SELECT Id, Amount__c, Status__c, Donor_Contact__c, Donor_Account__c, Household__c
            FROM Gift__c
            WHERE Household__c IN :householdIds
            WITH SYSTEM_MODE
            ORDER BY Gift_Date__c DESC NULLS LAST, Id DESC
            LIMIT :rowCap
        ];
    }

    /**
     * Which of these households have at least one gift (R-SC3): only their credits can need
     * recomputing after a change of membership. A semi-join, so the households are the rows read,
     * not their gifts, however long their giving histories are.
     *
     * Without sharing as well as in system mode (ADR-0021): whether a household has gifts is a
     * fact about the org, not about what the person changing its membership may see. A gift that
     * person cannot see would otherwise read as absent and its credits would never be put right.
     * It returns identifiers only and elevates nothing else.
     */
    public static Set<Id> selectHouseholdsWithGifts(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return new Set<Id>();
        }
        return new HouseholdsWithGifts().among(householdIds);
    }

    private without sharing class HouseholdsWithGifts {
        private Set<Id> among(Set<Id> householdIds) {
            return new Map<Id, Account>(
                    [
                        SELECT Id
                        FROM Account
                        WHERE Id IN :householdIds AND Id IN (SELECT Household__c FROM Gift__c)
                        WITH SYSTEM_MODE
                    ]
                )
                .keySet();
        }
    }

    /**
     * Gifts as matching gift maintenance needs them: who gave, how much, what the donor account
     * is, and where the donor works.
     *
     * System mode, because the link and the credit it creates must be right whatever the saving
     * user can see; every write the matching gift service makes from these records still runs in
     * user mode, so nobody edits a gift they have no access to.
     */
    public static List<Gift__c> selectForMatching(Set<Id> giftIds) {
        if (giftIds == null || giftIds.isEmpty()) {
            return new List<Gift__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Amount__c,
                Gift_Date__c,
                Status__c,
                Matched_Gift__c,
                Donor_Contact__c,
                Donor_Contact__r.Name,
                Donor_Contact__r.Employer__c,
                Donor_Account__c,
                Donor_Account__r.Name,
                Donor_Account__r.Employer__c,
                Donor_Account__r.RecordType.DeveloperName
            FROM Gift__c
            WHERE Id IN :giftIds
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
    }
}
