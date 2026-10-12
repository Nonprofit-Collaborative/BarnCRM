/**
 * Turns a Rollup Definition filter document into the where clause the rollup engine understands.
 *
 * The document format is canonical model R-R2: a version, an optional logic string, and a list of
 * conditions of {id, field, operator, value}. Maria never sees it; the filter builder on the
 * Rollups page writes it and this class reads it. Nothing an administrator types reaches a query
 * without passing through here: every operator is checked against a fixed list, every string value
 * is escaped, and a logic string that is not made of condition numbers and the words AND, OR and
 * NOT is refused.
 */
public with sharing class RollupFilterParser {
    /** Raised when a filter document cannot be turned into a where clause. */
    public class RollupFilterException extends Exception {
    }

    private static final Integer SUPPORTED_VERSION = 1;

    /** Operators the filter builder offers, mapped to the comparison the engine parses. */
    private static final Map<String, String> COMPARISON_BY_OPERATOR = new Map<String, String>{
        'equals' => '=',
        'not equals' => '!=',
        'less than' => '<',
        'less or equal' => '<=',
        'greater than' => '>',
        'greater or equal' => '>=',
        'contains' => 'like',
        'does not contain' => 'not like',
        'starts with' => 'like',
        'is null' => '=',
        'is not null' => '!=',
        'in' => 'in',
        'not in' => 'not in'
    };

    private static final Set<String> NO_VALUE_OPERATORS = new Set<String>{
        'is null',
        'is not null'
    };
    private static final Set<String> LIST_OPERATORS = new Set<String>{ 'in', 'not in' };
    private static final Pattern DATE_VALUE = Pattern.compile('^\\d{4}-\\d{2}-\\d{2}$');
    private static final Pattern DATETIME_VALUE = Pattern.compile(
        '^\\d{4}-\\d{2}-\\d{2}T[0-9:.]+Z$'
    );
    private static final Pattern FIELD_NAME = Pattern.compile(
        '^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)*$'
    );
    private static final Pattern LOGIC_TOKEN = Pattern.compile('^(\\d+|AND|OR|NOT|\\(|\\))$');

    /**
     * Renders a filter document as a where clause fragment, or an empty string when the document
     * is empty. The caller joins the result with any other fragment it has.
     */
    public static String toWhereClause(String filterDocument) {
        if (String.isBlank(filterDocument)) {
            return '';
        }
        Map<String, Object> parsed;
        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(filterDocument);
        } catch (Exception parseFailure) {
            throw new RollupFilterException(System.Label.Core_Rollups_ErrorInvalidFilter);
        }
        Integer version = parsed.get('version') == null
            ? SUPPORTED_VERSION
            : Integer.valueOf(parsed.get('version'));
        if (version != SUPPORTED_VERSION) {
            throw new RollupFilterException(System.Label.Core_Rollups_ErrorInvalidFilter);
        }
        List<Object> rawConditions = (List<Object>) parsed.get('conditions');
        if (rawConditions == null || rawConditions.isEmpty()) {
            return '';
        }

        Map<String, String> clauseByConditionId = new Map<String, String>();
        List<String> inOrder = new List<String>();
        Integer fallbackId = 0;
        for (Object rawCondition : rawConditions) {
            fallbackId++;
            Map<String, Object> condition = (Map<String, Object>) rawCondition;
            String conditionId = condition.get('id') == null
                ? String.valueOf(fallbackId)
                : String.valueOf(condition.get('id'));
            String clause = renderCondition(condition);
            clauseByConditionId.put(conditionId, clause);
            inOrder.add(clause);
        }

        String logic = (String) parsed.get('logic');
        if (String.isBlank(logic)) {
            return String.join(inOrder, ' AND ');
        }
        return renderLogic(logic, clauseByConditionId);
    }

    /**
     * The attribute names a filter document's conditions test, as written (`Status__c`,
     * `Gift__r.Status__c`), so the engine can tell which changes move a total (R-R11). A document
     * that cannot be read names nothing; `toWhereClause` is what refuses it.
     */
    public static Set<String> fieldsOf(String filterDocument) {
        Set<String> fields = new Set<String>();
        if (String.isBlank(filterDocument)) {
            return fields;
        }
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
                filterDocument
            );
            for (Object rawCondition : (List<Object>) parsed.get('conditions')) {
                String fieldName = (String) ((Map<String, Object>) rawCondition).get('field');
                if (String.isNotBlank(fieldName) && FIELD_NAME.matcher(fieldName).matches()) {
                    fields.add(fieldName.trim());
                }
            }
        } catch (Exception unreadable) {
            return new Set<String>();
        }
        return fields;
    }

    /** One condition as `Field operator value`. */
    private static String renderCondition(Map<String, Object> condition) {
        String fieldName = (String) condition.get('field');
        String operator = ((String) condition.get('operator'))?.toLowerCase()?.trim();
        if (String.isBlank(fieldName) || FIELD_NAME.matcher(fieldName).matches() == false) {
            throw new RollupFilterException(System.Label.Core_Rollups_ErrorInvalidFilter);
        }
        if (COMPARISON_BY_OPERATOR.containsKey(operator) == false) {
            throw new RollupFilterException(System.Label.Core_Rollups_ErrorInvalidOperator);
        }
        String comparison = COMPARISON_BY_OPERATOR.get(operator);
        if (NO_VALUE_OPERATORS.contains(operator)) {
            return fieldName + ' ' + comparison + ' null';
        }
        Object rawValue = condition.get('value');
        if (LIST_OPERATORS.contains(operator)) {
            List<Object> values = rawValue instanceof List<Object>
                ? (List<Object>) rawValue
                : new List<Object>{ rawValue };
            List<String> rendered = new List<String>();
            for (Object value : values) {
                rendered.add(renderValue(value));
            }
            return fieldName + ' ' + comparison + ' (' + String.join(rendered, ',') + ')';
        }
        if (operator == 'contains' || operator == 'does not contain') {
            return fieldName +
                ' ' +
                comparison +
                ' ' +
                renderValue('%' + String.valueOf(rawValue) + '%');
        }
        if (operator == 'starts with') {
            return fieldName + ' ' + comparison + ' ' + renderValue(String.valueOf(rawValue) + '%');
        }
        return fieldName + ' ' + comparison + ' ' + renderValue(rawValue);
    }

    /**
     * Numbers, booleans, dates and datetimes go in unquoted, because both the engine's query and
     * its in-memory evaluator read them that way. Everything else is a string: it is quoted and
     * escaped, which is the only place an administrator's typing reaches a query.
     */
    private static String renderValue(Object value) {
        if (value == null) {
            return 'null';
        }
        if (
            value instanceof Boolean ||
            value instanceof Decimal ||
            value instanceof Integer ||
            value instanceof Double ||
            value instanceof Long
        ) {
            return String.valueOf(value);
        }
        String text = String.valueOf(value);
        if (DATE_VALUE.matcher(text).matches() || DATETIME_VALUE.matcher(text).matches()) {
            return text;
        }
        return '\'' + String.escapeSingleQuotes(text) + '\'';
    }

    /**
     * Substitutes each condition number in the logic string with its clause. Every token has to be
     * a condition number, a bracket, or one of AND, OR and NOT, so nothing else can be smuggled in.
     */
    private static String renderLogic(String logic, Map<String, String> clauseByConditionId) {
        String spaced = logic.replace('(', ' ( ').replace(')', ' ) ');
        List<String> tokens = spaced.trim().split('\\s+');
        List<String> rendered = new List<String>();
        for (String token : tokens) {
            String upper = token.toUpperCase();
            if (LOGIC_TOKEN.matcher(upper).matches() == false) {
                throw new RollupFilterException(System.Label.Core_Rollups_ErrorInvalidFilter);
            }
            if (clauseByConditionId.containsKey(token)) {
                rendered.add('(' + clauseByConditionId.get(token) + ')');
            } else if (
                upper == 'AND' ||
                upper == 'OR' ||
                upper == 'NOT' ||
                upper == '(' ||
                upper == ')'
            ) {
                rendered.add(upper);
            } else {
                throw new RollupFilterException(System.Label.Core_Rollups_ErrorInvalidFilter);
            }
        }
        return String.join(rendered, ' ');
    }
}
