/**
 * What the bulk update and bulk delete controllers share about their jobs (C-35, C-37): which
 * jobs a person sees, a job's state read once, its first refusals, and the chunk size.
 *
 * A person sees their own jobs. A person who manages BarnCRM Settings may also ask for
 * everyone's, to look after a job someone else started. Jobs are read in user mode; a running
 * job's AsyncApexJob is read once, in system mode, by the identifier the job record holds.
 */
public with sharing class DataJobs {
    /** Who may see and undo every person's jobs: whoever manages BarnCRM Settings. */
    public static final String EVERYONE_PERMISSION = 'Manage_BarnCRM_Settings';
    /** How many refusals a job view lists. */
    public static final Integer FAILURES_SHOWN = 20;
    /** Records a chunk saves or deletes by default, and the most: one journal page (R-IJ1). */
    public static final Integer MAX_CHUNK = 200;
    /** The fewest records a chunk may hold. */
    public static final Integer MIN_CHUNK = 10;
    private static final String CHUNK_SETTING = 'Bulk_Chunk_Size__c';

    /** A record the platform refused, and why. */
    public class Failure {
        @AuraEnabled
        public String recordId;
        @AuraEnabled
        public String reason;
    }

    /** A job's state as the page shows it, from one read of its AsyncApexJob. */
    public class State {
        public String status;
        public Boolean running;
        /** Why it cannot be undone, or blank when it can. */
        public String refusal;
        public Integer chunksDone;
        public Integer chunksTotal;
    }

    /** Whether the running user may see everyone's jobs. */
    public static Boolean canSeeEveryone() {
        return FeatureManagement.checkPermission(EVERYONE_PERMISSION);
    }

    /**
     * Jobs of one operation, newest first, read as the person: their own, or everyone's when
     * asked for and allowed.
     */
    public static List<Import_Batch__c> read(
        String fields,
        String operation,
        Id jobId,
        Integer howMany,
        Boolean everyone
    ) {
        Boolean all = everyone == true && canSeeEveryone();
        return Database.queryWithBinds(
            'SELECT ' +
                fields +
                ' FROM Import_Batch__c WHERE Operation__c = :operation' +
                (all ? '' : ' AND Committed_By__c = :me') +
                (jobId == null ? '' : ' AND Id = :jobId') +
                ' ORDER BY CreatedDate DESC LIMIT :howMany',
            new Map<String, Object>{
                'operation' => operation,
                'howMany' => howMany,
                'jobId' => jobId,
                'me' => UserInfo.getUserId()
            },
            AccessLevel.USER_MODE
        );
    }

    /** One job the person may see, or null: theirs, or anyone's for someone allowed. */
    public static Import_Batch__c find(String fields, String operation, String jobId) {
        Id parsed;
        try {
            parsed = String.isBlank(jobId) ? null : Id.valueOf(jobId);
        } catch (Exception notAnId) {
            parsed = null;
        }
        if (parsed == null) {
            return null;
        }
        List<Import_Batch__c> found = read(fields, operation, parsed, 1, true);
        return found.isEmpty() ? null : found[0];
    }

    /**
     * The job's status, whether it runs, why it cannot be undone and, when `withProgress`, its
     * chunks: the AsyncApexJob is read at most once for all of them.
     */
    public static State stateOf(Import_Batch__c job, Boolean withProgress) {
        AsyncApexJob asyncJob = ImportBatchService.asyncJobOf(job);
        State state = new State();
        state.status = ImportUndoService.effectiveStatus(
            job,
            ImportBatchService.isRunning(job, asyncJob)
        );
        state.running = ImportBatchService.STATUS_COMMITTING.equals(state.status);
        state.refusal = ImportUndoService.refusal(job, state.status);
        if (withProgress == true && state.running && asyncJob != null) {
            state.chunksDone = asyncJob.JobItemsProcessed;
            state.chunksTotal = asyncJob.TotalJobItems;
        }
        return state;
    }

    /** The first refusals the job journaled, with the platform's reasons, wherever they fell. */
    public static List<Failure> failures(Id jobId) {
        List<Failure> result = new List<Failure>();
        for (
            Map<String, Object> entry : ImportJournalService.firstWithAction(
                jobId,
                ImportJournalService.PHASE_COMMIT,
                ImportJournalService.ACTION_FAILED,
                FAILURES_SHOWN
            )
        ) {
            Failure failure = new Failure();
            failure.recordId = (String) entry.get('id');
            failure.reason = (String) entry.get('reason');
            result.add(failure);
        }
        return result;
    }

    /**
     * Records per chunk for bulk update and bulk delete, from BarnCRM Settings: 200 when empty,
     * held between MIN_CHUNK and MAX_CHUNK. A smaller chunk lets a job pass where the org's
     * automation runs out of limits on 200 records at a time.
     */
    public static Integer chunkSize() {
        Object configured = SettingsService.hasKey(CHUNK_SETTING)
            ? SettingsService.getValue(CHUNK_SETTING)
            : null;
        if (configured == null) {
            return MAX_CHUNK;
        }
        try {
            Integer records = Decimal.valueOf(String.valueOf(configured)).intValue();
            return Math.max(MIN_CHUNK, Math.min(records, MAX_CHUNK));
        } catch (Exception ignored) {
            return MAX_CHUNK;
        }
    }

    public static Integer intOf(Decimal value) {
        return value == null ? 0 : value.intValue();
    }

    /**
     * Anything the person can fix (`known`, or a query or field refusal, or an import error) is
     * shown as it is; anything else is logged and summarized.
     */
    public static AuraHandledException userError(Exception caught, String context, Boolean known) {
        String message = caught.getMessage();
        if (
            known != true &&
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
