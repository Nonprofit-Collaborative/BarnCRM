/**
 * Reads what a file's names say about where its columns load (C-49a): a heading that names an
 * object and a field together ("Contact.First Name", "Phone (Contact)", "Contact_Phone"), and a
 * sheet or file name that names an object ("Contacts", "contacts_2026.xlsx").
 *
 * Pure logic over maps the caller builds from describe (`ImportObjectSchema`), so it holds no
 * org shape. `match` is exact after `ImportColumnLibrary.normalize` (lower case, letters and
 * digits only). When nothing matches exactly, `find` falls back to a best guess (C-49e, plan
 * D-150): the spelling `FuzzyMatch` scores closest, at or above GUESS_THRESHOLD, flagged as a
 * guess so the wizard asks the administrator to accept it. An exact match always wins, and a
 * tie between two names is no guess.
 */
@NamespaceAccessible
public with sharing class ImportHeaderParser {
    /** The value of a normalized key two objects share, which therefore names neither. */
    @NamespaceAccessible
    public static final String AMBIGUOUS = '';

    /**
     * The lowest FuzzyMatch score a guess may have (C-49e): a typo of one or two letters
     * ("Frist Name", "Emial", "Contcts") reaches it, a different word does not.
     */
    @NamespaceAccessible
    public static final Double GUESS_THRESHOLD = 0.88;

    /** A normalized spelling shorter than this is never guessed: a few letters match too much. */
    private static final Integer GUESS_MIN_LENGTH = 4;

    /**
     * The shorter of a part and a spelling must be at least this share of the longer. A typo
     * changes a letter or two; without this, Jaro-Winkler's weight on a shared start would
     * read "Contact.Status" as the field "Contact".
     */
    private static final Double GUESS_MIN_LENGTH_RATIO = 0.75;

    /** A name found for a part of a heading or a file name, and whether it is a guess. */
    @NamespaceAccessible
    public class Found {
        @NamespaceAccessible
        public String name;
        @NamespaceAccessible
        public Boolean guessed;

        @NamespaceAccessible
        public Found(String name, Boolean guessed) {
            this.name = name;
            this.guessed = guessed;
        }
    }

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
        /** True when the object or the field is a best guess, not an exact match (C-49e). */
        @NamespaceAccessible
        public Boolean guessed = false;

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

    /** The name a part of a heading or a file name spells exactly, or null. */
    @NamespaceAccessible
    public static String match(String part, Map<String, String> keys) {
        if (keys == null || String.isBlank(part)) {
            return null;
        }
        String found = keys.get(ImportColumnLibrary.normalize(part));
        return String.isBlank(found) ? null : found;
    }

    /**
     * The name a part spells: exact when one is (never a guess), else the best guess (C-49e),
     * else null. The seam every fuzzy reading goes through.
     */
    @NamespaceAccessible
    public static Found find(String part, Map<String, String> keys) {
        String exact = match(part, keys);
        if (exact != null) {
            return new Found(exact, false);
        }
        String guessed = guess(part, keys);
        return guessed == null ? null : new Found(guessed, true);
    }

    /**
     * The name whose spelling `FuzzyMatch.bestMatch` scores closest to the part, at or above
     * GUESS_THRESHOLD, or null: also null for a short part, and when two names tie for the best
     * score (an ambiguous guess is no guess). Only spellings of a near length are offered, and
     * never one two names share (AMBIGUOUS).
     */
    @NamespaceAccessible
    public static String guess(String part, Map<String, String> keys) {
        String key = ImportColumnLibrary.normalize(part);
        if (keys == null || key.length() < GUESS_MIN_LENGTH) {
            return null;
        }
        List<String> spellings = new List<String>();
        for (String spelling : keys.keySet()) {
            Double shorter = Math.min(spelling.length(), key.length());
            Double longer = Math.max(spelling.length(), key.length());
            if (
                String.isNotBlank(keys.get(spelling)) && shorter / longer >= GUESS_MIN_LENGTH_RATIO
            ) {
                spellings.add(spelling);
            }
        }
        String best = FuzzyMatch.bestMatch(key, spellings, GUESS_THRESHOLD);
        if (best == null) {
            return null;
        }
        String name = keys.get(best);
        Double bestScore = FuzzyMatch.score(key, best);
        for (String spelling : spellings) {
            if (!keys.get(spelling).equals(name) && FuzzyMatch.score(key, spelling) >= bestScore) {
                return null;
            }
        }
        return name;
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
        Map<String, Resolved> found = readings(explicitSplits(text), objectKeys, fields, false);
        if (found.isEmpty()) {
            found = readings(underscoreSplits(text), objectKeys, fields, false);
        }
        return found.size() == 1 ? found.values()[0] : null;
    }

    /**
     * As `resolve`, and when no reading is exact, the one reading whose object or field is a
     * best guess (C-49e), flagged as guessed; null when none reads, or several do. The caller
     * passes only the objects a template loads, so the guesses stay few.
     */
    @NamespaceAccessible
    public static Resolved resolveOrGuess(
        String header,
        Map<String, String> objectKeys,
        FieldKeys fields
    ) {
        String text = clean(header);
        List<List<String>> explicit = explicitSplits(text);
        List<List<String>> underscores = underscoreSplits(text);
        Boolean anyExact =
            !readings(explicit, objectKeys, fields, false).isEmpty() ||
            !readings(underscores, objectKeys, fields, false).isEmpty();
        if (anyExact) {
            // Exact readings win; two of them that disagree name nothing, and are not guessed.
            return resolve(header, objectKeys, fields);
        }
        Map<String, Resolved> found = readings(explicit, objectKeys, fields, true);
        if (found.isEmpty()) {
            found = readings(underscores, objectKeys, fields, true);
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

    /**
     * The object a sheet or file name names exactly (as `objectOfName`), else the best guess at
     * it (C-49e): "Contcts" for Contact. Null when neither reads.
     */
    @NamespaceAccessible
    public static Found objectOfNameOrGuess(String name, Map<String, String> objectKeys) {
        String exact = objectOfName(name, objectKeys);
        if (exact != null) {
            return new Found(exact, false);
        }
        String withoutDigits = clean(name).replaceAll('[0-9]', ' ');
        String guessed = guess(withoutDigits, objectKeys);
        if (guessed == null) {
            List<String> kept = new List<String>();
            for (String word : withoutDigits.toLowerCase().split('[^a-z]+')) {
                if (!IGNORED_WORDS.contains(word)) {
                    kept.add(word);
                }
            }
            guessed = guess(String.join(kept, ' '), objectKeys);
        }
        return guessed == null ? null : new Found(guessed, true);
    }

    /** As `objectOfNameOrGuess`, for a file name with its extension. */
    @NamespaceAccessible
    public static Found objectOfFileNameOrGuess(String fileName, Map<String, String> objectKeys) {
        return objectOfNameOrGuess(
            clean(fileName).replaceAll('\\.[A-Za-z0-9]{1,5}$', ''),
            objectKeys
        );
    }

    // -------------------------------------------------------------------------------------
    // Splits, each an [object part, field part] pair
    // -------------------------------------------------------------------------------------

    /**
     * Whether the heading, split at a separator or in parentheses ("Contact.Shoe Size",
     * "Phone (Contact)"), has a part that spells one of the objects exactly. Such a heading
     * names an object, so it is read as object plus field, never fuzzy-matched whole (D-150).
     */
    @NamespaceAccessible
    public static Boolean namesObject(String header, Map<String, String> objectKeys) {
        for (List<String> split : explicitSplits(clean(header))) {
            if (match(split[0], objectKeys) != null) {
                return true;
            }
        }
        return false;
    }

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

    /**
     * The distinct object and field pairs the splits read as, keyed by object and field. With
     * guesses, only readings with a guessed object or field, each flagged (C-49e).
     */
    private static Map<String, Resolved> readings(
        List<List<String>> splits,
        Map<String, String> objectKeys,
        FieldKeys fields,
        Boolean withGuesses
    ) {
        Map<String, Resolved> found = new Map<String, Resolved>();
        for (List<String> split : splits) {
            Found objectFound = withGuesses
                ? find(split[0], objectKeys)
                : asFound(match(split[0], objectKeys));
            Found fieldFound = objectFound == null
                ? null
                : withGuesses
                      ? find(split[1], fields.keysOf(objectFound.name))
                      : asFound(match(split[1], fields.keysOf(objectFound.name)));
            if (fieldFound == null) {
                continue;
            }
            Boolean guessed = objectFound.guessed || fieldFound.guessed;
            if (withGuesses && !guessed) {
                continue;
            }
            Resolved reading = new Resolved(objectFound.name, fieldFound.name);
            reading.guessed = guessed;
            found.put((objectFound.name + '.' + fieldFound.name).toLowerCase(), reading);
        }
        return found;
    }

    private static Found asFound(String exact) {
        return exact == null ? null : new Found(exact, false);
    }
}
