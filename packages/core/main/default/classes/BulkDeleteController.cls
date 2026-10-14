/**
 * What the bulk delete panel and its list on the Bulk Update tab read and write (C-37,
 * canonical model R-BD1 to R-BD6, ADR-0091).
 *
 * Every method requires the Bulk Delete Records custom permission and, because every bulk
 * delete starts from a Find query, Find and Export Records (R-BD6). Neither grants record
 * access: the query is compiled and counted as the person, and every record is deleted in their
 * own mode. A person sees and undoes their own bulk deletes; one who manages BarnCRM Settings
 * may also list and undo everyone's (`DataJobs`). Jobs are read in user mode; the progress of a
 * running job is read from its AsyncApexJob in system mode, filtered by the job identifier the
 * job record holds.
 */
public with sharing class BulkDeleteController {
    public static final String PERMISSION = 'Bulk_Delete_Records';
    private static final Integer RECENT_JOBS = 10;
    private static final String JOB_FIELDS =
        'Id, Name, Status__c, Is_Dry_Run__c, Operation__c, Operation_JSON__c, Row_Count__c, ' +
        'Rows_Deleted__c, Rows_Rejected__c, Run_Log__c, Started_At__c, Completed_At__c, ' +
        'Undo_Deadline__c, Job_Id__c';

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
        public List<DataJobs.Failure> failures;
    }

    /** The list on the Bulk Update tab: whether the person may, and recent jobs. */
    public class BulkDeletePage {
        @AuraEnabled
        public Boolean allowed;
        /** Whether the person may list everyone's bulk deletes, not only their own. */
        @AuraEnabled
        public Boolean canSeeEveryone;
        @AuraEnabled
        public List<JobView> jobs;
    }

    /**
     * The person's recent bulk deletes, or everyone's when asked for by someone who manages
     * BarnCRM Settings. A person without the permission gets an empty page that says so, rather
     * than an error, because the Bulk Update tab shows the list to all.
     */
    @AuraEnabled
    public static BulkDeletePage getPage(Boolean everyone) {
        try {
            BulkDeletePage page = new BulkDeletePage();
            page.allowed = hasPermission();
            page.jobs = new List<JobView>();
            if (!page.allowed) {
                return page;
            }
            page.canSeeEveryone = DataJobs.canSeeEveryone();
            for (
                Import_Batch__c job : DataJobs.read(
                    JOB_FIELDS,
                    BulkDeleteService.OPERATION_DELETE,
                    null,
                    RECENT_JOBS,
                    everyone
                )
            ) {
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

    /** One bulk delete with its progress and the first refusals, for polling while it runs. */
    @AuraEnabled
    public static JobView getJob(String jobId) {
        try {
            requirePermission();
            return toView(requireJob(jobId), true);
        } catch (Exception caught) {
            throw asUserError(caught, 'Read a bulk delete');
        }
    }

    /** Undoes a bulk delete once the person confirms how many records it brings back (R-BD5). */
    @AuraEnabled
    public static JobView undo(String jobId, Integer confirmedRecords) {
        try {
            requirePermission();
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

    private static Import_Batch__c requireJob(String jobId) {
        Import_Batch__c found = DataJobs.find(
            JOB_FIELDS,
            BulkDeleteService.OPERATION_DELETE,
            jobId
        );
        if (found == null) {
            throw new BulkDeleteService.BulkDeleteException(
                System.Label.Core_BulkDelete_ErrorNotBulkDelete
            );
        }
        return found;
    }

    private static JobView toView(Import_Batch__c job, Boolean detail) {
        DataJobs.State state = DataJobs.stateOf(job, detail);
        JobView view = new JobView();
        view.recordId = job.Id;
        view.name = job.Name;
        view.status = state.status;
        view.matched = DataJobs.intOf(job.Row_Count__c);
        view.deleted = DataJobs.intOf(job.Rows_Deleted__c);
        view.failed = DataJobs.intOf(job.Rows_Rejected__c);
        view.runLog = job.Run_Log__c;
        view.startedAt = job.Started_At__c;
        view.undoDeadline = job.Undo_Deadline__c;
        view.running = state.running;
        view.chunksDone = state.chunksDone;
        view.chunksTotal = state.chunksTotal;
        Boolean undoable = String.isBlank(state.refusal);
        view.canUndo = undoable && view.deleted > 0;
        view.recordsToUndo = view.deleted;
        // A job aborted, or stopped before its finish counted, deleted records it never
        // counted: the undo's own count (from the journal) is the number to confirm.
        if (view.deleted == 0 && undoable) {
            BulkDeleteService.UndoPreview undoPreview = BulkDeleteService.undoPreview(job.Id);
            view.canUndo = undoPreview.allowed;
            view.recordsToUndo = undoPreview.records;
        }
        view.failures = detail && view.failed > 0
            ? DataJobs.failures(job.Id)
            : new List<DataJobs.Failure>();
        return view;
    }

    private static AuraHandledException asUserError(Exception caught, String context) {
        return DataJobs.userError(
            caught,
            context,
            caught instanceof BulkDeleteService.BulkDeleteException
        );
    }
}
