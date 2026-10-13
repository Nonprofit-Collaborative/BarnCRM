/**
 * Turns a Rollup Definition filter document into the where clause the rollup engine understands.
 *
 * The document format is canonical model R-R2: a version, an optional logic string, and a list of
 * conditions of {id, field, operator, value}. Maria never sees it; the filter builder on the
 * Rollups page writes it and this class reads it. Nothing an administrator types reaches a query
 * without passing through here: every operator is checked against a fixed list, every string value
 * is escaped, and a logic string that is not made of condition numbers and the words AND, OR and
 * NOT is refused.
 *
 * Two renderings share that parsing. `toWhereClause` writes escaped literals, which the rollup
 * engine reads. `toBoundClause` (Find, C-34) checks every field against the running user's
 * describe of a named object and puts every value in a bind variable (FilterValueBinder), so
 * nothing typed is ever concatenated into the query (plan Section 4.9, ADR-0047).
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

    /**
     * Relative date operators (R-R2 extensions). They render as the platform's date literals, and
     * the only value any of them takes is a whole number of days, written back from an Integer.
     */
    private static final Map<String, String> DATE_LITERAL_BY_OPERATOR = new Map<String, String>{
        'this year' => 'THIS_YEAR',
        'last year' => 'LAST_YEAR'
    };
    private static final String LAST_N_DAYS = 'last n days';
    private static final Integer MAX_DAYS = 3650;
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
        return compile(filterDocument, null, null);
    }

    /**
     * The same, for conditions on this entity: a value shaped like a date is written as a date
     * only when its attribute is a date or a date and time, and quoted as text otherwise, so
     * `2026-01-01` in a text attribute is compared as text (ROLLUPS-15).
     */
    public static String toWhereClause(String filterDocument, Schema.SObjectType entity) {
        return compile(filterDocument, null, entity);
    }

    /**
     * Whether a filter document compares a date with today: is this year, is last year or is in
     * the last N days. Such a total changes as the date moves on, with no record saved
     * (ROLLUPS-8). A document that cannot be read compares nothing.
     */
    public static Boolean usesRelativeDate(String filterDocument) {
        if (String.isBlank(filterDocument)) {
            return false;
        }
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
                filterDocument
            );
            for (Object rawCondition : (List<Object>) parsed.get('conditions')) {
                String operator = ((String) ((Map<String, Object>) rawCondition).get('operator'))
                    ?.toLowerCase()
                    ?.trim();
                if (DATE_LITERAL_BY_OPERATOR.containsKey(operator) || operator == LAST_N_DAYS) {
                    return true;
                }
            }
        } catch (Exception unreadable) {
            return false;
        }
        return false;
    }

    /**
     * Renders a filter document over one object with every value in a bind variable. The clause
     * is empty when the document is; the binder carries the values and the display rendering.
     */
    public static FilterValueBinder toBoundClause(String filterDocument, String objectApiName) {
        return toBoundClause(filterDocument, new FilterValueBinder(objectApiName));
    }

    /** The same, with bind names of the caller's own prefix (C-36, related records). */
    public static FilterValueBinder toBoundClause(
        String filterDocument,
        String objectApiName,
        String bindPrefix
    ) {
        return toBoundClause(filterDocument, new FilterValueBinder(objectApiName, bindPrefix));
    }

    private static FilterValueBinder toBoundClause(
        String filterDocument,
        FilterValueBinder binder
    ) {
        binder.clause = compile(filterDocument, binder, null);
        return binder;
    }

    private static String compile(
        String filterDocument,
        FilterValueBinder binder,
        Schema.SObjectType entity
    ) {
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
            String clause = renderCondition(condition, binder, entity);
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

    /**
     * One condition as `Field operator value`. With a binder, the field is checked against the
     * running user's describe and every value becomes a bind variable; without one, values are
     * escaped literals for the rollup engine.
     */
    private static String renderCondition(
        Map<String, Object> condition,
        FilterValueBinder binder,
        Schema.SObjectType entity
    ) {
        String fieldName = (String) condition.get('field');
        String operator = ((String) condition.get('operator'))?.toLowerCase()?.trim();
        if (String.isBlank(fieldName) || FIELD_NAME.matcher(fieldName).matches() == false) {
            throw new RollupFilterException(System.Label.Core_Rollups_ErrorInvalidFilter);
        }
        if (binder != null) {
            fieldName = binder.useField(fieldName, operator);
            return binder.render(fieldName, operator, condition.get('value'));
        }
        if (DATE_LITERAL_BY_OPERATOR.containsKey(operator)) {
            return fieldName + ' = ' + DATE_LITERAL_BY_OPERATOR.get(operator);
        }
        if (operator == LAST_N_DAYS) {
            return fieldName + ' = LAST_N_DAYS:' + dayCount(condition.get('value'));
        }
        if (COMPARISON_BY_OPERATOR.containsKey(operator) == false) {
            throw new RollupFilterException(System.Label.Core_Rollups_ErrorInvalidOperator);
        }
        String comparison = COMPARISON_BY_OPERATOR.get(operator);
        if (NO_VALUE_OPERATORS.contains(operator)) {
            return fieldName + ' ' + comparison + ' null';
        }
        Object rawValue = condition.get('value');
        // Described only when a value could be read as a date, so a status filter costs nothing.
        Boolean datesAsText = entity != null && looksLikeADate(rawValue)
            ? isNotADate(entity, fieldName)
            : false;
        if (LIST_OPERATORS.contains(operator)) {
            List<Object> values = rawValue instanceof List<Object>
                ? (List<Object>) rawValue
                : new List<Object>{ rawValue };
            List<String> rendered = new List<String>();
            for (Object value : values) {
                rendered.add(renderValue(value, datesAsText));
            }
            return fieldName + ' ' + comparison + ' (' + String.join(rendered, ',') + ')';
        }
        // What the administrator typed is matched as typed: % and _ are not wildcards.
        if (operator == 'contains' || operator == 'does not contain') {
            return fieldName + ' ' + comparison + ' ' + likeValue('%' + escapeLike(rawValue) + '%');
        }
        if (operator == 'starts with') {
            return fieldName + ' ' + comparison + ' ' + likeValue(escapeLike(rawValue) + '%');
        }
        return fieldName + ' ' + comparison + ' ' + renderValue(rawValue, datesAsText);
    }

    /** A value for LIKE with its own backslashes, % and _ escaped, so they match themselves. */
    private static String escapeLike(Object rawValue) {
        return String.valueOf(rawValue)
            .replace('\\', '\\\\')
            .replace('%', '\\%')
            .replace('_', '\\_');
    }

    /** A LIKE pattern, already escaped, quoted as text. */
    private static String likeValue(String pattern) {
        return '\'' + String.escapeSingleQuotes(pattern) + '\'';
    }

    /**
     * True when the attribute is known and is not a date or a date and time, so a value shaped
     * like a date is text there. Unknown (no entity, or a path this cannot follow) keeps the
     * rendering every filter had before.
     */
    private static Boolean looksLikeADate(Object rawValue) {
        for (
            Object value : rawValue instanceof List<Object>
                ? (List<Object>) rawValue
                : new List<Object>{ rawValue }
        ) {
            String text = value instanceof String ? (String) value : null;
            if (
                text != null &&
                (DATE_VALUE.matcher(text).matches() || DATETIME_VALUE.matcher(text).matches())
            ) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isNotADate(Schema.SObjectType entity, String fieldName) {
        Schema.DisplayType type = typeAt(entity, fieldName);
        return type != null &&
            type != Schema.DisplayType.DATE &&
            type != Schema.DisplayType.DATETIME;
    }

    /** The type of an attribute or a path such as `Gift__r.Status__c`, or null when unknown. */
    private static Schema.DisplayType typeAt(Schema.SObjectType entity, String path) {
        if (entity == null) {
            return null;
        }
        List<String> parts = path.split('\\.');
        Schema.SObjectType current = entity;
        for (Integer i = 0; i < parts.size() - 1 && current != null; i++) {
            current = referencedThrough(current, parts[i]);
        }
        if (current == null) {
            return null;
        }
        Schema.SObjectField field = current.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap()
            .get(parts[parts.size() - 1].toLowerCase());
        return field == null ? null : field.getDescribe().getType();
    }

    private static Schema.SObjectType referencedThrough(
        Schema.SObjectType entity,
        String relationshipName
    ) {
        for (
            Schema.SObjectField field : entity.getDescribe(SObjectDescribeOptions.DEFERRED)
                .fields.getMap()
                .values()
        ) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (
                describe.getType() == Schema.DisplayType.REFERENCE &&
                relationshipName.equalsIgnoreCase(describe.getRelationshipName()) &&
                !describe.getReferenceTo().isEmpty()
            ) {
                return describe.getReferenceTo()[0];
            }
        }
        return null;
    }

    /** The day count of `last n days`: a whole number from 1 to MAX_DAYS, or a refusal. */
    public static Integer dayCount(Object rawValue) {
        Decimal days;
        try {
            days = rawValue == null ? null : Decimal.valueOf(String.valueOf(rawValue).trim());
        } catch (TypeException notANumber) {
            days = null;
        }
        if (days == null || days.stripTrailingZeros().scale() > 0 || days < 1 || days > MAX_DAYS) {
            throw new RollupFilterException(System.Label.Core_Rollups_ErrorInvalidFilter);
        }
        return days.intValue();
    }

    /**
     * Numbers, booleans, dates and datetimes go in unquoted, because both the engine's query and
     * its in-memory evaluator read them that way. Everything else is a string: it is quoted and
     * escaped, which is the only place an administrator's typing reaches a query.
     */
    private static String renderValue(Object value, Boolean datesAsText) {
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
        if (
            datesAsText != true &&
            (DATE_VALUE.matcher(text).matches() || DATETIME_VALUE.matcher(text).matches())
        ) {
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
