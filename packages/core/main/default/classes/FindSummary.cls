/**
 * A Find summary (C-36, canonical model R-SQ9): count, total, lowest or highest value of the
 * records a query document matches, optionally grouped by one field, in one aggregate query.
 *
 * The records are the document's own (filter and related records), compiled by QueryCompiler;
 * the measured and grouping fields are resolved through QueryFieldCatalog as the running user,
 * and the query runs in user mode. The records are counted first, at most MAX_RECORDS plus one,
 * so the count and the aggregate together stay inside one request's query rows.
 */
public with sharing class FindSummary {
    public static final Integer MAX_RECORDS = 20000;
    public static final Integer MAX_GROUPS = 2000;
    private static final Pattern FIELD_PATH = Pattern.compile(
        '^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)*$'
    );
    private static final Map<String, String> SOQL_BY_FUNCTION = new Map<String, String>{
        'count' => 'COUNT',
        'sum' => 'SUM',
        'min' => 'MIN',
        'max' => 'MAX'
    };
    private static final Set<Schema.DisplayType> NUMBERS = new Set<Schema.DisplayType>{
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.CURRENCY,
        Schema.DisplayType.PERCENT,
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.LONG
    };
    private static final Set<Schema.DisplayType> DATES = new Set<Schema.DisplayType>{
        Schema.DisplayType.DATE,
        Schema.DisplayType.DATETIME
    };

    /** One line of a summary: the group's value (null for blank) and the result. */
    public class SummaryLine {
        @AuraEnabled
        public String groupValue;
        @AuraEnabled
        public String groupLabel;
        @AuraEnabled
        public Object value;
    }

    /** A summary and the SOQL it ran, for display only. */
    public class SummaryResult {
        @AuraEnabled
        public String soql;
        @AuraEnabled
        public List<SummaryLine> lines = new List<SummaryLine>();
        /** True when there were more groups than MAX_GROUPS and only the first are shown. */
        @AuraEnabled
        public Boolean capped = false;
    }

    /** Runs the document's summary as the running user. */
    public static SummaryResult summarize(String queryJson) {
        QueryCompiler.QueryDocument document = QueryCompiler.parse(queryJson);
        Map<String, Object> aggregate = document.aggregate;
        String function = aggregate == null ||
            aggregate.get('function') == null
            ? ''
            : String.valueOf(aggregate.get('function')).toLowerCase();
        if (!SOQL_BY_FUNCTION.containsKey(function)) {
            throw new QueryCompiler.QueryCompilerException(System.Label.Core_Find_ErrorSummary);
        }
        QueryCompiler.Compiled records = QueryCompiler.compileSelection(
            queryJson,
            new Set<String>{ 'Id' },
            null
        );
        String measured = function == 'count'
            ? 'Id'
            : measuredField(records.objectName, function, aggregate.get('field'));
        String groupPath = aggregate.get('groupBy') == null ||
            String.isBlank(String.valueOf(aggregate.get('groupBy')))
            ? null
            : String.valueOf(aggregate.get('groupBy'));
        Schema.DescribeFieldResult groupField = groupPath == null
            ? null
            : groupingField(records.objectName, groupPath);

        if (QueryCompiler.count(queryJson, MAX_RECORDS + 1) > MAX_RECORDS) {
            throw new QueryCompiler.QueryCompilerException(
                String.format(
                    System.Label.Core_Find_ErrorSummaryTooMany,
                    new List<Object>{ MAX_RECORDS.format() }
                )
            );
        }

        String head =
            'SELECT ' +
            (groupPath == null ? '' : groupPath + ' grp, ') +
            SOQL_BY_FUNCTION.get(function) +
            '(' +
            measured +
            ') val';
        String tail = groupPath == null
            ? ''
            : ' GROUP BY ' + groupPath + ' ORDER BY ' + groupPath + ' NULLS FIRST';
        String shownFromWhere = records.display.substring(records.display.indexOf(' FROM '));
        Map<String, Object> binds = new Map<String, Object>(records.binds);
        if (groupPath != null) {
            binds.put('groupLimit', MAX_GROUPS + 1);
        }
        SummaryResult result = new SummaryResult();
        result.soql =
            head +
            shownFromWhere +
            tail +
            (groupPath == null ? '' : ' LIMIT ' + MAX_GROUPS);

        Map<String, String> labelByValue = picklistLabels(groupField);
        for (
            AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
                head + records.fromWhere + tail + (groupPath == null ? '' : ' LIMIT :groupLimit'),
                binds,
                AccessLevel.USER_MODE
            )
        ) {
            if (result.lines.size() == MAX_GROUPS) {
                result.capped = true;
                break;
            }
            SummaryLine line = new SummaryLine();
            Object grouped = groupPath == null ? null : row.get('grp');
            line.groupValue = groupText(groupField, grouped);
            line.groupLabel = line.groupValue == null
                ? null
                : (labelByValue.containsKey(line.groupValue)
                      ? labelByValue.get(line.groupValue)
                      : line.groupValue);
            line.value = row.get('val');
            result.lines.add(line);
        }
        return result;
    }

    /**
     * A group's value as text. A date is cast first: an untyped date written as text gains a
     * time of day ("2026-01-05 00:00:00"), the trap FilterValueBinder notes too.
     */
    @TestVisible
    private static String groupText(Schema.DescribeFieldResult field, Object grouped) {
        if (grouped == null) {
            return null;
        }
        if (field != null && field.getType() == Schema.DisplayType.DATE) {
            return String.valueOf((Date) grouped);
        }
        return String.valueOf(grouped);
    }

    /** The field a sum, lowest or highest measures, or a refusal naming it. */
    private static String measuredField(String objectName, String function, Object rawPath) {
        String path = rawPath == null ? '' : String.valueOf(rawPath);
        Schema.DescribeFieldResult field = resolve(objectName, path);
        Schema.DisplayType type = field.getType();
        Boolean fits = function == 'sum'
            ? NUMBERS.contains(type)
            : NUMBERS.contains(type) || DATES.contains(type);
        if (!fits || !field.isAggregatable()) {
            throw new QueryCompiler.QueryCompilerException(
                String.format(
                    System.Label.Core_Find_ErrorSummaryField,
                    new List<Object>{ field.getLabel() }
                )
            );
        }
        return path;
    }

    private static Schema.DescribeFieldResult groupingField(String objectName, String path) {
        Schema.DescribeFieldResult field = resolve(objectName, path);
        if (!field.isGroupable()) {
            throw new QueryCompiler.QueryCompilerException(
                String.format(
                    System.Label.Core_Find_ErrorSummaryGroup,
                    new List<Object>{ field.getLabel() }
                )
            );
        }
        return field;
    }

    private static Schema.DescribeFieldResult resolve(String objectName, String path) {
        if (!FIELD_PATH.matcher(path).matches()) {
            throw new QueryCompiler.QueryCompilerException(
                String.format(
                    System.Label.Core_Filter_ErrorUnknownField,
                    new List<Object>{ path.abbreviate(80) }
                )
            );
        }
        try {
            return QueryFieldCatalog.resolvePath(objectName, path);
        } catch (QueryFieldCatalog.QueryFieldCatalogException refused) {
            throw new QueryCompiler.QueryCompilerException(refused.getMessage());
        }
    }

    private static Map<String, String> picklistLabels(Schema.DescribeFieldResult field) {
        Map<String, String> labels = new Map<String, String>();
        if (field == null) {
            return labels;
        }
        for (Schema.PicklistEntry entry : field.getPicklistValues()) {
            labels.put(entry.getValue(), entry.getLabel());
        }
        return labels;
    }
}
