/**
 * What the Rollup Builder reads and writes (rollup proposal Part 2 section 3, slice S11;
 * `decisions/0082-barncrm-owns-its-rollup-engine.md` decision 7).
 *
 * The five steps read the org's own describe, as the running user sees it, so every choice the
 * Builder offers is a real object and field, and nothing an administrator types reaches a query:
 * names are checked against describe here, and filters go through `RollupFilterParser`.
 *
 * Saving runs the whole save check of canonical model R-R10 and the overlap check of R-R8, then
 * writes the definition in user mode. Each check answers in plain words with what to do, never a
 * stack trace. The "Check rollups before saving" automation still runs on the save, so a
 * definition the Builder saves is one the engine can plan.
 */
public with sharing class RollupBuilderController {
    private static final String KEY_PREFIX = 'Custom_';

    /** BarnCRM's own bookkeeping, never a place for a total, by local API name. */
    private static final Set<String> NOT_TARGETS = new Set<String>{
        'automation_setting__c',
        'duplicate_dismissal__c',
        'error_log__c',
        'import_batch__c',
        'import_journal__c',
        'import_row__c',
        'import_template__c',
        'rollup_definition__c',
        'rollup_queue__c',
        'setting_change__c'
    };

    private static final Set<String> STANDARD_ENTITIES = new Set<String>{ 'account', 'contact' };

    private static final Set<Schema.DisplayType> NUMBER_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.LONG,
        Schema.DisplayType.CURRENCY,
        Schema.DisplayType.PERCENT
    };

    private static final Set<Schema.DisplayType> DATE_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.DATE,
        Schema.DisplayType.DATETIME
    };

    private static final Set<Schema.DisplayType> TARGET_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.BOOLEAN,
        Schema.DisplayType.STRING,
        Schema.DisplayType.TEXTAREA
    };

    private static final Set<String> READS_NO_FIELD = new Set<String>{ 'COUNT', 'ANY', 'NONE' };
    private static final Set<String> ORDERED = new Set<String>{ 'FIRST', 'LAST' };
    private static final Set<Integer> FISCAL_OFFSETS = new Set<Integer>{ 0, -1, -2 };

    static {
        TARGET_TYPES.addAll(NUMBER_TYPES);
        TARGET_TYPES.addAll(DATE_TYPES);
    }

    /** A value and the words an administrator reads for it. */
    public class Option {
        @AuraEnabled
        public String value { get; set; }
        @AuraEnabled
        public String label { get; set; }

        public Option(String value, String label) {
            this.value = value;
            this.label = label;
        }
    }

    /** One field the Builder offers. */
    public class FieldOption {
        @AuraEnabled
        public String value { get; set; }
        @AuraEnabled
        public String label { get; set; }
        /** The field's type in lower case, as describe names it: currency, date, picklist. */
        @AuraEnabled
        public String type { get; set; }
        /** The name of the active rollup that already fills this field, if any (R-R8). */
        @AuraEnabled
        public String filledBy { get; set; }
        @AuraEnabled
        public List<Option> picklistValues { get; set; }
    }

    /** One way of reaching the target: a source entity and the path from it. */
    public class SourceOption {
        @AuraEnabled
        public String value { get; set; }
        @AuraEnabled
        public String label { get; set; }
        @AuraEnabled
        public String sourceObject { get; set; }
        @AuraEnabled
        public String relationshipPath { get; set; }
        /** The counted records' plural name, for the filter sentence: "Gifts". */
        @AuraEnabled
        public String recordsLabel { get; set; }
    }

    /** What the Builder needs before step 1. */
    public class BuilderModel {
        @AuraEnabled
        public Boolean canManage { get; set; }
        @AuraEnabled
        public Boolean multiCurrency { get; set; }
        @AuraEnabled
        public String defaultMode { get; set; }
        @AuraEnabled
        public List<Option> targets { get; set; }
        @AuraEnabled
        public List<Option> aggregates { get; set; }
        @AuraEnabled
        public List<Option> delimiters { get; set; }
        @AuraEnabled
        public List<Option> modes { get; set; }
    }

    /** One rollup as the Builder edits it. */
    public class Draft {
        @AuraEnabled
        public String recordId { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String description { get; set; }
        @AuraEnabled
        public String targetObject { get; set; }
        @AuraEnabled
        public String targetField { get; set; }
        @AuraEnabled
        public String sourceObject { get; set; }
        @AuraEnabled
        public String relationshipPath { get; set; }
        @AuraEnabled
        public String aggregate { get; set; }
        @AuraEnabled
        public String sourceField { get; set; }
        @AuraEnabled
        public String orderByField { get; set; }
        @AuraEnabled
        public String delimiter { get; set; }
        @AuraEnabled
        public String filterJson { get; set; }
        @AuraEnabled
        public String targetFilterJson { get; set; }
        @AuraEnabled
        public Boolean fiscalYearAware { get; set; }
        @AuraEnabled
        public Integer fiscalYearOffset { get; set; }
        @AuraEnabled
        public String fiscalDateField { get; set; }
        @AuraEnabled
        public String mode { get; set; }
        @AuraEnabled
        public Boolean active { get; set; }
    }

    // ----------------------------------------------------------------------------------- reads

    @AuraEnabled(cacheable=true)
    public static BuilderModel getModel() {
        try {
            BuilderModel model = new BuilderModel();
            model.canManage = FeatureManagement.checkPermission('Manage_BarnCRM_Settings');
            model.multiCurrency = RollupCurrency.isMultiCurrency();
            model.defaultMode = RollupService.defaultMode();
            model.targets = targetEntities();
            model.aggregates = picklist(Rollup_Definition__c.Aggregate__c);
            model.delimiters = picklist(Rollup_Definition__c.Delimiter__c);
            model.modes = picklist(Rollup_Definition__c.Mode__c);
            return model;
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /**
     * Step 1: the fields of this entity BarnCRM can fill, and which a rollup already fills. Not
     * cacheable: which rollup fills a field changes with every save, and the wizard asks again
     * for each new rollup (ROLLUPS-16).
     */
    @AuraEnabled
    public static List<FieldOption> getTargetFields(String targetObject) {
        try {
            Schema.SObjectType targetType = requireEntity(targetObject);
            Map<Schema.SObjectField, String> filledBy = filledFields(targetType);
            List<FieldOption> options = new List<FieldOption>();
            for (Schema.SObjectField field : fieldMap(targetType).values()) {
                Schema.DescribeFieldResult described = field.getDescribe();
                if (
                    !described.isUpdateable() ||
                    described.isCalculated() ||
                    !TARGET_TYPES.contains(described.getType()) ||
                    described.getName().endsWithIgnoreCase(RollupService.FRESHNESS_FIELD)
                ) {
                    continue;
                }
                FieldOption option = toOption(described);
                option.filledBy = filledBy.get(field);
                options.add(option);
            }
            return sorted(options);
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /**
     * Step 2: every entity with a reference to this one, by each such reference, and for an
     * Account, every entity with a reference to a person, through that person's household.
     */
    @AuraEnabled(cacheable=true)
    public static List<SourceOption> getSources(String targetObject) {
        try {
            Schema.SObjectType targetType = requireEntity(targetObject);
            List<SourceOption> options = childrenOf(targetType, null);
            if (targetType == Account.SObjectType) {
                options.addAll(childrenOf(Contact.SObjectType, RollupPath.TOKEN_HOUSEHOLD));
            }
            return options;
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /** Steps 3 and 4: the fields of the counted records the user can read. */
    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getSourceFields(String sourceObject) {
        try {
            List<FieldOption> options = new List<FieldOption>();
            for (Schema.SObjectField field : fieldMap(requireEntity(sourceObject)).values()) {
                Schema.DescribeFieldResult described = field.getDescribe();
                if (described.isAccessible()) {
                    options.add(toOption(described));
                }
            }
            return sorted(options);
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /** An existing rollup, to edit or to copy. */
    @AuraEnabled
    public static Draft getDraft(Id definitionId) {
        try {
            Rollup_Definition__c definition = RollupSelector.selectById(definitionId);
            if (definition == null) {
                throw new RollupService.RollupServiceException(
                    Label.Core_Rollups_ErrorUnknownDefinition
                );
            }
            return toDraft(definition);
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    // -------------------------------------------------------------------------------- preview

    /** What step 5 shows before a save: the total on one record, and how many it maintains. */
    public class PreviewResult {
        @AuraEnabled
        public String result { get; set; }
        @AuraEnabled
        public String maintains { get; set; }
    }

    /**
     * Calculates the unsaved rollup for one record, writing nothing, and counts the records it
     * would maintain (slice S12). Runs the save's checks first, apart from the name and the
     * overlap with other rollups, which only a save needs.
     *
     * @param draft the rollup as the Builder holds it
     * @param recordId a record of the target entity to calculate, or null for the count only
     */
    @AuraEnabled
    public static PreviewResult preview(Draft draft, Id recordId) {
        try {
            // It calculates any field of any record in system mode, so only an admin may ask.
            if (!FeatureManagement.checkPermission('Manage_BarnCRM_Settings')) {
                throw new RollupService.RollupServiceException(
                    Label.Core_Rollups_ErrorNoPermission
                );
            }
            if (draft != null) {
                draft.name = String.isBlank(draft.name) ? draft.targetField : draft.name;
                draft.active = false;
            }
            String problem = problemWith(draft);
            if (problem != null) {
                throw new RollupService.RollupServiceException(problem);
            }
            Schema.SObjectType targetType = SettingsService.typeByName(draft.targetObject);
            String condition = RollupFilterParser.toWhereClause(draft.targetFilterJson, targetType);
            Integer count = Database.countQueryWithBinds(
                'SELECT COUNT() FROM ' +
                    String.valueOf(targetType) +
                    (String.isBlank(condition) ? '' : ' WHERE ' + condition),
                new Map<String, Object>(),
                AccessLevel.USER_MODE
            );
            PreviewResult preview = new PreviewResult();
            preview.maintains = String.format(
                Label.Core_RollupBuilder_Maintains,
                new List<String>{ count.format() }
            );
            if (recordId != null) {
                preview.result = describe(RollupEngine.preview(toRecord(draft), recordId));
            }
            return preview;
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    private static String describe(RollupEngine.Preview preview) {
        if (!preview.planned) {
            return Label.Core_RollupBuilder_PreviewFailed;
        }
        if (!preview.admitted) {
            return Label.Core_RollupBuilder_PreviewNotFilled;
        }
        return String.format(
            Label.Core_RollupBuilder_PreviewResult,
            new List<String>{ display(preview.calculated), display(preview.current) }
        );
    }

    /** A value as the administrator reads it, in her locale. */
    @TestVisible
    private static String display(Object value) {
        if (value == null || value == '') {
            return Label.Core_RollupBuilder_PreviewEmpty;
        }
        if (value instanceof Integer) {
            return ((Integer) value).format();
        }
        if (value instanceof Decimal) {
            return ((Decimal) value).format();
        }
        if (value instanceof Date) {
            return ((Date) value).format();
        }
        if (value instanceof Datetime) {
            return ((Datetime) value).format();
        }
        return String.valueOf(value);
    }

    // ---------------------------------------------------------------------------------- saving

    /** What a save did: the record, and what to tell the administrator. */
    public class SaveResult {
        @AuraEnabled
        public Id recordId { get; set; }
        @AuraEnabled
        public String notice { get; set; }
    }

    /**
     * Saves a new or edited rollup after every check.
     *
     * @param draft the rollup as the Builder holds it
     * @param calculateNow true to start its recalculation once it is saved
     * @return the saved record and the notice to show
     */
    @AuraEnabled
    public static SaveResult save(Draft draft, Boolean calculateNow) {
        try {
            if (!FeatureManagement.checkPermission('Manage_BarnCRM_Settings')) {
                throw new RollupService.RollupServiceException(
                    Label.Core_Rollups_ErrorNoPermission
                );
            }
            String problem = problemWith(draft);
            if (problem != null) {
                throw new RollupService.RollupServiceException(problem);
            }
            Rollup_Definition__c definition = toRecord(draft);
            // Checked on save only: the preview runs before the mode is chosen (ROLLUPS-8).
            if (
                RollupService.MODE_REAL_TIME.equals(definition.Mode__c) &&
                RollupDateWindow.movesWithTheDate(definition)
            ) {
                throw new RollupService.RollupServiceException(
                    Label.Core_RollupBuilder_ErrorInstantMovesWithDate
                );
            }
            RollupWriter.saveAsUser(definition);
            SaveResult result = new SaveResult();
            result.recordId = definition.Id;
            result.notice = Label.Core_RollupBuilder_Saved;
            if (calculateNow == true && definition.Active__c) {
                // R-R14: one full run at a time. The rollup is saved either way.
                if (RollupFullRecalcBatch.runningJobId() != null) {
                    result.notice = Label.Core_RollupBuilder_SavedNotCalculated;
                } else {
                    RollupService.recalculate(definition.Id);
                    result.notice = Label.Core_RollupBuilder_SavedAndCalculating;
                }
            }
            return result;
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /**
     * Why this rollup cannot be saved, in words the administrator acts on, or null (R-R10, R-R8).
     * Visible to tests so each check is proved on its own.
     */
    @TestVisible
    private static String problemWith(Draft draft) {
        if (draft == null || String.isBlank(draft.name)) {
            return Label.Core_RollupBuilder_ErrorNameNeeded;
        }
        Schema.SObjectType targetType = SettingsService.typeByName(draft.targetObject);
        if (targetType == null || String.isBlank(draft.targetField)) {
            return Label.Core_RollupBuilder_ErrorTargetNeeded;
        }
        Schema.SObjectField target = fieldMap(targetType).get(draft.targetField.toLowerCase());
        if (target == null || !target.getDescribe().isUpdateable()) {
            return Label.Core_Rollups_ErrorTargetNotWritable;
        }
        String aggregate = String.isBlank(draft.aggregate) ? '' : draft.aggregate.toUpperCase();
        if (!valuesOf(Rollup_Definition__c.Aggregate__c).contains(aggregate)) {
            return Label.Core_Rollups_ErrorInvalidOperator;
        }
        String problem = RollupPlanner.targetTypeProblem(aggregate, target.getDescribe().getType());
        if (problem == null) {
            problem = sourceProblem(draft, aggregate);
        }
        if (problem == null) {
            problem = filterProblem(draft, targetType);
        }
        if (problem == null && draft.active != false) {
            problem = overlapProblem(draft, targetType, target);
        }
        return problem;
    }

    /** The source entity, the path, the attributes read and the fiscal window. */
    private static String sourceProblem(Draft draft, String aggregate) {
        Schema.SObjectType sourceType = SettingsService.typeByName(draft.sourceObject);
        if (sourceType == null || String.isBlank(draft.relationshipPath)) {
            return Label.Core_RollupBuilder_ErrorSourceNeeded;
        }
        Map<String, Schema.SObjectField> fields = fieldMap(sourceType);
        try {
            for (RollupPath.Branch branch : RollupPath.parse(draft.relationshipPath).branches) {
                String first = branch.segments[0];
                Schema.SObjectField reference = fields.get(first.toLowerCase());
                if (
                    !RollupPath.isToken(first) &&
                    (reference == null ||
                    reference.getDescribe().getType() != Schema.DisplayType.REFERENCE)
                ) {
                    return Label.Core_RollupBuilder_ErrorPathInvalid;
                }
            }
        } catch (RollupPath.RollupPathException unreadable) {
            return Label.Core_RollupBuilder_ErrorPathInvalid;
        }
        Schema.DisplayType readType = typeOf(fields, draft.sourceField);
        if (!READS_NO_FIELD.contains(aggregate)) {
            if (String.isBlank(draft.sourceField)) {
                return Label.Core_Rollups_ErrorSourceFieldNeeded;
            }
            if (readType == null) {
                return Label.Core_RollupBuilder_ErrorFieldUnknown;
            }
        }
        if ((aggregate == 'SUM' || aggregate == 'AVG') && !NUMBER_TYPES.contains(readType)) {
            return Label.Core_RollupBuilder_ErrorSumNeedsNumber;
        }
        if (
            (aggregate == 'MIN' ||
            aggregate == 'MAX') &&
            !NUMBER_TYPES.contains(readType) &&
            !DATE_TYPES.contains(readType)
        ) {
            return Label.Core_RollupBuilder_ErrorMinMaxType;
        }
        if (ORDERED.contains(aggregate) && String.isBlank(draft.orderByField)) {
            return Label.Core_RollupBuilder_ErrorOrderByNeeded;
        }
        if (String.isNotBlank(draft.orderByField) && typeOf(fields, draft.orderByField) == null) {
            return Label.Core_RollupBuilder_ErrorFieldUnknown;
        }
        if (draft.fiscalYearAware == true) {
            if (!FISCAL_OFFSETS.contains(draft.fiscalYearOffset)) {
                return Label.Core_RollupBuilder_ErrorWindowInvalid;
            }
            String dateField = String.isNotBlank(draft.fiscalDateField)
                ? draft.fiscalDateField
                : draft.sourceField;
            // A date only: the window's bounds are dates, which SOQL refuses against a date
            // and time (ROLLUPS-3).
            if (typeOf(fields, dateField) != Schema.DisplayType.DATE) {
                return Label.Core_RollupBuilder_ErrorWindowNeedsDate;
            }
        }
        return null;
    }

    /** Both filter documents read, and name only attributes their entity has (R-R2). */
    private static String filterProblem(Draft draft, Schema.SObjectType targetType) {
        String problem = documentProblem(
            SettingsService.typeByName(draft.sourceObject),
            draft.filterJson
        );
        return problem != null ? problem : documentProblem(targetType, draft.targetFilterJson);
    }

    private static String documentProblem(Schema.SObjectType entity, String document) {
        try {
            RollupFilterParser.toWhereClause(document, entity);
        } catch (Exception unreadable) {
            return Label.Core_Rollups_ErrorInvalidFilter;
        }
        Map<String, Schema.SObjectField> fields = fieldMap(entity);
        for (String field : RollupFilterParser.fieldsOf(document)) {
            if (!field.contains('.') && !fields.containsKey(field.toLowerCase())) {
                return Label.Core_RollupBuilder_ErrorFieldUnknown;
            }
        }
        return null;
    }

    /**
     * R-R8: another active rollup filling the same field may share no record with this one. Two
     * documents cannot be compared in general, so a pair is an overlap when either has no target
     * filter, the two are the same, or a record in the org meets both.
     */
    private static String overlapProblem(
        Draft draft,
        Schema.SObjectType targetType,
        Schema.SObjectField target
    ) {
        String mine = RollupFilterParser.toWhereClause(draft.targetFilterJson, targetType);
        Map<String, Schema.SObjectField> fields = fieldMap(targetType);
        for (Rollup_Definition__c other : RollupSelector.selectAll()) {
            if (
                other.Active__c != true ||
                String.valueOf(other.Id) == draft.recordId ||
                String.isBlank(other.Target_Field__c) ||
                SettingsService.typeByName(other.Target_Object__c) != targetType ||
                fields.get(other.Target_Field__c.toLowerCase()) != target
            ) {
                continue;
            }
            String theirs;
            try {
                theirs = RollupFilterParser.toWhereClause(other.Target_Filter_JSON__c, targetType);
            } catch (Exception unreadable) {
                continue;
            }
            if (
                String.isBlank(mine) ||
                String.isBlank(theirs) ||
                mine == theirs ||
                bothMet(targetType, mine, theirs)
            ) {
                return String.format(
                    Label.Core_RollupBuilder_ErrorOverlap,
                    new List<String>{ other.Name }
                );
            }
        }
        return null;
    }

    /**
     * Whether a record meets both target filters. The entity comes from describe and both
     * clauses from `RollupFilterParser`, which checks every name and escapes every value.
     */
    private static Boolean bothMet(Schema.SObjectType targetType, String mine, String theirs) {
        String query =
            'SELECT COUNT() FROM ' +
            String.valueOf(targetType) +
            ' WHERE (' +
            mine +
            ') AND (' +
            theirs +
            ') LIMIT 1';
        return Database.countQueryWithBinds(
                query,
                new Map<String, Object>(),
                AccessLevel.USER_MODE
            ) > 0;
    }

    // --------------------------------------------------------------------------------- helpers

    private static List<Option> targetEntities() {
        List<Option> options = new List<Option>();
        for (Schema.SObjectType type : Schema.getGlobalDescribe().values()) {
            String name = String.valueOf(type).toLowerCase();
            Boolean candidate =
                STANDARD_ENTITIES.contains(name) ||
                (name.endsWith('__c') && !NOT_TARGETS.contains(localName(name)));
            if (!candidate) {
                continue;
            }
            Schema.DescribeSObjectResult described = type.getDescribe(
                SObjectDescribeOptions.DEFERRED
            );
            if (described.isCustomSetting() || !described.isUpdateable()) {
                continue;
            }
            options.add(new Option(described.getName(), described.getLabel()));
        }
        return sortedOptions(options);
    }

    private static List<SourceOption> childrenOf(Schema.SObjectType parent, String token) {
        List<SourceOption> options = new List<SourceOption>();
        for (
            Schema.ChildRelationship child : parent.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getChildRelationships()
        ) {
            Schema.DescribeSObjectResult childType = child.getChildSObject()
                .getDescribe(SObjectDescribeOptions.DEFERRED);
            String name = childType.getName().toLowerCase();
            Boolean candidate = STANDARD_ENTITIES.contains(name) || name.endsWith('__c');
            if (!candidate || !childType.isQueryable() || childType.isCustomSetting()) {
                continue;
            }
            if (token != null && child.getChildSObject() == Account.SObjectType) {
                continue;
            }
            Schema.DescribeFieldResult reference = child.getField().getDescribe();
            SourceOption option = new SourceOption();
            option.sourceObject = childType.getName();
            option.relationshipPath = token == null
                ? reference.getName()
                : reference.getName() + ' > ' + token;
            option.value = option.sourceObject + '|' + option.relationshipPath;
            option.recordsLabel = childType.getLabelPlural();
            option.label = String.format(
                token == null
                    ? Label.Core_RollupBuilder_SourceBy
                    : Label.Core_RollupBuilder_SourceByHousehold,
                new List<String>{ childType.getLabel(), reference.getLabel() }
            );
            options.add(option);
        }
        return options;
    }

    /** Each target field an active rollup fills, with that rollup's name. */
    private static Map<Schema.SObjectField, String> filledFields(Schema.SObjectType targetType) {
        Map<Schema.SObjectField, String> filledBy = new Map<Schema.SObjectField, String>();
        Map<String, Schema.SObjectField> fields = fieldMap(targetType);
        for (Rollup_Definition__c definition : RollupSelector.selectAllAsUser()) {
            if (
                definition.Active__c == true &&
                String.isNotBlank(definition.Target_Field__c) &&
                SettingsService.typeByName(definition.Target_Object__c) == targetType
            ) {
                Schema.SObjectField field = fields.get(definition.Target_Field__c.toLowerCase());
                if (field != null && !filledBy.containsKey(field)) {
                    filledBy.put(field, definition.Name);
                }
            }
        }
        return filledBy;
    }

    private static FieldOption toOption(Schema.DescribeFieldResult described) {
        FieldOption option = new FieldOption();
        option.value = described.getName();
        option.label = described.getLabel();
        option.type = String.valueOf(described.getType()).toLowerCase();
        if (
            described.getType() == Schema.DisplayType.PICKLIST ||
            described.getType() == Schema.DisplayType.MULTIPICKLIST
        ) {
            option.picklistValues = new List<Option>();
            for (Schema.PicklistEntry entry : described.getPicklistValues()) {
                if (entry.isActive()) {
                    option.picklistValues.add(new Option(entry.getValue(), entry.getLabel()));
                }
            }
        }
        return option;
    }

    private static Draft toDraft(Rollup_Definition__c definition) {
        Draft draft = new Draft();
        draft.recordId = definition.Id;
        draft.name = definition.Name;
        draft.description = definition.Description__c;
        draft.targetObject = definition.Target_Object__c;
        draft.targetField = definition.Target_Field__c;
        draft.sourceObject = definition.Source_Object__c;
        draft.relationshipPath = definition.Relationship_Path__c;
        draft.aggregate = definition.Aggregate__c;
        draft.sourceField = definition.Source_Field__c;
        draft.orderByField = definition.Order_By_Field__c;
        draft.delimiter = definition.Delimiter__c;
        draft.filterJson = definition.Filter_JSON__c;
        draft.targetFilterJson = definition.Target_Filter_JSON__c;
        draft.fiscalYearAware = definition.Fiscal_Year_Aware__c;
        draft.fiscalYearOffset = definition.Fiscal_Year_Offset__c == null
            ? null
            : definition.Fiscal_Year_Offset__c.intValue();
        draft.fiscalDateField = definition.Fiscal_Date_Field__c;
        draft.mode = definition.Mode__c;
        draft.active = definition.Active__c;
        return draft;
    }

    private static Rollup_Definition__c toRecord(Draft draft) {
        Rollup_Definition__c record = new Rollup_Definition__c(
            Name = draft.name.trim(),
            Description__c = draft.description,
            Target_Object__c = draft.targetObject,
            Target_Field__c = draft.targetField,
            Source_Object__c = draft.sourceObject,
            Relationship_Path__c = draft.relationshipPath,
            Aggregate__c = draft.aggregate.toUpperCase(),
            Source_Field__c = String.isBlank(draft.sourceField) ? null : draft.sourceField,
            Order_By_Field__c = String.isBlank(draft.orderByField) ? null : draft.orderByField,
            Delimiter__c = String.isBlank(draft.delimiter) ? null : draft.delimiter,
            Filter_JSON__c = String.isBlank(draft.filterJson) ? null : draft.filterJson,
            Target_Filter_JSON__c = String.isBlank(draft.targetFilterJson)
                ? null
                : draft.targetFilterJson,
            Fiscal_Year_Aware__c = draft.fiscalYearAware == true,
            Fiscal_Year_Offset__c = draft.fiscalYearAware == true ? draft.fiscalYearOffset : null,
            Fiscal_Date_Field__c = draft.fiscalYearAware == true &&
                String.isNotBlank(draft.fiscalDateField)
                ? draft.fiscalDateField
                : null,
            Mode__c = valuesOf(Rollup_Definition__c.Mode__c).contains(draft.mode)
                ? draft.mode
                : RollupService.defaultMode(),
            Active__c = draft.active != false
        );
        if (String.isNotBlank(draft.recordId)) {
            record.Id = Id.valueOf(draft.recordId);
        } else {
            record.Definition_Key__c =
                KEY_PREFIX + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(16);
        }
        return record;
    }

    private static Schema.SObjectType requireEntity(String name) {
        Schema.SObjectType type = SettingsService.typeByName(name);
        if (type == null) {
            throw new RollupService.RollupServiceException(Label.Core_Rollups_ErrorUnknownObject);
        }
        return type;
    }

    private static Map<String, Schema.SObjectField> fieldMap(Schema.SObjectType type) {
        return type == null
            ? new Map<String, Schema.SObjectField>()
            : type.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap();
    }

    private static Schema.DisplayType typeOf(Map<String, Schema.SObjectField> fields, String name) {
        Schema.SObjectField field = String.isBlank(name) ? null : fields.get(name.toLowerCase());
        return field == null ? null : field.getDescribe().getType();
    }

    private static String localName(String name) {
        List<String> parts = name.split('__');
        return parts.size() > 2 ? parts[1] + '__c' : name;
    }

    private static Set<String> valuesOf(Schema.SObjectField picklist) {
        Set<String> values = new Set<String>();
        for (Schema.PicklistEntry entry : picklist.getDescribe().getPicklistValues()) {
            values.add(entry.getValue());
        }
        return values;
    }

    private static List<Option> picklist(Schema.SObjectField picklist) {
        List<Option> options = new List<Option>();
        for (Schema.PicklistEntry entry : picklist.getDescribe().getPicklistValues()) {
            options.add(new Option(entry.getValue(), entry.getLabel()));
        }
        return options;
    }

    private static List<FieldOption> sorted(List<FieldOption> options) {
        Map<String, FieldOption> byKey = new Map<String, FieldOption>();
        for (FieldOption option : options) {
            byKey.put(option.label.toLowerCase() + '|' + option.value, option);
        }
        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        List<FieldOption> result = new List<FieldOption>();
        for (String key : keys) {
            result.add(byKey.get(key));
        }
        return result;
    }

    private static List<Option> sortedOptions(List<Option> options) {
        Map<String, Option> byKey = new Map<String, Option>();
        for (Option option : options) {
            byKey.put(option.label.toLowerCase() + '|' + option.value, option);
        }
        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        List<Option> result = new List<Option>();
        for (String key : keys) {
            result.add(byKey.get(key));
        }
        return result;
    }

    /** A message the Builder can show; anything it cannot explain is logged. */
    private static AuraHandledException asUserError(Exception caught) {
        String message;
        if (caught instanceof RollupService.RollupServiceException) {
            message = caught.getMessage();
        } else if (caught instanceof DmlException) {
            message = ((DmlException) caught).getDmlMessage(0);
        } else {
            ErrorLogger.log(caught, 'RollupBuilderController');
            message = Label.Core_Rollups_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
