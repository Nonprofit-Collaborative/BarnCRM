/**
 * Every query related-record matching makes (plan Section 7.2: every query lives in a
 * Selector). ADR-NEXT, `NEXT-related-record-matching.md`.
 */
public with sharing class MatchSourceSelector {
    @TestVisible
    private static List<Match_Source__mdt> sourcesOverride;

    /**
     * The active match sources. Read as shipped rather than in user mode: package metadata
     * that holds no organization data (the same reasoning as RelationshipSelector).
     */
    public static List<Match_Source__mdt> selectActiveSources() {
        if (sourcesOverride != null) {
            return sourcesOverride;
        }
        return [
            SELECT
                DeveloperName,
                MasterLabel,
                Object_Name__c,
                Value_Field__c,
                Postal_Code_Field__c,
                Parent_Field__c,
                Normalization__c
            FROM Match_Source__mdt
            WHERE Active__c = TRUE
            WITH SYSTEM_MODE
            ORDER BY DeveloperName
            LIMIT 200
        ];
    }
}
