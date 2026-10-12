/**
 * Every query against import batches, including the counts the results screen shows.
 *
 * The counts come from one aggregate query over the staged rows rather than from a running
 * total kept in memory, so a run that was resumed, retried, or partly processed still
 * reports what is actually on the rows (R-IB1).
 */
@NamespaceAccessible
public with sharing class ImportBatchSelector {
    private static final String FIELDS =
        'Id, Name, Import_Template__c, Import_Template__r.Name, ' +
        'File_Id__c, File_Name__c, Status__c, Is_Dry_Run__c, Row_Count__c, Rows_Created__c, ' +
        'Rows_Updated__c, Rows_Matched__c, Rows_Rejected__c, Run_Log__c, Started_At__c, ' +
        'Completed_At__c, Chunk_Size__c, Undo_Deadline__c, Committed_By__c, Expected_Count__c, ' +
        'Expected_Amount__c, File_Amount__c, Processor_Settings_JSON__c, Pass_Number__c, Job_Id__c, ' +
        'Operation__c';

    /** One batch, or null. */
    @NamespaceAccessible
    public static Import_Batch__c selectById(Id batchId) {
        if (batchId == null) {
            return null;
        }
        List<Import_Batch__c> found = Database.queryWithBinds(
            'SELECT ' + FIELDS + ' FROM Import_Batch__c WHERE Id = :batchId LIMIT 1',
            new Map<String, Object>{ 'batchId' => batchId },
            AccessLevel.USER_MODE
        );
        return found.isEmpty() ? null : found[0];
    }

    /**
     * The most recent imports, newest first, for the results screen's history list. Bulk
     * updates are listed on their own page (canonical model Section 29E); a batch from before
     * Operation existed has none, and SOQL's not-equal keeps it.
     */
    @NamespaceAccessible
    public static List<Import_Batch__c> selectRecent(Integer howMany) {
        Integer limitSize = howMany == null || howMany <= 0 ? 10 : Math.min(howMany, 200);
        return Database.queryWithBinds(
            'SELECT ' +
                FIELDS +
                ' FROM Import_Batch__c WHERE Operation__c != :bulkUpdate' +
                ' ORDER BY CreatedDate DESC LIMIT :limitSize',
            new Map<String, Object>{
                'limitSize' => limitSize,
                'bulkUpdate' => BulkUpdateService.OPERATION_UPDATE
            },
            AccessLevel.USER_MODE
        );
    }

    /**
     * How many staged rows a batch has in each status, from one grouped query. Runs in
     * system mode because it feeds the batch's own counters, which the package owns
     * (ADR-0021); the rows themselves are shown to the user through a user-mode read.
     */
    @NamespaceAccessible
    public static Map<String, Integer> countRowsByStatus(Id batchId) {
        Map<String, Integer> result = new Map<String, Integer>();
        if (batchId == null) {
            return result;
        }
        List<AggregateResult> grouped = Database.queryWithBinds(
            'SELECT Status__c status, COUNT(Id) total FROM Import_Row__c ' +
            'WHERE Import_Batch__c = :batchId GROUP BY Status__c',
            new Map<String, Object>{ 'batchId' => batchId },
            AccessLevel.SYSTEM_MODE
        );
        for (AggregateResult row : grouped) {
            String status = (String) row.get('status');
            if (status != null) {
                result.put(status, (Integer) row.get('total'));
            }
        }
        return result;
    }
}
