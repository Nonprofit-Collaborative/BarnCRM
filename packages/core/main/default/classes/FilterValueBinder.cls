/**
 * The bound rendering of an R-R2 filter document over one object, for Find (C-34).
 *
 * RollupFilterParser parses the document and checks the operators and the logic; this class
 * checks each field against the running user's describe (QueryFieldCatalog), checks that the
 * operator suits the field's type, coerces each value to that type, and puts it in a bind
 * variable. Relative dates are the platform's date literals, written from an Integer. Nothing a
 * person typed is ever concatenated into the query (plan Section 4.9, ADR-0047). It also keeps a
 * display rendering, with the values written in, which is only ever shown, never run.
 */
public with sharing class FilterValueBinder {
    /** The where clause with bind names, set by RollupFilterParser.toBoundClause. */
    public String clause;
    /** The bind values by name, for Database.queryWithBinds. */
    public Map<String, Object> binds = new Map<String, Object>();

    private static final String BIND_PREFIX = 'fb';
    private static final Set<Schema.DisplayType> TEXT_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.TEXTAREA,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.URL,
        Schema.DisplayType.COMBOBOX
    };
    private static final Set<Schema.DisplayType> NUMBER_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.CURRENCY,
        Schema.DisplayType.PERCENT,
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.LONG
    };
    private static final Set<Schema.DisplayType> DATE_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.DATE,
        Schema.DisplayType.DATETIME
    };
    private static final Set<Schema.DisplayType> ID_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.ID,
        Schema.DisplayType.REFERENCE
    };
    private static final Set<String> NULL_TESTS = new Set<String>{ 'is null', 'is not null' };
    private static final Set<String> COMPARISONS = new Set<String>{
        'equals',
        'not equals',
        'less than',
        'less or equal',
        'greater than',
        'greater or equal'
    };
    private static final Map<String, String> SOQL_BY_COMPARISON = new Map<String, String>{
        'equals' => '=',
        'not equals' => '!=',
        'less than' => '<',
        'less or equal' => '<=',
        'greater than' => '>',
        'greater or equal' => '>='
    };
    private static final Map<String, String> DATE_LITERAL_BY_OPERATOR = new Map<String, String>{
        'this year' => 'THIS_YEAR',
        'last year' => 'LAST_YEAR'
    };

    private final String objectApiName;
    private final Map<String, String> displayByName = new Map<String, String>();
    private Schema.DescribeFieldResult field;
    private String path;
    private final String bindPrefix;

    public FilterValueBinder(String objectApiName) {
        this(objectApiName, BIND_PREFIX);
    }

    /**
     * A binder whose bind names start with `bindPrefix`, so a second filter in the same query
     * (a related-records condition, C-36 R-SQ8) never reuses the first one's names. The prefix
     * is the caller's constant, never anything a person typed.
     */
    public FilterValueBinder(String objectApiName, String bindPrefix) {
        this.objectApiName = objectApiName;
        this.bindPrefix = bindPrefix;
    }

    /** The clause with each value written in, for display only. */
    public String display() {
        String shown = clause == null ? '' : clause;
        // Highest first, so :fb1 never rewrites the start of :fb10.
        for (Integer index = displayByName.size() - 1; index >= 0; index--) {
            String name = bindPrefix + index;
            shown = shown.replace(':' + name, displayByName.get(name));
        }
        return shown;
    }

    /**
     * Checks a field path and an operator for the next condition and returns the path. Refuses a
     * field the user cannot see or filter on, and an operator that does not suit its type.
     */
    public String useField(String fieldPath, String operator) {
        try {
            field = QueryFieldCatalog.resolvePath(objectApiName, fieldPath);
        } catch (QueryFieldCatalog.QueryFieldCatalogException refused) {
            throw new RollupFilterParser.RollupFilterException(refused.getMessage());
        }
        path = fieldPath;
        if (!field.isFilterable() || !operatorsFor(field.getType()).contains(operator)) {
            throw new RollupFilterParser.RollupFilterException(
                String.format(
                    System.Label.Core_Filter_ErrorOperatorType,
                    new List<Object>{ fieldPath, String.valueOf(operator) }
                )
            );
        }
        return fieldPath;
    }

    /** The condition on the field useField accepted, with its value bound. */
    public String render(String fieldPath, String operator, Object rawValue) {
        if (operator == 'is null') {
            return fieldPath + ' = null';
        }
        if (operator == 'is not null') {
            return fieldPath + ' != null';
        }
        if (DATE_LITERAL_BY_OPERATOR.containsKey(operator)) {
            return fieldPath + ' = ' + DATE_LITERAL_BY_OPERATOR.get(operator);
        }
        if (operator == 'last n days') {
            return fieldPath + ' = LAST_N_DAYS:' + RollupFilterParser.dayCount(rawValue);
        }
        if (operator == 'in' || operator == 'not in') {
            return fieldPath + (operator == 'in' ? ' IN ' : ' NOT IN ') + bindList(rawValue);
        }
        if (operator == 'contains') {
            return fieldPath + ' LIKE ' + bind('%' + escapeLike(text(rawValue)) + '%');
        }
        if (operator == 'does not contain') {
            return '(NOT ' +
                fieldPath +
                ' LIKE ' +
                bind('%' + escapeLike(text(rawValue)) + '%') +
                ')';
        }
        if (operator == 'starts with') {
            return fieldPath + ' LIKE ' + bind(escapeLike(text(rawValue)) + '%');
        }
        return fieldPath + ' ' + SOQL_BY_COMPARISON.get(operator) + ' ' + bind(coerce(rawValue));
    }

    private static Set<String> operatorsFor(Schema.DisplayType type) {
        Set<String> operators = new Set<String>();
        if (TEXT_TYPES.contains(type)) {
            operators.addAll(
                new List<String>{
                    'equals',
                    'not equals',
                    'contains',
                    'does not contain',
                    'starts with',
                    'in',
                    'not in'
                }
            );
        } else if (type == Schema.DisplayType.PICKLIST || ID_TYPES.contains(type)) {
            operators.addAll(new List<String>{ 'equals', 'not equals', 'in', 'not in' });
        } else if (type == Schema.DisplayType.MULTIPICKLIST) {
            operators.addAll(new List<String>{ 'equals', 'not equals' });
        } else if (NUMBER_TYPES.contains(type)) {
            operators.addAll(COMPARISONS);
        } else if (DATE_TYPES.contains(type)) {
            operators.addAll(COMPARISONS);
            operators.addAll(new List<String>{ 'this year', 'last year', 'last n days' });
        } else if (type == Schema.DisplayType.BOOLEAN) {
            return new Set<String>{ 'equals' };
        } else {
            return operators;
        }
        operators.addAll(NULL_TESTS);
        return operators;
    }

    /** One value, typed to the field. */
    private Object coerce(Object rawValue) {
        Schema.DisplayType type = field.getType();
        if (rawValue == null || String.isBlank(String.valueOf(rawValue))) {
            throw valueDoesNotFit();
        }
        String raw = String.valueOf(rawValue).trim();
        if (type == Schema.DisplayType.BOOLEAN) {
            if (raw != 'true' && raw != 'false') {
                throw valueDoesNotFit();
            }
            return raw == 'true';
        }
        try {
            if (NUMBER_TYPES.contains(type)) {
                return Decimal.valueOf(raw);
            }
            if (type == Schema.DisplayType.DATE) {
                return Date.valueOf(raw);
            }
            if (type == Schema.DisplayType.DATETIME) {
                return (Datetime) JSON.deserialize(
                    '"' + raw.replace('"', '') + '"',
                    Datetime.class
                );
            }
            if (ID_TYPES.contains(type)) {
                return String.valueOf(Id.valueOf(raw));
            }
            return String.valueOf(rawValue);
        } catch (Exception notThatType) {
            throw valueDoesNotFit();
        }
    }

    private String text(Object rawValue) {
        if (rawValue == null || String.isBlank(String.valueOf(rawValue))) {
            throw valueDoesNotFit();
        }
        return String.valueOf(rawValue);
    }

    private String bindList(Object rawValue) {
        List<Object> values = rawValue instanceof List<Object>
            ? (List<Object>) rawValue
            : new List<Object>{ rawValue };
        List<String> typed = new List<String>();
        for (Object value : values) {
            typed.add((String) coerce(value));
        }
        if (typed.isEmpty()) {
            throw valueDoesNotFit();
        }
        return bind(typed);
    }

    /** Stores a value under the next bind name and returns `:name`. */
    private String bind(Object value) {
        String name = bindPrefix + binds.size();
        binds.put(name, value);
        displayByName.put(name, literal(value));
        return ':' + name;
    }

    /** `%` and `_` in typed text are matched as themselves, not as wildcards. */
    private static String escapeLike(String value) {
        return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }

    private static String literal(Object value) {
        if (value instanceof List<String>) {
            List<String> shown = new List<String>();
            for (String each : (List<String>) value) {
                shown.add(literal(each));
            }
            return '(' + String.join(shown, ', ') + ')';
        }
        if (value instanceof Date) {
            return String.valueOf(value);
        }
        if (value instanceof Datetime) {
            return ((Datetime) value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        }
        if (value instanceof Decimal || value instanceof Boolean) {
            return String.valueOf(value);
        }
        return '\'' + String.escapeSingleQuotes(String.valueOf(value)) + '\'';
    }

    private RollupFilterParser.RollupFilterException valueDoesNotFit() {
        return new RollupFilterParser.RollupFilterException(
            String.format(System.Label.Core_Filter_ErrorValueType, new List<Object>{ path })
        );
    }
}
