/**
 * A DLRS Relationship Criteria, the where clause an administrator typed, read into the Rollup
 * Builder's filter document (canonical model R-R2, R-R16) for Import from DLRS.
 *
 * BarnCRM never runs typed SOQL (ADR-0136 decision 7), so this reads only the simple shapes the
 * filter builder can hold: a field (or one lookup's field) compared with a literal, `= null`,
 * `IN` and `NOT IN` lists, `LIKE 'x%'` and `LIKE '%x%'`, THIS_YEAR, LAST_YEAR and LAST_N_DAYS:n,
 * joined by AND, OR, NOT and brackets. Anything else is refused with the part it could not read,
 * and the rollup stays in DLRS. Whether each field exists is the Builder's own check, run after.
 */
public with sharing class RollupDlrsCriteria {
    /** The criteria cannot be read; the message names the part. */
    public class CriteriaException extends Exception {
    }

    private static final Map<String, String> OPERATOR_BY_COMPARISON = new Map<String, String>{
        '=' => 'equals',
        '!=' => 'not equals',
        '<>' => 'not equals',
        '<' => 'less than',
        '<=' => 'less or equal',
        '>' => 'greater than',
        '>=' => 'greater or equal'
    };
    private static final Map<String, String> OPERATOR_BY_DATE_LITERAL = new Map<String, String>{
        'THIS_YEAR' => 'this year',
        'LAST_YEAR' => 'last year'
    };
    // Not called FIELD: Apex names ignore case, and a local `field` would hide it.
    private static final Pattern FIELD_PATH = Pattern.compile(
        '^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)?$'
    );
    private static final Pattern NUMERAL = Pattern.compile('^-?\\d+(\\.\\d+)?$');
    private static final Pattern DATE_VALUE = Pattern.compile(
        '^\\d{4}-\\d{2}-\\d{2}(T[0-9:.]+(Z|[+-]\\d{2}:?\\d{2}))?$'
    );
    private static final Pattern RECENT_DAYS = Pattern.compile('^LAST_N_DAYS:(\\d+)$');
    private static final String STRING_TOKEN = '\'';

    private List<String> tokens = new List<String>();
    /** True for a token that was a quoted string, so the word AND in quotes stays text. */
    private List<Boolean> quoted = new List<Boolean>();
    private Integer position = 0;
    private List<Map<String, Object>> conditions = new List<Map<String, Object>>();

    /**
     * The filter document for this criteria and any further conditions, all of which must hold,
     * or null when there is nothing to filter on.
     *
     * @param criteria the DLRS Relationship Criteria, or blank
     * @param required conditions added with AND, each {field, operator[, value]}
     */
    public static String toFilter(String criteria, List<Map<String, Object>> required) {
        RollupDlrsCriteria reader = new RollupDlrsCriteria();
        String logic = '';
        if (String.isNotBlank(criteria)) {
            reader.tokenize(criteria.trim());
            logic = reader.expression();
            if (reader.position < reader.tokens.size()) {
                throw reader.unreadable(reader.position);
            }
        }
        List<Map<String, Object>> alsoRequired = required == null
            ? new List<Map<String, Object>>()
            : required;
        for (Map<String, Object> condition : alsoRequired) {
            String id = reader.add(condition);
            logic = String.isBlank(logic) ? id : '(' + logic + ') AND ' + id;
        }
        if (reader.conditions.isEmpty()) {
            return null;
        }
        return JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'logic' => logic,
                'conditions' => reader.conditions
            }
        );
    }

    // ------------------------------------------------------------------------------- reading

    private void tokenize(String text) {
        Integer index = 0;
        Integer length = text.length();
        while (index < length) {
            String character = text.substring(index, index + 1);
            if (character.isWhitespace()) {
                index++;
            } else if (character == STRING_TOKEN) {
                String value = '';
                index++;
                Boolean closed = false;
                while (index < length) {
                    String next = text.substring(index, index + 1);
                    if (next == '\\' && index + 1 < length) {
                        value += text.substring(index + 1, index + 2);
                        index += 2;
                    } else if (next == STRING_TOKEN) {
                        closed = true;
                        index++;
                        break;
                    } else {
                        value += next;
                        index++;
                    }
                }
                if (!closed) {
                    throw new CriteriaException(text);
                }
                push(value, true);
            } else if ('(),'.contains(character)) {
                push(character, false);
                index++;
            } else if ('=!<>'.contains(character)) {
                String two = index + 1 < length ? text.substring(index, index + 2) : character;
                String comparison = OPERATOR_BY_COMPARISON.containsKey(two) ? two : character;
                push(comparison, false);
                index += comparison.length();
            } else {
                Integer start = index;
                while (index < length && !isBreak(text.substring(index, index + 1))) {
                    index++;
                }
                push(text.substring(start, index), false);
            }
        }
    }

    private static Boolean isBreak(String character) {
        return character.isWhitespace() || '(),=!<>\''.contains(character);
    }

    private void push(String token, Boolean isString) {
        tokens.add(token);
        quoted.add(isString);
    }

    /** OR binds loosest, then AND, then NOT, as in SOQL; the logic string keeps the grouping. */
    private String expression() {
        String logic = conjunction();
        while (isWord('OR')) {
            position++;
            logic = '(' + logic + ') OR (' + conjunction() + ')';
        }
        return logic;
    }

    private String conjunction() {
        String logic = factor();
        while (isWord('AND')) {
            position++;
            logic = '(' + logic + ') AND (' + factor() + ')';
        }
        return logic;
    }

    private String factor() {
        if (isWord('NOT')) {
            position++;
            return 'NOT (' + factor() + ')';
        }
        if (is('(')) {
            position++;
            String grouped = expression();
            expect(')');
            return grouped;
        }
        return condition();
    }

    private String condition() {
        Integer start = position;
        String field = next();
        if (field == null || quoted[start] || !FIELD_PATH.matcher(field).matches()) {
            throw unreadable(start);
        }
        Map<String, Object> condition = new Map<String, Object>{ 'field' => field };
        String comparison = next();
        String upper = comparison == null ? '' : comparison.toUpperCase();
        if (upper == 'NOT' && isWord('IN')) {
            position++;
            condition.put('operator', 'not in');
            condition.put('value', valueList(start));
        } else if (upper == 'IN') {
            condition.put('operator', 'in');
            condition.put('value', valueList(start));
        } else if (upper == 'LIKE') {
            likePattern(condition, start);
        } else if (OPERATOR_BY_COMPARISON.containsKey(comparison)) {
            compare(condition, comparison, start);
        } else {
            throw unreadable(start);
        }
        return add(condition);
    }

    private void compare(Map<String, Object> condition, String comparison, Integer start) {
        Integer valueAt = position;
        String token = next();
        if (token == null) {
            throw unreadable(start);
        }
        String upper = quoted[valueAt] ? null : token.toUpperCase();
        Matcher days = upper == null ? null : RECENT_DAYS.matcher(upper);
        if (upper == 'NULL' && (comparison == '=' || comparison == '!=' || comparison == '<>')) {
            condition.put('operator', comparison == '=' ? 'is null' : 'is not null');
        } else if (upper != null && OPERATOR_BY_DATE_LITERAL.containsKey(upper)) {
            if (comparison != '=') {
                throw unreadable(start);
            }
            condition.put('operator', OPERATOR_BY_DATE_LITERAL.get(upper));
        } else if (days != null && days.matches()) {
            if (comparison != '=') {
                throw unreadable(start);
            }
            condition.put('operator', 'last n days');
            condition.put('value', Integer.valueOf(days.group(1)));
        } else {
            condition.put('operator', OPERATOR_BY_COMPARISON.get(comparison));
            condition.put('value', literal(valueAt, start));
        }
    }

    /** LIKE 'x%' is starts with, LIKE '%x%' contains; other patterns have no equivalent. */
    private void likePattern(Map<String, Object> condition, Integer start) {
        Integer valueAt = position;
        String pattern = next();
        if (pattern == null || !quoted[valueAt] || pattern.contains('_')) {
            throw unreadable(start);
        }
        Boolean leading = pattern.startsWith('%');
        String text = pattern.removeStart('%').removeEnd('%');
        if (String.isEmpty(text) || text.contains('%') || !pattern.endsWith('%')) {
            throw unreadable(start);
        }
        condition.put('operator', leading ? 'contains' : 'starts with');
        condition.put('value', text);
    }

    private List<Object> valueList(Integer start) {
        expect('(');
        List<Object> values = new List<Object>{ literal(position++, start) };
        while (!is(')')) {
            expect(',');
            values.add(literal(position++, start));
        }
        position++;
        return values;
    }

    /** A text, number, true or false, or date literal; anything else cannot be read. */
    private Object literal(Integer at, Integer start) {
        if (at >= tokens.size()) {
            throw unreadable(start);
        }
        String token = tokens[at];
        if (quoted[at]) {
            return token;
        }
        String upper = token.toUpperCase();
        if (upper == 'TRUE' || upper == 'FALSE') {
            return upper == 'TRUE';
        }
        if (NUMERAL.matcher(token).matches()) {
            return Decimal.valueOf(token);
        }
        if (DATE_VALUE.matcher(token).matches()) {
            return token;
        }
        throw unreadable(start);
    }

    private String add(Map<String, Object> condition) {
        Map<String, Object> numbered = condition.clone();
        String id = String.valueOf(conditions.size() + 1);
        numbered.put('id', id);
        conditions.add(numbered);
        return id;
    }

    private String next() {
        return position < tokens.size() ? tokens[position++] : null;
    }

    private Boolean is(String token) {
        return position < tokens.size() && !quoted[position] && tokens[position] == token;
    }

    private Boolean isWord(String word) {
        return position < tokens.size() &&
            !quoted[position] &&
            tokens[position].equalsIgnoreCase(word);
    }

    private void expect(String token) {
        if (!is(token)) {
            throw unreadable(position);
        }
        position++;
    }

    /** The criteria from the part that could not be read, in the administrator's words. */
    private CriteriaException unreadable(Integer at) {
        List<String> rest = new List<String>();
        // Run out of words (a bracket never closed): the last few words are the part.
        Integer first = at < tokens.size() ? at : Math.max(0, tokens.size() - 6);
        for (Integer index = first; index < tokens.size() && rest.size() < 6; index++) {
            rest.add(quoted[index] ? '\'' + tokens[index] + '\'' : tokens[index]);
        }
        return new CriteriaException(String.join(rest, ' '));
    }
}
