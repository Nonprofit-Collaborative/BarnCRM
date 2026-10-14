/**
 * The work of one bulk delete (C-37, canonical model R-BD3), run as the person who started it.
 *
 * - **Only what was confirmed.** The query reads at most the confirmed number of records, in Id
 *   order, in user mode. A delete by file (R-BD7) reads at most that many of its dry run's
 *   Matched rows instead, and each chunk reads the records they name again as the person.
 * - **Only records that still match.** Each chunk reads its records again with the query's
 *   filter, so a record changed since the job started so that it no longer matches is left
 *   alone and counted.
 * - **The person's own access.** The definition is checked again as the person when the job
 *   starts and in every chunk, and every delete is `Database.delete(records, false, USER_MODE)`.
 * - **Journaled.** Each chunk writes one commit page (R-IJ1): a Deleted entry per record
 *   deleted, with its name, and a Failed entry per record the platform refused. The undo
 *   (`BulkDeleteUndoBatch`) brings Deleted records back from the Recycle Bin.
 *
 * The job record and the journal are the package's own bookkeeping, written in system mode
 * (ADR-0021).
 */
public with sharing class BulkDeleteBatch implements Database.Batchable<SObject>, Database.Stateful {
    private final Id jobId;
    /** Read in start; a test replaces it to stand for access taken away part way. */
    @TestVisible
    private String definition;
    private Integer deletedRecords = 0;
    private Integer noLongerMatching = 0;
    private Integer failedRecords = 0;
    private Boolean failed = false;
    private Boolean journalIncomplete = false;
    private String stoppedBecause;

    /**
     * Set only by tests: the error count a job reports when the platform stopped a chunk, which
     * a test cannot bring about for real.
     */
    @TestVisible
    private static Integer jobErrorsForTest;

    public BulkDeleteBatch(Id jobId) {
        this.jobId = jobId;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        definition = DataJobs.definitionOf(jobId);
        try {
            BulkDeleteService.Plan checked = BulkDeleteService.planFromDefinition(definition);
            if (checked.fromFile) {
                // A delete by file (R-BD7): the dry run's Matched rows, the package's own
                // bookkeeping, read in system mode; each chunk reads their records as the person.
                return Database.getQueryLocatorWithBinds(
                    'SELECT Gift_Id__c FROM Import_Row__c WHERE Import_Batch__c = :owner' +
                        ' AND Status__c = :matched AND Gift_Id__c != NULL' +
                        ' ORDER BY Row_Number__c LIMIT :confirmed',
                    new Map<String, Object>{
                        'owner' => jobId,
                        'matched' => ImportRowProcessor.STATUS_MATCHED,
                        'confirmed' => DataJobs.confirmedCountOf(definition)
                    },
                    AccessLevel.SYSTEM_MODE
                );
            }
            return DataJobs.locatorFor(checked.queryJson, DataJobs.confirmedCountOf(definition));
        } catch (Exception e) {
            failed = true;
            stoppedBecause = e.getMessage();
            if (
                !(e instanceof BulkDeleteService.BulkDeleteException) &&
                !(e instanceof QueryCompiler.QueryCompilerException)
            ) {
                ErrorLogger.log(e, 'BulkDeleteBatch.start', jobId);
            }
            return DataJobs.noRecords(jobId);
        }
    }

    public void execute(Database.BatchableContext context, List<SObject> records) {
        if (String.isNotBlank(stoppedBecause)) {
            return;
        }
        List<Map<String, Object>> journal = new List<Map<String, Object>>();
        try {
            BulkDeleteService.Plan checked = BulkDeleteService.planFromDefinition(definition);
            Set<Id> ids = checked.fromFile
                ? resultingRecords(records)
                : new Map<Id, SObject>(records).keySet();
            List<SObject> current = checked.fromFile
                ? BulkDeleteService.readAgain(checked, ids)
                : QueryCompiler.run(
                      QueryCompiler.compileSelection(checked.queryJson, checked.readFields(), ids)
                  );
            noLongerMatching += ids.size() - current.size();
            remove(checked, current, journal);
        } catch (BulkDeleteService.BulkDeleteException refused) {
            stop(refused);
        } catch (QueryCompiler.QueryCompilerException refused) {
            stop(refused);
        } catch (Exception e) {
            failed = true;
            ErrorLogger.log(e, 'BulkDeleteBatch.execute', jobId);
        }
        if (!ImportJournalService.write(jobId, ImportJournalService.PHASE_COMMIT, journal)) {
            journalIncomplete = true;
        }
    }

    /**
     * Stops the job for something the person can fix, found when a chunk checks the definition
     * again: the remaining chunks return at once, and the reason goes in the run log.
     */
    private void stop(Exception refused) {
        failed = true;
        stoppedBecause = refused.getMessage();
    }

    /** Deletes one chunk as the person and journals each record. */
    private void remove(
        BulkDeleteService.Plan checked,
        List<SObject> records,
        List<Map<String, Object>> journal
    ) {
        if (records.isEmpty()) {
            return;
        }
        List<Database.DeleteResult> results = Database.delete(
            records,
            false,
            AccessLevel.USER_MODE
        );
        for (Integer i = 0; i < results.size(); i++) {
            SObject record = records[i];
            if (results[i].isSuccess()) {
                deletedRecords++;
                journal.add(
                    ImportJournalService.deleted(
                        checked.objectName,
                        record.Id,
                        checked.nameOf(record)
                    )
                );
            } else {
                failedRecords++;
                journal.add(
                    ImportJournalService.failed(
                        checked.objectName,
                        record.Id,
                        message(results[i].getErrors())
                    )
                );
            }
        }
    }

    public void finish(Database.BatchableContext context) {
        Boolean platformStopped = DataJobs.chunkStopped(context, jobErrorsForTest);
        if (platformStopped) {
            failed = true;
        }
        try {
            Import_Batch__c job = DataJobs.forFinish(jobId);
            job.Run_Log__c = DataJobs.finalLog(
                job,
                String.isBlank(stoppedBecause)
                    ? null
                    : String.format(
                          System.Label.Core_BulkDelete_LogStopped,
                          new List<Object>{ stoppedBecause }
                      ),
                String.format(
                    System.Label.Core_BulkDelete_LogFinished,
                    new List<Object>{
                        deletedRecords.format(),
                        noLongerMatching.format(),
                        failedRecords.format()
                    }
                ),
                platformStopped,
                deletedRecords + noLongerMatching + failedRecords,
                journalIncomplete
            );
            job.Status__c = failed
                ? ImportBatchService.STATUS_FAILED
                : ImportBatchService.STATUS_COMPLETE;
            job.Completed_At__c = Datetime.now();
            job.Rows_Deleted__c = deletedRecords;
            job.Rows_Rejected__c = failedRecords;
            Database.update(job, AccessLevel.SYSTEM_MODE);
            JobNotifier.aboutRecord(
                UserInfo.getUserId(),
                System.Label.Core_JobNotice_BulkDelete,
                failed,
                String.format(
                    System.Label.Core_JobNotice_BulkDeleteBody,
                    new List<Object>{
                        deletedRecords.format(),
                        noLongerMatching.format(),
                        failedRecords.format()
                    }
                ),
                jobId
            );
        } catch (Exception e) {
            ErrorLogger.log(e, 'BulkDeleteBatch.finish', jobId);
        }
    }

    /** The records a chunk of a delete by file's rows name (R-BD7). */
    private static Set<Id> resultingRecords(List<SObject> rows) {
        Set<Id> ids = new Set<Id>();
        for (SObject row : rows) {
            ids.add(Id.valueOf((String) row.get('Gift_Id__c')));
        }
        return ids;
    }

    private static String message(List<Database.Error> errors) {
        List<String> parts = new List<String>();
        for (Database.Error error : errors) {
            parts.add(error.getMessage());
        }
        return String.join(parts, ' ');
    }
}
