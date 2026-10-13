/**
 * Bulk update (C-35, canonical model Section 29E, ADR-0077 bulk update): up to five changes to
 * every record a Find query returns, checked and counted as the person before anything is
 * saved.
 *
 * Everything the person sends is checked here, as them: the query document through
 * `QueryCompiler` (no SOQL text is accepted), and each change against the object's own describe
 * through `BulkUpdateFields`. Nothing they send is used as a field name before describe has
 * found it.
 */
public with sharing class BulkUpdateService {
    public static final String OPERATION_UPDATE = 'Update';
    public static final String ACTION_SET = 'set';
    public static final String ACTION_CLEAR = 'clear';
    public static final String ACTION_COPY = 'copy';
    /** Change each record's own value with transform steps (C-37, R-BU7). */
    public static final String ACTION_TRANSFORM = 'transform';
    public static final Integer MAX_CHANGES = 5;
    /** How many records the preview shows before and after. */
    public static final Integer SAMPLE_SIZE = 5;
    /** Records a chunk saves, so one journal page holds one chunk (R-IJ1). */
    public static final Integer MAX_CHUNK = 200;
    /** The run limit's default and highest value (R-BU2). */
    public static final Integer MAX_RUN_LIMIT = 48000;
    /** Query rows left free for the reads around a count. */
    private static final Integer COUNT_MARGIN = 100;
    private static final Integer DEFINITION_VERSION = 1;
    private static final String RECORD_TYPE_FIELD = 'RecordTypeId';

    /** One change, as checked: the field it writes and the value or field it takes. */
    public class Change {
        public String action;
        public Schema.DescribeFieldResult target;
        public Schema.DescribeFieldResult source;
        /** The value to set, typed for the target; null for clear and copy. */
        public Object value;
        /** The value as the person sent it, kept in the job's definition. */
        public Object rawValue;
        /** transform: the steps, checked by DataTransform.problems. */
        public List<DataTransform.Step> steps;
        /** transform: the fields of the same record its `append` steps name. */
        public List<Schema.DescribeFieldResult> otherFields = new List<Schema.DescribeFieldResult>();

        /**
         * The value this change gives one record. A transform's result is typed for the
         * target; a result the target cannot take is refused for this record alone, with a
         * `BulkUpdateException` whose message is the reason (R-BU7). So is a household's
         * Account Name, which household naming keeps (R-H8), as an import refuses it.
         */
        public Object newValueFor(SObject record) {
            if (keptOnRecord(record)) {
                throw new BulkUpdateFields.BulkUpdateException(
                    System.Label.Core_BulkUpdate_ErrorHouseholdName
                );
            }
            if (action == ACTION_COPY) {
                return record.get(source.getName());
            }
            if (action == ACTION_TRANSFORM) {
                Map<String, String> others = new Map<String, String>();
                for (Schema.DescribeFieldResult other : otherFields) {
                    others.put(
                        DataTransform.key(other.getName()),
                        BulkUpdateFields.toText(other, record.get(other.getName()))
                    );
                }
                String result = DataTransform.apply(
                    steps,
                    BulkUpdateFields.toText(target, record.get(target.getName())),
                    others
                );
                return BulkUpdateFields.fromText(target, result);
            }
            return action == ACTION_CLEAR ? null : value;
        }

        /** Whether this change's field is one this record keeps for itself. */
        private Boolean keptOnRecord(SObject record) {
            if (record.getSObjectType() != Account.SObjectType) {
                return false;
            }
            Object recordType = record.getPopulatedFieldsAsMap().get(RECORD_TYPE_FIELD);
            return DataProtectedFields.isProtectedOnRecord(
                Account.SObjectType,
                target.getName(),
                (Id) recordType
            );
        }

        public Map<String, Object> toMap() {
            Map<String, Object> result = new Map<String, Object>{
                'field' => target.getName(),
                'action' => action
            };
            if (action == ACTION_SET) {
                result.put('value', rawValue);
            }
            if (action == ACTION_COPY) {
                result.put('source', source.getName());
            }
            if (action == ACTION_TRANSFORM) {
                result.put('transforms', JSON.deserializeUntyped(JSON.serialize(steps, true)));
            }
            return result;
        }
    }

    /** A checked bulk update: the query document, its object and the changes. */
    public class Plan {
        public String queryJson;
        public String objectName;
        public Schema.SObjectType objectType;
        public List<Change> changes = new List<Change>();

        /** The fields the job reads: every target and every copied source. */
        public Set<String> readFields() {
            Set<String> names = new Set<String>();
            for (Change change : changes) {
                names.add(change.target.getName());
                // A household's name is kept by household naming: the record type tells.
                if (
                    objectType == Account.SObjectType &&
                    'Name'.equalsIgnoreCase(change.target.getName()) &&
                    Schema.SObjectType.Account.fields.getMap()
                        .containsKey(RECORD_TYPE_FIELD.toLowerCase())
                ) {
                    names.add(RECORD_TYPE_FIELD);
                }
                if (change.source != null) {
                    names.add(change.source.getName());
                }
                for (Schema.DescribeFieldResult other : change.otherFields) {
                    names.add(other.getName());
                }
            }
            return names;
        }

        /** What a job keeps (R-BU1): the query document, the changes and the count. */
        public String definition(Integer confirmedCount) {
            List<Object> rawChanges = new List<Object>();
            for (Change change : changes) {
                rawChanges.add(change.toMap());
            }
            return JSON.serialize(
                new Map<String, Object>{
                    'version' => DEFINITION_VERSION,
                    'query' => JSON.deserializeUntyped(queryJson),
                    'changes' => rawChanges,
                    'confirmedCount' => confirmedCount
                }
            );
        }
    }

    /** One field before and after, as the preview shows it. */
    public class FieldChange {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public Object before;
        @AuraEnabled
        public Object after;
        /** Why this record's field cannot take the changed value, when it cannot (R-BU7). */
        @AuraEnabled
        public String problem;
    }

    /** One record of the preview's sample. */
    public class SampleRecord {
        @AuraEnabled
        public String recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public List<FieldChange> changes = new List<FieldChange>();
    }

    /** What a bulk update would do. */
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
    }

    // -------------------------------------------------------------------------------------
    // Checking
    // -------------------------------------------------------------------------------------

    /** Checks a query document and its changes as the running user. */
    public static Plan plan(String queryJson, String changesJson) {
        List<Object> rawChanges;
        try {
            rawChanges = String.isBlank(changesJson)
                ? new List<Object>()
                : (List<Object>) JSON.deserializeUntyped(changesJson);
        } catch (Exception unreadable) {
            throw new BulkUpdateFields.BulkUpdateException(
                System.Label.Core_BulkUpdate_ErrorNoChanges
            );
        }
        return plan(queryJson, rawChanges);
    }

    /** Checks a job's stored definition again, as the person running the job (R-BU1). */
    public static Plan planFromDefinition(String definitionJson) {
        Map<String, Object> definition = (Map<String, Object>) JSON.deserializeUntyped(
            definitionJson
        );
        return plan(
            JSON.serialize(definition.get('query')),
            (List<Object>) definition.get('changes')
        );
    }

    /** The confirmed count a job's definition holds. */
    public static Integer confirmedCountOf(String definitionJson) {
        Map<String, Object> definition = (Map<String, Object>) JSON.deserializeUntyped(
            definitionJson
        );
        return Integer.valueOf(definition.get('confirmedCount'));
    }

    private static Plan plan(String queryJson, List<Object> rawChanges) {
        Plan result = new Plan();
        result.queryJson = queryJson;
        result.objectType = BulkUpdateFields.writableObject(
            QueryCompiler.parse(queryJson).objectName
        );
        result.objectName = result.objectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getName();
        if (rawChanges == null || rawChanges.isEmpty()) {
            throw new BulkUpdateFields.BulkUpdateException(
                System.Label.Core_BulkUpdate_ErrorNoChanges
            );
        }
        if (rawChanges.size() > MAX_CHANGES) {
            throw new BulkUpdateFields.BulkUpdateException(
                System.Label.Core_BulkUpdate_ErrorTooManyChanges
            );
        }
        Set<String> targets = new Set<String>();
        for (Object entry : rawChanges) {
            if (!(entry instanceof Map<String, Object>)) {
                throw new BulkUpdateFields.BulkUpdateException(
                    System.Label.Core_BulkUpdate_ErrorNoChanges
                );
            }
            Change change = change(result.objectType, (Map<String, Object>) entry);
            if (!targets.add(change.target.getName().toLowerCase())) {
                throw new BulkUpdateFields.BulkUpdateException(
                    String.format(
                        System.Label.Core_BulkUpdate_ErrorDuplicateField,
                        new List<Object>{ change.target.getLabel() }
                    )
                );
            }
            result.changes.add(change);
        }
        return result;
    }

    private static Change change(Schema.SObjectType type, Map<String, Object> raw) {
        Change change = new Change();
        change.action = raw.get('action') == null
            ? ''
            : String.valueOf(raw.get('action')).trim().toLowerCase();
        change.target = BulkUpdateFields.writableField(type, raw.get('field'));
        String label = change.target.getLabel();
        if (change.action == ACTION_CLEAR) {
            if (!change.target.isNillable()) {
                throw new BulkUpdateFields.BulkUpdateException(
                    String.format(
                        System.Label.Core_BulkUpdate_ErrorRequired,
                        new List<Object>{ label }
                    )
                );
            }
            return change;
        }
        if (change.action == ACTION_COPY) {
            change.source = BulkUpdateFields.ownField(type, raw.get('source'));
            if (
                change.source.getName() == change.target.getName() ||
                !BulkUpdateFields.compatible(change.target, change.source)
            ) {
                throw new BulkUpdateFields.BulkUpdateException(
                    String.format(
                        System.Label.Core_BulkUpdate_ErrorIncompatibleCopy,
                        new List<Object>{ change.source.getLabel(), label }
                    )
                );
            }
            return change;
        }
        if (change.action == ACTION_SET) {
            change.rawValue = raw.get('value');
            change.value = BulkUpdateFields.typed(change.target, change.rawValue);
            return change;
        }
        if (change.action == ACTION_TRANSFORM) {
            return withSteps(type, change, raw.get('transforms'));
        }
        throw new BulkUpdateFields.BulkUpdateException(System.Label.Core_BulkUpdate_ErrorNoChanges);
    }

    /**
     * A change with steps (R-BU7): refused when the target cannot be changed with steps, when
     * there is no step, when DataTransform names a problem (apply would skip such a step
     * silently), or when an `append` step names a field the person may not read.
     */
    private static Change withSteps(Schema.SObjectType type, Change change, Object rawSteps) {
        String label = change.target.getLabel();
        if (!BulkUpdateFields.canTransform(change.target)) {
            throw new BulkUpdateFields.BulkUpdateException(
                String.format(
                    System.Label.Core_BulkUpdate_ErrorCannotTransform,
                    new List<Object>{ label }
                )
            );
        }
        change.steps = rawSteps instanceof List<Object>
            ? DataTransform.parse(JSON.serialize(rawSteps))
            : new List<DataTransform.Step>();
        if (change.steps.isEmpty()) {
            throw new BulkUpdateFields.BulkUpdateException(
                String.format(System.Label.Core_BulkUpdate_ErrorNoSteps, new List<Object>{ label })
            );
        }
        List<String> problems = DataTransform.problems(change.steps);
        if (!problems.isEmpty()) {
            throw new BulkUpdateFields.BulkUpdateException(
                String.format(
                    System.Label.Core_BulkUpdate_ErrorSteps,
                    new List<Object>{ label, String.join(problems, ' ') }
                )
            );
        }
        Set<String> named = new Set<String>();
        for (DataTransform.Step step : change.steps) {
            if (step.op != DataTransform.OP_APPEND) {
                continue;
            }
            for (String column : step.columns) {
                Schema.DescribeFieldResult other = BulkUpdateFields.ownField(type, column);
                if (named.add(other.getName())) {
                    change.otherFields.add(other);
                }
            }
        }
        return change;
    }

    // -------------------------------------------------------------------------------------
    // Preview
    // -------------------------------------------------------------------------------------

    /**
     * Counts the records the query matches now and shows the first few before and after. The
     * count is the number the person confirms; nothing is saved.
     */
    public static Preview preview(String queryJson, String changesJson) {
        Plan checked = plan(queryJson, changesJson);
        Integer ceiling = runLimit();
        Preview result = new Preview();
        result.count = countWithin(checked, ceiling);
        if (result.count > ceiling) {
            throw new BulkUpdateFields.BulkUpdateException(overLimit(ceiling));
        }
        result.runLimit = ceiling;
        result.objectLabel = checked.objectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getLabelPlural();
        Set<String> fields = checked.readFields();
        String nameField = nameField(checked.objectType);
        if (nameField != null) {
            fields.add(nameField);
        }
        QueryCompiler.Compiled sample = QueryCompiler.compileSelection(queryJson, fields, null);
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
            shown.name = nameField == null
                ? String.valueOf(record.Id)
                : String.valueOf(record.get(nameField));
            for (Change change : checked.changes) {
                FieldChange field = new FieldChange();
                field.label = change.target.getLabel();
                field.before = record.get(change.target.getName());
                try {
                    field.after = change.newValueFor(record);
                } catch (BulkUpdateFields.BulkUpdateException refused) {
                    field.problem = refused.getMessage();
                }
                shown.changes.add(field);
            }
            result.sample.add(shown);
        }
        return result;
    }

    /**
     * How many records match, counting at most one past `ceiling`. Refused when none match, or
     * when the request cannot read enough rows to tell (R-BU2); a count past the ceiling is
     * returned, so the caller can say which limit it passed.
     */
    public static Integer countWithin(Plan checked, Integer ceiling) {
        Integer headroom = Limits.getLimitQueryRows() - Limits.getQueryRows() - COUNT_MARGIN;
        Integer cap = Math.min(ceiling + 1, headroom);
        Integer count = QueryCompiler.count(checked.queryJson, cap);
        if (count >= cap && cap <= ceiling) {
            throw new BulkUpdateFields.BulkUpdateException(
                System.Label.Core_BulkUpdate_ErrorTooManyToCount
            );
        }
        if (count == 0) {
            throw new BulkUpdateFields.BulkUpdateException(
                System.Label.Core_BulkUpdate_ErrorNothingMatches
            );
        }
        return count;
    }

    // -------------------------------------------------------------------------------------
    // Start
    // -------------------------------------------------------------------------------------

    /**
     * Starts a bulk update of at most `confirmedCount` records after counting again: refused
     * when more records match now than were confirmed, or than the run limit allows (R-BU2).
     * The job record is the package's own bookkeeping, written in system mode (ADR-0021); every
     * record the job changes is saved in the person's own mode.
     */
    public static Import_Batch__c start(
        String queryJson,
        String changesJson,
        Integer confirmedCount
    ) {
        Plan checked = plan(queryJson, changesJson);
        if (confirmedCount == null || confirmedCount < 1) {
            throw new BulkUpdateFields.BulkUpdateException(
                System.Label.Core_BulkUpdate_ErrorConfirm
            );
        }
        Integer ceiling = runLimit();
        if (confirmedCount > ceiling) {
            throw new BulkUpdateFields.BulkUpdateException(overLimit(ceiling));
        }
        Integer count = countWithin(checked, confirmedCount);
        if (count > confirmedCount) {
            throw new BulkUpdateFields.BulkUpdateException(
                String.format(
                    System.Label.Core_BulkUpdate_ErrorMoreThanConfirmed,
                    new List<Object>{ confirmedCount.format() }
                )
            );
        }
        Import_Batch__c job = createJob(checked, count, confirmedCount);
        Id jobId = Database.executeBatch(new BulkUpdateBatch(job.Id), MAX_CHUNK);
        job.Job_Id__c = jobId;
        Database.update(
            new Import_Batch__c(Id = job.Id, Job_Id__c = jobId),
            AccessLevel.SYSTEM_MODE
        );
        return job;
    }

    /**
     * The job record: committed when it starts, with its undo deadline stamped then, as an
     * import's is, so a later change to the setting never moves it (R-IB7, R-BU2).
     */
    @TestVisible
    private static Import_Batch__c createJob(Plan checked, Integer count, Integer confirmedCount) {
        Datetime now = Datetime.now();
        Import_Batch__c job = new Import_Batch__c(
            Operation__c = OPERATION_UPDATE,
            Operation_JSON__c = checked.definition(confirmedCount),
            Status__c = ImportBatchService.STATUS_COMMITTING,
            Is_Dry_Run__c = false,
            Row_Count__c = count,
            Rows_Created__c = 0,
            Rows_Updated__c = 0,
            Rows_Matched__c = 0,
            Rows_Rejected__c = 0,
            Chunk_Size__c = MAX_CHUNK,
            Started_At__c = now,
            Committed_By__c = UserInfo.getUserId(),
            Undo_Deadline__c = now.addDays(ImportBatchService.undoWindowDays()),
            Run_Log__c = String.format(
                System.Label.Core_BulkUpdate_LogStarted,
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

    /** The run limit from BarnCRM Settings, held between 1 and MAX_RUN_LIMIT (R-BU2). */
    public static Integer runLimit() {
        Object configured = SettingsService.hasKey('Bulk_Update_Run_Limit__c')
            ? SettingsService.getValue('Bulk_Update_Run_Limit__c')
            : null;
        if (configured == null) {
            return MAX_RUN_LIMIT;
        }
        try {
            Integer records = Decimal.valueOf(String.valueOf(configured)).intValue();
            return Math.max(1, Math.min(records, MAX_RUN_LIMIT));
        } catch (Exception ignored) {
            return MAX_RUN_LIMIT;
        }
    }

    public static String overLimit(Integer ceiling) {
        return String.format(
            System.Label.Core_BulkUpdate_ErrorOverLimit,
            new List<Object>{ ceiling.format() }
        );
    }

    /** The object's name field, when the person may read it, for the sample. */
    private static String nameField(Schema.SObjectType type) {
        for (
            Schema.SObjectField token : type.getDescribe(SObjectDescribeOptions.DEFERRED)
                .fields.getMap()
                .values()
        ) {
            Schema.DescribeFieldResult field = token.getDescribe();
            if (field.isNameField() && field.isAccessible()) {
                return field.getName();
            }
        }
        return null;
    }
}
