/**
 * Reads what a file's names say about where its columns load (C-49a): a heading that names an
 * object and a field together ("Contact.First Name", "Phone (Contact)", "Contact_Phone"), and a
 * sheet or file name that names an object ("Contacts", "contacts_2026.xlsx").
 *
 * Pure logic over maps the caller builds from describe (`ImportObjectSchema`), so it holds no
 * org shape. Every match is exact after `ImportColumnLibrary.normalize` (lower case, letters and
 * digits only); `match` is the one place a fuzzy fallback would plug in.
 */
@NamespaceAccessible
public with sharing class ImportHeaderParser {
    /** The value of a normalized key two objects share, which therefore names neither. */
    @NamespaceAccessible
    public static final String AMBIGUOUS = '';

    /** What separates an object from a field in a heading, besides parentheses and "_". */
    private static final String SEPARATORS = ':./|-';

    /** A field, then its object in parentheses: "Phone (Contact)". */
    private static final Pattern PARENTHESES = Pattern.compile('^(.+?)\\s*\\(([^()]+)\\)$');

    /** Words a file or sheet name carries that name no object. */
    private static final Set<String> IGNORED_WORDS = new Set<String>{
        'export',
        'exports',
        'exported',
        'import',
        'imports',
        'imported'
    };

    /** An object and a field one heading names. */
    @NamespaceAccessible
    public class Resolved {
        @NamespaceAccessible
        public String objectName;
        @NamespaceAccessible
        public String fieldName;

        @NamespaceAccessible
        public Resolved(String objectName, String fieldName) {
            this.objectName = objectName;
            this.fieldName = fieldName;
        }
    }

    /** An object's fields by normalized spelling, asked only for objects a heading names. */
    @NamespaceAccessible
    public interface FieldKeys {
        Map<String, String> keysOf(String objectName);
    }

    /**
     * A heading as read: no byte-order mark, every run of white space (line breaks and
     * non-breaking spaces included) one space, trimmed.
     */
    @NamespaceAccessible
    public static String clean(String text) {
        if (text == null) {
            return '';
        }
        return text.replace('﻿', '').replace(' ', ' ').replaceAll('\\s+', ' ').trim();
    }

    /**
     * Adds a spelling of a name to a map of normalized keys. A key two names share is kept as
     * AMBIGUOUS, so it matches neither.
     */
    @NamespaceAccessible
    public static void putKey(Map<String, String> keys, String spelling, String name) {
        String key = ImportColumnLibrary.normalize(spelling);
        if (String.isBlank(key)) {
            return;
        }
        String existing = keys.get(key);
        if (existing == null) {
            keys.put(key, name);
        } else if (!existing.equals(name)) {
            keys.put(key, AMBIGUOUS);
        }
    }

    /**
     * The name a part of a heading or a file name spells, or null. Exact only in C-49a: a fuzzy
     * fallback (awaiting the owner's decision) would plug in here, after the exact lookup
     * misses, and nowhere else.
     */
    @NamespaceAccessible
    public static String match(String part, Map<String, String> keys) {
        if (keys == null || String.isBlank(part)) {
            return null;
        }
        String found = keys.get(ImportColumnLibrary.normalize(part));
        return String.isBlank(found) ? null : found;
    }

    /**
     * The object and field a heading names together, or null. The caller tries the whole
     * heading as a field first. Parentheses and separators are tried before underscores, so an
     * underscore is split only when nothing clearer reads; and an underscore that is part of
     * "__" (a "__c" suffix or a namespace) is never split. Two readings that name different
     * fields name neither.
     */
    @NamespaceAccessible
    public static Resolved resolve(
        String header,
        Map<String, String> objectKeys,
        FieldKeys fields
    ) {
        String text = clean(header);
        Map<String, Resolved> found = readings(explicitSplits(text), objectKeys, fields);
        if (found.isEmpty()) {
            found = readings(underscoreSplits(text), objectKeys, fields);
        }
        return found.size() == 1 ? found.values()[0] : null;
    }

    /**
     * The object the headings name most often (the first named on a tie), or null when none
     * names one.
     */
    @NamespaceAccessible
    public static String objectOfHeaders(
        List<String> headers,
        Map<String, String> objectKeys,
        FieldKeys fields
    ) {
        Map<String, Integer> counts = new Map<String, Integer>();
        String best;
        Integer bestCount = 0;
        for (String header : headers == null ? new List<String>() : headers) {
            Resolved each = resolve(header, objectKeys, fields);
            if (each == null) {
                continue;
            }
            Integer count =
                (counts.containsKey(each.objectName) ? counts.get(each.objectName) : 0) + 1;
            counts.put(each.objectName, count);
            if (count > bestCount) {
                best = each.objectName;
                bestCount = count;
            }
        }
        return best;
    }

    /** The object a file name names, once its extension is taken off ("Volunteer Shifts.csv"). */
    @NamespaceAccessible
    public static String objectOfFileName(String fileName, Map<String, String> objectKeys) {
        return objectOfName(clean(fileName).replaceAll('\\.[A-Za-z0-9]{1,5}$', ''), objectKeys);
    }

    /**
     * The object a sheet or file name names, or null: the name without its digits (so dates
     * go), then also without the words export and import.
     */
    @NamespaceAccessible
    public static String objectOfName(String name, Map<String, String> objectKeys) {
        String withoutDigits = clean(name).replaceAll('[0-9]', ' ');
        String found = match(withoutDigits, objectKeys);
        if (found != null) {
            return found;
        }
        List<String> kept = new List<String>();
        for (String word : withoutDigits.toLowerCase().split('[^a-z]+')) {
            if (!IGNORED_WORDS.contains(word)) {
                kept.add(word);
            }
        }
        return match(String.join(kept, ' '), objectKeys);
    }

    // -------------------------------------------------------------------------------------
    // Splits, each an [object part, field part] pair
    // -------------------------------------------------------------------------------------

    /** "Phone (Contact)", then each separator, either part first. */
    @TestVisible
    private static List<List<String>> explicitSplits(String text) {
        List<List<String>> result = new List<List<String>>();
        Matcher parentheses = PARENTHESES.matcher(text);
        if (parentheses.matches()) {
            result.add(new List<String>{ parentheses.group(2), parentheses.group(1) });
        }
        for (Integer i = 0; i < text.length(); i++) {
            if (SEPARATORS.contains(text.substring(i, i + 1))) {
                addBothWays(result, text.left(i), text.substring(i + 1));
            }
        }
        return result;
    }

    /** Each lone underscore, either part first; never one of a "__" pair. */
    @TestVisible
    private static List<List<String>> underscoreSplits(String text) {
        List<List<String>> result = new List<List<String>>();
        for (Integer i = 1; i < text.length() - 1; i++) {
            Boolean lone =
                text.substring(i, i + 1) == '_' &&
                text.substring(i - 1, i) != '_' &&
                text.substring(i + 1, i + 2) != '_';
            if (lone) {
                addBothWays(result, text.left(i), text.substring(i + 1));
            }
        }
        return result;
    }

    private static void addBothWays(List<List<String>> result, String left, String right) {
        left = left.trim();
        right = right.trim();
        if (String.isNotBlank(left) && String.isNotBlank(right)) {
            result.add(new List<String>{ left, right });
            result.add(new List<String>{ right, left });
        }
    }

    /** The distinct object and field pairs the splits read as, keyed by object and field. */
    private static Map<String, Resolved> readings(
        List<List<String>> splits,
        Map<String, String> objectKeys,
        FieldKeys fields
    ) {
        Map<String, Resolved> found = new Map<String, Resolved>();
        for (List<String> split : splits) {
            String objectName = match(split[0], objectKeys);
            String fieldName = objectName == null
                ? null
                : match(split[1], fields.keysOf(objectName));
            if (fieldName != null) {
                found.put(
                    (objectName + '.' + fieldName).toLowerCase(),
                    new Resolved(objectName, fieldName)
                );
            }
        }
        return found;
    }
}
