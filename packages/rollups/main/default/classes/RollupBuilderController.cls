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

    /** The two standard entities Core itself holds, always offered first (R-R7). */
    private static final Set<String> CORE_ENTITIES = new Set<String>{ 'account', 'contact' };

    /**
     * The standard objects most often rolled up from or to, listed first with Account, Contact
     * and the org's own objects; every other object is found by searching (ADR-0136). Names
     * only, resolved through describe: an object the org does not have is skipped.
     */
    private static final String COMMON_STANDARD = 'Opportunity,OpportunityLineItem,Case,Campaign,CampaignMember,Lead,Task,Event,Asset,Order,OrderItem,Contract'; // detection-only: Builder shortlist resolved through describe, an absent object is skipped (ADR-0136)

    /** The platform's companion objects: sharing, history, feeds and change events. */
    private static final List<String> COMPANION_SUFFIXES = new List<String>{
        'share',
        'history',
        'feed',
        'changeevent'
    };

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
        Schema.DisplayType.TEXTAREA,
        Schema.DisplayType.PICKLIST
    };

    /** Lookups the platform keeps for itself, whose records no filter needs (ADR-0136). */
    private static final Set<String> NOT_FOLLOWED = new Set<String>{
        'createdbyid',
        'lastmodifiedbyid',
        'masterrecordid'
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
        /** For an entity: true when it is listed before searching (ADR-0136). */
        @AuraEnabled
        public Boolean common { get; set; }

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
        /** Whether saving one of them updates the total at once (R-R12, ADR-0136). */
        @AuraEnabled
        public Boolean instant { get; set; }
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
        public List<Option> directions { get; set; }
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
        public String orderDirection { get; set; }
        @AuraEnabled
        public Integer rowLimit { get; set; }
        @AuraEnabled
        public String delimiter { get; set; }
        @AuraEnabled
        public String customDelimiter { get; set; }
        @AuraEnabled
        public Boolean includeDeleted { get; set; }
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
        @AuraEnabled
        public String bypassPermission { get; set; }
    }

    // ----------------------------------------------------------------------------------- reads

    @AuraEnabled(cacheable=true)
    public static BuilderModel getModel() {
        try {
            BuilderModel model = new BuilderModel();
            model.canManage = BarnCRMPermissions.canManageSettings();
            model.multiCurrency = RollupCurrency.isMultiCurrency();
            model.defaultMode = RollupService.defaultMode();
            model.targets = targetEntities();
            model.aggregates = picklist(Rollup_Definition__c.Aggregate__c);
            model.delimiters = picklist(Rollup_Definition__c.Delimiter__c);
            model.directions = picklist(Rollup_Definition__c.Order_Direction__c);
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

    /**
     * Step 4: the fields of each record the counted records point to, one lookup away and as the
     * user sees them, named by path (`Appeal__r.Type__c`) for the filter (R-R2, ADR-0136).
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getParentFields(String sourceObject) {
        try {
            List<FieldOption> options = new List<FieldOption>();
            for (Schema.SObjectField field : fieldMap(requireEntity(sourceObject)).values()) {
                Schema.DescribeFieldResult lookup = field.getDescribe();
                if (
                    !isParentLookup(lookup) || NOT_FOLLOWED.contains(lookup.getName().toLowerCase())
                ) {
                    continue;
                }
                String lookupLabel = lookup.getLabel().removeEndIgnoreCase(' ID');
                for (
                    Schema.SObjectField parentField : fieldMap(lookup.getReferenceTo()[0]).values()
                ) {
                    Schema.DescribeFieldResult described = parentField.getDescribe();
                    if (!described.isAccessible() || !described.isFilterable()) {
                        continue;
                    }
                    FieldOption option = toOption(described);
                    option.value = lookup.getRelationshipName() + '.' + described.getName();
                    option.label = String.format(
                        Label.Core_RollupBuilder_ParentField,
                        new List<String>{ lookupLabel, described.getLabel() }
                    );
                    options.add(option);
                }
            }
            return sorted(options);
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /** A lookup a filter may read through: readable, named, and to one object only. */
    private static Boolean isParentLookup(Schema.DescribeFieldResult lookup) {
        return lookup.getType() == Schema.DisplayType.REFERENCE &&
            lookup.isAccessible() &&
            String.isNotBlank(lookup.getRelationshipName()) &&
            lookup.getReferenceTo().size() == 1;
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
            if (!BarnCRMPermissions.canManageSettings()) {
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
            String instantProblem = instantProblem(definition);
            if (instantProblem != null) {
                throw new RollupService.RollupServiceException(instantProblem);
            }
            RollupWriter.saveAsUser(definition);
            SaveResult result = new SaveResult();
            result.recordId = definition.Id;
            result.notice = Label.Core_RollupBuilder_Saved;
            if (calculateNow == true && definition.Active__c) {
                // R-R14: one full run at a time. The rollup is saved either way; while the module
                // is turned off, Turn on recalculates it with every other (ADR-0125 decision 9).
                if (RollupService.isTurnedOff()) {
                    result.notice = Label.Core_RollupBuilder_SavedTurnedOff;
                } else if (RollupFullRecalcBatch.runningJobId() != null) {
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
        if (problem == null && target.getDescribe().getType() == Schema.DisplayType.PICKLIST) {
            problem = picklistProblem(draft, target.getDescribe());
        }
        if (problem == null) {
            problem = filterProblem(draft, targetType);
        }
        if (problem == null && draft.active != false) {
            problem = overlapProblem(draft, targetType, target);
        }
        return problem;
    }

    /**
     * Why this rollup cannot be Instantly only, or null: its source entity has no rollup trigger,
     * so nothing would update it between nightly runs (R-R12, ADR-0136). Both and Every night
     * are always allowed; with the Flow template, Both is still instant. The rollup list's mode
     * change asks the same.
     */
    public static String instantProblem(Rollup_Definition__c definition) {
        if (
            definition == null ||
            !RollupService.MODE_REAL_TIME.equals(definition.Mode__c) ||
            RollupService.hasInstantUpdates(definition.Source_Object__c)
        ) {
            return null;
        }
        Schema.SObjectType sourceType = SettingsService.typeByName(definition.Source_Object__c);
        String records = sourceType == null
            ? definition.Source_Object__c
            : sourceType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural();
        return String.format(Label.Core_RollupBuilder_ErrorNoInstant, new List<String>{ records });
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
        String limitProblem = RollupPlanner.rowLimitProblem(
            aggregate,
            draft.rowLimit,
            draft.orderByField
        );
        if (limitProblem == null) {
            limitProblem = RollupPlanner.delimiterProblem(draft.delimiter, draft.customDelimiter);
        }
        if (limitProblem != null) {
            return limitProblem;
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

    /**
     * A picklist target is filled from a picklist or text attribute, and a source picklist may
     * hold only values the target has (R-R15). Text is checked as it is written (`RollupWriter`).
     */
    private static String picklistProblem(Draft draft, Schema.DescribeFieldResult target) {
        Schema.SObjectField source = String.isBlank(draft.sourceField)
            ? null
            : fieldMap(SettingsService.typeByName(draft.sourceObject))
                  .get(draft.sourceField.toLowerCase());
        Schema.DisplayType readType = source == null ? null : source.getDescribe().getType();
        if (readType == Schema.DisplayType.STRING) {
            return null;
        }
        if (readType != Schema.DisplayType.PICKLIST) {
            return Label.Core_RollupBuilder_ErrorPicklistSource;
        }
        Set<String> targetValues = new Set<String>();
        for (Schema.PicklistEntry entry : target.getPicklistValues()) {
            if (entry.isActive()) {
                targetValues.add(entry.getValue().toLowerCase());
            }
        }
        List<String> missing = new List<String>();
        for (Schema.PicklistEntry entry : source.getDescribe().getPicklistValues()) {
            if (entry.isActive() && !targetValues.contains(entry.getValue().toLowerCase())) {
                missing.add(entry.getValue());
            }
        }
        return missing.isEmpty()
            ? null
            : String.format(
                  Label.Core_RollupBuilder_ErrorPicklistValues,
                  new List<String>{ String.join(missing, ', ') }
              );
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
            String problem = field.contains('.')
                ? parentFieldProblem(fields, field)
                : (fields.containsKey(field.toLowerCase())
                      ? null
                      : Label.Core_RollupBuilder_ErrorFieldUnknown);
            if (problem != null) {
                return problem;
            }
        }
        return null;
    }

    /**
     * A field of a record one lookup away (`Appeal__r.Type__c`): the lookup is readable and to
     * one object, and the field is on it and readable, all as the administrator sees them.
     */
    private static String parentFieldProblem(Map<String, Schema.SObjectField> fields, String path) {
        List<String> parts = path.split('\\.');
        if (parts.size() > 2) {
            return Label.Core_RollupBuilder_ErrorOneLookup;
        }
        for (Schema.SObjectField field : fields.values()) {
            Schema.DescribeFieldResult lookup = field.getDescribe();
            if (isParentLookup(lookup) && parts[0].equalsIgnoreCase(lookup.getRelationshipName())) {
                Schema.SObjectField parentField = fieldMap(lookup.getReferenceTo()[0])
                    .get(parts[1].toLowerCase());
                return parentField != null && parentField.getDescribe().isAccessible()
                    ? null
                    : Label.Core_RollupBuilder_ErrorFieldUnknown;
            }
        }
        return Label.Core_RollupBuilder_ErrorFieldUnknown;
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

    /**
     * Every entity a total can be shown on: common ones first (Account, Contact, the org's own
     * objects and the standard shortlist), then every other the user may see, by label.
     */
    private static List<Option> targetEntities() {
        List<Option> common = new List<Option>();
        List<Option> others = new List<Option>();
        Set<String> shortlist = commonStandard();
        for (Schema.SObjectType type : Schema.getGlobalDescribe().values()) {
            String name = String.valueOf(type).toLowerCase();
            if (!plausible(name) || NOT_TARGETS.contains(localName(name))) {
                continue;
            }
            Schema.DescribeSObjectResult described = type.getDescribe(
                SObjectDescribeOptions.DEFERRED
            );
            if (!offered(described, shortlist) || !described.isUpdateable()) {
                continue;
            }
            Option option = new Option(described.getName(), described.getLabel());
            option.common = isCommon(name, shortlist);
            if (option.common) {
                common.add(option);
            } else {
                others.add(option);
            }
        }
        List<Option> options = sortedOptions(common);
        options.addAll(sortedOptions(others));
        return options;
    }

    /** The standard shortlist, in lower case. */
    private static Set<String> commonStandard() {
        return new Set<String>(COMMON_STANDARD.toLowerCase().split(','));
    }

    private static Boolean isCommon(String name, Set<String> shortlist) {
        return name.endsWith('__c') || CORE_ENTITIES.contains(name) || shortlist.contains(name);
    }

    /**
     * Whether a name can be an entity the Builder offers, before paying for its describe: an
     * object of the org's own (`__c`) or a standard one, and not a companion object.
     */
    private static Boolean plausible(String name) {
        if (name.endsWith('__c')) {
            return true;
        }
        if (name.contains('__')) {
            return false;
        }
        for (String suffix : COMPANION_SUFFIXES) {
            if (name.endsWith(suffix)) {
                return false;
            }
        }
        return true;
    }

    /**
     * Whether the Builder offers this entity (ADR-0136): the user can read and query it, and it
     * is not a custom setting or retired. A standard object off the shortlist must also be one
     * people create and search for, which leaves out logs and the platform's own records.
     */
    private static Boolean offered(Schema.DescribeSObjectResult described, Set<String> shortlist) {
        if (
            !described.isQueryable() ||
            !described.isAccessible() ||
            described.isCustomSetting() ||
            described.isDeprecatedAndHidden()
        ) {
            return false;
        }
        String name = described.getName().toLowerCase();
        return isCommon(name, shortlist) || (described.isCreateable() && described.isSearchable());
    }

    private static List<SourceOption> childrenOf(Schema.SObjectType parent, String token) {
        List<SourceOption> options = new List<SourceOption>();
        Set<String> shortlist = commonStandard();
        for (
            Schema.ChildRelationship child : parent.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getChildRelationships()
        ) {
            String name = String.valueOf(child.getChildSObject()).toLowerCase();
            if (!plausible(name) || (token != null && name == 'account')) {
                continue;
            }
            Schema.DescribeSObjectResult childType = child.getChildSObject()
                .getDescribe(SObjectDescribeOptions.DEFERRED);
            Schema.DescribeFieldResult reference = child.getField().getDescribe();
            // The engine's query filters and groups on the reference (RollupAggregator).
            if (
                !offered(childType, shortlist) ||
                !reference.isFilterable() ||
                !reference.isGroupable()
            ) {
                continue;
            }
            SourceOption option = new SourceOption();
            option.sourceObject = childType.getName();
            option.relationshipPath = token == null
                ? reference.getName()
                : reference.getName() + ' > ' + token;
            option.value = option.sourceObject + '|' + option.relationshipPath;
            option.recordsLabel = childType.getLabelPlural();
            option.instant = RollupService.hasInstantUpdates(option.sourceObject);
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
        draft.orderDirection = definition.Order_Direction__c;
        draft.rowLimit = definition.Row_Limit__c == null
            ? null
            : definition.Row_Limit__c.intValue();
        draft.delimiter = definition.Delimiter__c;
        draft.customDelimiter = definition.Custom_Delimiter__c;
        draft.includeDeleted = definition.Include_Deleted__c;
        draft.filterJson = definition.Filter_JSON__c;
        draft.targetFilterJson = definition.Target_Filter_JSON__c;
        draft.fiscalYearAware = definition.Fiscal_Year_Aware__c;
        draft.fiscalYearOffset = definition.Fiscal_Year_Offset__c == null
            ? null
            : definition.Fiscal_Year_Offset__c.intValue();
        draft.fiscalDateField = definition.Fiscal_Date_Field__c;
        draft.mode = definition.Mode__c;
        draft.active = definition.Active__c;
        draft.bypassPermission = definition.Bypass_Permission__c;
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
            Order_Direction__c = draft.orderDirection == 'Descending' ? 'Descending' : 'Ascending',
            Row_Limit__c = draft.rowLimit,
            Delimiter__c = String.isBlank(draft.delimiter) ? null : draft.delimiter,
            Custom_Delimiter__c = draft.delimiter == RollupPlanner.CUSTOM_DELIMITER
                ? draft.customDelimiter
                : null,
            Include_Deleted__c = draft.includeDeleted == true,
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
            Active__c = draft.active != false,
            Bypass_Permission__c = String.isBlank(draft.bypassPermission)
                ? null
                : draft.bypassPermission.trim()
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
