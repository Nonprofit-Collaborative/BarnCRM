/**
 * Plans one pass of BarnCRM's own rollup engine over one target entity (rollup proposal, Part 2
 * section 4, "Single pass per target object").
 *
 * Every definition that writes the target entity is read once and turned into source queries.
 * Definitions that read the same source entity, through the same path alternative, with the same
 * filter and fiscal window, share one aggregate query: the 28 shipped totals on Account become a
 * handful of queries, not 28. FIRST and LAST read rows, so each has a row query of its own.
 *
 * A definition that cannot be planned is refused here, named in `refused`, and left out, so one
 * broken rollup never stops the others (R-R10). Nothing an administrator types reaches a query
 * unchecked: paths go through `RollupPath`, filters through `RollupFilterParser`, windows through
 * `RollupDateWindow`, and attribute names must be plain API names.
 *
 * What a target attribute may be depends on the aggregate (canonical model R-R15): checkbox for
 * ANY and NONE, text for the text lists, a number for COUNT_DISTINCT, text and picklists as well
 * as numbers and dates for FIRST and LAST, and numbers and dates for the rest. `targetTypeProblem` is the one
 * place that rule lives, read here and by the save check.
 */
public with sharing class RollupPlanner {
    /** Raised when a definition cannot be planned. */
    public class RollupPlanException extends Exception {
    }

    /**
     * How the calculator gathers an aggregate: grouped in the query, from ordered rows (FIRST and
     * LAST), or from every matching row, collected and ordered in Apex (COUNT_DISTINCT and the
     * text lists, which a grouped answer cannot merge across path alternatives or household
     * members).
     */
    public static final String KIND_GROUPED = 'grouped';
    public static final String KIND_ORDERED = 'ordered';
    public static final String KIND_LISTED = 'listed';

    private static final Map<String, String> KIND_BY_AGGREGATE = new Map<String, String>{
        'SUM' => KIND_GROUPED,
        'COUNT' => KIND_GROUPED,
        'MIN' => KIND_GROUPED,
        'MAX' => KIND_GROUPED,
        'AVG' => KIND_GROUPED,
        'ANY' => KIND_GROUPED,
        'NONE' => KIND_GROUPED,
        'FIRST' => KIND_ORDERED,
        'LAST' => KIND_ORDERED,
        'COUNT_DISTINCT' => KIND_LISTED,
        'TEXT_LIST' => KIND_LISTED,
        'TEXT_LIST_DISTINCT' => KIND_LISTED
    };

    /** What goes between the values of a text list, by `Delimiter__c` value; Comma when blank. */
    private static final Map<String, String> SEPARATOR_BY_DELIMITER = new Map<String, String>{
        'Comma' => ', ',
        'Semicolon' => '; ',
        'New line' => '\n',
        'Pipe' => ' | '
    };

    /** The `Delimiter__c` value whose separator is the Custom Delimiter (ADR-0136). */
    public static final String CUSTOM_DELIMITER = 'Custom';

    /** Aggregates that read no attribute of the source rows: the filter is the whole question. */
    private static final Set<String> READS_NO_FIELD = new Set<String>{ 'COUNT', 'ANY', 'NONE' };

    /**
     * Aggregates that take a row limit (R-R15, ADR-0136). A grouped query cannot limit rows per
     * target, so a limited one is read as rows, as a text list is, and the first N are kept.
     */
    public static final Set<String> ROW_LIMITED = new Set<String>{
        'SUM',
        'AVG',
        'MIN',
        'MAX',
        'TEXT_LIST',
        'TEXT_LIST_DISTINCT'
    };

    private static final Set<Schema.DisplayType> NUMBER_AND_DATE_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.LONG,
        Schema.DisplayType.CURRENCY,
        Schema.DisplayType.PERCENT,
        Schema.DisplayType.DATE,
        Schema.DisplayType.DATETIME
    };

    private static final Set<Schema.DisplayType> NUMBER_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.LONG
    };

    private static final Set<Schema.DisplayType> TEXT_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.TEXTAREA
    };

    private static final Pattern FIELD_PATH = Pattern.compile(
        '^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)*$'
    );

    /** One pass over one target entity. Lists indexed by definition share their index. */
    public class Plan {
        public Schema.SObjectType targetType;
        public List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>();
        public List<Schema.SObjectField> targetFields = new List<Schema.SObjectField>();
        /** The target filter of each definition as a where clause, or blank for every record. */
        public List<String> targetFilters = new List<String>();
        public List<SourceQuery> queries = new List<SourceQuery>();
        public List<Rollup_Definition__c> refused = new List<Rollup_Definition__c>();
    }

    /** One query against a source entity, feeding one or more definitions. */
    public class SourceQuery {
        public String sourceObject;
        /** The reference read off each source row: the target itself, or the person before a token. */
        public String keyExpression;
        /** `{Household}`, `{HouseholdMembers}`, or null for a plain path. */
        public String token;
        /** Earlier alternatives of the same path, which must be blank for this one to count (R-R1). */
        public List<String> earlierKeys = new List<String>();
        /** The filter and the fiscal window, or blank. */
        public String whereClause;
        public String kind;
        /** For an ordered query: the attribute that orders the rows, and the direction. */
        public String orderBy;
        public Boolean descending = false;
        /** True to read Recycle Bin rows and archived activities too (ALL ROWS, ADR-0136). */
        public Boolean includeDeleted = false;
        public List<Measure> measures = new List<Measure>();
    }

    /** One definition's share of a query. */
    public class Measure {
        public Integer definitionIndex;
        public String aggregate;
        /** The attribute aggregated, or null for COUNT, ANY and NONE. */
        public String field;
        /** True when the target is text, so a value is copied as it was entered, never converted. */
        public Boolean asText = false;
        /** Only the first this many rows, in the query's order, count; null for every row. */
        public Integer rowLimit;
    }

    /**
     * Why this row limit cannot be used, or null when it can or there is none (R-R10, R-R15):
     * below 1, on an aggregate that takes none, or with no order to say which rows come first.
     */
    public static String rowLimitProblem(String aggregate, Decimal rowLimit, String orderBy) {
        if (rowLimit == null) {
            return null;
        }
        if (rowLimit < 1) {
            return System.Label.Core_Rollups_ErrorRowLimitInvalid;
        }
        if (String.isBlank(aggregate) || !ROW_LIMITED.contains(aggregate.toUpperCase())) {
            return System.Label.Core_Rollups_ErrorRowLimitAggregate;
        }
        return String.isBlank(orderBy) ? System.Label.Core_Rollups_ErrorRowLimitNeedsOrder : null;
    }

    /**
     * A definition's row limit, or null. Read only when the caller queried it, so a caller that
     * queried a definition without it still calculates every row, as before ADR-0136.
     */
    private static Decimal rowLimitOf(Rollup_Definition__c definition) {
        return definition.isSet(Rollup_Definition__c.Row_Limit__c) ? definition.Row_Limit__c : null;
    }

    /** Whether a text list or row limited aggregate is ordered descending; Ascending when unread. */
    private static Boolean isDescending(Rollup_Definition__c definition) {
        return definition.isSet(Rollup_Definition__c.Order_Direction__c) &&
            definition.Order_Direction__c == 'Descending';
    }

    /** What separates the values of a text list for this `Delimiter__c` value. */
    public static String separatorFor(String delimiter) {
        return String.isNotBlank(delimiter) && SEPARATOR_BY_DELIMITER.containsKey(delimiter)
            ? SEPARATOR_BY_DELIMITER.get(delimiter)
            : SEPARATOR_BY_DELIMITER.get('Comma');
    }

    /**
     * What separates the values of this definition's text list: the Custom Delimiter exactly as
     * stored when Delimiter is Custom (Comma if it is empty), otherwise as above.
     */
    public static String separatorOf(Rollup_Definition__c definition) {
        if (
            definition.Delimiter__c == CUSTOM_DELIMITER &&
            definition.isSet(Rollup_Definition__c.Custom_Delimiter__c) &&
            String.isNotEmpty(definition.Custom_Delimiter__c)
        ) {
            return definition.Custom_Delimiter__c;
        }
        return separatorFor(definition.Delimiter__c);
    }

    /** Why this delimiter cannot be saved (R-R10): Custom with nothing to write. */
    public static String delimiterProblem(String delimiter, String customDelimiter) {
        return delimiter == CUSTOM_DELIMITER && String.isEmpty(customDelimiter)
            ? System.Label.Core_Rollups_ErrorCustomDelimiterNeeded
            : null;
    }

    /**
     * Why this aggregate cannot fill a target attribute of this type, in words an administrator
     * reads, or null when it can (canonical model R-R15).
     *
     * @param aggregate the stored Aggregate value
     * @param type the target attribute's type
     */
    public static String targetTypeProblem(String aggregate, Schema.DisplayType type) {
        String operation = String.isBlank(aggregate) ? '' : aggregate.toUpperCase();
        if (operation == 'ANY' || operation == 'NONE') {
            return type == Schema.DisplayType.BOOLEAN
                ? null
                : System.Label.Core_Rollups_ErrorTargetNeedsCheckbox;
        }
        if (operation == 'TEXT_LIST' || operation == 'TEXT_LIST_DISTINCT') {
            return TEXT_TYPES.contains(type)
                ? null
                : System.Label.Core_Rollups_ErrorTargetNeedsText;
        }
        if (operation == 'COUNT_DISTINCT') {
            return NUMBER_TYPES.contains(type)
                ? null
                : System.Label.Core_Rollups_ErrorTargetNeedsNumber;
        }
        if (type == Schema.DisplayType.BOOLEAN) {
            return System.Label.Core_Rollups_ErrorCheckboxTarget;
        }
        if (TEXT_TYPES.contains(type)) {
            return operation == 'FIRST' ||
                operation == 'LAST'
                ? null
                : System.Label.Core_Rollups_ErrorTextTarget;
        }
        // A picklist holds one of its values: FIRST and LAST copy one (ADR-0136).
        if (type == Schema.DisplayType.PICKLIST) {
            return operation == 'FIRST' ||
                operation == 'LAST'
                ? null
                : System.Label.Core_Rollups_ErrorPicklistTarget;
        }
        return NUMBER_AND_DATE_TYPES.contains(type)
            ? null
            : System.Label.Core_Rollups_ErrorTargetType;
    }

    /**
     * What the save check refuses (canonical model R-R10): a target attribute whose type does not
     * suit the aggregate, and a COUNT_DISTINCT or text list with nothing to read. A target entity
     * or attribute this org does not have is left to the planner, which refuses it at run time,
     * so a definition for a module that is not installed can still be saved.
     *
     * @param definition the definition about to be saved
     * @return the message to show, or null when the save may go ahead
     */
    public static String saveProblem(Rollup_Definition__c definition) {
        String optionProblem = rowLimitProblem(
            definition.Aggregate__c,
            rowLimitOf(definition),
            definition.Order_By_Field__c
        );
        if (optionProblem == null) {
            optionProblem = delimiterProblem(
                definition.Delimiter__c,
                definition.Custom_Delimiter__c
            );
        }
        if (optionProblem != null) {
            return optionProblem;
        }
        Schema.SObjectType targetType = SettingsService.typeByName(definition.Target_Object__c);
        if (targetType == null || String.isBlank(definition.Target_Field__c)) {
            return null;
        }
        Schema.SObjectField field = targetType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap()
            .get(definition.Target_Field__c.trim().toLowerCase());
        if (field == null) {
            return null;
        }
        String problem = targetTypeProblem(definition.Aggregate__c, field.getDescribe().getType());
        String kind = String.isBlank(definition.Aggregate__c)
            ? null
            : KIND_BY_AGGREGATE.get(definition.Aggregate__c.toUpperCase());
        if (problem == null && kind == KIND_LISTED && String.isBlank(definition.Source_Field__c)) {
            problem = System.Label.Core_Rollups_ErrorSourceFieldNeeded;
        }
        return problem;
    }

    /**
     * Plans every given definition that targets this entity.
     *
     * @param targetType the entity written
     * @param definitions the definitions to calculate; those for another entity are ignored
     */
    public static Plan plan(Schema.SObjectType targetType, List<Rollup_Definition__c> definitions) {
        Plan result = new Plan();
        result.targetType = targetType;
        if (targetType == null || definitions == null) {
            return result;
        }
        String targetName = String.valueOf(targetType);
        Map<String, Schema.SObjectField> targetFieldMap = targetType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .fields.getMap();
        Map<String, SourceQuery> queryByKey = new Map<String, SourceQuery>();
        for (Rollup_Definition__c definition : definitions) {
            if (!targetName.equalsIgnoreCase(definition.Target_Object__c)) {
                continue;
            }
            try {
                Schema.SObjectField targetField = writableTarget(definition, targetFieldMap);
                String targetFilter = RollupFilterParser.toWhereClause(
                    definition.Target_Filter_JSON__c,
                    targetType
                );
                List<SourceQuery> planned = queriesFor(definition);
                Integer index = result.definitions.size();
                result.definitions.add(definition);
                result.targetFields.add(targetField);
                result.targetFilters.add(targetFilter);
                Schema.DisplayType fieldType = targetField.getDescribe().getType();
                Boolean asText =
                    TEXT_TYPES.contains(fieldType) || fieldType == Schema.DisplayType.PICKLIST;
                for (SourceQuery query : planned) {
                    query.measures[0].definitionIndex = index;
                    query.measures[0].asText = asText;
                    foldInto(query, queryByKey, result.queries);
                }
            } catch (Exception refused) {
                result.refused.add(definition);
                ErrorLogger.log(refused, 'RollupPlanner.plan', definition.Id);
            }
        }
        return result;
    }

    /**
     * The target attribute, refused unless it exists, the engine can write it, and it has a type
     * we fill.
     */
    private static Schema.SObjectField writableTarget(
        Rollup_Definition__c definition,
        Map<String, Schema.SObjectField> targetFieldMap
    ) {
        Schema.SObjectField field = String.isBlank(definition.Target_Field__c)
            ? null
            : targetFieldMap.get(definition.Target_Field__c.toLowerCase());
        if (field == null || !engineCanWrite(field.getDescribe())) {
            throw new RollupPlanException(System.Label.Core_Rollups_ErrorTargetNotWritable);
        }
        String problem = targetTypeProblem(definition.Aggregate__c, field.getDescribe().getType());
        if (problem != null) {
            throw new RollupPlanException(problem);
        }
        return field;
    }

    /**
     * Whether the engine can write this attribute at all (R-R10), not whether the running user
     * may edit it. A run plans for whoever saved the record that set it off, and `RollupWriter`
     * writes the totals in system mode on the administrator's definition's behalf (ADR-0021).
     * Every module's non-admin permission sets keep the totals read only, so the running user's
     * field-level security would refuse every definition on a staff member's save and leave the
     * totals to the nightly run. The administrator's own access is checked where an administrator
     * acts: the Rollup Builder's save and its list of target attributes.
     *
     * A formula, roll-up summary or auto number attribute is never written. Otherwise the
     * attribute is writable for this user, or kept from them only by field-level security: a
     * permissionable attribute is one an administrator can grant edit on, which a system
     * attribute (Id, CreatedDate, LastModifiedDate and the like) is not.
     */
    @TestVisible
    private static Boolean engineCanWrite(Schema.DescribeFieldResult field) {
        if (field.isCalculated() || field.isAutoNumber()) {
            return false;
        }
        return field.isUpdateable() || field.isPermissionable();
    }

    /** One query per path alternative, each carrying this definition's one measure. */
    private static List<SourceQuery> queriesFor(Rollup_Definition__c definition) {
        String aggregate = String.isBlank(definition.Aggregate__c)
            ? ''
            : definition.Aggregate__c.toUpperCase();
        String kind = KIND_BY_AGGREGATE.get(aggregate);
        if (kind == null) {
            throw new RollupPlanException(System.Label.Core_Rollups_ErrorInvalidOperator);
        }
        if (SettingsService.typeByName(definition.Source_Object__c) == null) {
            throw new RollupPlanException(System.Label.Core_Rollups_ErrorUnknownObject);
        }
        if (!READS_NO_FIELD.contains(aggregate) && String.isBlank(definition.Source_Field__c)) {
            throw new RollupPlanException(System.Label.Core_Rollups_ErrorSourceFieldNeeded);
        }
        String field = READS_NO_FIELD.contains(aggregate)
            ? null
            : checkedPath(definition.Source_Field__c);
        Decimal rowLimit = rowLimitOf(definition);
        String limitProblem = rowLimitProblem(aggregate, rowLimit, definition.Order_By_Field__c);
        if (limitProblem != null) {
            throw new RollupPlanException(limitProblem);
        }
        if (rowLimit != null) {
            kind = KIND_LISTED;
        }
        // FIRST and LAST need an order; a text list may have one, and is otherwise alphabetical;
        // a row limit has one (checked above).
        String orderBy = kind == KIND_ORDERED ||
            (kind == KIND_LISTED && String.isNotBlank(definition.Order_By_Field__c))
            ? checkedPath(definition.Order_By_Field__c)
            : null;
        String whereClause = whereClauseFor(definition);

        List<SourceQuery> queries = new List<SourceQuery>();
        List<String> earlier = new List<String>();
        for (
            RollupPath.Branch branch : RollupPath.parse(definition.Relationship_Path__c).branches
        ) {
            SourceQuery query = new SourceQuery();
            query.sourceObject = definition.Source_Object__c;
            query.token = tokenOf(branch);
            query.keyExpression = keyExpressionFor(branch.referencePrefix());
            query.earlierKeys.addAll(earlier);
            query.whereClause = whereClause;
            query.kind = kind;
            query.orderBy = orderBy;
            // FIRST is the lowest and LAST the highest whatever the direction (R-R15), so a
            // saved definition means what it always meant.
            query.descending = kind == KIND_LISTED ? isDescending(definition) : aggregate == 'LAST';
            // Read only when the caller queried it, so such a caller calculates as before.
            query.includeDeleted =
                definition.isSet(Rollup_Definition__c.Include_Deleted__c) &&
                definition.Include_Deleted__c == true;
            Measure measure = new Measure();
            measure.aggregate = aggregate;
            measure.field = field;
            measure.rowLimit = rowLimit == null ? null : rowLimit.intValue();
            query.measures.add(measure);
            queries.add(query);
            earlier.add(query.keyExpression);
        }
        return queries;
    }

    /** A token may only end a path: nothing is walked from a household onwards. */
    private static String tokenOf(RollupPath.Branch branch) {
        String token;
        for (Integer i = 0; i < branch.segments.size(); i++) {
            if (RollupPath.isToken(branch.segments[i])) {
                if (i != branch.segments.size() - 1) {
                    throw new RollupPlanException(System.Label.Core_Rollups_ErrorInvalidFilter);
                }
                token = RollupPath.TOKEN_HOUSEHOLD.equalsIgnoreCase(branch.segments[i])
                    ? RollupPath.TOKEN_HOUSEHOLD
                    : RollupPath.TOKEN_HOUSEHOLD_MEMBERS;
            }
        }
        return token;
    }

    /**
     * The reference to read off a source row: `Donor_Account__c` for one hop,
     * `Donor_Contact__r.AccountId` for two, and the row's own `Id` when a token starts the path.
     */
    @TestVisible
    private static String keyExpressionFor(List<String> segments) {
        if (segments.isEmpty()) {
            return 'Id';
        }
        List<String> parts = new List<String>();
        for (Integer i = 0; i < segments.size() - 1; i++) {
            parts.add(RollupPath.relationshipNameFor(segments[i]));
        }
        parts.add(segments[segments.size() - 1]);
        return String.join(parts, '.');
    }

    /** The filter and the fiscal window of one definition, as one WHERE clause. */
    private static String whereClauseFor(Rollup_Definition__c definition) {
        List<String> fragments = new List<String>();
        String filterClause = RollupFilterParser.toWhereClause(
            definition.Filter_JSON__c,
            SettingsService.typeByName(definition.Source_Object__c)
        );
        if (String.isNotBlank(filterClause)) {
            fragments.add('(' + filterClause + ')');
        }
        String dateField = String.isNotBlank(definition.Fiscal_Date_Field__c)
            ? definition.Fiscal_Date_Field__c
            : definition.Source_Field__c;
        String windowClause = RollupDateWindow.toWhereClause(
            definition.Fiscal_Year_Aware__c,
            definition.Fiscal_Year_Offset__c == null
                ? 0
                : definition.Fiscal_Year_Offset__c.intValue(),
            definition.Fiscal_Year_Aware__c == true ? checkedPath(dateField) : dateField
        );
        if (String.isNotBlank(windowClause)) {
            fragments.add('(' + windowClause + ')');
        }
        return String.join(fragments, ' AND ');
    }

    /** An attribute name, or a dotted path to one, and nothing else. */
    private static String checkedPath(String value) {
        if (String.isBlank(value) || !FIELD_PATH.matcher(value.trim()).matches()) {
            throw new RollupPlanException(System.Label.Core_Rollups_ErrorInvalidOperator);
        }
        return value.trim();
    }

    /** Folds a single-measure query into an existing one that reads the same rows. */
    private static void foldInto(
        SourceQuery query,
        Map<String, SourceQuery> queryByKey,
        List<SourceQuery> queries
    ) {
        String key = String.join(
                new List<String>{
                    query.sourceObject,
                    query.keyExpression,
                    String.valueOf(query.token),
                    String.join(query.earlierKeys, ','),
                    query.whereClause,
                    query.kind,
                    String.valueOf(query.orderBy),
                    String.valueOf(query.descending),
                    String.valueOf(query.includeDeleted)
                },
                '|'
            )
            .toLowerCase();
        if (queryByKey.containsKey(key)) {
            queryByKey.get(key).measures.addAll(query.measures);
            return;
        }
        queryByKey.put(key, query);
        queries.add(query);
    }
}
