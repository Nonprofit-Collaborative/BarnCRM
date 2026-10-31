/**
 * The Auto-Merge area of the Duplicate Matching tab (C-51, R-DP9, R-DP10): preview the exact
 * people matches waiting in the review list, merge them in one background run, and undo a run.
 *
 * Every action needs Manage BarnCRM Settings, as merging from the review list does. Previewing
 * and merging also need access to the platform's duplicate record sets (BarnCRM Duplicate
 * Review), since the pairs come from the review list; undo reads only the journal.
 */
public with sharing class AutoMergeController {
    private static final String EDIT_PERMISSION = 'Manage_BarnCRM_Settings';
    private static final String JOB_CLASS = 'AutoMergeJob';
    private static final String SCAN_CLASS = 'DuplicateScanBatch';
    /** The most pairs a preview lists; the count still covers them all. */
    private static final Integer MAX_SHOWN = 200;
    private static final Integer MAX_RUNS = 10;

    /** One run, as the Recent Runs list shows it. */
    public class RunView {
        @AuraEnabled
        public String runId;
        @AuraEnabled
        public Datetime startedAt;
        @AuraEnabled
        public Integer merged = 0;
        @AuraEnabled
        public Integer undone = 0;
        @AuraEnabled
        public Integer notUndone = 0;
        @AuraEnabled
        public Boolean canUndo = false;
        /** What could not be recorded or restored, one line per person. */
        @AuraEnabled
        public List<String> notes = new List<String>();
    }

    /** The area, in one round trip. */
    public class PanelView {
        @AuraEnabled
        public Boolean canRun = false;
        @AuraEnabled
        public Boolean running = false;
        @AuraEnabled
        public String exactRule;
        @AuraEnabled
        public List<RunView> runs = new List<RunView>();
    }

    /** What a run would merge. */
    public class PreviewView {
        @AuraEnabled
        public Integer total = 0;
        @AuraEnabled
        public String exactRule;
        @AuraEnabled
        public List<AutoMergeService.Candidate> pairs = new List<AutoMergeService.Candidate>();
    }

    @AuraEnabled
    public static PanelView getView() {
        try {
            requirePermission();
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Auto-merge panel');
        }
    }

    @AuraEnabled
    public static PreviewView preview() {
        try {
            requireRunAccess();
            List<AutoMergeService.Candidate> found = AutoMergeService.candidates();
            PreviewView view = new PreviewView();
            view.total = found.size();
            view.exactRule = AutoMergeService.exactRule();
            for (Integer i = 0; i < found.size() && i < MAX_SHOWN; i++) {
                view.pairs.add(found[i]);
            }
            return view;
        } catch (Exception caught) {
            throw asUserError(caught, 'Preview an auto-merge');
        }
    }

    /** Starts merging every pair the preview would list now; refused while a run or scan runs. */
    @AuraEnabled
    public static PanelView startRun() {
        try {
            requireRunAccess();
            requireNothingRunning();
            List<String> refs = new List<String>();
            for (AutoMergeService.Candidate pair : AutoMergeService.candidates()) {
                refs.add(pair.ref);
            }
            if (refs.isEmpty()) {
                throw new DuplicateService.DuplicateException(Label.Core_AutoMerge_ErrorNothing);
            }
            AutoMergeJob.startMerge(refs);
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Start an auto-merge');
        }
    }

    /** Undoes every merge of one run still marked Merged, within the undo window. */
    @AuraEnabled
    public static PanelView undoRun(String runId) {
        try {
            requirePermission();
            requireNothingRunning();
            Datetime since = Datetime.now().addDays(-AutoMergeService.UNDO_DAYS);
            List<Id> journalIds = new List<Id>(
                new Map<Id, Merge_Journal__c>(
                        [
                            SELECT Id
                            FROM Merge_Journal__c
                            WHERE
                                Run_Id__c = :runId
                                AND Status__c = :AutoMergeService.MERGED
                                AND CreatedDate >= :since
                            WITH USER_MODE
                        ]
                    )
                    .keySet()
            );
            if (journalIds.isEmpty()) {
                throw new DuplicateService.DuplicateException(Label.Core_AutoMerge_ErrorNoUndo);
            }
            AutoMergeJob.startUndo(runId, journalIds);
            return currentView();
        } catch (Exception caught) {
            throw asUserError(caught, 'Undo an auto-merge');
        }
    }

    // ------------------------------------------------------------------ the view

    private static PanelView currentView() {
        PanelView view = new PanelView();
        view.canRun = canReviewSuggestions();
        view.exactRule = AutoMergeService.exactRule();
        view.running = DuplicateSelector.scanRunning(JOB_CLASS);
        Datetime since = Datetime.now().addDays(-AutoMergeService.UNDO_DAYS);
        Map<String, RunView> byRun = new Map<String, RunView>();
        for (Merge_Journal__c journal : [
            SELECT Run_Id__c, Status__c, Merged_Name__c, Notes__c, CreatedDate
            FROM Merge_Journal__c
            WHERE CreatedDate >= :since
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 5000
        ]) {
            RunView run = byRun.get(journal.Run_Id__c);
            if (run == null) {
                if (byRun.size() >= MAX_RUNS) {
                    continue;
                }
                run = new RunView();
                run.runId = journal.Run_Id__c;
                byRun.put(journal.Run_Id__c, run);
            }
            run.startedAt = journal.CreatedDate;
            run.merged++;
            if (journal.Status__c == AutoMergeService.MERGED) {
                run.canUndo = true;
            } else if (journal.Status__c == AutoMergeService.UNDONE) {
                run.undone++;
            } else {
                run.notUndone++;
            }
            if (String.isNotBlank(journal.Notes__c)) {
                run.notes.add(journal.Merged_Name__c + ': ' + journal.Notes__c.replace('\n', ' '));
            }
        }
        view.runs = byRun.values();
        return view;
    }

    private static Boolean canReviewSuggestions() {
        return Schema.SObjectType.DuplicateRecordSet.isAccessible() &&
            Schema.SObjectType.DuplicateRecordSet.isDeletable() &&
            Schema.SObjectType.DuplicateRecordItem.isAccessible();
    }

    // ------------------------------------------------------------------ helpers

    private static void requirePermission() {
        if (!FeatureManagement.checkPermission(EDIT_PERMISSION)) {
            throw new DuplicateService.DuplicateException(
                Label.Core_Duplicates_ErrorPermissionRequired
            );
        }
    }

    private static void requireRunAccess() {
        requirePermission();
        if (!canReviewSuggestions()) {
            throw new DuplicateService.DuplicateException(
                Label.Core_Duplicates_ErrorNoSuggestionAccess
            );
        }
    }

    /** One run or undo at a time, and none while a scan is still writing the pairs. */
    private static void requireNothingRunning() {
        if (DuplicateSelector.scanRunning(JOB_CLASS) || DuplicateSelector.scanRunning(SCAN_CLASS)) {
            throw new DuplicateService.DuplicateException(Label.Core_AutoMerge_ErrorRunning);
        }
    }

    private static AuraHandledException asUserError(Exception caught, String context) {
        String message = caught.getMessage();
        if (!(caught instanceof DuplicateService.DuplicateException)) {
            ErrorLogger.log(caught, context);
            message = Label.Core_Duplicates_ErrorUnexpected;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
