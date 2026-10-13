/**
 * The undo of one bulk delete (C-37, canonical model R-BD5): brings each record the job
 * journaled as Deleted back from the Recycle Bin, one journal page a chunk.
 *
 * - **Found by the Id the journal holds.** The object is the Id's own type, from describe, never
 *   text from the page. Each record is looked for with `ALL ROWS`, in system mode, so a record
 *   the person can no longer see is still met and refused by the user-mode undelete, and
 *   journaled, instead of silently staying deleted.
 * - **As the person.** `Database.undelete(ids, false, AccessLevel.USER_MODE)`: one refusal does
 *   not stop the rest.
 * - **Said plainly.** A record no longer in the Recycle Bin is counted as purged, a record
 *   somebody already restored is left alone and counted, and each record not brought back is
 *   journaled as NotRestored with the reason.
 *
 * The job record and the journal are the package's own bookkeeping, written in system mode
 * (ADR-0021). The latch (Undoing) is taken by `BulkDeleteService.undo` through
 * `ImportUndoService.latch`, and an undo that stops can be run again.
 */
public with sharing class BulkDeleteUndoBatch implements Database.Batchable<SObject>, Database.Stateful {
    private final Id jobId;
    private final Integer counted;
    private Integer restored = 0;
    private Integer purged = 0;
    private Integer alreadyBack = 0;
    private Integer refused = 0;
    private Boolean failed = false;
    private Boolean journalIncomplete = false;
    /** When the bulk delete started: households binned since then may be its side effect. */
    private Datetime startedAt;

    /**
     * Set only by tests: the error count a job reports when the platform stopped a chunk, which
     * a test cannot bring about for real.
     */
    @TestVisible
    private static Integer jobErrorsForTest;

    /** `counted` is the number of deleted records the person confirmed. */
    public BulkDeleteUndoBatch(Id jobId, Integer counted) {
        this.jobId = jobId;
        this.counted = counted;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Id owner = jobId;
        String phase = ImportJournalService.PHASE_COMMIT;
        for (Import_Batch__c job : [
            SELECT Started_At__c
            FROM Import_Batch__c
            WHERE Id = :owner
            WITH SYSTEM_MODE
            LIMIT 1
        ]) {
            startedAt = job.Started_At__c;
        }
        return Database.getQueryLocator(
            [
                SELECT Id, Entries_JSON__c
                FROM Import_Journal__c
                WHERE Import_Batch__c = :owner AND Phase__c = :phase
                WITH SYSTEM_MODE
                ORDER BY CreatedDate, Id
            ]
        );
    }

    public void execute(Database.BatchableContext context, List<SObject> pages) {
        List<Map<String, Object>> journal = new List<Map<String, Object>>();
        try {
            for (SObject page : pages) {
                restorePage((Import_Journal__c) page, journal);
            }
        } catch (Exception e) {
            failed = true;
            ErrorLogger.log(e, 'BulkDeleteUndoBatch.execute', jobId);
        }
        if (!ImportJournalService.write(jobId, ImportJournalService.PHASE_UNDO, journal)) {
            journalIncomplete = true;
        }
    }

    /** Brings back the Deleted records of one page, grouped by object. */
    private void restorePage(Import_Journal__c page, List<Map<String, Object>> journal) {
        Map<Schema.SObjectType, List<Id>> idsByType = new Map<Schema.SObjectType, List<Id>>();
        for (Map<String, Object> entry : ImportJournalService.entries(page)) {
            if (!ImportJournalService.ACTION_DELETED.equals(entry.get('action'))) {
                continue;
            }
            Id recordId = Id.valueOf(String.valueOf(entry.get('id')));
            Schema.SObjectType type = recordId.getSObjectType();
            if (!idsByType.containsKey(type)) {
                idsByType.put(type, new List<Id>());
            }
            idsByType.get(type).add(recordId);
        }
        restoreTidiedHouseholds(idsByType);
        for (Schema.SObjectType type : idsByType.keySet()) {
            restore(type, idsByType.get(type), journal);
        }
    }

    /**
     * Brings back, before the people, the households that automation deleted because this job
     * left them empty (Delete Empty Households, R-H11). Those deletes are not the job's own, so
     * they are not in the journal, but a person cannot come back into a household that is still
     * in the Recycle Bin: in contact mode the person's account is that household, and in
     * junction mode the person's memberships name it.
     *
     * Only a household (record type Household) deleted since the job started is restored, so a
     * household somebody deleted before it on purpose stays deleted. Restored as the person; a
     * refusal shows up as the person's own refusal, which is journaled.
     */
    private void restoreTidiedHouseholds(Map<Schema.SObjectType, List<Id>> idsByType) {
        Id householdType = HouseholdService.householdRecordTypeId();
        if (householdType == null || startedAt == null) {
            return;
        }
        List<Id> contactIds = idsByType.containsKey(Contact.SObjectType)
            ? idsByType.get(Contact.SObjectType)
            : new List<Id>();
        List<Id> accountIds = idsByType.containsKey(Account.SObjectType)
            ? idsByType.get(Account.SObjectType)
            : new List<Id>();
        if (contactIds.isEmpty() && accountIds.isEmpty()) {
            return;
        }
        Set<Id> households = new Set<Id>();
        for (Contact person : [
            SELECT AccountId
            FROM Contact
            WHERE Id IN :contactIds AND AccountId != NULL
            WITH SYSTEM_MODE
            ALL ROWS
        ]) {
            households.add(person.AccountId);
        }
        for (Household_Member__c membership : [
            SELECT Household__c
            FROM Household_Member__c
            WHERE (Contact__c IN :contactIds OR Account__c IN :accountIds) AND Household__c != NULL
            WITH SYSTEM_MODE
            ALL ROWS
        ]) {
            households.add(membership.Household__c);
        }
        if (households.isEmpty()) {
            return;
        }
        Datetime since = startedAt;
        List<Account> binned = [
            SELECT Id
            FROM Account
            WHERE
                Id IN :households
                AND IsDeleted = TRUE
                AND RecordTypeId = :householdType
                AND SystemModstamp >= :since
            WITH SYSTEM_MODE
            ALL ROWS
        ];
        if (!binned.isEmpty()) {
            Database.undelete(binned, false, AccessLevel.USER_MODE);
        }
    }

    private void restore(Schema.SObjectType type, List<Id> ids, List<Map<String, Object>> journal) {
        String objectName = type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        Map<Id, SObject> found = new Map<Id, SObject>(
            Database.queryWithBinds(
                'SELECT Id, IsDeleted FROM ' +
                    String.escapeSingleQuotes(objectName) +
                    ' WHERE Id IN :ids ALL ROWS',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.SYSTEM_MODE
            )
        );
        List<Id> toUndelete = new List<Id>();
        for (Id recordId : ids) {
            SObject record = found.get(recordId);
            if (record == null) {
                purged++;
                journal.add(
                    ImportJournalService.notRestored(
                        objectName,
                        recordId,
                        null,
                        System.Label.Core_BulkDelete_UndoPurged
                    )
                );
            } else if (record.get('IsDeleted') != true) {
                alreadyBack++;
            } else {
                toUndelete.add(recordId);
            }
        }
        if (toUndelete.isEmpty()) {
            return;
        }
        List<Database.UndeleteResult> results = Database.undelete(
            toUndelete,
            false,
            AccessLevel.USER_MODE
        );
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                restored++;
                continue;
            }
            List<String> parts = new List<String>();
            Boolean emptied = false;
            for (Database.Error error : results[i].getErrors()) {
                parts.add(error.getMessage());
                emptied = emptied || isEmptiedFromTheBin(error);
            }
            if (emptied) {
                purged++;
            } else {
                refused++;
            }
            journal.add(
                ImportJournalService.notRestored(
                    objectName,
                    toUndelete[i],
                    null,
                    emptied ? System.Label.Core_BulkDelete_UndoPurged : String.join(parts, ' ')
                )
            );
        }
    }

    /**
     * A record emptied from the Recycle Bin can still be met by `ALL ROWS` until the platform
     * finishes the hard delete, and its undelete then fails with UNDELETE_FAILED. That status
     * also covers other refusals, so the platform's English text decides; in another language
     * the record is reported as refused with the platform's own words, which is still true.
     */
    private static Boolean isEmptiedFromTheBin(Database.Error error) {
        return error.getStatusCode() == StatusCode.UNDELETE_FAILED &&
            String.valueOf(error.getMessage()).containsIgnoreCase('not in the recycle bin');
    }

    public void finish(Database.BatchableContext context) {
        if (chunkStopped(context)) {
            failed = true;
        }
        try {
            Import_Batch__c job = [
                SELECT Id, Run_Log__c
                FROM Import_Batch__c
                WHERE Id = :jobId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            String line = String.format(
                System.Label.Core_BulkDelete_LogUndone,
                new List<Object>{
                    UserInfo.getName(),
                    Datetime.now().format(),
                    restored.format(),
                    purged.format(),
                    alreadyBack.format(),
                    refused.format(),
                    (counted == null ? 0 : counted).format()
                }
            );
            if (journalIncomplete) {
                line += '\n' + System.Label.Core_BulkUpdate_LogJournalIncomplete;
            }
            job.Run_Log__c = (String.isBlank(job.Run_Log__c) ? line : job.Run_Log__c + '\n' + line)
                .right(32768);
            job.Status__c = failed
                ? ImportBatchService.STATUS_UNDO_FAILED
                : ImportBatchService.STATUS_UNDONE;
            Database.update(job, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            ErrorLogger.log(e, 'BulkDeleteUndoBatch.finish', jobId);
        }
    }

    /** Whether the platform stopped any chunk: the job's own error count is the one record. */
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
}
