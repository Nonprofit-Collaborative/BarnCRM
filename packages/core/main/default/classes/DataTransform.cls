/**
 * Changes a value by a short list of named steps (canonical model R-IT15, ADR-0081
 * `0081-data-transform-document.md`): the column changes of an import mapping, and the
 * formulas and find-and-replace of bulk update.
 *
 * The steps are data, never code. Each is one of a closed set of operations with bounded
 * literal parameters; nothing here evaluates an expression, compiles a pattern from text an
 * administrator typed, or reads a record. Find and replace quotes its text before any pattern
 * call, and every step is linear in the length of the value.
 *
 * The engine knows nothing of imports. It takes a value and the other values of the same row
 * (or record) by name, so the importer passes a row's cells by column name and bulk update can
 * pass a record's fields by API name.
 *
 * Reading is forgiving and saving is strict, as for the rest of the mapping document (R-IT1):
 * `problems` names what is wrong with a list of steps so a save can be refused, and `apply`
 * skips a step that would fail that check rather than failing a whole file.
 */
@NamespaceAccessible
public with sharing class DataTransform {
    /** The most steps one value may have. */
    @NamespaceAccessible
    public static final Integer MAX_STEPS = 10;
    /** The longest text a step may hold (find, replacement, a value when blank). */
    @NamespaceAccessible
    public static final Integer MAX_TEXT = 255;
    /** The most other values one step may add. */
    @NamespaceAccessible
    public static final Integer MAX_COLUMNS = 5;
    /** The longest separator between added values. */
    @NamespaceAccessible
    public static final Integer MAX_SEPARATOR = 10;

    @NamespaceAccessible
    public static final String OP_TRIM = 'trim';
    @NamespaceAccessible
    public static final String OP_UPPER = 'upper';
    @NamespaceAccessible
    public static final String OP_LOWER = 'lower';
    @NamespaceAccessible
    public static final String OP_PROPER = 'proper';
    @NamespaceAccessible
    public static final String OP_REPLACE = 'replace';
    @NamespaceAccessible
    public static final String OP_IF_BLANK = 'ifBlank';
    @NamespaceAccessible
    public static final String OP_APPEND = 'append';
    @NamespaceAccessible
    public static final String OP_DATE = 'date';

    /** The orders a date may be written in: month first, day first, year first. */
    @NamespaceAccessible
    public static final Set<String> DATE_ORDERS = new Set<String>{ 'MDY', 'DMY', 'YMD' };

    /** Every operation, in the order the wizard offers them. */
    @NamespaceAccessible
    public static final List<String> OPERATIONS = new List<String>{
        OP_TRIM,
        OP_UPPER,
        OP_LOWER,
        OP_PROPER,
        OP_REPLACE,
        OP_IF_BLANK,
        OP_APPEND,
        OP_DATE
    };

    /** The separator `append` uses when the step names none. */
    private static final String DEFAULT_SEPARATOR = ' ';

    /** A two-digit year below this is in the 2000s, otherwise in the 1900s. */
    private static final Integer CENTURY_PIVOT = 50;

    /**
     * One step. Only the parameters its operation reads are set; the field names are the keys
     * of the stored document.
     */
    @NamespaceAccessible
    public class Step {
        /** One of OPERATIONS. */
        @AuraEnabled
        public String op;
        /** replace: the literal text to find. */
        @AuraEnabled
        public String text;
        /** replace: what it is replaced with; empty removes it. */
        @AuraEnabled
        public String replaceWith;
        /** replace: whether capitals must match; false when absent. */
        @AuraEnabled
        public Boolean matchCase;
        /** replace: whether only a value that is exactly the text is replaced. */
        @AuraEnabled
        public Boolean wholeValue;
        /** ifBlank: the value a blank becomes. */
        @AuraEnabled
        public String value;
        /** append: the other values added, by name. */
        @AuraEnabled
        public List<String> columns;
        /** append: what goes between values; one space when absent. */
        @AuraEnabled
        public String separator;
        /** date: one of DATE_ORDERS. */
        @AuraEnabled
        public String dateOrder;

        // JSON.deserialize builds a step from the stored document; it needs this constructor.
        @NamespaceAccessible
        public Step() {
            this.op = null;
        }

        @NamespaceAccessible
        public Step(String op) {
            this.op = op;
        }
    }

    /**
     * Reads a list of steps from its JSON text. A blank or unreadable document reads as no
     * steps, so a hand-edited template cannot fail an import.
     */
    @NamespaceAccessible
    public static List<Step> parse(String document) {
        if (String.isBlank(document)) {
            return new List<Step>();
        }
        try {
            List<Step> parsed = (List<Step>) JSON.deserialize(document, List<Step>.class);
            return parsed == null ? new List<Step>() : parsed;
        } catch (Exception unreadable) {
            return new List<Step>();
        }
    }

    /**
     * What is wrong with these steps, one sentence each, or an empty list when nothing is. A
     * save is refused while this is not empty (R-IT15).
     */
    @NamespaceAccessible
    public static List<String> problems(List<Step> steps) {
        List<String> result = new List<String>();
        if (steps == null) {
            return result;
        }
        if (steps.size() > MAX_STEPS) {
            result.add(
                String.format(
                    Label.Core_Transform_ErrorTooMany,
                    new List<String>{ String.valueOf(MAX_STEPS) }
                )
            );
        }
        for (Step step : steps) {
            String problem = problemWith(step);
            if (problem != null && !result.contains(problem)) {
                result.add(problem);
            }
        }
        return result;
    }

    /** What is wrong with one step, or null when nothing is. */
    @NamespaceAccessible
    public static String problemWith(Step step) {
        String op = step == null ? null : step.op;
        if (op == null || !OPERATIONS.contains(op)) {
            return String.format(
                Label.Core_Transform_ErrorUnknown,
                new List<String>{ op == null ? '' : op.abbreviate(40) }
            );
        }
        if (tooLong(step.text) || tooLong(step.replaceWith) || tooLong(step.value)) {
            return Label.Core_Transform_ErrorTooLong;
        }
        if (step.separator != null && step.separator.length() > MAX_SEPARATOR) {
            return Label.Core_Transform_ErrorTooLong;
        }
        if (op == OP_REPLACE && String.isEmpty(step.text)) {
            return Label.Core_Transform_ErrorNeedsText;
        }
        if (op == OP_IF_BLANK && String.isBlank(step.value)) {
            return Label.Core_Transform_ErrorNeedsValue;
        }
        if (op == OP_APPEND && !namesColumns(step.columns)) {
            return String.format(
                Label.Core_Transform_ErrorNeedsColumns,
                new List<String>{ String.valueOf(MAX_COLUMNS) }
            );
        }
        if (op == OP_DATE && (step.dateOrder == null || !DATE_ORDERS.contains(step.dateOrder))) {
            return Label.Core_Transform_ErrorDateOrder;
        }
        return null;
    }

    private static Boolean tooLong(String text) {
        return text != null && text.length() > MAX_TEXT;
    }

    private static Boolean namesColumns(List<String> columns) {
        if (columns == null || columns.isEmpty() || columns.size() > MAX_COLUMNS) {
            return false;
        }
        for (String column : columns) {
            if (String.isBlank(column) || column.length() > MAX_TEXT) {
                return false;
            }
        }
        return true;
    }

    /**
     * The value after every step, in order. A step that fails `problemWith` is skipped.
     *
     * @param steps the steps; null or empty returns the value unchanged
     * @param value the value to change; may be null
     * @param others the other values of the same row or record, keyed by `key(name)`, which
     *        `append` reads; may be null
     */
    @NamespaceAccessible
    public static String apply(List<Step> steps, String value, Map<String, String> others) {
        if (steps == null || steps.isEmpty()) {
            return value;
        }
        String result = value;
        Integer applied = 0;
        for (Step step : steps) {
            if (applied >= MAX_STEPS) {
                break;
            }
            if (problemWith(step) != null) {
                continue;
            }
            result = applyStep(step, result, others == null ? new Map<String, String>() : others);
            applied++;
        }
        return result;
    }

    /** The key a name is looked up by in `others`: trimmed and folded to lower case. */
    @NamespaceAccessible
    public static String key(String name) {
        return name == null ? '' : name.trim().toLowerCase();
    }

    private static String applyStep(Step step, String value, Map<String, String> others) {
        switch on step.op {
            when 'trim' {
                return value == null ? null : value.normalizeSpace();
            }
            when 'upper' {
                return value == null ? null : value.toUpperCase();
            }
            when 'lower' {
                return value == null ? null : value.toLowerCase();
            }
            when 'proper' {
                return proper(value);
            }
            when 'replace' {
                return replace(step, value);
            }
            when 'ifBlank' {
                return String.isBlank(value) ? step.value : value;
            }
            when 'append' {
                return append(step, value, others);
            }
            when else {
                return asDate(step.dateOrder, value);
            }
        }
    }

    /**
     * A capital for each letter that starts a word, every other letter small. A word is a run
     * of letters, digits and apostrophes, so "o'neil" reads "O'neil" and "don't" stays one word.
     */
    private static String proper(String value) {
        if (String.isBlank(value)) {
            return value;
        }
        String lowered = value.toLowerCase();
        List<String> result = new List<String>();
        Boolean inWord = false;
        for (Integer i = 0; i < lowered.length(); i++) {
            String character = lowered.substring(i, i + 1);
            Boolean isLetter = character.isAlpha();
            Boolean isWordCharacter = isLetter || character.isNumeric() || character == '\'';
            result.add(isLetter && !inWord ? character.toUpperCase() : character);
            inWord = isWordCharacter;
        }
        return String.join(result, '');
    }

    /** Find and replace, always on literal text: the text is quoted before any pattern call. */
    private static String replace(Step step, String value) {
        if (value == null) {
            return null;
        }
        String replacement = step.replaceWith == null ? '' : step.replaceWith;
        Boolean matchCase = step.matchCase == true;
        if (step.wholeValue == true) {
            Boolean same = matchCase ? value.equals(step.text) : value.equalsIgnoreCase(step.text);
            return same ? replacement : value;
        }
        if (matchCase) {
            return value.replace(step.text, replacement);
        }
        return value.replaceAll(
            '(?iu)' + Pattern.quote(step.text),
            Matcher.quoteReplacement(replacement)
        );
    }

    /** The value followed by the named other values, leaving blank ones out. */
    private static String append(Step step, String value, Map<String, String> others) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(value)) {
            parts.add(value);
        }
        for (String column : step.columns) {
            String other = others.get(key(column));
            if (String.isNotBlank(other)) {
                parts.add(other.trim());
            }
        }
        if (parts.isEmpty()) {
            return value;
        }
        return String.join(parts, step.separator == null ? DEFAULT_SEPARATOR : step.separator);
    }

    /**
     * A date written in the given order as `YYYY-MM-DD`, or the value unchanged when it is not
     * a real date in that order. The first three runs of digits are read; any separator is
     * accepted, and anything after the third number (a time) is ignored.
     */
    @NamespaceAccessible
    public static String asDate(String dateOrder, String value) {
        if (String.isBlank(value) || dateOrder == null || !DATE_ORDERS.contains(dateOrder)) {
            return value;
        }
        List<String> numbers = new List<String>();
        for (String piece : value.trim().split('[^0-9]+')) {
            if (piece.length() > 0) {
                numbers.add(piece);
            }
        }
        if (numbers.size() < 3) {
            return value;
        }
        Integer yearAt = dateOrder.indexOf('Y');
        Integer monthAt = dateOrder.indexOf('M');
        Integer dayAt = dateOrder.indexOf('D');
        String yearText = numbers[yearAt];
        String monthText = numbers[monthAt];
        String dayText = numbers[dayAt];
        if (
            monthText.length() > 2 ||
            dayText.length() > 2 ||
            (yearText.length() != 2 &&
            yearText.length() != 4)
        ) {
            return value;
        }
        Integer year = Integer.valueOf(yearText);
        if (yearText.length() == 2) {
            year += year < CENTURY_PIVOT ? 2000 : 1900;
        }
        Integer month = Integer.valueOf(monthText);
        Integer day = Integer.valueOf(dayText);
        if (
            year < 1700 ||
            year > 4000 ||
            month < 1 ||
            month > 12 ||
            day < 1 ||
            day > Date.daysInMonth(year, month)
        ) {
            return value;
        }
        return String.valueOf(year) +
            '-' +
            String.valueOf(month).leftPad(2, '0') +
            '-' +
            String.valueOf(day).leftPad(2, '0');
    }
}
