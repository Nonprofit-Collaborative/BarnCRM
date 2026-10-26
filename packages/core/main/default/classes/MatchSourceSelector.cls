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

    /** Every match source, active or not, for Matching Logic (tests set it). */
    @TestVisible
    private static List<Match_Source__mdt> allSourcesOverride;

    /**
     * Every match source, active or not, for the Matching Logic list (ADR-NEXT). Read as
     * shipped, as `selectActiveSources` is.
     */
    public static List<Match_Source__mdt> selectAllSources() {
        if (allSourcesOverride != null) {
            return allSourcesOverride;
        }
        return [
            SELECT
                DeveloperName,
                MasterLabel,
                Object_Name__c,
                Value_Field__c,
                Postal_Code_Field__c,
                Parent_Field__c,
                Normalization__c,
                Active__c,
                Is_Shipped__c
            FROM Match_Source__mdt
            WITH SYSTEM_MODE
            ORDER BY MasterLabel
            LIMIT 200
        ];
    }

    /**
     * The names of these people or households, for "Try a value", in user mode so a record
     * the person cannot see is not named. At most `max`.
     */
    public static List<SObject> namesOf(Schema.SObjectType target, Set<Id> ids, Integer max) {
        if (ids == null || ids.isEmpty()) {
            return new List<SObject>();
        }
        return Database.queryWithBinds(
            'SELECT Id, Name FROM ' +
                target.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
                ' WHERE Id IN :ids ORDER BY Name LIMIT :max',
            new Map<String, Object>{ 'ids' => ids, 'max' => max },
            AccessLevel.USER_MODE
        );
    }

    /**
     * The most rows one lookup reads. A lookup that reaches it reads a sample and never fails,
     * but matches past the cap are missed, so it is counted and logged (ADR-0133 decision 8).
     */
    @TestVisible
    private static Integer maxRows = 5000;

    /**
     * Queries and rows every lookup leaves for the rest of the transaction (the scan's chunk
     * or the import's chunk still has its own work to do). A lookup reads at most what is left
     * above these, and with nothing left it is skipped, never failed: a limit exception
     * cannot be caught.
     */
    @TestVisible
    private static Integer queryReserve = 20;
    @TestVisible
    private static Integer rowReserve = 5000;

    /** How many lookups in this transaction reached their cap or were skipped. */
    @TestVisible
    private static Integer cappedLookups = 0;

    /** The sources already logged as capped in this transaction: one warning each. */
    private static Set<String> cappedLogged = new Set<String>();

    private static final String LOG_CONTEXT = 'Match sources';

    /**
     * How many lookups so far in this transaction read less than all their matches. A caller
     * compares it before and after a lookup: a value counted from a cut lookup may be held by
     * more records than it read (ADR-0133 decision 8).
     */
    public static Integer cutLookups() {
        return cappedLookups;
    }

    /**
     * Runs one lookup with a LIMIT of `maxRows`, or of what the transaction has left above
     * the reserves when that is less, and skips it (no rows, counted, logged once) when
     * nothing is left.
     */
    private static List<SObject> lookup(String name, String query, Map<String, Object> binds) {
        Integer rowsLeft = Limits.getLimitQueryRows() - Limits.getQueryRows() - rowReserve;
        Integer queriesLeft = Limits.getLimitQueries() - Limits.getQueries() - queryReserve;
        Integer cap = Math.min(maxRows, rowsLeft);
        if (cap <= 0 || queriesLeft <= 0) {
            cappedLookups++;
            warnOnce(name, System.Label.Core_MatchSource_BudgetSpent, new List<Object>{ name });
            return new List<SObject>();
        }
        List<SObject> rows = Database.queryWithBinds(
            query + ' LIMIT ' + cap,
            binds,
            AccessLevel.USER_MODE
        );
        if (rows.size() >= cap) {
            cappedLookups++;
            warnOnce(
                name,
                System.Label.Core_MatchSource_RowCapReached,
                new List<Object>{ name, String.valueOf(cap) }
            );
        }
        return rows;
    }

    private static void warnOnce(String name, String format, List<Object> values) {
        if (cappedLogged.add(name)) {
            ErrorLogger.logMessage(
                String.format(format, values),
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_WARNING
            );
        }
    }

    /**
     * A source's rows whose parent is one of these, with a value. The object and fields come
     * from MatchSourceService.usableSources, which resolved them through describe, never from a
     * caller; they are escaped regardless. User mode, so a row the user cannot see is not used.
     */
    public static List<SObject> rowsByParents(MatchSourceService.Source source, Set<Id> parentIds) {
        if (parentIds == null || parentIds.isEmpty()) {
            return new List<SObject>();
        }
        return lookup(
            source.developerName,
            selectFrom(source) +
                ' WHERE ' +
                String.escapeSingleQuotes(source.parentField) +
                ' IN :parentIds AND ' +
                String.escapeSingleQuotes(source.valueField) +
                ' != null',
            new Map<String, Object>{ 'parentIds' => parentIds }
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
        return lookup(
            source.developerName,
            selectFrom(source) +
                ' WHERE ' +
                filter +
                ' AND ' +
                String.escapeSingleQuotes(source.parentField) +
                ' != null',
            binds
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
        return lookup(
            individualField,
            'SELECT Id, ' +
                field +
                ' FROM ' +
                target.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
                ' WHERE ' +
                filter +
                ' AND ' +
                field +
                ' != null',
            new Map<String, Object>{ 'ids' => ids }
        );
    }
}
