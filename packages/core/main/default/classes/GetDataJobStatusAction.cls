/**
 * The Get Data Job Status action (Q-14): where an import, bulk update or bulk delete has got
 * to, for a Flow or for a customer's own AI agent. BarnCRM ships no AI (ADR-NEXT,
 * agent-ready Core actions).
 *
 * It adds no rule of its own: it reads the job the way the import results screen does
 * (ImportBatchSelector, in user mode, so a job the running user cannot see is not found) and
 * reports the status that screen shows (ImportUndoService.effectiveStatus, so a run whose
 * job the platform aborted reads as failed rather than running for ever). It never starts,
 * commits or undoes a job: that stays a decision a person makes on the screen.
 *
 * `global` because only a global invocable method is offered to a Flow or an agent in a
 * subscriber org; every variable is permanent once the package is managed.
 *
 * Bulk: one query for every job named in the call. Only a job still marked as running costs
 * a further check of its background job, as on the results screen.
 */
global with sharing class GetDataJobStatusAction {
    private static final String OPERATION_IMPORT = 'Import';

    /** One job asked about. */
    global class Request {
        @InvocableVariable(
            label='Data Job Id'
            description='Optional. The record id of the import, bulk update or bulk delete. Leave empty to get the most recent import the running user can see.'
        )
        global String jobId;
    }

    /** Where one job stands, in the same position as the request. */
    global class Result {
        @InvocableVariable(label='Data Job Id' description='The job\'s record id.')
        global String jobId;

        @InvocableVariable(
            label='Name'
            description='The job\'s name, as shown on the import results screen.'
        )
        global String name;

        @InvocableVariable(
            label='Operation'
            description='What the job does: Import, Update (a bulk update) or Delete (a bulk delete).'
        )
        global String operation;

        @InvocableVariable(
            label='Status'
            description='One of: Draft, Parsing, Dry run, Dry run complete, Committing, Complete, Failed, Undoing, Undone, Undo failed. Dry run and Committing mean it is still running.'
        )
        global String status;

        @InvocableVariable(
            label='Is Dry Run'
            description='True when the job only checked the rows and saved nothing.'
        )
        global Boolean isDryRun;

        @InvocableVariable(label='File Name' description='The name of the file imported, if any.')
        global String fileName;

        @InvocableVariable(label='Row Count' description='How many rows the job has.')
        global Integer rowCount;

        @InvocableVariable(label='Rows Created' description='How many rows created a record.')
        global Integer rowsCreated;

        @InvocableVariable(label='Rows Updated' description='How many rows updated a record.')
        global Integer rowsUpdated;

        @InvocableVariable(
            label='Rows Matched'
            description='How many rows matched an existing record and changed nothing.'
        )
        global Integer rowsMatched;

        @InvocableVariable(
            label='Rows Rejected'
            description='How many rows were refused. The reasons are on the import results screen.'
        )
        global Integer rowsRejected;

        @InvocableVariable(label='Started At' description='When the job started.')
        global Datetime startedAt;

        @InvocableVariable(
            label='Completed At'
            description='When the job finished. Empty while it is running.'
        )
        global Datetime completedAt;

        @InvocableVariable(
            label='Undo Deadline'
            description='Until when the job can still be undone on the import results screen. Empty when it cannot be undone.'
        )
        global Datetime undoDeadline;

        @InvocableVariable(
            label='Error Message'
            description='Empty when the job was found. Otherwise why not, in plain words to show the user.'
        )
        global String errorMessage;
    }

    /**
     * Reports each job asked about, in the order sent. One that cannot be found is answered
     * with an error message rather than failing the others.
     *
     * @param requests one per job
     * @return one result per request, in the same order
     */
    @InvocableMethod(
        label='Get Data Job Status'
        description='Reports the status and row counts of a BarnCRM import, bulk update or bulk delete. With no id, reports the most recent import. Read only: never starts, commits or undoes a job.'
        category='BarnCRM'
    )
    global static List<Result> getStatus(List<Request> requests) {
        List<Request> asked = requests == null ? new List<Request>() : requests;
        List<Result> results = new List<Result>();
        try {
            Map<Id, Import_Batch__c> jobs = jobsFor(asked);
            for (Request request : asked) {
                Boolean latest = namesNoJob(request);
                Id jobId = idOf(request);
                Import_Batch__c job = latest || jobId != null ? jobs.get(jobId) : null;
                results.add(job == null ? notFound(latest) : toResult(job));
            }
        } catch (QueryException denied) {
            results = allFailed(asked.size(), Label.Core_AgentActions_NoAccess);
        } catch (Exception failed) {
            ErrorLogger.log(failed, Label.Core_AgentActions_ErrorContext);
            results = allFailed(asked.size(), Label.Core_AgentActions_Unexpected);
        }
        return results;
    }

    /**
     * Every job named, by id, read once; the most recent import under a null key when any
     * request names none.
     */
    private static Map<Id, Import_Batch__c> jobsFor(List<Request> asked) {
        Set<Id> jobIds = new Set<Id>();
        Boolean wantsLatest = false;
        for (Request request : asked) {
            Id jobId = idOf(request);
            if (jobId != null) {
                jobIds.add(jobId);
            }
            wantsLatest = wantsLatest || namesNoJob(request);
        }
        Map<Id, Import_Batch__c> result = new Map<Id, Import_Batch__c>(
            ImportBatchSelector.selectByIds(jobIds)
        );
        if (wantsLatest) {
            List<Import_Batch__c> latest = ImportBatchSelector.selectRecent(1);
            result.put(null, latest.isEmpty() ? null : latest[0]);
        }
        return result;
    }

    private static Result toResult(Import_Batch__c job) {
        Result result = new Result();
        result.jobId = job.Id;
        result.name = job.Name;
        result.operation = String.isBlank(job.Operation__c) ? OPERATION_IMPORT : job.Operation__c;
        result.status = ImportUndoService.effectiveStatus(job);
        result.isDryRun = job.Is_Dry_Run__c == true;
        result.fileName = job.File_Name__c;
        result.rowCount = intOf(job.Row_Count__c);
        result.rowsCreated = intOf(job.Rows_Created__c);
        result.rowsUpdated = intOf(job.Rows_Updated__c);
        result.rowsMatched = intOf(job.Rows_Matched__c);
        result.rowsRejected = intOf(job.Rows_Rejected__c);
        result.startedAt = job.Started_At__c;
        result.completedAt = job.Completed_At__c;
        result.undoDeadline = job.Undo_Deadline__c;
        return result;
    }

    private static Result notFound(Boolean latest) {
        Result result = new Result();
        result.errorMessage = latest
            ? Label.Core_AgentActions_NoDataJobs
            : Label.Core_AgentActions_DataJobNotFound;
        return result;
    }

    private static List<Result> allFailed(Integer howMany, String message) {
        List<Result> results = new List<Result>();
        for (Integer i = 0; i < howMany; i++) {
            Result result = new Result();
            result.errorMessage = message;
            results.add(result);
        }
        return results;
    }

    /** True when the request names no job, so the most recent import is wanted. */
    private static Boolean namesNoJob(Request request) {
        return request == null || String.isBlank(request.jobId);
    }

    /**
     * The data job id asked for, or null when none was given or the text names no data job.
     * Text that is not a data job id is answered as not found, never as the latest import.
     */
    private static Id idOf(Request request) {
        if (namesNoJob(request)) {
            return null;
        }
        try {
            Id candidate = Id.valueOf(request.jobId.trim());
            return candidate.getSObjectType() == Import_Batch__c.SObjectType ? candidate : null;
        } catch (StringException notAnId) {
            return null;
        }
    }

    private static Integer intOf(Decimal value) {
        return value == null ? 0 : value.intValue();
    }
}
