/**
 * Help and guidance text for Apex, from the packaged JSON catalogs (ADR-NEXT help-text-json).
 *
 * Each package ships its help prose as one static resource, BarnHelp_<Package>, shaped
 * { "languages": ["en"], "texts": { "<key>": "<text>" } }, keyed by the API name the text had as
 * a custom label. A translation is a second resource, BarnHelp_<Package>_<language>, listed in
 * the English file's "languages" and holding only the keys it translates. Custom labels count
 * toward an org's 5,000 when BarnCRM is installed from source or unmanaged, so help prose lives
 * here; buttons, titles and messages stay custom labels.
 *
 * A catalog is read once per transaction: one query for the package's resources (the English
 * file and the user's language), then cached. A missing key, resource or translation reads as
 * an empty string (English for a missing translation), never an exception: help must never
 * break the work it explains. Lightning web components read the same files through
 * c/barnHelpText, not through this class.
 */
@NamespaceAccessible
public with sharing class BarnHelp {
    private static final String BASE_LANGUAGE = 'en';

    /** Texts by package, loaded once per transaction. */
    private static Map<String, Map<String, String>> textsByPackage = new Map<String, Map<String, String>>();

    /** Stands in for the static resources in tests: resource name to JSON body. */
    @TestVisible
    private static Map<String, String> bodiesForTest;

    /** Stands in for UserInfo.getLanguage() in tests. */
    @TestVisible
    private static String languageForTest;

    /**
     * The help text for a key in a package's catalog (Core, Giving, Rollups, Volunteers,
     * Programs, LogicModels, Funders, Mirror), or an empty string when there is none.
     */
    @NamespaceAccessible
    public static String text(String packageName, String key) {
        String value = texts(packageName).get(key);
        return value == null ? '' : value;
    }

    /** The same, with {0}, {1} and so on filled in as String.format does for a label. */
    @NamespaceAccessible
    public static String text(String packageName, String key, List<Object> args) {
        String value = text(packageName, key);
        return String.isBlank(value) ||
            args == null ||
            args.isEmpty()
            ? value
            : String.format(value, args);
    }

    private static Map<String, String> texts(String packageName) {
        if (!textsByPackage.containsKey(packageName)) {
            textsByPackage.put(packageName, load(packageName));
        }
        return textsByPackage.get(packageName);
    }

    /** The user's language, then its base language, never English: en_US gives none. */
    @TestVisible
    private static List<String> languageCandidates(String language) {
        List<String> out = new List<String>();
        if (String.isBlank(language) || language.substringBefore('_') == BASE_LANGUAGE) {
            return out;
        }
        out.add(language);
        if (language.contains('_')) {
            out.add(language.substringBefore('_'));
        }
        return out;
    }

    private static Map<String, String> load(String packageName) {
        String base = 'BarnHelp_' + packageName;
        List<String> languages = languageCandidates(
            languageForTest != null ? languageForTest : UserInfo.getLanguage()
        );
        Set<String> names = new Set<String>{ base };
        for (String language : languages) {
            names.add(base + '_' + language);
        }
        Map<String, String> bodies = bodies(names);
        Map<String, Object> english = parse(bodies.get(base));
        Map<String, String> merged = textsOf(english);
        Set<String> available = new Set<String>();
        if (english.get('languages') instanceof List<Object>) {
            for (Object language : (List<Object>) english.get('languages')) {
                available.add(String.valueOf(language));
            }
        }
        // Least specific first, so the regional translation wins.
        for (Integer i = languages.size() - 1; i >= 0; i--) {
            if (available.contains(languages[i])) {
                merged.putAll(textsOf(parse(bodies.get(base + '_' + languages[i]))));
            }
        }
        return merged;
    }

    private static Map<String, String> bodies(Set<String> names) {
        Map<String, String> out = new Map<String, String>();
        if (bodiesForTest != null) {
            for (String name : names) {
                if (bodiesForTest.containsKey(name)) {
                    out.put(name, bodiesForTest.get(name));
                }
            }
            return out;
        }
        String prefix = NamespaceUtil.prefix().removeEnd('__');
        String namespace = String.isBlank(prefix) ? null : prefix;
        // System mode: a static resource is packaged text every user is meant to read, and
        // reading StaticResource in user mode needs a setup permission most users lack. The
        // namespace filter keeps this package's resources, never a same-named one of the org's.
        for (StaticResource resource : [
            SELECT Name, Body
            FROM StaticResource
            WHERE Name IN :names AND NamespacePrefix = :namespace
            WITH SYSTEM_MODE
        ]) {
            out.put(resource.Name, resource.Body.toString());
        }
        return out;
    }

    private static Map<String, Object> parse(String body) {
        if (String.isBlank(body)) {
            return new Map<String, Object>();
        }
        try {
            Object parsed = JSON.deserializeUntyped(body);
            return parsed instanceof Map<String, Object>
                ? (Map<String, Object>) parsed
                : new Map<String, Object>();
        } catch (JSONException e) {
            return new Map<String, Object>();
        }
    }

    private static Map<String, String> textsOf(Map<String, Object> catalog) {
        Map<String, String> out = new Map<String, String>();
        if (catalog.get('texts') instanceof Map<String, Object>) {
            Map<String, Object> texts = (Map<String, Object>) catalog.get('texts');
            for (String key : texts.keySet()) {
                out.put(key, String.valueOf(texts.get(key)));
            }
        }
        return out;
    }
}
