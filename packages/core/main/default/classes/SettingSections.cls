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
    @NamespaceAccessible
    public static final String HOUSEHOLDS = 'Households';
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
    @NamespaceAccessible
    public static final String ADDRESSES = 'Addresses';
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
            HOUSEHOLDS,
            DUPLICATE_MATCHING,
            RELATIONSHIPS,
            ADDRESSES,
            GIVING,
            RECEIPTS,
            ROLLUPS,
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

    /** True when the given name is one of the shipped sections, ignoring case and spacing. */
    @NamespaceAccessible
    public static Boolean isKnown(String name) {
        if (String.isBlank(name)) {
            return false;
        }
        for (String section : all()) {
            if (section.equalsIgnoreCase(name.trim())) {
                return true;
            }
        }
        return false;
    }
}
