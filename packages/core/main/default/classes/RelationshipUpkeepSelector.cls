/**
 * The reads behind keeping both sides of a relationship in step (C-15, R-RL1, R-RL4a), and
 * nothing else.
 *
 * ADR-0021 (system mode writes for package owned data), category 2, is the authority for this
 * class: a read whose only purpose is to compute package upkeep may run in system mode for the
 * same reason as the write it feeds. Every read here feeds `RelationshipUpkeepWriter`. The
 * other side of a relationship is a record of its own, described from the other person, and
 * under private sharing it is often owned by somebody else. Read with the saving user's
 * access, an existing other side is invisible, so the package would build a duplicate instead
 * of pairing (R-RL4a), or would treat a live mirror as deleted and rebuild it.
 *
 * The conditions of ADR-0021 hold:
 *
 * - Only `RelationshipService` reaches it, after the platform has authorized the user's own
 *   relationship save, edit, delete or restore.
 * - Its inputs are identifiers taken from the records being saved. No user-typed text reaches
 *   a query, and nothing here builds dynamic SOQL.
 * - No answer reaches a screen: the relationship card reads through `RelationshipSelector`,
 *   which stays in user mode.
 * - It is `without sharing` because the rows it must find are exactly the ones the saving user
 *   may not be able to see.
 */
public without sharing class RelationshipUpkeepSelector {
    /**
     * Every relationship described from one of these people: the pool the service searches for
     * a record that is already the other side. Not shown to anyone.
     */
    public static List<Relationship__c> selectByFromPersonIds(Set<Id> personIds) {
        if (personIds == null || personIds.isEmpty()) {
            return new List<Relationship__c>();
        }
        return [
            SELECT
                Id,
                Contact__c,
                Person_Account__c,
                Related_Contact__c,
                Related_Person_Account__c,
                Type__c,
                Reciprocal_Type__c,
                Status__c,
                Start_Date__c,
                End_Date__c,
                Description__c,
                Reciprocal_Relationship__c,
                Is_Reciprocal_Managed__c,
                CreatedDate
            FROM Relationship__c
            WHERE Contact__c IN :personIds OR Person_Account__c IN :personIds
            WITH SYSTEM_MODE
            ORDER BY Status__c, CreatedDate DESC
            LIMIT 10000
        ];
    }

    /** The other sides with these ids, as the service compares and writes them. */
    public static List<Relationship__c> selectByIds(Set<Id> relationshipIds) {
        if (relationshipIds == null || relationshipIds.isEmpty()) {
            return new List<Relationship__c>();
        }
        return [
            SELECT
                Id,
                Contact__c,
                Person_Account__c,
                Related_Contact__c,
                Related_Person_Account__c,
                Type__c,
                Reciprocal_Type__c,
                Status__c,
                Start_Date__c,
                End_Date__c,
                Description__c,
                Reciprocal_Relationship__c,
                Is_Reciprocal_Managed__c,
                CreatedDate
            FROM Relationship__c
            WHERE Id IN :relationshipIds
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
    }
}
