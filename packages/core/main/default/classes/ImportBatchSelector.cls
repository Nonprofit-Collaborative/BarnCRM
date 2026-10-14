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
        'File_Values_JSON__c, Match_Only__c, Operation__c, Trial_Rows__c, Retry_After_Row__c';

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

    /** These batches, those the running user can see, in one query. */
    @NamespaceAccessible
    public static List<Import_Batch__c> selectByIds(Set<Id> batchIds) {
        if (batchIds == null || batchIds.isEmpty()) {
            return new List<Import_Batch__c>();
        }
        return Database.queryWithBinds(
            'SELECT ' + FIELDS + ' FROM Import_Batch__c WHERE Id IN :batchIds LIMIT 2000',
            new Map<String, Object>{ 'batchIds' => batchIds },
            AccessLevel.USER_MODE
        );
    }

    /**
     * The most recent imports, newest first, for the results screen's history list. Bulk
     * updates and bulk deletes are listed on their own page (canonical model Section 29E); a
     * batch from before Operation existed has none, and is kept by the explicit null test.
     */
    @NamespaceAccessible
    public static List<Import_Batch__c> selectRecent(Integer howMany) {
        Integer limitSize = howMany == null || howMany <= 0 ? 10 : Math.min(howMany, 200);
        return Database.queryWithBinds(
            'SELECT ' +
                FIELDS +
                ' FROM Import_Batch__c WHERE (Operation__c = NULL OR Operation__c NOT IN :notImports)' +
                ' ORDER BY CreatedDate DESC LIMIT :limitSize',
            new Map<String, Object>{
                'limitSize' => limitSize,
                'notImports' => new List<String>{
                    BulkUpdateService.OPERATION_UPDATE,
                    BulkDeleteService.OPERATION_DELETE
                }
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
        return countRowsBy(batchId, 'Status__c', null);
    }

    /** As above, counting only the rows the given pass processed when one is given (R-IB16). */
    @NamespaceAccessible
    public static Map<String, Integer> countRowsByStatus(Id batchId, Decimal pass) {
        return countRowsBy(batchId, 'Status__c', pass);
    }

    /** The same for what the rows' related records did (R-IT17), for the run log. */
    @NamespaceAccessible
    public static Map<String, Integer> countRelatedByStatus(Id batchId) {
        return countRowsBy(batchId, 'Related_Status__c', null);
    }

    /** The field is one of the two above, never a caller's text. */
    private static Map<String, Integer> countRowsBy(Id batchId, String field, Decimal pass) {
        Map<String, Integer> result = new Map<String, Integer>();
        if (batchId == null) {
            return result;
        }
        List<AggregateResult> grouped = Database.queryWithBinds(
            'SELECT ' +
                field +
                ' status, COUNT(Id) total FROM Import_Row__c ' +
                'WHERE Import_Batch__c = :batchId' +
                (pass == null ? '' : ' AND Pass_Number__c = :pass') +
                ' GROUP BY ' +
                field,
            new Map<String, Object>{ 'batchId' => batchId, 'pass' => pass },
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

    /**
     * The row number of the batch's nth row in file order (n from 1), or null when it has
     * fewer; the last row of a trial of n rows (R-IB16). Rows skipped at staging (R-IT18) are
     * not counted, as the trial does not process them. OFFSET reaches 2,000, the trial's
     * ceiling. System mode, as the processor reads the rows (ADR-0021).
     */
    @NamespaceAccessible
    public static Decimal selectRowNumberAt(Id batchId, Integer n) {
        if (batchId == null || n == null || n < 1) {
            return null;
        }
        List<Import_Row__c> rows = Database.queryWithBinds(
            'SELECT Row_Number__c FROM Import_Row__c WHERE Import_Batch__c = :batchId' +
            ' AND Status__c != :skipped ORDER BY Row_Number__c ASC LIMIT 1 OFFSET :skip',
            new Map<String, Object>{
                'batchId' => batchId,
                'skipped' => ImportRowProcessor.STATUS_SKIPPED,
                'skip' => n - 1
            },
            AccessLevel.SYSTEM_MODE
        );
        return rows.isEmpty() ? null : rows[0].Row_Number__c;
    }

    /**
     * The template a batch's last dry run started with (R-IB1), or null. Read on its own, not
     * with the batch, because it can be long and the history list never needs it. System mode
     * because the package writes and reads it as its own bookkeeping (ADR-0021).
     */
    @NamespaceAccessible
    public static String selectTemplateSnapshot(Id batchId) {
        if (batchId == null) {
            return null;
        }
        List<Import_Batch__c> found = Database.queryWithBinds(
            'SELECT Template_Snapshot_JSON__c FROM Import_Batch__c WHERE Id = :batchId LIMIT 1',
            new Map<String, Object>{ 'batchId' => batchId },
            AccessLevel.SYSTEM_MODE
        );
        return found.isEmpty() ? null : found[0].Template_Snapshot_JSON__c;
    }

    /**
     * How many of a batch's rows numbered after this one are in each status: a retry's own rows
     * (R-IB17). System mode for the reason `countRowsByStatus` gives.
     */
    @NamespaceAccessible
    public static Map<String, Integer> countRowsByStatusAfter(Id batchId, Decimal afterRow) {
        Map<String, Integer> result = new Map<String, Integer>();
        List<AggregateResult> grouped = Database.queryWithBinds(
            'SELECT Status__c status, COUNT(Id) total FROM Import_Row__c ' +
            'WHERE Import_Batch__c = :batchId AND Row_Number__c > :afterRow GROUP BY Status__c',
            new Map<String, Object>{ 'batchId' => batchId, 'afterRow' => afterRow },
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

    /** The highest row number a batch has, or 0 when it has none (R-IB17). */
    @NamespaceAccessible
    public static Decimal selectLastRowNumber(Id batchId) {
        List<Import_Row__c> found = [
            SELECT Row_Number__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batchId AND Row_Number__c != NULL
            WITH SYSTEM_MODE
            ORDER BY Row_Number__c DESC
            LIMIT 1
        ];
        return found.isEmpty() ? 0 : found[0].Row_Number__c;
    }
}
