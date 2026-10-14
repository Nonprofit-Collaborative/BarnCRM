/**
 * The small value helpers every import path shares, so the people import, Load one object and
 * the row selector read, compare and slice the same way.
 *
 * `same` is the one answer to "would this value change the record" (R-IT14, R-IJ2): numbers
 * as numbers (100.00 is 100), dates and times as values, IDs in either length, and text
 * exactly, since a correction of capitals is a correction. Converting a file's text to the
 * field's type is `ImportObjectSchema.typed`, which reads numbers with `number` here; this class
 * compares what it returns.
 */
@NamespaceAccessible
public inherited sharing class ImportValues {
    /** How many keys one IN clause is given. A chunk with more is queried in slices. */
    @NamespaceAccessible
    public static final Integer KEYS_PER_QUERY = 1000;

    /** Whether a stored value equals the typed value a row would write. */
    @NamespaceAccessible
    public static Boolean same(Object stored, Object incoming) {
        if (stored == null || incoming == null) {
            return stored == null && incoming == null;
        }
        if (
            incoming instanceof Decimal ||
            incoming instanceof Integer ||
            incoming instanceof Long ||
            incoming instanceof Double
        ) {
            try {
                return Decimal.valueOf(String.valueOf(stored)) ==
                    Decimal.valueOf(String.valueOf(incoming));
            } catch (Exception notANumber) {
                return false;
            }
        }
        if (incoming instanceof Id) {
            return idOrNull(String.valueOf(stored)) == incoming;
        }
        if (
            incoming instanceof Date ||
            incoming instanceof Datetime ||
            incoming instanceof Time ||
            incoming instanceof Boolean
        ) {
            return stored == incoming;
        }
        return String.valueOf(stored).equals(String.valueOf(incoming));
    }

    /** A record ID as typed, or null when the text is not one. */
    @NamespaceAccessible
    public static Id idOrNull(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value.trim());
        } catch (Exception notAnId) {
            return null;
        }
    }

    /** A staged row's file row number, or null. */
    @NamespaceAccessible
    public static Integer rowNumber(Import_Row__c row) {
        return row == null || row.Row_Number__c == null ? null : row.Row_Number__c.intValue();
    }

    /**
     * A key as sixteen hex digits: the first eight bytes of the MD5 digest of the kind and the
     * key, so 64 bits keep two keys well clear of sharing one. Compared only, never shown.
     */
    @NamespaceAccessible
    public static String digest(String kind, String key) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('MD5', Blob.valueOf(kind + key)))
            .left(16);
    }

    /** The keys cut into lists of `size`, blanks dropped, so no IN clause grows past it. */
    @NamespaceAccessible
    public static List<List<String>> slices(Set<String> keys, Integer size) {
        List<List<String>> result = new List<List<String>>();
        if (keys == null || keys.isEmpty()) {
            return result;
        }
        List<String> current = new List<String>();
        for (String key : keys) {
            if (String.isBlank(key)) {
                continue;
            }
            current.add(key);
            if (current.size() == size) {
                result.add(current);
                current = new List<String>();
            }
        }
        if (!current.isEmpty()) {
            result.add(current);
        }
        return result;
    }

    /** The running user's decimal mark, read once from how their locale writes a number. */
    private static String localeDecimal;
    /** The running user's grouping mark, empty when their locale groups with a space. */
    private static String localeGroup;

    /**
     * A number as a spreadsheet exports it, read in the running user's locale (R-IT11), or null
     * when it cannot be read without guessing. Currency symbols and codes ("$", "€", "USD"),
     * a percent sign, spaces and apostrophes are dropped; a minus sign at either end or
     * accounting brackets, "(45.00)", make it negative. When a value holds both a point and a
     * comma, the later one is the decimal mark. A value holding one of them reads it as the
     * user's locale does: the decimal mark is a decimal mark, and the grouping mark must
     * separate groups of three digits. A point or comma that is neither in the user's locale
     * is a decimal mark unless it is followed by exactly three digits, which could be either,
     * so that value is refused rather than read a thousand times wrong.
     */
    @NamespaceAccessible
    public static Decimal number(String text) {
        if (localeDecimal == null) {
            // 1234.5 as the user's locale writes it: "1,234.5", "1.234,5", "1 234,5".
            String marks = Decimal.valueOf('1234.5')
                .format()
                .replaceAll('[0-9\\s\\u00A0\\u202F]', '');
            localeDecimal = String.isEmpty(marks) ? '.' : marks.right(1);
            localeGroup = marks.length() > 1 ? marks.left(1) : '';
        }
        return number(text, localeDecimal, localeGroup);
    }

    /** `number` with the locale's marks given, so every locale can be tested from one user. */
    @TestVisible
    private static Decimal number(String text, String decimalMark, String groupMark) {
        String value = text == null ? '' : text.trim();
        Boolean bracketed = value.startsWith('(') && value.endsWith(')');
        if (bracketed) {
            value = value.substring(1, value.length() - 1).trim();
        }
        value = value.replaceAll('\\p{Sc}', '').trim();
        value = value.replaceAll('^[A-Z]{3}(?![A-Z])|(?<![A-Z])[A-Z]{3}$', '');
        value = value.replaceAll('[%\\s\\u00A0\\u202F\'\\u2019]', '').replace('−', '-');
        Boolean negative = false;
        if (value.startsWith('-') || value.endsWith('-')) {
            negative = true;
            value = value.startsWith('-') ? value.substring(1) : value.removeEnd('-');
        } else if (value.startsWith('+')) {
            value = value.substring(1);
        }
        if ((bracketed && negative) || !Pattern.matches('[0-9.,]*[0-9][0-9.,]*', value)) {
            return null;
        }
        String decimalSeparator = decimalOf(value, decimalMark, groupMark);
        if (decimalSeparator == 'none') {
            return null;
        }
        String whole = decimalSeparator == null
            ? value
            : value.substringBeforeLast(decimalSeparator);
        String fraction = decimalSeparator == null
            ? ''
            : value.substringAfterLast(decimalSeparator);
        // What is left in the whole part is the grouping mark, which must group in threes.
        if (whole.containsAny('.,')) {
            if (!Pattern.matches('[0-9]{1,3}([.,][0-9]{3})+', whole)) {
                return null;
            }
            whole = whole.replaceAll('[.,]', '');
        }
        Decimal result = Decimal.valueOf(
            (String.isEmpty(whole) ? '0' : whole) + (String.isEmpty(fraction) ? '' : '.' + fraction)
        );
        return bracketed || negative ? -result : result;
    }

    /**
     * Which mark is the decimal mark in a value of digits, points and commas: the mark, null
     * for none (a whole number, perhaps grouped), or 'none' when it cannot be told.
     */
    private static String decimalOf(String value, String decimalMark, String groupMark) {
        Integer points = value.countMatches('.');
        Integer commas = value.countMatches(',');
        if (points > 0 && commas > 0) {
            String later = value.lastIndexOf('.') > value.lastIndexOf(',') ? '.' : ',';
            return value.countMatches(later) == 1 ? later : 'none';
        }
        if (points + commas == 0) {
            return null;
        }
        String mark = points > 0 ? '.' : ',';
        if (points + commas > 1) {
            return null;
        }
        if (mark == decimalMark) {
            return mark;
        }
        Boolean groupsOfThree = Pattern.matches('[0-9]{1,3}[.,][0-9]{3}', value);
        if (mark == groupMark) {
            return groupsOfThree ? null : 'none';
        }
        return groupsOfThree ? 'none' : mark;
    }
}
