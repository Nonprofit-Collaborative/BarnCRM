/**
 * Every query the custom metadata manager makes: the rows of an editable type, and the outcome
 * of a deployment it started (plan Section 7.2: every query lives in a Selector).
 *
 * All of them run in system mode. The rows are package metadata that holds no organization
 * data (the same reasoning as RelationshipSelector), and the outcome queries return only
 * whether a deployment finished, to a caller the controller has already checked holds
 * Manage BarnCRM Metadata.
 */
public with sharing class CustomMetadataManagerSelector {
    /**
     * One stored row, as plain values. A test cannot insert custom metadata, and cannot set
     * DeveloperName on an in-memory row, so tests put these here instead.
     */
    public class StoredRow {
        public String developerName;
        public String label;
        public Map<String, Object> values = new Map<String, Object>();
    }

    @TestVisible
    private static Map<String, List<StoredRow>> rowsOverride;

    /** Every row of the type, shipped and the organization's own, by label. */
    public static List<StoredRow> selectRows(Schema.SObjectType type, List<String> fieldNames) {
        String typeName = type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        if (rowsOverride != null) {
            List<StoredRow> rows = rowsOverride.get(typeName);
            return rows == null ? new List<StoredRow>() : rows;
        }
        List<String> columns = new List<String>{ 'DeveloperName', 'MasterLabel' };
        columns.addAll(fieldNames);
        // The type and its field names come from the service's own registry, never from the
        // caller, so nothing user supplied reaches this query; they are escaped regardless.
        String soql = String.escapeSingleQuotes(
            'SELECT ' +
                String.join(columns, ', ') +
                ' FROM ' +
                typeName +
                ' ORDER BY MasterLabel LIMIT 2000'
        );
        List<StoredRow> rows = new List<StoredRow>();
        for (
            SObject record : Database.queryWithBinds(
                soql,
                new Map<String, Object>(),
                AccessLevel.SYSTEM_MODE
            )
        ) {
            StoredRow row = new StoredRow();
            row.developerName = (String) record.get('DeveloperName');
            row.label = (String) record.get('MasterLabel');
            for (String fieldName : fieldNames) {
                row.values.put(fieldName, record.get(fieldName));
            }
            rows.add(row);
        }
        return rows;
    }

    /** The audit row a successful deployment wrote, if it has been written. */
    public static Boolean hasSucceeded(Id deploymentId) {
        return [
                SELECT COUNT()
                FROM Setting_Change__c
                WHERE Deployment_Id__c = :deploymentId
                WITH SYSTEM_MODE
                LIMIT 1
            ] > 0;
    }

    /** The message a failed deployment logged, or null while there is none. */
    public static String failureMessage(Id deploymentId) {
        List<Error_Log__c> entries = [
            SELECT Message__c
            FROM Error_Log__c
            WHERE Record_Reference__c = :deploymentId
            WITH SYSTEM_MODE
            ORDER BY Timestamp__c DESC
            LIMIT 1
        ];
        return entries.isEmpty() ? null : entries[0].Message__c;
    }
}
