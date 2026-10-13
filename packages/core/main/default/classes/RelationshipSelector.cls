/**
 * All SOQL against Relationship__c and against the shipped relationship type mapping.
 * Feature code never queries either directly (plan Section 7.2: every query lives in a
 * Selector).
 *
 * Every query here reads a relationship from the side it is described from: the person on
 * Contact__c or Person_Account__c. The other side is its own record, so a person's card is
 * one query with no OR across four columns.
 */
public with sharing class RelationshipSelector {
    /**
     * Custom metadata cannot be inserted by a test, so tests put in-memory rows here and
     * every read in the package sees them.
     */
    @TestVisible
    private static List<Relationship_Type__mdt> typeMappingOverride;

    /**
     * Every relationship described from one of these people, newest first. This is what the
     * relationship card on a person's record shows, and it is also the pool the reciprocal
     * service searches when it looks for a record that is already the other side.
     */
    public static List<Relationship__c> selectByFromPersonIds(Set<Id> personIds) {
        if (personIds == null || personIds.isEmpty()) {
            return new List<Relationship__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Contact__c,
                Contact__r.Name,
                Person_Account__c,
                Person_Account__r.Name,
                Related_Contact__c,
                Related_Contact__r.Name,
                Related_Person_Account__c,
                Related_Person_Account__r.Name,
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
            WITH USER_MODE
            ORDER BY Status__c, CreatedDate DESC
            LIMIT 10000
        ];
    }

    /** The given relationships, with every field the service and the card read. */
    public static List<Relationship__c> selectByIds(Set<Id> relationshipIds) {
        if (relationshipIds == null || relationshipIds.isEmpty()) {
            return new List<Relationship__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Contact__c,
                Contact__r.Name,
                Person_Account__c,
                Person_Account__r.Name,
                Related_Contact__c,
                Related_Contact__r.Name,
                Related_Person_Account__c,
                Related_Person_Account__r.Name,
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
            WITH USER_MODE
            LIMIT 10000
        ];
    }

    /**
     * The shipped mapping from a type to its reciprocal. Read as shipped rather than in user
     * mode: it is package metadata, read only to administrators, and it holds no organization
     * data (the same reasoning as AutomationRegistrySelector).
     */
    public static List<Relationship_Type__mdt> selectTypeMappings() {
        if (typeMappingOverride != null) {
            return typeMappingOverride;
        }
        return [
            SELECT
                DeveloperName,
                MasterLabel,
                Type__c,
                Reciprocal_Type__c,
                Is_Gendered__c,
                Active__c
            FROM Relationship_Type__mdt
            WHERE Active__c = TRUE
            WITH SYSTEM_MODE
            ORDER BY DeveloperName
            LIMIT 1000
        ];
    }
}
