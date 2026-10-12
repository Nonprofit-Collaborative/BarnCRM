/**
 * What the bulk update panel and the Bulk Update tab read and write (C-35, canonical model
 * Section 29E, ADR-0077 bulk update).
 *
 * Every method requires the Bulk Update Records custom permission and, because every bulk update
 * starts from a Find query, Find and Export Records (R-BU6). Neither grants record access: the
 * query is compiled and counted as the person, and every record is saved in their own mode. Jobs
 * are read in user mode; the progress of a running job is read from its AsyncApexJob in system
 * mode, filtered by the job identifier the person's own job record holds.
 */
public with sharing class BulkUpdateController {
    public static final String PERMISSION = 'Bulk_Update_Records';
    private static final Integer RECENT_JOBS = 10;
    private static final Integer FAILURES_SHOWN = 20;
    private static final String JOB_FIELDS =
        'Id, Name, Status__c, Is_Dry_Run__c, Operation__c, Operation_JSON__c, Row_Count__c, ' +
        'Rows_Updated__c, Rows_Matched__c, Rows_Rejected__c, Run_Log__c, Started_At__c, ' +
        'Completed_At__c, Undo_Deadline__c, Job_Id__c';

    /** A record the platform refused, and why. */
    public class Failure {
        @AuraEnabled
        public String recordId;
        @AuraEnabled
        public String reason;
    }

    /** One bulk update, as the page shows it. */
    public class JobView {
        @AuraEnabled
        public String recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public Integer matched;
        @AuraEnabled
        public Integer updated;
        @AuraEnabled
        public Integer unchanged;
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
        /** Chunks done and in all, while the job runs. */
        @AuraEnabled
        public Integer chunksDone;
        @AuraEnabled
        public Integer chunksTotal;
        @AuraEnabled
        public Boolean canUndo;
        /** The values an undo would put back: the number the person confirms. */
        @AuraEnabled
        public Integer updatesToUndo;
        @AuraEnabled
        public List<Failure> failures;
    }

    /** The tab: the run limit and the recent bulk updates. */
    public class Page {
        @AuraEnabled
        public Integer runLimit;
        @AuraEnabled
        public Integer maxChanges;
        @AuraEnabled
        public List<JobView> jobs;
    }

    @AuraEnabled
    public static Page getPage() {
        try {
            requirePermission();
            Page page = new Page();
            page.runLimit = BulkUpdateService.runLimit();
            page.maxChanges = BulkUpdateService.MAX_CHANGES;
            page.jobs = new List<JobView>();
            for (Import_Batch__c job : jobs(null, RECENT_JOBS)) {
                page.jobs.add(toView(job, false));
            }
            return page;
        } catch (Exception caught) {
            throw asUserError(caught, 'Bulk update page');
        }
    }

    /** The fields of the object the person may bulk update. Cached per object in the browser. */
    @AuraEnabled(cacheable=true)
    public static List<BulkUpdateFields.Target> getTargets(String objectName) {
        try {
            requirePermission();
            return BulkUpdateFields.targets(objectName);
        } catch (Exception caught) {
            throw asUserError(caught, 'Bulk update fields');
        }
    }

    /** The fields whose values may be copied into one target. */
    @AuraEnabled(cacheable=true)
    public static List<QueryFieldCatalog.PicklistOption> getCopySources(
        String objectName,
        String fieldName
    ) {
        try {
            requirePermission();
            return BulkUpdateFields.copySources(objectName, fieldName);
        } catch (Exception caught) {
            throw asUserError(caught, 'Bulk update copy sources');
        }
    }

    /** How many records match now, and five before and after. Nothing is saved. */
    @AuraEnabled
    public static BulkUpdateService.Preview preview(String queryJson, String changesJson) {
        try {
            requirePermission();
            return BulkUpdateService.preview(queryJson, changesJson);
        } catch (Exception caught) {
            throw asUserError(caught, 'Bulk update preview');
        }
    }

    /** Starts a bulk update of the number of records the person confirmed. */
    @AuraEnabled
    public static JobView start(String queryJson, String changesJson, Integer confirmedCount) {
        try {
            requirePermission();
            Import_Batch__c started = BulkUpdateService.start(
                queryJson,
                changesJson,
                confirmedCount
            );
            return toView(requireJob(started.Id), true);
        } catch (Exception caught) {
            throw asUserError(caught, 'Start a bulk update');
        }
    }

    /** One bulk update with its progress and the first refusals, for polling while it runs. */
    @AuraEnabled
    public static JobView getJob(String jobId) {
        try {
            requirePermission();
            return toView(requireJob(jobId), true);
        } catch (Exception caught) {
            throw asUserError(caught, 'Read a bulk update');
        }
    }

    /**
     * Undoes a bulk update after checking the number of values it would put back is the number
     * the person was shown (R-BU5). The undo itself is the import undo.
     */
    @AuraEnabled
    public static JobView undo(String jobId, Integer confirmedUpdates) {
        try {
            requirePermission();
            Import_Batch__c job = requireJob(jobId);
            ImportUndoService.Preview undoPreview = ImportUndoService.preview(job.Id);
            if (!undoPreview.allowed) {
                throw new BulkUpdateFields.BulkUpdateException(undoPreview.reason);
            }
            if (confirmedUpdates != undoPreview.updates) {
                throw new BulkUpdateFields.BulkUpdateException(
                    String.format(
                        System.Label.Core_Import_UndoErrorCountChanged,
                        new List<Object>{
                            String.valueOf(confirmedUpdates == null ? 0 : confirmedUpdates),
                            String.valueOf(undoPreview.updates)
                        }
                    )
                );
            }
            ImportUndoService.start(job.Id, undoPreview.total);
            return toView(requireJob(job.Id), false);
        } catch (Exception caught) {
            throw asUserError(caught, 'Undo a bulk update');
        }
    }

    /** Whether the running user may bulk update: both permissions (R-BU6). */
    public static Boolean hasPermission() {
        return FeatureManagement.checkPermission(PERMISSION) &&
            FeatureManagement.checkPermission(FindController.PERMISSION);
    }

    private static void requirePermission() {
        if (!hasPermission()) {
            throw new BulkUpdateFields.BulkUpdateException(
                System.Label.Core_BulkUpdate_ErrorNoPermission
            );
        }
    }

    /** Bulk updates the person can see, newest first, read as them. */
    private static List<Import_Batch__c> jobs(Id jobId, Integer howMany) {
        Map<String, Object> binds = new Map<String, Object>{
            'operation' => BulkUpdateService.OPERATION_UPDATE,
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
            throw new BulkUpdateFields.BulkUpdateException(
                System.Label.Core_BulkUpdate_ErrorNotBulkUpdate
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
        view.updated = intOf(job.Rows_Updated__c);
        view.unchanged = intOf(job.Rows_Matched__c);
        view.failed = intOf(job.Rows_Rejected__c);
        view.runLog = job.Run_Log__c;
        view.startedAt = job.Started_At__c;
        view.undoDeadline = job.Undo_Deadline__c;
        view.running = ImportBatchService.STATUS_COMMITTING.equals(view.status);
        view.canUndo = String.isBlank(ImportUndoService.refusal(job));
        view.updatesToUndo = view.updated;
        view.objectLabel = objectLabel(job.Operation_JSON__c);
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

    /** The plural label of the object a job's definition names, or its name if gone. */
    private static String objectLabel(String definitionJson) {
        try {
            Map<String, Object> definition = (Map<String, Object>) JSON.deserializeUntyped(
                definitionJson
            );
            String objectName = String.valueOf(
                ((Map<String, Object>) definition.get('query')).get('object')
            );
            try {
                return QueryFieldCatalog.describeObject(objectName).getLabelPlural();
            } catch (QueryFieldCatalog.QueryFieldCatalogException gone) {
                return objectName;
            }
        } catch (Exception unreadable) {
            return null;
        }
    }

    private static Integer intOf(Decimal value) {
        return value == null ? 0 : value.intValue();
    }

    /** Anything the person can fix is shown as it is; anything else is logged and summarized. */
    private static AuraHandledException asUserError(Exception caught, String context) {
        String message = caught.getMessage();
        if (
            !(caught instanceof BulkUpdateFields.BulkUpdateException) &&
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
