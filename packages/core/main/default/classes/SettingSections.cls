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
    @NamespaceAccessible
    public static final String AUTOMATION = 'Automation';
    /** The error digest (C-23): its own section because it is a job, not an automation. */
    @NamespaceAccessible
    public static final String ERROR_LOG = 'Error Log';
    @NamespaceAccessible
    public static final String ACCESS = 'Access';
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
    public static final String ADDRESSES = 'Addresses';
    @NamespaceAccessible
    public static final String RELATIONSHIPS = 'Relationships';

    /** Every section name a package may use, in the order the console lists them. */
    @NamespaceAccessible
    public static List<String> all() {
        return new List<String>{
            GENERAL,
            MODULES,
            ORGANIZATION,
            HOUSEHOLDS,
            RELATIONSHIPS,
            ADDRESSES,
            GIVING,
            RECEIPTS,
            ROLLUPS,
            AUTOMATION,
            ERROR_LOG,
            ACCESS,
            IMPORTING,
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
