/**
 * The values Salesforce Setup holds that the settings console shows read only (ADR-NEXT): a
 * Setting Definition row whose data type is SetupValue names one of these keys, and the
 * console shows what Setup says rather than keeping a copy that could drift from it.
 *
 * Only the keys listed here can be shown, so a row cannot be pointed at an arbitrary field.
 * `check-custom-metadata.py` fails a SetupValue row whose key is not one of them.
 */
public with sharing class SetupValueSelector {
    /** The object every SetupValue row names as its settings object. */
    public static final String ORGANIZATION = 'Organization';

    /** The organization's name, from Setup, Company Settings, Company Information. */
    public static final String KEY_ORGANIZATION_NAME = 'Name';

    /** The month the fiscal year starts, from Setup, Company Settings, Fiscal Year. */
    public static final String KEY_FISCAL_YEAR_START = 'FiscalYearStartMonth';

    /** Injected by tests, which cannot rename the org. */
    @TestVisible
    private static String organizationNameOverride;

    /**
     * Whether a row's settings object and key name a value this class can show. A row that
     * does not is left out of the console, as a row naming a missing setting is.
     */
    public static Boolean supports(String settingsObject, String key) {
        return ORGANIZATION.equalsIgnoreCase(String.valueOf(settingsObject).trim()) &&
            (KEY_ORGANIZATION_NAME.equalsIgnoreCase(key) ||
            KEY_FISCAL_YEAR_START.equalsIgnoreCase(key));
    }

    /** The value as a person reads it, or null when the key is not one this class shows. */
    public static String valueOf(String settingsObject, String key) {
        if (!supports(settingsObject, key)) {
            return null;
        }
        if (KEY_FISCAL_YEAR_START.equalsIgnoreCase(key)) {
            return FiscalYearSelector.monthName(FiscalYearSelector.fiscalYearStartMonth());
        }
        return organizationName();
    }

    /**
     * System mode, as FiscalYearSelector reads the fiscal year: the name is org configuration
     * every user already sees, not record data, and the page must show it whoever opens it.
     */
    private static String organizationName() {
        if (organizationNameOverride != null) {
            return organizationNameOverride;
        }
        List<Organization> organizations = [
            SELECT Name
            FROM Organization
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return organizations.isEmpty() ? null : organizations[0].Name;
    }
}
