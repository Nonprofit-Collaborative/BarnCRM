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
        return wholeNumberSetting(CHUNK_SETTING, MAX_CHUNK, MIN_CHUNK, MAX_CHUNK);
    }

    /**
     * A whole-number setting from BarnCRM Settings, held between `lowest` and `highest`; the
     * fallback when it is empty or unreadable.
     */
    public static Integer wholeNumberSetting(
        String key,
        Integer fallback,
        Integer lowest,
        Integer highest
    ) {
        Object configured = SettingsService.hasKey(key) ? SettingsService.getValue(key) : null;
        if (configured == null) {
            return fallback;
        }
        try {
            Integer value = Decimal.valueOf(String.valueOf(configured)).intValue();
            return Math.max(lowest, Math.min(value, highest));
        } catch (Exception ignored) {
            return fallback;
        }
    }

    public static Integer intOf(Decimal value) {
        return value == null ? 0 : value.intValue();
    }

    // -------------------------------------------------------------------------------------
    // What the services and the batches share
    // -------------------------------------------------------------------------------------

    /** The confirmed count a job's definition holds. */
    public static Integer confirmedCountOf(String definitionJson) {
        Map<String, Object> definition = (Map<String, Object>) JSON.deserializeUntyped(
            definitionJson
        );
        return Integer.valueOf(definition.get('confirmedCount'));
    }

    /** The object's name field, when the person may read it, for a sample. */
    public static String nameField(Schema.DescribeSObjectResult described) {
        for (Schema.SObjectField token : described.fields.getMap().values()) {
            Schema.DescribeFieldResult field = token.getDescribe();
            if (field.isNameField() && field.isAccessible()) {
                return field.getName();
            }
        }
        return null;
    }

    /**
     * How many records match, counting at most one past `ceiling`, or null when the request
     * cannot read enough rows to tell. A count past the ceiling is returned, so the caller can
     * say which limit it passed.
     */
    public static Integer countWithin(String queryJson, Integer ceiling, Integer margin) {
        Integer headroom = Limits.getLimitQueryRows() - Limits.getQueryRows() - margin;
        Integer cap = Math.min(ceiling + 1, headroom);
        Integer count = QueryCompiler.count(queryJson, cap);
        return count >= cap && cap <= ceiling ? null : count;
    }

    /** Starts the job's batch at the chunk size stamped on it, and records the batch's job. */
    public static Import_Batch__c launch(Database.Batchable<SObject> work, Import_Batch__c job) {
        Id asyncJobId = Database.executeBatch(work, job.Chunk_Size__c.intValue());
        job.Job_Id__c = asyncJobId;
        Database.update(
            new Import_Batch__c(Id = job.Id, Job_Id__c = asyncJobId),
            AccessLevel.SYSTEM_MODE
        );
        return job;
    }

    /** The definition a job stored when it started, read in system mode (ADR-0021). */
    public static String definitionOf(Id jobId) {
        return [
            SELECT Operation_JSON__c
            FROM Import_Batch__c
            WHERE Id = :jobId
            WITH SYSTEM_MODE
            LIMIT 1
        ]
        .Operation_JSON__c;
    }

    /** The records a job reads: at most the confirmed number, in Id order, as the person. */
    public static Database.QueryLocator locatorFor(String queryJson, Integer confirmed) {
        QueryCompiler.Compiled selection = QueryCompiler.compileSelection(
            queryJson,
            new Set<String>{ 'Id' },
            null
        );
        selection.binds.put('confirmed', confirmed);
        return Database.getQueryLocatorWithBinds(
            selection.soql + ' ORDER BY Id LIMIT :confirmed',
            selection.binds,
            AccessLevel.USER_MODE
        );
    }

    /** A locator that reads no record, so a job that could not start still finishes. */
    public static Database.QueryLocator noRecords(Id jobId) {
        return Database.getQueryLocatorWithBinds(
            'SELECT Id FROM Import_Batch__c WHERE Id = :owner AND Id = NULL',
            new Map<String, Object>{ 'owner' => jobId },
            AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * Whether the platform stopped any chunk of a batch. A governor limit cannot be caught, so
     * the job's own error count is the one record of it (R-IB8). `errorsForTest`, when set,
     * stands for that count, which a test cannot bring about for real.
     */
    public static Boolean chunkStopped(Database.BatchableContext context, Integer errorsForTest) {
        if (errorsForTest != null) {
            return errorsForTest > 0;
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

    /** The job as a finishing batch reads it: its run log so far and its count. */
    public static Import_Batch__c forFinish(Id jobId) {
        return [
            SELECT Id, Run_Log__c, Row_Count__c
            FROM Import_Batch__c
            WHERE Id = :jobId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
    }

    /**
     * The run log a finishing bulk job writes: the lines before, why it stopped (`stoppedLine`,
     * or null), what it did (`finishedLine`), how many confirmed records the platform stopped it
     * reaching, and whether the journal missed anything. Cut to the field's size from the start.
     */
    public static String finalLog(
        Import_Batch__c job,
        String stoppedLine,
        String finishedLine,
        Boolean platformStopped,
        Integer counted,
        Boolean journalIncomplete
    ) {
        List<String> lines = new List<String>();
        if (String.isNotBlank(job.Run_Log__c)) {
            lines.add(job.Run_Log__c);
        }
        if (String.isNotBlank(stoppedLine)) {
            lines.add(stoppedLine);
        }
        lines.add(finishedLine);
        Integer missed = platformStopped == true ? notReached(job.Row_Count__c, counted) : 0;
        if (missed > 0) {
            lines.add(
                String.format(
                    System.Label.Core_BulkUpdate_LogNotReached,
                    new List<Object>{ missed.format() }
                )
            );
        }
        if (journalIncomplete == true) {
            lines.add(System.Label.Core_BulkUpdate_LogJournalIncomplete);
        }
        return String.join(lines, '\n').right(32768);
    }

    /**
     * How many of the confirmed records a job stopped by the platform never reached: the
     * confirmed count less every record it counted an outcome for. An upper bound, since a
     * record deleted after the confirmation was never there to reach.
     */
    public static Integer notReached(Decimal confirmed, Integer counted) {
        if (confirmed == null) {
            return 0;
        }
        return Math.max(0, confirmed.intValue() - (counted == null ? 0 : counted));
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
