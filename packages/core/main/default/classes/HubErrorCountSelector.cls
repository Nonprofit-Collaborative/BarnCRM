/**
 * Counts the errors the Hub tile shows.
 *
 * The Error Log belongs to another feature and may not be present in a given package
 * build, so the object and its status field are found by describe, in this package's
 * namespace first and then with none, and the count runs as a dynamic query in user mode.
 * When the object is absent, or the reader cannot see it or its status, the tile shows zero:
 * what somebody cannot see is told to them as nothing, never as a fault.
 *
 * The count stops at `cap() + 1`, so a flooded Error Log costs the home page at most that
 * many query rows; a result above `cap()` means "more than `cap()`".
 */
public with sharing class HubErrorCountSelector {
    private static final String ERROR_LOG = 'Error_Log__c';
    private static final String STATUS_FIELD = 'Status__c';
    private static final String STATUS_NEW = 'New';

    /** The tile counts this many and then says "more". A test lowers it. */
    @TestVisible
    private static Integer countCap = 999;

    /** Set by tests to see the org as having no Error Log. */
    @TestVisible
    private static Boolean absentForTest = false;

    /** The Error Log object, looked up once per transaction; null when it is absent. */
    private static Schema.SObjectType errorLogType;
    private static Boolean typeResolved = false;

    /** The most the tile counts exactly. */
    public static Integer cap() {
        return countCap;
    }

    /**
     * How many Error Log entries have the status New, up to `cap() + 1`, or zero when the
     * Error Log is absent or the running user cannot read it or its status.
     */
    public static Integer countNewErrors() {
        Schema.SObjectType errorLog = errorLogType();
        if (errorLog == null) {
            return 0;
        }
        Schema.DescribeSObjectResult describe = errorLog.getDescribe(
            SObjectDescribeOptions.DEFERRED
        );
        if (!describe.isAccessible()) {
            return 0;
        }
        Schema.SObjectField status = fieldOf(describe.fields.getMap(), STATUS_FIELD);
        if (status == null) {
            return 0;
        }
        Schema.DescribeFieldResult statusDescribe = status.getDescribe();
        if (!statusDescribe.isAccessible()) {
            return 0;
        }
        return Database.countQueryWithBinds(
            countQuery(describe.getName(), statusDescribe.getName()),
            new Map<String, Object>{ 'statusNew' => STATUS_NEW, 'readUpTo' => countCap + 1 },
            AccessLevel.USER_MODE
        );
    }

    /** The count, kept apart so a test can read what would be asked. */
    @TestVisible
    private static String countQuery(String objectName, String statusName) {
        return 'SELECT COUNT() FROM ' +
            String.escapeSingleQuotes(objectName) +
            ' WHERE ' +
            String.escapeSingleQuotes(statusName) +
            ' = :statusNew LIMIT :readUpTo';
    }

    private static Schema.SObjectType errorLogType() {
        if (absentForTest == true) {
            return null;
        }
        if (!typeResolved) {
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            errorLogType = globalDescribe.get(NamespaceUtil.qualify(ERROR_LOG));
            if (errorLogType == null) {
                errorLogType = globalDescribe.get(ERROR_LOG);
            }
            typeResolved = true;
        }
        return errorLogType;
    }

    private static Schema.SObjectField fieldOf(
        Map<String, Schema.SObjectField> fields,
        String fieldName
    ) {
        Schema.SObjectField field = fields.get(NamespaceUtil.qualify(fieldName).toLowerCase());
        return field != null ? field : fields.get(fieldName.toLowerCase());
    }
}
