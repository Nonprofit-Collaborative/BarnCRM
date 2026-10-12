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
 * What a target attribute may be, for now: a number, currency, percent, date or datetime.
 * Checkbox targets wait for the operations slice, and text targets wait for the slice that adds
 * text FIRST and LAST and COUNT DISTINCT. Those slices add an entry to `KIND_BY_AGGREGATE` and to
 * `WRITABLE_TYPES`; nothing else in the planner changes.
 */
public with sharing class RollupPlanner {
    /** Raised when a definition cannot be planned. */
    public class RollupPlanException extends Exception {
    }

    /** How the calculator gathers an aggregate: grouped in the query, or from ordered rows. */
    public static final String KIND_GROUPED = 'grouped';
    public static final String KIND_ORDERED = 'ordered';

    private static final Map<String, String> KIND_BY_AGGREGATE = new Map<String, String>{
        'SUM' => KIND_GROUPED,
        'COUNT' => KIND_GROUPED,
        'MIN' => KIND_GROUPED,
        'MAX' => KIND_GROUPED,
        'AVG' => KIND_GROUPED,
        'FIRST' => KIND_ORDERED,
        'LAST' => KIND_ORDERED
    };

    private static final Set<Schema.DisplayType> WRITABLE_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.LONG,
        Schema.DisplayType.CURRENCY,
        Schema.DisplayType.PERCENT,
        Schema.DisplayType.DATE,
        Schema.DisplayType.DATETIME
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
        public List<Measure> measures = new List<Measure>();
    }

    /** One definition's share of a query. */
    public class Measure {
        public Integer definitionIndex;
        public String aggregate;
        /** The attribute aggregated, or null for COUNT. */
        public String field;
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
                    definition.Target_Filter_JSON__c
                );
                List<SourceQuery> planned = queriesFor(definition);
                Integer index = result.definitions.size();
                result.definitions.add(definition);
                result.targetFields.add(targetField);
                result.targetFilters.add(targetFilter);
                for (SourceQuery query : planned) {
                    query.measures[0].definitionIndex = index;
                    foldInto(query, queryByKey, result.queries);
                }
            } catch (Exception refused) {
                result.refused.add(definition);
                ErrorLogger.log(refused, 'RollupPlanner.plan', definition.Id);
            }
        }
        return result;
    }

    /** The target attribute, refused unless it exists, can be written, and has a type we fill. */
    private static Schema.SObjectField writableTarget(
        Rollup_Definition__c definition,
        Map<String, Schema.SObjectField> targetFieldMap
    ) {
        Schema.SObjectField field = String.isBlank(definition.Target_Field__c)
            ? null
            : targetFieldMap.get(definition.Target_Field__c.toLowerCase());
        if (field == null) {
            throw new RollupPlanException(System.Label.Core_Rollups_ErrorUnknownObject);
        }
        Schema.DescribeFieldResult describe = field.getDescribe();
        if (!describe.isUpdateable() || !WRITABLE_TYPES.contains(describe.getType())) {
            throw new RollupPlanException(System.Label.Core_Rollups_ErrorInvalidOperator);
        }
        return field;
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
        String field = aggregate == 'COUNT' ? null : checkedPath(definition.Source_Field__c);
        String orderBy = kind == KIND_ORDERED ? checkedPath(definition.Order_By_Field__c) : null;
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
            query.descending = aggregate == 'LAST';
            Measure measure = new Measure();
            measure.aggregate = aggregate;
            measure.field = field;
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

    /** The filter and the fiscal window, as `RollupAdapter` builds them for the vendored engine. */
    private static String whereClauseFor(Rollup_Definition__c definition) {
        List<String> fragments = new List<String>();
        String filterClause = RollupFilterParser.toWhereClause(definition.Filter_JSON__c);
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
                    String.valueOf(query.descending)
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
