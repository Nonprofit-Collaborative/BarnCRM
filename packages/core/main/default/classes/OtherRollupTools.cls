/**
 * Other rollup tools in this org: DLRS (Declarative Lookup Rollup Summaries) and Rollup Helper.
 * BarnCRM says they are here, on the Rollup Builder tab, in the Setup Assistant and on the
 * Modules page; it never manages, edits or switches off their rollups (canonical model R-R16).
 *
 * Detection is not dependency (ADR-0013): each tool is found by the namespace prefix of its
 * objects in the global describe, held as a String, so Core deploys and runs on an org without
 * either. The answer is kept for the transaction, because a global describe is expensive.
 */
@NamespaceAccessible
public with sharing class OtherRollupTools {
    /** The managed namespace of DLRS. */
    @NamespaceAccessible
    public static final String DLRS_NAMESPACE = 'dlrs';
    /** The managed namespace of Rollup Helper (Passage Technology). */
    @NamespaceAccessible
    public static final String ROLLUP_HELPER_NAMESPACE = 'rh2';

    private static final List<String> NAMESPACES = new List<String>{
        DLRS_NAMESPACE,
        ROLLUP_HELPER_NAMESPACE
    };

    private static Set<String> found;

    /**
     * Makes a test see these namespaces as installed, or detect again with null. A module's
     * test cannot reach a `@TestVisible` member across the package boundary, so this is the seam;
     * it does nothing outside a test.
     */
    @NamespaceAccessible
    public static void overrideForTest(Set<String> namespaces) {
        if (Test.isRunningTest()) {
            found = namespaces;
        }
    }

    /** Whether DLRS is installed. */
    @NamespaceAccessible
    public static Boolean hasDlrs() {
        return installed().contains(DLRS_NAMESPACE);
    }

    /** Whether Rollup Helper is installed. */
    @NamespaceAccessible
    public static Boolean hasRollupHelper() {
        return installed().contains(ROLLUP_HELPER_NAMESPACE);
    }

    /** One plain notice per tool found, DLRS first; empty when neither is here. */
    @NamespaceAccessible
    public static List<String> notices() {
        List<String> notices = new List<String>();
        if (hasDlrs()) {
            notices.add(System.Label.Core_OtherRollupTools_Dlrs);
        }
        if (hasRollupHelper()) {
            notices.add(System.Label.Core_OtherRollupTools_RollupHelper);
        }
        return notices;
    }

    private static Set<String> installed() {
        if (found == null) {
            found = new Set<String>();
            for (String objectName : NamespaceUtil.globalDescribe().keySet()) {
                String name = objectName.toLowerCase();
                for (String namespace : NAMESPACES) {
                    if (name.startsWith(namespace + '__')) {
                        found.add(namespace);
                    }
                }
            }
        }
        return found;
    }
}
