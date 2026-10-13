/**
 * Every query against the Error Log object (plan Section 9.3).
 *
 * Reads run in user mode: the Hub tile and the Error Log tab must show a person only what their
 * access allows. Writing is the other way round and lives in `ErrorLogWriter`, which explains
 * why.
 */
public with sharing class ErrorLogSelector {
    private static final Integer DEFAULT_ROWS = 5;
    private static final Integer MAX_ROWS = 200;

    // Counting new entries is ErrorLogCountSelector.countNewUpTo, the one capped count.

    public static List<Error_Log__c> selectRecent(Integer rowCount) {
        Integer rows = rowCount == null ||
            rowCount <= 0
            ? DEFAULT_ROWS
            : Math.min(rowCount, MAX_ROWS);
        return [
            SELECT
                Id,
                Name,
                Timestamp__c,
                Context__c,
                Message__c,
                Severity__c,
                Status__c,
                Object_Name__c,
                Record_Reference__c
            FROM Error_Log__c
            WITH USER_MODE
            ORDER BY Timestamp__c DESC NULLS LAST, Name DESC
            LIMIT :rows
        ];
    }

    public static List<Error_Log__c> selectByIds(Set<Id> errorLogIds) {
        if (errorLogIds == null || errorLogIds.isEmpty()) {
            return new List<Error_Log__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Timestamp__c,
                Context__c,
                Message__c,
                Severity__c,
                Status__c,
                Object_Name__c,
                Record_Reference__c
            FROM Error_Log__c
            WHERE Id IN :errorLogIds
            WITH USER_MODE
            LIMIT 200
        ];
    }
}
