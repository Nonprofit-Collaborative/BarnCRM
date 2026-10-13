/**
 * All SOQL against Affiliation__c, and the two small reads of the person records that carry
 * the primary affiliation. Feature code never queries any of them directly (plan Section 7.2:
 * every query lives in a Selector).
 */
public with sharing class AffiliationSelector {
    /**
     * Every affiliation belonging to any of these people, whether the person is held as a
     * contact or as an account. Current ones first, then newest first, which is the order the
     * card shows and the order the primary is chosen in.
     */
    public static List<Affiliation__c> selectByPersonIds(Set<Id> personIds) {
        if (personIds == null || personIds.isEmpty()) {
            return new List<Affiliation__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Contact__c,
                Contact__r.Name,
                Person_Account__c,
                Person_Account__r.Name,
                Organization__c,
                Organization__r.Name,
                Role__c,
                Status__c,
                Is_Primary__c,
                Start_Date__c,
                End_Date__c,
                Description__c,
                CreatedDate
            FROM Affiliation__c
            WHERE Contact__c IN :personIds OR Person_Account__c IN :personIds
            WITH USER_MODE
            ORDER BY Status__c, Is_Primary__c DESC, CreatedDate DESC
            LIMIT 10000
        ];
    }

    /** Every affiliation pointing at one of these organizations, for the organization's card. */
    public static List<Affiliation__c> selectByOrganizationIds(Set<Id> organizationIds) {
        if (organizationIds == null || organizationIds.isEmpty()) {
            return new List<Affiliation__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Contact__c,
                Contact__r.Name,
                Person_Account__c,
                Person_Account__r.Name,
                Organization__c,
                Organization__r.Name,
                Role__c,
                Status__c,
                Is_Primary__c,
                Start_Date__c,
                End_Date__c,
                Description__c,
                CreatedDate
            FROM Affiliation__c
            WHERE Organization__c IN :organizationIds
            WITH USER_MODE
            ORDER BY Status__c, CreatedDate DESC
            LIMIT 10000
        ];
    }

    /**
     * The primary affiliation each of these contacts currently carries, so that the package
     * writes a person record only when the value it holds is actually wrong.
     */
    public static List<Contact> selectContactPrimaries(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new List<Contact>();
        }
        return [
            SELECT Id, Primary_Affiliation__c
            FROM Contact
            WHERE Id IN :contactIds
            WITH USER_MODE
            LIMIT 10000
        ];
    }

    /** The same for people an org holds as accounts. */
    public static List<Account> selectAccountPrimaries(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Account>();
        }
        return [
            SELECT Id, Primary_Affiliation__c
            FROM Account
            WHERE Id IN :accountIds
            WITH USER_MODE
            LIMIT 10000
        ];
    }
}
