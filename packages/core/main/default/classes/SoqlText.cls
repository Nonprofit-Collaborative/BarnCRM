/**
 * Text helpers for SOQL that more than one class needs.
 */
public with sharing class SoqlText {
    /**
     * Escapes the characters that carry meaning inside a LIKE pattern (backslash, % and _), so
     * typed text is matched as itself and a typed % does not match everything. Quotes are not
     * touched: a bound pattern needs none, and escapeSingleQuotes would double the backslashes.
     */
    public static String escapeLike(String value) {
        return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }
}
