/**
 * The work of one bulk update (C-35, canonical model R-BU3), run as the person who started it.
 *
 * - **Only what was confirmed.** The query reads at most the confirmed number of records, in Id
 *   order, in user mode.
 * - **Only records that still match.** Each chunk reads its records again with the query's
 *   filter, so a record changed since the job started so that it no longer matches is left
 *   alone and counted.
 * - **The person's own access.** The definition is checked again as the person when the job
 *   starts and in every chunk, so access taken away in between stops the job rather than being
 *   worked around, and every save is `Database.update(records, false, USER_MODE)`.
 * - **Journaled.** Each chunk writes one commit page (R-IJ1): an Updated entry per record saved,
 *   with the value before and after for each field that changed, and a Failed entry per record
 *   the platform refused. The undo is an import's (R-BU5).
 *
 * The job record and the journal are the package's own bookkeeping, written in system mode
 * (ADR-0021).
 */
public with sharing class BulkUpdateBatch implements Database.Batchable<SObject>, Database.Stateful {
    private final Id jobId;
    private String definition;
    private Integer updated = 0;
    private Integer unchanged = 0;
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

    public BulkUpdateBatch(Id jobId) {
        this.jobId = jobId;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        definition = DataJobs.definitionOf(jobId);
        try {
            BulkUpdateService.Plan checked = BulkUpdateService.planFromDefinition(definition);
            return DataJobs.locatorFor(checked.queryJson, DataJobs.confirmedCountOf(definition));
        } catch (Exception e) {
            failed = true;
            stoppedBecause = e.getMessage();
            if (
                !(e instanceof BulkUpdateFields.BulkUpdateException) &&
                !(e instanceof QueryCompiler.QueryCompilerException)
            ) {
                ErrorLogger.log(e, 'BulkUpdateBatch.start', jobId);
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
            BulkUpdateService.Plan checked = BulkUpdateService.planFromDefinition(definition);
            Set<Id> ids = new Map<Id, SObject>(records).keySet();
            List<SObject> current = QueryCompiler.run(
                QueryCompiler.compileSelection(checked.queryJson, checked.readFields(), ids)
            );
            noLongerMatching += ids.size() - current.size();
            apply(checked, current, journal);
        } catch (BulkUpdateFields.BulkUpdateException refused) {
            stop(refused);
        } catch (QueryCompiler.QueryCompilerException refused) {
            stop(refused);
        } catch (Exception e) {
            failed = true;
            ErrorLogger.log(e, 'BulkUpdateBatch.execute', jobId);
        }
        if (!ImportJournalService.write(jobId, ImportJournalService.PHASE_COMMIT, journal)) {
            journalIncomplete = true;
        }
    }

    /**
     * Stops the job for something the person can fix, found when a chunk checks the definition
     * again (access taken away, a field deleted): the remaining chunks return at once, and the
     * reason goes in the run log rather than one Error Log row per chunk.
     */
    private void stop(Exception refused) {
        failed = true;
        stoppedBecause = refused.getMessage();
    }

    /**
     * Saves one chunk's changes and journals each record. A record whose fields already hold
     * the new values is not saved: there is nothing to put back.
     */
    private void apply(
        BulkUpdateService.Plan checked,
        List<SObject> records,
        List<Map<String, Object>> journal
    ) {
        List<SObject> toSave = new List<SObject>();
        List<Map<String, Object>> beforeOf = new List<Map<String, Object>>();
        List<Map<String, Object>> afterOf = new List<Map<String, Object>>();
        for (SObject record : records) {
            SObject change = checked.objectType.newSObject(record.Id);
            Map<String, Object> before = new Map<String, Object>();
            Map<String, Object> after = new Map<String, Object>();
            String refusal;
            for (BulkUpdateService.Change planned : checked.changes) {
                String field = planned.target.getName();
                Object was = record.get(field);
                Object becomes;
                try {
                    becomes = planned.newValueFor(record);
                } catch (BulkUpdateFields.BulkUpdateException cannotTake) {
                    // A transform's result this field cannot take (R-BU7): this record only.
                    refusal = cannotTake.getMessage();
                    break;
                }
                if (!same(was, becomes)) {
                    before.put(field, was);
                    after.put(field, becomes);
                    change.put(field, becomes);
                }
            }
            if (refusal != null) {
                failedRecords++;
                journal.add(ImportJournalService.failed(checked.objectName, record.Id, refusal));
                continue;
            }
            if (after.isEmpty()) {
                unchanged++;
                continue;
            }
            // Every saved record can be undone: one whose before and after values are too long
            // for a journal page (long text) is refused rather than saved without an undo.
            if (
                !ImportJournalService.fitsOnAPage(
                    ImportJournalService.updated(checked.objectName, record.Id, null, before, after)
                )
            ) {
                failedRecords++;
                journal.add(
                    ImportJournalService.failed(
                        checked.objectName,
                        record.Id,
                        System.Label.Core_BulkUpdate_ErrorTooLargeToUndo
                    )
                );
                continue;
            }
            toSave.add(change);
            beforeOf.add(before);
            afterOf.add(after);
        }
        if (toSave.isEmpty()) {
            return;
        }
        List<Database.SaveResult> results = Database.update(toSave, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            Id recordId = toSave[i].Id;
            if (results[i].isSuccess()) {
                updated++;
                journal.add(
                    ImportJournalService.updated(
                        checked.objectName,
                        recordId,
                        null,
                        beforeOf[i],
                        afterOf[i]
                    )
                );
            } else {
                failedRecords++;
                journal.add(
                    ImportJournalService.failed(
                        checked.objectName,
                        recordId,
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
                          System.Label.Core_BulkUpdate_LogStopped,
                          new List<Object>{ stoppedBecause }
                      ),
                String.format(
                    System.Label.Core_BulkUpdate_LogFinished,
                    new List<Object>{
                        updated.format(),
                        unchanged.format(),
                        noLongerMatching.format(),
                        failedRecords.format()
                    }
                ),
                platformStopped,
                updated + unchanged + noLongerMatching + failedRecords,
                journalIncomplete
            );
            job.Status__c = failed
                ? ImportBatchService.STATUS_FAILED
                : ImportBatchService.STATUS_COMPLETE;
            job.Completed_At__c = Datetime.now();
            job.Rows_Updated__c = updated;
            job.Rows_Matched__c = unchanged;
            job.Rows_Rejected__c = failedRecords;
            Database.update(job, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            ErrorLogger.log(e, 'BulkUpdateBatch.finish', jobId);
        }
    }

    /**
     * Whether two values are the same for a bulk update: numbers as numbers, text exactly, so a
     * value that differs only in capitals is still written.
     */
    @TestVisible
    private static Boolean same(Object stored, Object wanted) {
        if (stored == null || wanted == null) {
            return stored == null && wanted == null;
        }
        if (stored instanceof Decimal || stored instanceof Integer || stored instanceof Double) {
            try {
                return Decimal.valueOf(String.valueOf(stored)) ==
                    Decimal.valueOf(String.valueOf(wanted));
            } catch (Exception notANumber) {
                return false;
            }
        }
        if (stored instanceof String || wanted instanceof String) {
            return String.valueOf(stored).equals(String.valueOf(wanted));
        }
        return stored == wanted;
    }

    private static String message(List<Database.Error> errors) {
        List<String> parts = new List<String>();
        for (Database.Error error : errors) {
            parts.add(error.getMessage());
        }
        return String.join(parts, ' ');
    }
}
