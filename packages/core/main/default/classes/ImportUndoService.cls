/**
 * Undoing one import (C-19, canonical model R-IB7 to R-IB9).
 *
 * This deletes records, so it is written to be boring. The rules it keeps are not style:
 *
 * 1. **One batch, named by its identifier.** Every count and every delete is filtered by the
 *    Created By Import Batch reference equal to one bound identifier. Nothing is filtered by a
 *    flag, a date, a status, a name or a user, and a blank identifier is refused rather than
 *    read as "everything".
 * 2. **Counted, shown, then confirmed.** `preview` counts what carries the tag. `start`
 *    refuses unless it is handed back the number it would count now, so an undo only ever
 *    deletes a set somebody has seen the size of.
 * 3. **Once.** The status moves to Undoing inside a locked read of the batch, so a second
 *    request is refused rather than queued.
 * 4. **Deleted, not destroyed.** Nothing here empties the recycle bin.
 *
 * The work itself is `ImportUndoBatch`.
 */
@NamespaceAccessible
public with sharing class ImportUndoService {
    /** Whether an undo job is queued or running, asked once per transaction. */
    private static Boolean undoJobRunning;

    /** What an undo would do, or why it cannot be done. */
    @NamespaceAccessible
    public class Preview {
        @AuraEnabled
        public Boolean allowed = false;
        /** Why an undo is refused, in a sentence an administrator can act on. */
        @AuraEnabled
        public String reason;
        @AuraEnabled
        public Integer people = 0;
        @AuraEnabled
        public Integer households = 0;
        @AuraEnabled
        public Integer organizations = 0;
        /** The records an undo would delete: the number the person confirms. */
        @AuraEnabled
        public Integer total = 0;
        /** The updates the journal holds, which an undo puts back where nobody changed them. */
        @AuraEnabled
        public Integer updates = 0;
        /**
         * The records of an installed module's own objects the import created (for example
         * gifts), one entry per object, in the order the undo deletes them (R-IB9).
         */
        @AuraEnabled
        public List<TaggedCount> others = new List<TaggedCount>();
    }

    /** How many records of one module object carry the batch's tag. */
    @NamespaceAccessible
    public class TaggedCount {
        /** The object's API name, stable for a key. */
        @AuraEnabled
        public String objectName;
        /** The object's plural label, as the org shows it. */
        @AuraEnabled
        public String label;
        @AuraEnabled
        public Integer count = 0;
    }

    /**
     * Counts what an undo of this batch would delete and put back, deleting nothing. The
     * counts come from the tag on the records themselves, not from the batch's row counters,
     * because this has to say what is there now rather than what the run did.
     */
    @NamespaceAccessible
    public static Preview preview(Id batchId) {
        Preview view = new Preview();
        Import_Batch__c batch = ImportBatchSelector.selectById(batchId);
        view.reason = refusal(batch);
        if (batch == null) {
            return view;
        }
        countTagged(batch.Id, view);
        view.updates = ImportJournalService.entryCount(batch.Id, ImportJournalService.PHASE_COMMIT);
        // A bulk update journals a Failed entry for each record it could not save, which has
        // nothing to put back, so its count is the records it saved (R-BU5). A job the platform
        // stopped before its finish counted them keeps the journal's count.
        if (
            BulkUpdateService.OPERATION_UPDATE.equals(batch.Operation__c) &&
            batch.Rows_Updated__c != null &&
            batch.Rows_Updated__c > 0
        ) {
            view.updates = batch.Rows_Updated__c.intValue();
        }
        if (String.isBlank(view.reason) && view.total == 0 && view.updates == 0) {
            view.reason = Label.Core_Import_UndoErrorNothingToUndo;
        }
        view.allowed = String.isBlank(view.reason);
        return view;
    }

    /**
     * Starts the undo of one batch after checking every guard again. `confirmedTotal` is the
     * total the person was shown: a set that has changed size since is refused, and counted
     * again, rather than deleted (R-IB8).
     *
     * @return the identifier of the job doing the work
     */
    @NamespaceAccessible
    public static Id start(Id batchId, Integer confirmedTotal) {
        Preview view = preview(batchId);
        if (!view.allowed) {
            throw new ImportException(view.reason);
        }
        if (confirmedTotal != view.total) {
            throw new ImportException(
                String.format(
                    Label.Core_Import_UndoErrorCountChanged,
                    new List<String>{
                        String.valueOf(confirmedTotal == null ? 0 : confirmedTotal),
                        String.valueOf(view.total)
                    }
                )
            );
        }
        latch(batchId);
        return ImportUndoBatch.run(batchId, view.total);
    }

    /**
     * Takes the once-only latch inside a locked read, so two people pressing Undo at the same
     * moment produce one undo and one refusal. The status is the package's own bookkeeping,
     * written in system mode (ADR-0021).
     */
    public static void latch(Id batchId) {
        Import_Batch__c batch = [
            SELECT Id, Status__c, Is_Dry_Run__c, Undo_Deadline__c, Completed_At__c, Job_Id__c
            FROM Import_Batch__c
            WHERE Id = :batchId
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        String refused = refusal(batch);
        if (String.isNotBlank(refused)) {
            throw new ImportException(refused);
        }
        batch.Status__c = ImportBatchService.STATUS_UNDOING;
        Database.update(batch, AccessLevel.SYSTEM_MODE);
        undoJobRunning = true;
    }

    /**
     * Closes an undo: its status, and one line added to the run log saying who ran it, when,
     * and what it deleted, kept and put back. Called from the job's last finish, in system
     * mode over fields the package owns (ADR-0021). `createdGone` is how many journaled
     * creations the undo deleted (R-IJ3), so the ones left are the ones kept.
     */
    @NamespaceAccessible
    public static void finish(
        Id batchId,
        Integer countedAtStart,
        Integer restored,
        Boolean failed,
        Integer createdGone
    ) {
        try {
            Preview left = new Preview();
            countTagged(batchId, left);
            left.total = Math.max(left.total - (createdGone == null ? 0 : createdGone), 0);
            Integer counted = countedAtStart == null ? 0 : countedAtStart;
            Import_Batch__c batch = [
                SELECT Id, Run_Log__c
                FROM Import_Batch__c
                WHERE Id = :batchId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            String line = String.format(
                Label.Core_Import_LogUndone,
                new List<String>{
                    UserInfo.getName(),
                    Datetime.now().format(),
                    String.valueOf(Math.max(counted - left.total, 0)),
                    String.valueOf(left.total),
                    String.valueOf(restored == null ? 0 : restored)
                }
            );
            batch.Run_Log__c = (String.isBlank(batch.Run_Log__c)
                    ? line
                    : batch.Run_Log__c + '\n' + line)
                .right(32768);
            batch.Status__c = failed == true
                ? ImportBatchService.STATUS_UNDO_FAILED
                : ImportBatchService.STATUS_UNDONE;
            Database.update(batch, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportUndoService.finish', batchId);
        }
    }

    /**
     * Why this batch cannot be undone, or blank when it can. A commit that failed part way is
     * undoable, because the chunks that ran did write (R-IB7), and so is an undo that stopped
     * on an error, or whose job was aborted, because running it again only finishes it
     * (R-IB8).
     */
    @NamespaceAccessible
    public static String refusal(Import_Batch__c batch) {
        return refusal(batch, null);
    }

    /**
     * As above, for a batch whose effective status the caller has already worked out, so the
     * job is not asked about twice; a null status is worked out here.
     */
    @NamespaceAccessible
    public static String refusal(Import_Batch__c batch, String knownStatus) {
        if (batch == null) {
            return Label.Core_Import_ErrorBatchGone;
        }
        if (batch.Is_Dry_Run__c == true) {
            return Label.Core_Import_UndoErrorDryRun;
        }
        String status = knownStatus == null ? effectiveStatus(batch) : knownStatus;
        if (
            ImportBatchService.STATUS_UNDOING.equals(status) ||
            ImportBatchService.STATUS_UNDONE.equals(status)
        ) {
            return Label.Core_Import_UndoErrorAlreadyUndone;
        }
        if (
            !(ImportBatchService.STATUS_COMPLETE.equals(status) ||
            ImportBatchService.STATUS_FAILED.equals(status) ||
            ImportBatchService.STATUS_UNDO_FAILED.equals(status)) ||
            batch.Undo_Deadline__c == null ||
            (batch.Completed_At__c == null &&
            !ImportBatchService.STATUS_COMMITTING.equals(batch.Status__c))
        ) {
            return Label.Core_Import_UndoErrorNotCommitted;
        }
        if (batch.Undo_Deadline__c < Datetime.now()) {
            return String.format(
                Label.Core_Import_UndoErrorWindowClosed,
                new List<String>{ batch.Undo_Deadline__c.format() }
            );
        }
        return null;
    }

    /**
     * The batch's status as it really stands: Undoing with no undo job queued or running
     * means the job was aborted, which is Undo failed, so it can be run again rather than
     * staying Undoing for ever (R-IB8).
     */
    @NamespaceAccessible
    public static String effectiveStatus(Import_Batch__c batch) {
        if (batch == null) {
            return null;
        }
        if (ImportBatchService.STATUS_UNDOING.equals(batch.Status__c) && !isUndoJobRunning()) {
            return ImportBatchService.STATUS_UNDO_FAILED;
        }
        // A dry run or commit whose job the platform aborted, or whose finish failed, is
        // Failed, and an aborted commit can be undone like any failed one (R-IB13).
        if (
            (ImportBatchService.STATUS_DRY_RUN.equals(batch.Status__c) ||
            ImportBatchService.STATUS_COMMITTING.equals(batch.Status__c)) &&
            !ImportBatchService.isRunning(batch)
        ) {
            return ImportBatchService.STATUS_FAILED;
        }
        return batch.Status__c;
    }

    /**
     * Whether any undo job is queued or running. Batches carry no job reference, so this asks
     * about the undo job classes (an import's, and a bulk delete's undelete); a second undo
     * running for another batch only delays the moment an aborted one is seen as failed. Read
     * in system mode: the job may be another user's.
     */
    private static Boolean isUndoJobRunning() {
        if (undoJobRunning == null) {
            Set<String> running = ImportBatchService.RUNNING_JOB_STATUSES;
            Set<String> undoClasses = new Set<String>{ 'ImportUndoBatch', 'BulkDeleteUndoBatch' };
            undoJobRunning = ![
                    SELECT Id
                    FROM AsyncApexJob
                    WHERE ApexClass.Name IN :undoClasses AND Status IN :running
                    WITH SYSTEM_MODE
                    LIMIT 1
                ]
                .isEmpty();
        }
        return undoJobRunning;
    }

    /**
     * Counts the records carrying this batch's tag, by kind. People stored as accounts are
     * counted as people, and an installed module's own objects each have their own count. Read in system mode (ADR-0021): the count has to include records the
     * running user cannot see, because an undo that says "nothing to delete" about records it
     * merely cannot see has told the administrator something false.
     */
    private static void countTagged(Id batchId, Preview view) {
        if (batchId == null) {
            return;
        }
        view.people = [
            SELECT COUNT()
            FROM Contact
            WHERE Created_By_Import_Batch__c = :batchId
            WITH SYSTEM_MODE
        ];
        Set<Id> personTypes = OrgShapeDetector.detect().personAccountRecordTypeIds;
        Id householdType = HouseholdService.householdRecordTypeId();
        for (AggregateResult counted : [
            SELECT RecordTypeId recordType, COUNT(Id) total
            FROM Account
            WHERE Created_By_Import_Batch__c = :batchId
            WITH SYSTEM_MODE
            GROUP BY RecordTypeId
        ]) {
            Id recordType = (Id) counted.get('recordType');
            Integer total = (Integer) counted.get('total');
            if (recordType != null && personTypes.contains(recordType)) {
                view.people += total;
            } else if (recordType != null && recordType == householdType) {
                view.households += total;
            } else {
                view.organizations += total;
            }
        }
        view.others = new List<TaggedCount>();
        Integer otherTotal = 0;
        for (Schema.SObjectType type : ImportEntityProcessors.taggedTypes()) {
            Schema.DescribeSObjectResult described = type.getDescribe(
                SObjectDescribeOptions.DEFERRED
            );
            TaggedCount counted = new TaggedCount();
            counted.objectName = described.getName();
            counted.label = described.getLabelPlural();
            counted.count = Database.countQueryWithBinds(
                'SELECT COUNT() FROM ' +
                    String.escapeSingleQuotes(described.getName()) +
                    ' WHERE ' +
                    ImportEntityProcessors.TAG_FIELD +
                    ' = :batchId',
                new Map<String, Object>{ 'batchId' => batchId },
                AccessLevel.SYSTEM_MODE
            );
            otherTotal += counted.count;
            view.others.add(counted);
        }
        TaggedCount created = createdCount(batchId);
        if (created != null) {
            otherTotal += created.count;
            view.others.add(created);
        }
        view.total = view.people + view.households + view.organizations + otherTotal;
    }

    /**
     * The records a one-object import journaled as created (R-IJ3), under their object's plural
     * label, or null when it created none. A one-object import loads one object, so the first
     * Created page names it. Read in system mode, as the tagged counts are.
     */
    private static TaggedCount createdCount(Id batchId) {
        Integer count = ImportJournalService.entryCount(
            batchId,
            ImportJournalService.PHASE_CREATED
        );
        if (count == 0) {
            return null;
        }
        String phase = ImportJournalService.PHASE_CREATED;
        List<Import_Journal__c> first = [
            SELECT Entries_JSON__c
            FROM Import_Journal__c
            WHERE Import_Batch__c = :batchId AND Phase__c = :phase
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT 1
        ];
        List<Map<String, Object>> entries = first.isEmpty()
            ? new List<Map<String, Object>>()
            : ImportJournalService.entries(first[0]);
        String objectName = entries.isEmpty() ? null : (String) entries[0].get('object');
        Schema.SObjectType type = ImportObjectSchema.typeNamed(objectName);
        TaggedCount counted = new TaggedCount();
        counted.objectName = type == null
            ? objectName
            : type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        counted.label = type == null
            ? objectName
            : type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural();
        counted.count = count;
        return counted;
    }
}
