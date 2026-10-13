/**
 * The nightly Import row cleanup (R-IR5, D-40): deletes the staged rows of every import whose
 * last pass completed more than the org's `Import_Row_Retention_Days__c` ago, so a large
 * import does not sit in storage for ever. The batch record keeps its counts and run log, and
 * undo never reads the rows (R-IB9). A retention of 0 keeps every row.
 *
 * The rows are the package's own staging, and the job runs as whoever scheduled it, so they
 * are read and deleted in system mode and without sharing: a cleanup that skipped the rows of
 * imports its scheduler cannot see or delete would leave them for ever (ADR-0021). It deletes
 * nothing but `Import_Row__c` records past the retention the org chose.
 */
public without sharing class ImportRowPurgeBatch implements Database.Batchable<SObject> {
    /** Rows deleted per chunk: one delete of bookkeeping rows nothing fires on. */
    public static final Integer CHUNK_SIZE = 2000;

    private static final String LOG_CONTEXT = 'ImportRowPurgeBatch';

    /** Rows of imports completed before this are deleted; null deletes nothing. */
    @TestVisible
    private Datetime cutoff;

    public ImportRowPurgeBatch() {
        Integer days = ImportBatchService.rowRetentionDays();
        cutoff = days == 0 ? null : Datetime.now().addDays(-days);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        String soql = cutoff == null
            ? 'SELECT Id FROM Import_Row__c WHERE Id = null'
            : 'SELECT Id FROM Import_Row__c WHERE Import_Batch__r.Completed_At__c < :cutoff';
        return Database.getQueryLocatorWithBinds(
            soql,
            new Map<String, Object>{ 'cutoff' => cutoff },
            AccessLevel.SYSTEM_MODE
        );
    }

    public void execute(Database.BatchableContext context, List<Import_Row__c> rows) {
        List<String> failures = new List<String>();
        for (Database.DeleteResult result : Database.delete(rows, false, AccessLevel.SYSTEM_MODE)) {
            if (!result.isSuccess() && !result.getErrors().isEmpty()) {
                failures.add(result.getId() + ': ' + result.getErrors()[0].getMessage());
            }
        }
        if (!failures.isEmpty()) {
            // One entry per chunk, so a run that cannot delete does not flood the Error Log.
            ErrorLogger.logMessage(
                String.format(
                    Label.Core_Import_LogRowsNotRemoved,
                    new List<String>{ String.valueOf(failures.size()), failures[0] }
                ),
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_WARNING
            );
        }
    }

    public void finish(Database.BatchableContext context) {
        // Nothing to close: the rows are gone or logged, and the batches keep their counts.
        return;
    }
}
