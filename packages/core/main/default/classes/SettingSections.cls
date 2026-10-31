/**
 * The section names the BarnCRM Settings console groups by.
 *
 * Every package that ships a Setting Definition row uses one of these exact strings in
 * `Section__c`, and the Setup Assistant points its steps at them, so a step's Open action lands
 * on the section it names. A new section is added here first.
 */
@NamespaceAccessible
public with sharing class SettingSections {
    @NamespaceAccessible
    public static final String GENERAL = 'General';
    /** The BarnCRM modules (ADR-0124): the one place a module is installed and opened from. */
    @NamespaceAccessible
    public static final String MODULES = 'Modules';
    /** People, households and relationships on one page: the old Households and Relationships. */
    @NamespaceAccessible
    public static final String PEOPLE_AND_HOUSEHOLDS = 'People and Households';
    /**
     * A sub-section (a box) of People and Households. A link may name a sub-section instead of
     * a page: the console opens the page it is on and scrolls to it. Households and
     * Relationships were pages until P1, so a link or a row that still names them lands there.
     */
    @NamespaceAccessible
    public static final String HOUSEHOLDS = 'Households';
    /** A sub-section of People and Households: how a person belongs to a household. */
    @NamespaceAccessible
    public static final String PEOPLE = 'People';
    /** A sub-section of People and Households: the naming patterns and their preview. */
    @NamespaceAccessible
    public static final String HOUSEHOLD_NAMES = 'Household Names and Greetings';
    /** The Duplicate Matching tool's settings and the way into its tab (ADR-0139). */
    @NamespaceAccessible
    public static final String DUPLICATE_MATCHING = 'Duplicate Matching';
    @NamespaceAccessible
    public static final String AUTOMATION = 'Automation';
    /** The error digest (C-23): its own section because it is a job, not an automation. */
    @NamespaceAccessible
    public static final String ERROR_LOG = 'Error Log';
    @NamespaceAccessible
    public static final String ACCESS = 'Access';
    /** The Org Optimizer thresholds (how old is stale, how long is unused): the tool's own section. */
    @NamespaceAccessible
    public static final String ORG_OPTIMIZER = 'Org Optimizer';
    @NamespaceAccessible
    public static final String HEALTH = 'Health';
    @NamespaceAccessible
    public static final String IMPORTING = 'Import';
    @NamespaceAccessible
    public static final String ORGANIZATION = 'Organization';
    @NamespaceAccessible
    public static final String GIVING = 'Giving';
    /** Receipts, which Giving ships: its own section because a receipt run is its own job. */
    @NamespaceAccessible
    public static final String RECEIPTS = 'Receipts';
    @NamespaceAccessible
    public static final String ROLLUPS = 'Rollups';
    @NamespaceAccessible
    public static final String VOLUNTEERS = 'Volunteers';
    /** The Programs module's section, which opens its own settings page. */
    @NamespaceAccessible
    public static final String PROGRAMS = 'Programs';
    @NamespaceAccessible
    public static final String ADDRESSES = 'Addresses';
    /** A sub-section of People and Households, and a page until P1 (see HOUSEHOLDS). */
    @NamespaceAccessible
    public static final String RELATIONSHIPS = 'Relationships';
    /** Other products that complement or overlap BarnCRM, listed and linked, never depended on. */
    @NamespaceAccessible
    public static final String INTEGRATIONS = 'Integrations';

    /** Every section name a package may use, in the order the console lists them. */
    @NamespaceAccessible
    public static List<String> all() {
        return new List<String>{
            GENERAL,
            MODULES,
            ORGANIZATION,
            PEOPLE_AND_HOUSEHOLDS,
            DUPLICATE_MATCHING,
            ADDRESSES,
            GIVING,
            RECEIPTS,
            ROLLUPS,
            PROGRAMS,
            VOLUNTEERS,
            AUTOMATION,
            ERROR_LOG,
            ACCESS,
            IMPORTING,
            ORG_OPTIMIZER,
            INTEGRATIONS,
            HEALTH
        };
    }

    /** The sub-sections a link may name, by name in lower case, each with the page it is on. */
    private static Map<String, String> pageBySubSection() {
        Map<String, String> pages = new Map<String, String>();
        for (String box : new List<String>{ PEOPLE, HOUSEHOLDS, HOUSEHOLD_NAMES, RELATIONSHIPS }) {
            pages.put(box.toLowerCase(), PEOPLE_AND_HOUSEHOLDS);
        }
        return pages;
    }

    /**
     * The page a section name is shown on: the page a sub-section is on, so a row or a link that
     * still names the old Households or Relationships page lands on People and Households; any
     * other name as given.
     */
    @NamespaceAccessible
    public static String pageFor(String name) {
        String key = name == null ? '' : name.trim().toLowerCase();
        Map<String, String> pages = pageBySubSection();
        return pages.containsKey(key) ? pages.get(key) : name;
    }

    /**
     * True when the given name is one of the shipped sections, or a sub-section a link may name,
     * ignoring case and spacing.
     */
    @NamespaceAccessible
    public static Boolean isKnown(String name) {
        if (String.isBlank(name)) {
            return false;
        }
        if (pageBySubSection().containsKey(name.trim().toLowerCase())) {
            return true;
        }
        for (String section : all()) {
            if (section.equalsIgnoreCase(name.trim())) {
                return true;
            }
        }
        return false;
    }
}
