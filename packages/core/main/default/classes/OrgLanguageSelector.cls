/**
 * The org's default language (Setup, Company Information), which household names and
 * greetings are written in whoever saves the household (owner decision, 2026-10-13).
 *
 * `Organization` is a standard object every org has and not one Core is forbidden to touch
 * (plan Section 4.2). It is read in system mode: the language is org configuration, not
 * anybody's data, and a household is named in a trigger running as whichever user saved,
 * who must not get a name in another language because they cannot read Company Information.
 * It is read once per transaction.
 */
public with sharing class OrgLanguageSelector {
    /** Injected by the tests, which cannot change the org's default language. */
    @TestVisible
    private static String languageOverride;

    private static String cached;
    private static Boolean read = false;

    /**
     * The org's default language, such as en_US, or null when it cannot be read.
     *
     * @return the language locale key, or null
     */
    public static String defaultLanguage() {
        if (languageOverride != null) {
            return languageOverride;
        }
        if (!read) {
            read = true;
            try {
                List<Organization> organizations = [
                    SELECT LanguageLocaleKey
                    FROM Organization
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];
                cached = organizations.isEmpty() ? null : organizations[0].LanguageLocaleKey;
            } catch (QueryException cannotRead) {
                cached = null;
            }
        }
        return cached;
    }
}
