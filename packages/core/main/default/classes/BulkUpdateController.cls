/**
 * What the bulk update panel and its list in Data jobs read and write (C-35, canonical model
 * Section 29E, ADR-0077 bulk update).
 *
 * Every method requires the Bulk Update Records custom permission and, because every bulk update
 * starts from a Find query, Find and Export Records (R-BU6). Neither grants record access: the
 * query is compiled and counted as the person, and every record is saved in their own mode. A
 * person sees and undoes their own bulk updates; one who manages BarnCRM Settings may also list
 * and undo everyone's (`DataJobs`). Jobs are read in user mode; the progress of a running job is
 * read from its AsyncApexJob in system mode, filtered by the job identifier the job record holds.
 */
public with sharing class BulkUpdateController {
    public static final String PERMISSION = 'Bulk_Update_Records';
    private static final Integer RECENT_JOBS = 10;
    /** Query rows left free for the reads around Super Transform's count. */
    private static final Integer COUNT_MARGIN = 100;
    private static final String JOB_FIELDS =
        'Id, Name, Status__c, Is_Dry_Run__c, Operation__c, Operation_JSON__c, Row_Count__c, ' +
        'Rows_Updated__c, Rows_Matched__c, Rows_Rejected__c, Run_Log__c, Started_At__c, ' +
        'Completed_At__c, Undo_Deadline__c, Job_Id__c';

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
        public List<DataJobs.Failure> failures;
    }

    /** The tab: whether the person may, the most changes, and the recent bulk updates. */
    public class BulkUpdatePage {
        @AuraEnabled
        public Boolean allowed;
        @AuraEnabled
        public Integer maxChanges;
        /** Whether the person may list everyone's bulk updates, not only their own. */
        @AuraEnabled
        public Boolean canSeeEveryone;
        @AuraEnabled
        public List<JobView> jobs;
    }

    /**
     * The person's recent bulk updates, or everyone's when asked for by someone who manages
     * BarnCRM Settings. A person without the permissions gets an empty page that says so,
     * rather than an error, because Data jobs shows the list to all.
     */
    @AuraEnabled
    public static BulkUpdatePage getPage(Boolean everyone) {
        try {
            BulkUpdatePage page = new BulkUpdatePage();
            page.allowed = hasPermission();
            page.jobs = new List<JobView>();
            if (!page.allowed) {
                return page;
            }
            page.maxChanges = BulkUpdateService.MAX_CHANGES;
            page.canSeeEveryone = DataJobs.canSeeEveryone();
            for (
                Import_Batch__c job : DataJobs.read(
                    JOB_FIELDS,
                    BulkUpdateService.OPERATION_UPDATE,
                    null,
                    RECENT_JOBS,
                    everyone
                )
            ) {
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

    /** How many records Super Transform's conditions match, against the run limit (C-50). */
    public class MatchCount {
        /** The records that match; null when there are too many to count in one request. */
        @AuraEnabled
        public Integer count;
        @AuraEnabled
        public Integer runLimit;
        /** True when more records match than one run may change (R-BU2). */
        @AuraEnabled
        public Boolean overLimit;
        @AuraEnabled
        public String objectLabel;
    }

    /**
     * Super Transform's object picker (C-50): every object Find offers that a bulk update may
     * write, by label. Cached per user in the browser.
     */
    @AuraEnabled(cacheable=true)
    public static List<FindController.Option> getObjects() {
        try {
            requirePermission();
            List<FindController.Option> writable = new List<FindController.Option>();
            for (FindController.Option option : FindController.listObjects()) {
                if (BulkUpdateFields.isWritable(option.value)) {
                    writable.add(option);
                }
            }
            return writable;
        } catch (Exception caught) {
            throw asUserError(caught, 'Super Transform objects');
        }
    }

    /**
     * Super Transform's live count (C-50): how many records the query document matches now,
     * counted as the person, at most one past the run limit. Zero is an answer, not a refusal.
     */
    @AuraEnabled
    public static MatchCount countMatches(String queryJson) {
        try {
            requirePermission();
            Schema.SObjectType type = BulkUpdateFields.writableObject(
                QueryCompiler.parse(queryJson).objectName
            );
            MatchCount result = new MatchCount();
            result.runLimit = BulkUpdateService.runLimit();
            result.count = DataJobs.countWithin(queryJson, result.runLimit, COUNT_MARGIN);
            result.overLimit = result.count == null || result.count > result.runLimit;
            result.objectLabel = type.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getLabelPlural();
            return result;
        } catch (Exception caught) {
            throw asUserError(caught, 'Super Transform count');
        }
    }

    /**
     * Super Transform's preview (C-50): the count and the first 25 records before and after,
     * worked out by the code the run uses, each value it would leave alone marked unchanged.
     */
    @AuraEnabled
    public static BulkUpdateService.Preview previewSample(String queryJson, String changesJson) {
        try {
            requirePermission();
            return BulkUpdateService.preview(
                queryJson,
                changesJson,
                BulkUpdateService.MAX_SAMPLE_SIZE
            );
        } catch (Exception caught) {
            throw asUserError(caught, 'Super Transform preview');
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

    private static Import_Batch__c requireJob(String jobId) {
        Import_Batch__c found = DataJobs.find(
            JOB_FIELDS,
            BulkUpdateService.OPERATION_UPDATE,
            jobId
        );
        if (found == null) {
            throw new BulkUpdateFields.BulkUpdateException(
                System.Label.Core_BulkUpdate_ErrorNotBulkUpdate
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
        view.updated = DataJobs.intOf(job.Rows_Updated__c);
        view.unchanged = DataJobs.intOf(job.Rows_Matched__c);
        view.failed = DataJobs.intOf(job.Rows_Rejected__c);
        view.runLog = job.Run_Log__c;
        view.startedAt = job.Started_At__c;
        view.undoDeadline = job.Undo_Deadline__c;
        view.running = state.running;
        view.chunksDone = state.chunksDone;
        view.chunksTotal = state.chunksTotal;
        view.canUndo = String.isBlank(state.refusal);
        view.updatesToUndo = view.updated;
        // A job aborted, or stopped before its finish counted, saved records it never counted:
        // the undo's own count (from the journal) is the number to confirm.
        if (view.canUndo && view.updated == 0) {
            ImportUndoService.Preview undoPreview = ImportUndoService.preview(job.Id);
            view.canUndo = undoPreview.allowed;
            view.updatesToUndo = undoPreview.updates;
        }
        view.objectLabel = objectLabel(job.Operation_JSON__c);
        view.failures = detail && view.failed > 0
            ? DataJobs.failures(job.Id)
            : new List<DataJobs.Failure>();
        return view;
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

    private static AuraHandledException asUserError(Exception caught, String context) {
        return DataJobs.userError(
            caught,
            context,
            caught instanceof BulkUpdateFields.BulkUpdateException
        );
    }
}
