/**
 * The work of one bulk delete (C-37, canonical model R-BD3), run as the person who started it.
 *
 * - **Only what was confirmed.** The query reads at most the confirmed number of records, in Id
 *   order, in user mode.
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
        Id owner = jobId;
        definition = [
            SELECT Operation_JSON__c
            FROM Import_Batch__c
            WHERE Id = :owner
            WITH SYSTEM_MODE
            LIMIT 1
        ]
        .Operation_JSON__c;
        try {
            BulkDeleteService.Plan checked = BulkDeleteService.planFromDefinition(definition);
            QueryCompiler.Compiled selection = QueryCompiler.compileSelection(
                checked.queryJson,
                new Set<String>{ 'Id' },
                null
            );
            selection.binds.put('confirmed', BulkDeleteService.confirmedCountOf(definition));
            return Database.getQueryLocatorWithBinds(
                selection.soql + ' ORDER BY Id LIMIT :confirmed',
                selection.binds,
                AccessLevel.USER_MODE
            );
        } catch (Exception e) {
            failed = true;
            stoppedBecause = e.getMessage();
            if (
                !(e instanceof BulkDeleteService.BulkDeleteException) &&
                !(e instanceof QueryCompiler.QueryCompilerException)
            ) {
                ErrorLogger.log(e, 'BulkDeleteBatch.start', jobId);
            }
            // A locator that reads no record, so finish still closes the job.
            return Database.getQueryLocatorWithBinds(
                'SELECT Id FROM Import_Batch__c WHERE Id = :owner AND Id = NULL',
                new Map<String, Object>{ 'owner' => owner },
                AccessLevel.SYSTEM_MODE
            );
        }
    }

    public void execute(Database.BatchableContext context, List<SObject> records) {
        if (String.isNotBlank(stoppedBecause)) {
            return;
        }
        List<Map<String, Object>> journal = new List<Map<String, Object>>();
        try {
            BulkDeleteService.Plan checked = BulkDeleteService.planFromDefinition(definition);
            Set<Id> ids = new Map<Id, SObject>(records).keySet();
            List<SObject> current = QueryCompiler.run(
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
        Boolean platformStopped = chunkStopped(context);
        if (platformStopped) {
            failed = true;
        }
        try {
            Import_Batch__c job = [
                SELECT Id, Run_Log__c, Row_Count__c
                FROM Import_Batch__c
                WHERE Id = :jobId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            List<String> lines = new List<String>();
            if (String.isNotBlank(job.Run_Log__c)) {
                lines.add(job.Run_Log__c);
            }
            if (String.isNotBlank(stoppedBecause)) {
                lines.add(
                    String.format(
                        System.Label.Core_BulkDelete_LogStopped,
                        new List<Object>{ stoppedBecause }
                    )
                );
            }
            lines.add(
                String.format(
                    System.Label.Core_BulkDelete_LogFinished,
                    new List<Object>{
                        deletedRecords.format(),
                        noLongerMatching.format(),
                        failedRecords.format()
                    }
                )
            );
            if (platformStopped) {
                Integer notReached = BulkUpdateService.notReached(
                    job.Row_Count__c,
                    deletedRecords + noLongerMatching + failedRecords
                );
                if (notReached > 0) {
                    lines.add(
                        String.format(
                            System.Label.Core_BulkUpdate_LogNotReached,
                            new List<Object>{ notReached.format() }
                        )
                    );
                }
            }
            if (journalIncomplete) {
                lines.add(System.Label.Core_BulkUpdate_LogJournalIncomplete);
            }
            job.Run_Log__c = String.join(lines, '\n').right(32768);
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

    /**
     * Whether the platform stopped any chunk. A governor limit cannot be caught, so the job's
     * own error count is the one record of it.
     */
    private Boolean chunkStopped(Database.BatchableContext context) {
        if (jobErrorsForTest != null) {
            return jobErrorsForTest > 0;
        }
        if (context == null || context.getJobId() == null) {
            return false;
        }
        Id asyncJobId = context.getJobId();
        List<AsyncApexJob> jobs = [
            SELECT NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :asyncJobId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return !jobs.isEmpty() && jobs[0].NumberOfErrors != null && jobs[0].NumberOfErrors > 0;
    }

    private static String message(List<Database.Error> errors) {
        List<String> parts = new List<String>();
        for (Database.Error error : errors) {
            parts.add(error.getMessage());
        }
        return String.join(parts, ' ');
    }
}
