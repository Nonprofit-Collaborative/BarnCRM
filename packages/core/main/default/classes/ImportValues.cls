/**
 * The small value helpers every import path shares, so the people import, Load one object and
 * the row selector read, compare and slice the same way.
 *
 * `same` is the one answer to "would this value change the record" (R-IT14, R-IJ2): numbers
 * as numbers (100.00 is 100), dates and times as values, IDs in either length, and text
 * exactly, since a correction of capitals is a correction. Converting a file's text to the
 * field's type is `ImportObjectSchema.typed`; this class compares what that returns.
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
}
