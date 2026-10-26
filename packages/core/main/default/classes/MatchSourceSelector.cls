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

    /**
     * The most rows one lookup reads. A lookup that reaches it reads a sample and never fails,
     * but matches past the cap are missed, so it is counted and logged (ADR-0133 decision 8).
     */
    @TestVisible
    private static Integer maxRows = 5000;

    /** How many lookups in this transaction reached `maxRows`. */
    @TestVisible
    private static Integer cappedLookups = 0;

    /** The sources already logged as capped in this transaction: one warning each. */
    private static Set<String> cappedLogged = new Set<String>();

    private static final String LOG_CONTEXT = 'Match sources';

    /**
     * A source's rows whose parent is one of these, with a value. The object and fields come
     * from MatchSourceService.usableSources, which resolved them through describe, never from a
     * caller; they are escaped regardless. User mode, so a row the user cannot see is not used.
     */
    public static List<SObject> rowsByParents(MatchSourceService.Source source, Set<Id> parentIds) {
        if (parentIds == null || parentIds.isEmpty()) {
            return new List<SObject>();
        }
        return capped(
            source.developerName,
            Database.queryWithBinds(
                selectFrom(source) +
                    ' WHERE ' +
                    String.escapeSingleQuotes(source.parentField) +
                    ' IN :parentIds AND ' +
                    String.escapeSingleQuotes(source.valueField) +
                    ' != null LIMIT ' +
                    maxRows,
                new Map<String, Object>{ 'parentIds' => parentIds },
                AccessLevel.USER_MODE
            )
        );
    }

    /**
     * A source's rows that may hold one of these values: equal to one of `equalTo` in the value
     * field (emails, compared without regard to capitals by SOQL), or matching one of
     * `likeClauses`, each a map of field to LIKE pattern that must all match (phones by the
     * value field; addresses by the postal code and a word of the street), since separators
     * vary. The caller sends at most 100 clauses at a time, normalizes each row and keeps only
     * exact matches.
     */
    public static List<SObject> rowsByValues(
        MatchSourceService.Source source,
        Set<String> equalTo,
        List<Map<String, String>> likeClauses
    ) {
        Map<String, Object> binds = new Map<String, Object>();
        String filter;
        if (equalTo != null && !equalTo.isEmpty()) {
            binds.put('equalTo', equalTo);
            filter = String.escapeSingleQuotes(source.valueField) + ' IN :equalTo';
        } else if (likeClauses != null && !likeClauses.isEmpty()) {
            // One bind per pattern: a list bound to LIKE is not relied on in dynamic SOQL.
            List<String> clauses = new List<String>();
            for (Integer index = 0; index < likeClauses.size(); index++) {
                List<String> parts = new List<String>();
                Integer part = 0;
                for (String field : likeClauses[index].keySet()) {
                    String name = 'p' + index + '_' + part++;
                    binds.put(name, likeClauses[index].get(field));
                    parts.add(String.escapeSingleQuotes(field) + ' LIKE :' + name);
                }
                clauses.add('(' + String.join(parts, ' AND ') + ')');
            }
            filter = '(' + String.join(clauses, ' OR ') + ')';
        } else {
            return new List<SObject>();
        }
        return capped(
            source.developerName,
            Database.queryWithBinds(
                selectFrom(source) +
                    ' WHERE ' +
                    filter +
                    ' AND ' +
                    String.escapeSingleQuotes(source.parentField) +
                    ' != null LIMIT ' +
                    maxRows,
                binds,
                AccessLevel.USER_MODE
            )
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
     * Records of the target object (Contact, or Account for person accounts) and the Individual
     * each carries, by record or by Individual. The field (`IndividualId` or
     * `PersonIndividualId`) is read by name, and only by a caller that found it in the target's
     * describe, so Core runs in an org without it.
     */
    public static List<SObject> holdersOfIndividuals(
        Schema.SObjectType target,
        String individualField,
        Set<Id> recordIds,
        Set<Id> individualIds
    ) {
        String field = String.escapeSingleQuotes(individualField);
        String filter = recordIds != null ? 'Id IN :ids' : field + ' IN :ids';
        Set<Id> ids = recordIds != null ? recordIds : individualIds;
        if (ids == null || ids.isEmpty()) {
            return new List<SObject>();
        }
        return capped(
            individualField,
            Database.queryWithBinds(
                'SELECT Id, ' +
                    field +
                    ' FROM ' +
                    target.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
                    ' WHERE ' +
                    filter +
                    ' AND ' +
                    field +
                    ' != null LIMIT ' +
                    maxRows,
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.USER_MODE
            )
        );
    }

    /** The rows, counted and logged once per name when the lookup reached its cap. */
    private static List<SObject> capped(String name, List<SObject> rows) {
        if (rows.size() >= maxRows) {
            cappedLookups++;
            if (cappedLogged.add(name)) {
                ErrorLogger.logMessage(
                    String.format(
                        System.Label.Core_MatchSource_RowCapReached,
                        new List<Object>{ name, String.valueOf(maxRows) }
                    ),
                    LOG_CONTEXT,
                    ErrorLogger.SEVERITY_WARNING
                );
            }
        }
        return rows;
    }
}
