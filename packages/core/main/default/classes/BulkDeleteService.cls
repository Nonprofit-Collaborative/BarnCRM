/**
 * Bulk delete (C-37, canonical model Section 29E, R-BD1 to R-BD6, ADR-NEXT
 * `NEXT-bulk-delete-from-a-find-query-with-undelete.md`): every record a Find query returns,
 * checked and counted as the person before anything is deleted.
 *
 * Everything the person sends is checked here, as them: the query document through
 * `QueryCompiler` (no SOQL text is accepted), and the object through `DataProtectedFields` and
 * the person's own describe. The job record is the package's own bookkeeping, written in system
 * mode (ADR-0021); every record is deleted in the person's own mode, by `BulkDeleteBatch`.
 */
public with sharing class BulkDeleteService {
    public static final String OPERATION_DELETE = 'Delete';
    /** How many records the preview names. */
    public static final Integer SAMPLE_SIZE = 5;
    /** Records a chunk deletes, so one journal page holds one chunk (R-IJ1). */
    public static final Integer MAX_CHUNK = 200;
    /** The run limit's default (R-BD2). */
    public static final Integer DEFAULT_RUN_LIMIT = 10000;
    /** The run limit's highest value: what one request can count exactly (R-BD2). */
    public static final Integer MAX_RUN_LIMIT = 48000;
    /** How long the platform keeps a deleted record in the Recycle Bin. */
    public static final Integer RECYCLE_BIN_DAYS = 15;
    /** The most kinds of child record the preview names. */
    private static final Integer MAX_CASCADES = 20;
    /** Query rows left free for the reads around a count. */
    private static final Integer COUNT_MARGIN = 100;
    private static final Integer DEFINITION_VERSION = 1;

    /** Raised for anything the person can fix; the message is for them. */
    public class BulkDeleteException extends Exception {
    }

    /** A checked bulk delete: the query document and its object. */
    public class Plan {
        public String queryJson;
        public String objectName;
        public Schema.SObjectType objectType;
        /** The object's name field, when the person may read it; null otherwise. */
        public String nameField;

        /** What a job keeps (R-BD1): the query document and the confirmed count. */
        public String definition(Integer confirmedCount) {
            return JSON.serialize(
                new Map<String, Object>{
                    'version' => DEFINITION_VERSION,
                    'query' => JSON.deserializeUntyped(queryJson),
                    'confirmedCount' => confirmedCount
                }
            );
        }

        /** The fields each chunk reads: the Id and the name the journal keeps. */
        public Set<String> readFields() {
            Set<String> names = new Set<String>{ 'Id' };
            if (nameField != null) {
                names.add(nameField);
            }
            return names;
        }

        /** A record's name for the preview and the journal, or its Id. */
        public String nameOf(SObject record) {
            Object name = nameField == null ? null : record.get(nameField);
            return name == null ? String.valueOf(record.Id) : String.valueOf(name);
        }
    }

    /** One record of the preview's sample. */
    public class SampleRecord {
        @AuraEnabled
        public String recordId;
        @AuraEnabled
        public String name;
    }

    /** What a bulk delete would do. */
    public class Preview {
        /** How many records match now: the number the person confirms. */
        @AuraEnabled
        public Integer count;
        @AuraEnabled
        public Integer runLimit;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public String soql;
        @AuraEnabled
        public List<SampleRecord> sample = new List<SampleRecord>();
        /** The kinds of child record the platform deletes with each record (R-BD2). */
        @AuraEnabled
        public List<String> cascades = new List<String>();
        /** The last moment an undo could run, if the job started now. */
        @AuraEnabled
        public Datetime undoDeadline;
    }

    // -------------------------------------------------------------------------------------
    // Checking
    // -------------------------------------------------------------------------------------

    /** Checks a query document as the running user (R-BD4). */
    public static Plan plan(String queryJson) {
        Schema.DescribeSObjectResult described;
        try {
            described = QueryFieldCatalog.describeObject(QueryCompiler.parse(queryJson).objectName);
        } catch (QueryFieldCatalog.QueryFieldCatalogException refused) {
            throw new BulkDeleteException(refused.getMessage());
        }
        String reason = objectReason(described);
        if (reason != null) {
            throw new BulkDeleteException(
                String.format(
                    System.Label.Core_BulkDelete_ErrorObject,
                    new List<Object>{ described.getLabelPlural(), reason }
                )
            );
        }
        Plan result = new Plan();
        result.queryJson = queryJson;
        result.objectType = described.getSObjectType();
        result.objectName = described.getName();
        result.nameField = nameField(described);
        return result;
    }

    /** Checks a job's stored definition again, as the person running the job. */
    public static Plan planFromDefinition(String definitionJson) {
        Map<String, Object> definition = (Map<String, Object>) JSON.deserializeUntyped(
            definitionJson
        );
        return plan(JSON.serialize(definition.get('query')));
    }

    /** The confirmed count a job's definition holds. */
    public static Integer confirmedCountOf(String definitionJson) {
        Map<String, Object> definition = (Map<String, Object>) JSON.deserializeUntyped(
            definitionJson
        );
        return Integer.valueOf(definition.get('confirmedCount'));
    }

    /** Why no record of this object may be bulk deleted, or null when its records may be. */
    @TestVisible
    private static String objectReason(Schema.DescribeSObjectResult described) {
        String refused = DataProtectedFields.objectRefusal(described.getSObjectType());
        if (refused != null) {
            return refused;
        }
        if (!described.isDeletable()) {
            return System.Label.Core_BulkDelete_ReasonNoDelete;
        }
        if (!described.isUndeletable()) {
            return System.Label.Core_BulkDelete_ReasonNoUndelete;
        }
        return null;
    }

    // -------------------------------------------------------------------------------------
    // Preview
    // -------------------------------------------------------------------------------------

    /**
     * Counts the records the query matches now, names the first few, and lists what the
     * platform deletes with them. The count is the number the person confirms; nothing is
     * deleted.
     */
    public static Preview preview(String queryJson) {
        Plan checked = plan(queryJson);
        Integer ceiling = runLimit();
        Preview result = new Preview();
        result.count = countWithin(checked, ceiling);
        if (result.count > ceiling) {
            throw new BulkDeleteException(overLimit(ceiling));
        }
        result.runLimit = ceiling;
        Schema.DescribeSObjectResult described = checked.objectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
        );
        result.objectLabel = described.getLabelPlural();
        result.cascades = cascades(described);
        result.undoDeadline = undoDeadlineFrom(Datetime.now());
        QueryCompiler.Compiled sample = QueryCompiler.compileSelection(
            queryJson,
            checked.readFields(),
            null
        );
        sample.binds.put('sampleSize', SAMPLE_SIZE);
        result.soql = sample.display;
        for (
            SObject record : Database.queryWithBinds(
                sample.soql + ' ORDER BY Id LIMIT :sampleSize',
                sample.binds,
                AccessLevel.USER_MODE
            )
        ) {
            SampleRecord shown = new SampleRecord();
            shown.recordId = record.Id;
            shown.name = checked.nameOf(record);
            result.sample.add(shown);
        }
        return result;
    }

    /**
     * The kinds of child record the platform deletes with a record of this object, by plural
     * label, sorted: child relationships marked cascade delete whose object the person may read.
     */
    @TestVisible
    private static List<String> cascades(Schema.DescribeSObjectResult described) {
        Set<String> labels = new Set<String>();
        for (Schema.ChildRelationship child : described.getChildRelationships()) {
            if (!child.isCascadeDelete() || child.getChildSObject() == null) {
                continue;
            }
            Schema.DescribeSObjectResult childObject = child.getChildSObject()
                .getDescribe(SObjectDescribeOptions.DEFERRED);
            if (childObject.isAccessible() && childObject.isQueryable()) {
                labels.add(childObject.getLabelPlural());
            }
        }
        List<String> sorted = new List<String>(labels);
        sorted.sort();
        while (sorted.size() > MAX_CASCADES) {
            sorted.remove(sorted.size() - 1);
        }
        return sorted;
    }

    /**
     * How many records match, counting at most one past `ceiling`. Refused when none match, or
     * when the request cannot read enough rows to tell; a count past the ceiling is returned,
     * so the caller can say which limit it passed.
     */
    public static Integer countWithin(Plan checked, Integer ceiling) {
        Integer headroom = Limits.getLimitQueryRows() - Limits.getQueryRows() - COUNT_MARGIN;
        Integer cap = Math.min(ceiling + 1, headroom);
        Integer count = QueryCompiler.count(checked.queryJson, cap);
        if (count >= cap && cap <= ceiling) {
            throw new BulkDeleteException(System.Label.Core_BulkUpdate_ErrorTooManyToCount);
        }
        if (count == 0) {
            throw new BulkDeleteException(System.Label.Core_BulkDelete_ErrorNothingMatches);
        }
        return count;
    }

    // -------------------------------------------------------------------------------------
    // Start
    // -------------------------------------------------------------------------------------

    /**
     * Starts a bulk delete of at most `confirmedCount` records after counting again: refused
     * when more records match now than were confirmed, or than the run limit allows (R-BD2).
     */
    public static Import_Batch__c start(String queryJson, Integer confirmedCount) {
        Plan checked = plan(queryJson);
        if (confirmedCount == null || confirmedCount < 1) {
            throw new BulkDeleteException(System.Label.Core_BulkUpdate_ErrorConfirm);
        }
        Integer ceiling = runLimit();
        if (confirmedCount > ceiling) {
            throw new BulkDeleteException(overLimit(ceiling));
        }
        Integer count = countWithin(checked, confirmedCount);
        if (count > confirmedCount) {
            throw new BulkDeleteException(
                String.format(
                    System.Label.Core_BulkDelete_ErrorMoreThanConfirmed,
                    new List<Object>{ confirmedCount.format() }
                )
            );
        }
        Import_Batch__c job = createJob(checked, count, confirmedCount);
        Id jobId = Database.executeBatch(new BulkDeleteBatch(job.Id), MAX_CHUNK);
        job.Job_Id__c = jobId;
        Database.update(
            new Import_Batch__c(Id = job.Id, Job_Id__c = jobId),
            AccessLevel.SYSTEM_MODE
        );
        return job;
    }

    /**
     * The job record, committed when it starts, with its undo deadline stamped then: the
     * earlier of the import undo window and the Recycle Bin's 15 days (R-BD2).
     */
    @TestVisible
    private static Import_Batch__c createJob(Plan checked, Integer count, Integer confirmedCount) {
        Datetime now = Datetime.now();
        Import_Batch__c job = new Import_Batch__c(
            Operation__c = OPERATION_DELETE,
            Operation_JSON__c = checked.definition(confirmedCount),
            Status__c = ImportBatchService.STATUS_COMMITTING,
            Is_Dry_Run__c = false,
            Row_Count__c = count,
            Rows_Created__c = 0,
            Rows_Updated__c = 0,
            Rows_Matched__c = 0,
            Rows_Rejected__c = 0,
            Rows_Deleted__c = 0,
            Chunk_Size__c = MAX_CHUNK,
            Started_At__c = now,
            Committed_By__c = UserInfo.getUserId(),
            Undo_Deadline__c = undoDeadlineFrom(now),
            Run_Log__c = String.format(
                System.Label.Core_BulkDelete_LogStarted,
                new List<Object>{
                    UserInfo.getName(),
                    now.format(),
                    count.format(),
                    checked.objectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                        .getLabelPlural(),
                    confirmedCount.format()
                }
            )
        );
        Database.insert(job, AccessLevel.SYSTEM_MODE);
        return job;
    }

    /** The undo deadline of a bulk delete started at `startedAt` (R-BD2). */
    public static Datetime undoDeadlineFrom(Datetime startedAt) {
        return startedAt.addDays(Math.min(ImportBatchService.undoWindowDays(), RECYCLE_BIN_DAYS));
    }

    /** The run limit from BarnCRM Settings, held between 1 and MAX_RUN_LIMIT (R-BD2). */
    public static Integer runLimit() {
        Object configured = SettingsService.hasKey('Bulk_Delete_Run_Limit__c')
            ? SettingsService.getValue('Bulk_Delete_Run_Limit__c')
            : null;
        if (configured == null) {
            return DEFAULT_RUN_LIMIT;
        }
        try {
            Integer records = Decimal.valueOf(String.valueOf(configured)).intValue();
            return Math.max(1, Math.min(records, MAX_RUN_LIMIT));
        } catch (Exception ignored) {
            return DEFAULT_RUN_LIMIT;
        }
    }

    public static String overLimit(Integer ceiling) {
        return String.format(
            System.Label.Core_BulkDelete_ErrorOverLimit,
            new List<Object>{ ceiling.format() }
        );
    }

    /** The object's name field, when the person may read it. */
    private static String nameField(Schema.DescribeSObjectResult described) {
        for (Schema.SObjectField token : described.fields.getMap().values()) {
            Schema.DescribeFieldResult field = token.getDescribe();
            if (field.isNameField() && field.isAccessible()) {
                return field.getName();
            }
        }
        return null;
    }
}
