/**
 * The reads behind primary affiliation upkeep (C-16, R-AF2), and nothing else.
 *
 * ADR-0021 (system mode writes for package owned data), category 2, is the authority for this
 * class: it allows a read whose only purpose is to compute a package owned value to run in
 * system mode for the same reason as the write it feeds. Every read here feeds
 * `AffiliationUpkeepWriter`. A recompute that sees only the affiliations the saving user can
 * see would leave a second primary flag on a row hidden from them, or would write the wrong
 * organization to the person; under private sharing that is the normal case, not an edge.
 *
 * The four conditions of ADR-0021 hold:
 *
 * - Only package upkeep reaches it, from `AffiliationService`, after the platform has already
 *   authorized the user's own affiliation save.
 * - Its inputs are person identifiers taken from the records being saved. No user-typed text
 *   reaches a query, and nothing here builds dynamic SOQL.
 * - No answer reaches a screen: the affiliation cards read through `AffiliationSelector`,
 *   which stays in user mode.
 * - It is `without sharing` because the rows it must count are exactly the ones the saving
 *   user may not be able to see.
 */
public without sharing class AffiliationUpkeepSelector {
    /**
     * Every affiliation of these people, with only the fields the primary rule reads. Not
     * shown to anyone.
     */
    public static List<Affiliation__c> selectForPrimary(Set<Id> personIds) {
        if (personIds == null || personIds.isEmpty()) {
            return new List<Affiliation__c>();
        }
        return [
            SELECT
                Id,
                Contact__c,
                Person_Account__c,
                Organization__c,
                Status__c,
                Is_Primary__c,
                CreatedDate
            FROM Affiliation__c
            WHERE Contact__c IN :personIds OR Person_Account__c IN :personIds
            WITH SYSTEM_MODE
            ORDER BY Status__c, Is_Primary__c DESC, CreatedDate DESC
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
            WITH SYSTEM_MODE
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
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
    }
}
