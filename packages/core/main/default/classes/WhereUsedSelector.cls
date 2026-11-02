/**
 * Every query Where Used (C-59) makes over Core's setup records (plan Section 7.2).
 *
 * Without sharing on purpose: retiring a field safely needs every saved query, including the
 * private ones other people own, so the reads ignore sharing and field security. Only
 * `WhereUsedController` calls this, after checking Manage BarnCRM Settings, and
 * `WhereUsedService` hides the name of a private query someone else owns
 * (ADR-0159, `0159-where-used-extension.md`). Nothing here writes.
 */
public without sharing class WhereUsedSelector {
    /** The most records of one kind read in one request. */
    public static final Integer ROW_LIMIT = 2000;

    @TestVisible
    private static List<Merge_Rule__mdt> mergeRulesOverride;

    /** Every saved Find query, which Giving also lists as donor segments. */
    public static List<Saved_Query__c> savedQueries() {
        return [
            SELECT Id, Name, Object_Name__c, Query_JSON__c, Shared__c, OwnerId, Owner.Name
            FROM Saved_Query__c
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT :ROW_LIMIT
        ];
    }

    /** Every saved Super Transform step list. */
    public static List<Saved_Transform__c> savedTransforms() {
        return [
            SELECT Id, Name, Object_Name__c, Definition_JSON__c
            FROM Saved_Transform__c
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT :ROW_LIMIT
        ];
    }

    /** Every import mapping (template), shipped or made in the org. */
    public static List<Import_Template__c> importTemplates() {
        return [
            SELECT
                Id,
                Name,
                Target_Object__c,
                Related_Object__c,
                Related_Parent_Field__c,
                Load_Match_Field__c,
                Person_Match_Field__c,
                Organization_Match_Field__c,
                Column_Mapping_JSON__c,
                Default_Values_JSON__c
            FROM Import_Template__c
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT :ROW_LIMIT
        ];
    }

    /** Every merge rule, active or not. */
    public static List<Merge_Rule__mdt> mergeRules() {
        return mergeRulesOverride != null ? mergeRulesOverride : Merge_Rule__mdt.getAll().values();
    }
}
