/**
 * What the bulk delete panel and its list on the Bulk Update tab read and write (C-37,
 * canonical model R-BD1 to R-BD6, ADR-0091).
 *
 * Every method requires the Bulk Delete Records custom permission and, where a bulk delete
 * starts from a Find query, Find and Export Records (R-BD6); the list, progress and undo read no
 * query, and a delete by file (R-BD7) starts from an import's dry run. Neither grants record
 * access: the query is compiled and counted as the person, and every record is deleted in their
 * own mode. Jobs are read in user mode; the progress of a running job is read from its
 * AsyncApexJob in system mode, filtered by the job identifier the person's own job record holds.
 */
public with sharing class BulkDeleteController {
    public static final String PERMISSION = 'Bulk_Delete_Records';
    private static final Integer RECENT_JOBS = 10;
    private static final Integer FAILURES_SHOWN = 20;
    private static final String JOB_FIELDS =
        'Id, Name, Status__c, Is_Dry_Run__c, Operation__c, Operation_JSON__c, Row_Count__c, ' +
        'Rows_Deleted__c, Rows_Rejected__c, Run_Log__c, Started_At__c, Completed_At__c, ' +
        'Undo_Deadline__c, Job_Id__c';

    /** A record the platform refused, and why. */
    public class Failure {
        @AuraEnabled
        public String recordId;
        @AuraEnabled
        public String reason;
    }

    /** One bulk delete, as the page shows it. */
    public class JobView {
        @AuraEnabled
        public String recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Integer matched;
        @AuraEnabled
        public Integer deleted;
        @AuraEnabled
        public Integer failed;
        @AuraEnabled
        public String runLog;
        @AuraEnabled
        public Datetime startedAt;
        @AuraEnabled
        public Datetime undoDeadline;
        @AuraEnabled
        public Boolean running;
        @AuraEnabled
        public Integer chunksDone;
        @AuraEnabled
        public Integer chunksTotal;
        @AuraEnabled
        public Boolean canUndo;
        /** The records an undo would bring back: the number the person confirms. */
        @AuraEnabled
        public Integer recordsToUndo;
        @AuraEnabled
        public List<Failure> failures;
    }

    /** The list on the Bulk Update tab: whether the person may, the limit, recent jobs. */
    public class BulkDeletePage {
        @AuraEnabled
        public Boolean allowed;
        @AuraEnabled
        public Integer runLimit;
        @AuraEnabled
        public List<JobView> jobs;
    }

    /**
     * The person's recent bulk deletes. A person without the permission gets an empty page
     * that says so, rather than an error, because the Bulk Update tab shows the list to all.
     */
    @AuraEnabled
    public static BulkDeletePage getPage() {
        try {
            BulkDeletePage page = new BulkDeletePage();
            page.allowed = mayDelete();
            page.jobs = new List<JobView>();
            if (!page.allowed) {
                return page;
            }
            page.runLimit = BulkDeleteService.runLimit();
            for (Import_Batch__c job : jobs(null, RECENT_JOBS)) {
                page.jobs.add(toView(job, false));
            }
            return page;
        } catch (Exception caught) {
            throw asUserError(caught, 'Bulk delete page');
        }
    }

    /** How many records match now, five of them by name, and what goes with them. */
    @AuraEnabled
    public static BulkDeleteService.Preview preview(String queryJson) {
        try {
            requirePermission();
            return BulkDeleteService.preview(queryJson);
        } catch (Exception caught) {
            throw asUserError(caught, 'Bulk delete preview');
        }
    }

    /** Starts a bulk delete of the number of records the person confirmed. */
    @AuraEnabled
    public static JobView start(String queryJson, Integer confirmedCount) {
        try {
            requirePermission();
            Import_Batch__c started = BulkDeleteService.start(queryJson, confirmedCount);
            return toView(requireJob(started.Id), true);
        } catch (Exception caught) {
            throw asUserError(caught, 'Start a bulk delete');
        }
    }

    /**
     * What deleting the records a delete by file's dry run Matched would do (R-BD7): the count
     * the person confirms, five by name, and what goes with them.
     */
    @AuraEnabled
    public static BulkDeleteService.Preview previewFile(String batchId) {
        try {
            requireDeletePermission();
            return BulkDeleteService.filePreview(Id.valueOf(batchId));
        } catch (Exception caught) {
            throw asUserError(caught, 'Delete by file preview');
        }
    }

    /** Starts deleting the records a delete by file's dry run Matched, once confirmed (R-BD7). */
    @AuraEnabled
    public static JobView startFile(String batchId, Integer confirmedCount) {
        try {
            requireDeletePermission();
            Import_Batch__c started = BulkDeleteService.startFromFile(
                Id.valueOf(batchId),
                confirmedCount
            );
            return toView(requireJob(started.Id), true);
        } catch (Exception caught) {
            throw asUserError(caught, 'Start a delete by file');
        }
    }

    /** One bulk delete with its progress and the first refusals, for polling while it runs. */
    @AuraEnabled
    public static JobView getJob(String jobId) {
        try {
            requireDeletePermission();
            return toView(requireJob(jobId), true);
        } catch (Exception caught) {
            throw asUserError(caught, 'Read a bulk delete');
        }
    }

    /** Undoes a bulk delete once the person confirms how many records it brings back (R-BD5). */
    @AuraEnabled
    public static JobView undo(String jobId, Integer confirmedRecords) {
        try {
            requireDeletePermission();
            Import_Batch__c job = requireJob(jobId);
            BulkDeleteService.undo(job.Id, confirmedRecords);
            return toView(requireJob(job.Id), false);
        } catch (Exception caught) {
            throw asUserError(caught, 'Undo a bulk delete');
        }
    }

    /** Whether the running user may bulk delete: both permissions (R-BD6). */
    public static Boolean hasPermission() {
        return FeatureManagement.checkPermission(PERMISSION) &&
            FeatureManagement.checkPermission(FindController.PERMISSION);
    }

    private static void requirePermission() {
        if (!hasPermission()) {
            throw new BulkDeleteService.BulkDeleteException(
                System.Label.Core_BulkDelete_ErrorNoPermission
            );
        }
    }

    /** Whether the running user holds Bulk Delete Records, which every action needs. */
    public static Boolean mayDelete() {
        return FeatureManagement.checkPermission(PERMISSION);
    }

    /** For what reads no query: the list, progress, undo and a delete by file (R-BD6, R-BD7). */
    private static void requireDeletePermission() {
        if (!mayDelete()) {
            throw new BulkDeleteService.BulkDeleteException(
                System.Label.Core_BulkDelete_ErrorNoPermission
            );
        }
    }

    /** Bulk deletes the person can see, newest first, read as them. */
    private static List<Import_Batch__c> jobs(Id jobId, Integer howMany) {
        Map<String, Object> binds = new Map<String, Object>{
            'operation' => BulkDeleteService.OPERATION_DELETE,
            'howMany' => howMany,
            'jobId' => jobId
        };
        return Database.queryWithBinds(
            'SELECT ' +
                JOB_FIELDS +
                ' FROM Import_Batch__c WHERE Operation__c = :operation' +
                (jobId == null ? '' : ' AND Id = :jobId') +
                ' ORDER BY CreatedDate DESC LIMIT :howMany',
            binds,
            AccessLevel.USER_MODE
        );
    }

    private static Import_Batch__c requireJob(String jobId) {
        Id parsed;
        try {
            parsed = String.isBlank(jobId) ? null : Id.valueOf(jobId);
        } catch (Exception notAnId) {
            parsed = null;
        }
        List<Import_Batch__c> found = parsed == null
            ? new List<Import_Batch__c>()
            : jobs(parsed, 1);
        if (found.isEmpty()) {
            throw new BulkDeleteService.BulkDeleteException(
                System.Label.Core_BulkDelete_ErrorNotBulkDelete
            );
        }
        return found[0];
    }

    private static JobView toView(Import_Batch__c job, Boolean detail) {
        JobView view = new JobView();
        view.recordId = job.Id;
        view.name = job.Name;
        view.status = ImportUndoService.effectiveStatus(job);
        view.matched = intOf(job.Row_Count__c);
        view.deleted = intOf(job.Rows_Deleted__c);
        view.failed = intOf(job.Rows_Rejected__c);
        view.runLog = job.Run_Log__c;
        view.startedAt = job.Started_At__c;
        view.undoDeadline = job.Undo_Deadline__c;
        view.running = ImportBatchService.STATUS_COMMITTING.equals(view.status);
        view.canUndo = String.isBlank(ImportUndoService.refusal(job)) && view.deleted > 0;
        view.recordsToUndo = view.deleted;
        // A job aborted, or stopped before its finish counted, deleted records it never
        // counted: the undo's own count (from the journal) is the number to confirm.
        if (view.deleted == 0 && String.isBlank(ImportUndoService.refusal(job))) {
            BulkDeleteService.UndoPreview undoPreview = BulkDeleteService.undoPreview(job.Id);
            view.canUndo = undoPreview.allowed;
            view.recordsToUndo = undoPreview.records;
        }
        if (detail && view.running && String.isNotBlank(job.Job_Id__c)) {
            Id asyncJobId = job.Job_Id__c;
            for (AsyncApexJob progress : [
                SELECT JobItemsProcessed, TotalJobItems
                FROM AsyncApexJob
                WHERE Id = :asyncJobId
                WITH SYSTEM_MODE
                LIMIT 1
            ]) {
                view.chunksDone = progress.JobItemsProcessed;
                view.chunksTotal = progress.TotalJobItems;
            }
        }
        view.failures = new List<Failure>();
        if (detail && view.failed > 0) {
            view.failures = failures(job.Id);
        }
        return view;
    }

    /** The first refusals the job journaled, with the platform's reasons. */
    private static List<Failure> failures(Id jobId) {
        List<Failure> result = new List<Failure>();
        for (
            Import_Journal__c page : ImportJournalService.pages(
                jobId,
                ImportJournalService.PHASE_COMMIT,
                FAILURES_SHOWN
            )
        ) {
            for (Map<String, Object> entry : ImportJournalService.entries(page)) {
                if (!ImportJournalService.ACTION_FAILED.equals(entry.get('action'))) {
                    continue;
                }
                Failure failure = new Failure();
                failure.recordId = (String) entry.get('id');
                failure.reason = (String) entry.get('reason');
                result.add(failure);
                if (result.size() == FAILURES_SHOWN) {
                    return result;
                }
            }
        }
        return result;
    }

    private static Integer intOf(Decimal value) {
        return value == null ? 0 : value.intValue();
    }

    /** Anything the person can fix is shown as it is; anything else is logged and summarized. */
    private static AuraHandledException asUserError(Exception caught, String context) {
        String message = caught.getMessage();
        if (
            !(caught instanceof BulkDeleteService.BulkDeleteException) &&
            !(caught instanceof QueryCompiler.QueryCompilerException) &&
            !(caught instanceof QueryFieldCatalog.QueryFieldCatalogException) &&
            !(caught instanceof ImportException)
        ) {
            ErrorLogger.log(caught, context);
            message = System.Label.Core_BulkUpdate_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
