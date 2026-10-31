/**
 * The nightly Import row cleanup (R-IR5): deletes the staged rows of every complete import
 * (Complete, Failed, Undone, Undo failed) by the org's Delete Import Rows setting: once
 * complete, after 30 days (the default), after 90 days, or never. A preview never committed
 * keeps its rows at least 30 days, so a file is never taken between its preview and its commit,
 * and a batch in any other status keeps them. The batch keeps its counts and run log, and undo
 * never reads the rows (R-IR8).
 *
 * The rows are the package's own staging, and the job runs as whoever scheduled it, so they
 * are read and deleted in system mode and without sharing: a cleanup that skipped the rows of
 * imports its scheduler cannot see or delete would leave them for ever (ADR-0021). It deletes
 * nothing but `Import_Row__c` records past the retention the org chose.
 */
public without sharing class ImportRowPurgeBatch implements Database.Batchable<SObject> {
    /** Rows deleted per chunk: one delete of bookkeeping rows nothing fires on. */
    public static final Integer CHUNK_SIZE = 2000;

    /** The fewest days an uncommitted preview keeps its rows, whatever the setting. */
    public static final Integer PREVIEW_DAYS = 30;

    /** The statuses of a batch whose last commit finished (R-IR5). */
    public static final List<String> COMPLETE_STATUSES = new List<String>{
        ImportBatchService.STATUS_COMPLETE,
        ImportBatchService.STATUS_FAILED,
        ImportBatchService.STATUS_UNDONE,
        ImportBatchService.STATUS_UNDO_FAILED
    };

    private static final String LOG_CONTEXT = 'ImportRowPurgeBatch';

    /** Rows of complete imports completed before this are deleted; null deletes nothing. */
    @TestVisible
    private Datetime cutoff;
    /** Rows of uncommitted previews completed before this are deleted. */
    @TestVisible
    private Datetime previewCutoff;

    public ImportRowPurgeBatch() {
        Integer days = ImportBatchService.rowRetentionDays();
        if (days != null) {
            cutoff = Datetime.now().addDays(-days);
            previewCutoff = Datetime.now().addDays(-Math.max(days, PREVIEW_DAYS));
        }
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        String soql = cutoff == null
            ? 'SELECT Id FROM Import_Row__c WHERE Id = null'
            : 'SELECT Id FROM Import_Row__c WHERE ' +
                  '(Import_Batch__r.Status__c IN :complete AND Import_Batch__r.Completed_At__c <= :cutoff)' +
                  ' OR (Import_Batch__r.Status__c = :preview AND Import_Batch__r.Completed_At__c < :previewCutoff)';
        return Database.getQueryLocatorWithBinds(
            soql,
            new Map<String, Object>{
                'cutoff' => cutoff,
                'previewCutoff' => previewCutoff,
                'complete' => COMPLETE_STATUSES,
                'preview' => ImportBatchService.STATUS_DRY_RUN_COMPLETE
            },
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
