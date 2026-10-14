/**
 * The user mode reads of Affiliation__c: what the cards show and what the save checks compare
 * against. Feature code never queries the object directly (plan Section 7.2: every query lives
 * in a Selector). The reads behind primary affiliation upkeep, which must see rows the saving
 * user cannot, are in `AffiliationUpkeepSelector` (ADR-0021).
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
}
