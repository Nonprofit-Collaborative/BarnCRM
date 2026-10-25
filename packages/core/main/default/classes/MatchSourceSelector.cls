/**
 * Every query related-record matching makes (plan Section 7.2: every query lives in a
 * Selector). ADR-0133, `0133-related-record-matching.md`.
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

    /** The most rows one lookup reads; a lookup that reaches it reads a sample, never fails. */
    @TestVisible
    private static final Integer MAX_ROWS = 5000;

    /**
     * A source's rows whose parent is one of these, with a value. The object and fields come
     * from MatchSourceService.usableSources, which resolved them through describe, never from a
     * caller; they are escaped regardless. User mode, so a row the user cannot see is not used.
     */
    public static List<SObject> rowsByParents(MatchSourceService.Source source, Set<Id> parentIds) {
        if (parentIds == null || parentIds.isEmpty()) {
            return new List<SObject>();
        }
        return Database.queryWithBinds(
            selectFrom(source) +
                ' WHERE ' +
                String.escapeSingleQuotes(source.parentField) +
                ' IN :parentIds AND ' +
                String.escapeSingleQuotes(source.valueField) +
                ' != null LIMIT ' +
                MAX_ROWS,
            new Map<String, Object>{ 'parentIds' => parentIds },
            AccessLevel.USER_MODE
        );
    }

    /**
     * A source's rows that may hold one of these values: equal to one of `equalTo` in the value
     * field (emails, compared without regard to capitals by SOQL), or like one of `likePatterns`
     * in `likeField` (phones and postal codes, whose separators vary). The caller normalizes
     * each row and keeps only exact matches.
     */
    public static List<SObject> rowsByValues(
        MatchSourceService.Source source,
        Set<String> equalTo,
        String likeField,
        List<String> likePatterns
    ) {
        Map<String, Object> binds = new Map<String, Object>();
        String filter;
        if (equalTo != null && !equalTo.isEmpty()) {
            binds.put('equalTo', equalTo);
            filter = String.escapeSingleQuotes(source.valueField) + ' IN :equalTo';
        } else if (likePatterns != null && !likePatterns.isEmpty()) {
            // One bind per pattern: a list bound to LIKE is not relied on in dynamic SOQL.
            List<String> clauses = new List<String>();
            for (Integer index = 0; index < likePatterns.size(); index++) {
                binds.put('p' + index, likePatterns[index]);
                clauses.add(String.escapeSingleQuotes(likeField) + ' LIKE :p' + index);
            }
            filter = '(' + String.join(clauses, ' OR ') + ')';
        } else {
            return new List<SObject>();
        }
        return Database.queryWithBinds(
            selectFrom(source) +
                ' WHERE ' +
                filter +
                ' AND ' +
                String.escapeSingleQuotes(source.parentField) +
                ' != null LIMIT ' +
                MAX_ROWS,
            binds,
            AccessLevel.USER_MODE
        );
    }

    private static String selectFrom(MatchSourceService.Source source) {
        List<String> columns = new List<String>{ source.parentField, source.valueField };
        if (source.postalField != null) {
            columns.add(source.postalField);
        }
        return 'SELECT ' +
            String.escapeSingleQuotes(String.join(columns, ', ')) +
            ' FROM ' +
            String.escapeSingleQuotes(source.objectName);
    }

    /**
     * Contacts and the Individual each carries, by contact or by Individual. `IndividualId` is
     * read by name, and only by a caller that found it in Contact's describe, so Core runs in an
     * org without it.
     */
    public static List<Contact> contactsWithIndividuals(Set<Id> contactIds, Set<Id> individualIds) {
        String filter = contactIds != null ? 'Id IN :ids' : 'IndividualId IN :ids';
        Set<Id> ids = contactIds != null ? contactIds : individualIds;
        if (ids == null || ids.isEmpty()) {
            return new List<Contact>();
        }
        return Database.queryWithBinds(
            'SELECT Id, IndividualId FROM Contact WHERE ' +
                filter +
                ' AND IndividualId != null LIMIT ' +
                MAX_ROWS,
            new Map<String, Object>{ 'ids' => ids },
            AccessLevel.USER_MODE
        );
    }
}
