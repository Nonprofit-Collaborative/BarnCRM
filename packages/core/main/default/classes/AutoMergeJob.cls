/**
 * Runs an auto-merge, or undoes one, in the background (C-51, R-DP9, R-DP10), as the person
 * who started it, so every read and write is theirs (user mode).
 *
 * A merge run is given the pair references the preview found; each chunk reads its pairs again
 * and merges those still exact (AutoMergeService.candidatesFor). An undo run is given the
 * journal rows of one run still marked Merged. Small chunks: each pair costs one query per
 * related-record link, a merge and a few writes. The summary goes to the Error Log and the
 * bell, as the duplicate scan's does.
 */
public with sharing class AutoMergeJob implements Database.Batchable<String>, Database.Stateful {
    public static final String LOG_CONTEXT = 'Auto-merge';
    @TestVisible
    private static final Integer MERGE_CHUNK = 10;
    private static final Integer UNDO_CHUNK = 20;

    private final Boolean undoing;
    private final List<String> work;
    private final String runId;
    @TestVisible
    private Integer done = 0;
    @TestVisible
    private Integer skipped = 0;
    @TestVisible
    private Integer failed = 0;

    private AutoMergeJob(Boolean undoing, List<String> work, String runId) {
        this.undoing = undoing;
        this.work = work;
        this.runId = runId;
    }

    /** Starts merging these pair references under a new run, and answers the run's id. */
    public static String startMerge(List<String> refs) {
        String runId = UUID.randomUUID().toString();
        Database.executeBatch(new AutoMergeJob(false, refs, runId), MERGE_CHUNK);
        return runId;
    }

    /** Starts undoing these journal rows of one run. */
    public static void startUndo(String runId, List<Id> journalIds) {
        List<String> work = new List<String>();
        for (Id journalId : journalIds) {
            work.add(journalId);
        }
        Database.executeBatch(new AutoMergeJob(true, work, runId), UNDO_CHUNK);
    }

    public Iterable<String> start(Database.BatchableContext context) {
        return work;
    }

    public void execute(Database.BatchableContext context, List<String> scope) {
        if (undoing) {
            undoChunk(scope);
            return;
        }
        Integer failuresBefore = AutoMergeService.failureCount;
        List<AutoMergeService.Candidate> pairs = AutoMergeService.candidatesFor(scope);
        Integer merged = AutoMergeService.mergeAll(pairs, runId);
        done += merged;
        failed += AutoMergeService.failureCount - failuresBefore;
        skipped += scope.size() - pairs.size();
    }

    private void undoChunk(List<String> scope) {
        List<Merge_Journal__c> journals = [
            SELECT
                Id,
                Survivor_Id__c,
                Merged_Id__c,
                Merged_Name__c,
                Status__c,
                Changed_Values__c,
                Moved_Records__c,
                Notes__c
            FROM Merge_Journal__c
            WHERE Id IN :scope AND Status__c = :AutoMergeService.MERGED
            WITH USER_MODE
        ];
        AutoMergeService.undo(journals);
        for (Merge_Journal__c journal : journals) {
            if (journal.Status__c == AutoMergeService.UNDO_FAILED) {
                failed++;
            } else {
                done++;
            }
        }
        skipped += scope.size() - journals.size();
    }

    public void finish(Database.BatchableContext context) {
        String summary = String.format(
            undoing ? Label.Core_AutoMerge_UndoFinished : Label.Core_AutoMerge_RunFinished,
            new List<Object>{ done, skipped, failed }
        );
        ErrorLogger.logMessage(
            summary,
            LOG_CONTEXT,
            failed > 0 ? ErrorLogger.SEVERITY_WARNING : ErrorLogger.SEVERITY_INFO
        );
        JobNotifier.aboutSettings(
            UserInfo.getUserId(),
            undoing ? Label.Core_AutoMerge_UndoNotice : Label.Core_AutoMerge_RunNotice,
            false,
            summary,
            JobNotifier.SECTION_DUPLICATE_MATCHING
        );
    }
}
