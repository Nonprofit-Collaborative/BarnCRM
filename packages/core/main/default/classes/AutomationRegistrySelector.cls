/**
 * Every query against the shipped automation registry.
 *
 * The registry is package-shipped custom metadata, read only to administrators, and it holds no
 * organization data, so it is read as shipped rather than in user mode. It is small and it is
 * read on every save through the dispatcher, so it is read once per transaction and grouped by
 * object here.
 *
 * v0.1 ships the type with no records. Feature C-01 adds the first entries, for the contact and
 * account handlers, in the same change that adds those triggers.
 */
public with sharing class AutomationRegistrySelector {
    /**
     * Custom metadata cannot be inserted by a test, so tests put in-memory records here and
     * every read in the package sees them.
     */
    @TestVisible
    private static List<Automation_Registry__mdt> registryOverride;

    private static Map<String, List<Automation_Registry__mdt>> byObjectName;

    public static List<Automation_Registry__mdt> selectAll() {
        if (registryOverride != null) {
            return registryOverride;
        }
        return [
            SELECT
                DeveloperName,
                MasterLabel,
                Description__c,
                Handler_Class__c,
                Object_Name__c,
                Execution_Order__c,
                Enabled_By_Default__c,
                Always_Runs__c,
                Module__c
            FROM Automation_Registry__mdt
            WITH SYSTEM_MODE
            ORDER BY Execution_Order__c NULLS LAST, DeveloperName
            LIMIT 1000
        ];
    }

    /**
     * The automations registered against one object, in the order they run. Read once per
     * transaction however many times a trigger fires.
     */
    public static List<Automation_Registry__mdt> selectForObject(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return new List<Automation_Registry__mdt>();
        }
        if (byObjectName == null) {
            byObjectName = groupByObjectName(selectAll());
        }
        List<Automation_Registry__mdt> forObject = byObjectName.get(objectApiName.toLowerCase());
        return forObject == null ? new List<Automation_Registry__mdt>() : forObject;
    }

    public static void clearCache() {
        byObjectName = null;
    }

    private static Map<String, List<Automation_Registry__mdt>> groupByObjectName(
        List<Automation_Registry__mdt> entries
    ) {
        Map<String, List<Automation_Registry__mdt>> grouped = new Map<String, List<Automation_Registry__mdt>>();
        for (Automation_Registry__mdt entry : sortedByOrder(entries)) {
            if (String.isBlank(entry.Object_Name__c)) {
                continue;
            }
            String key = entry.Object_Name__c.toLowerCase();
            if (!grouped.containsKey(key)) {
                grouped.put(key, new List<Automation_Registry__mdt>());
            }
            grouped.get(key).add(entry);
        }
        return grouped;
    }

    /**
     * The query orders the rows, but an override supplied by a test may not be ordered, so the
     * grouping sorts by execution order and then by name.
     */
    private static List<Automation_Registry__mdt> sortedByOrder(
        List<Automation_Registry__mdt> entries
    ) {
        Map<String, Automation_Registry__mdt> bySortKey = new Map<String, Automation_Registry__mdt>();
        for (Automation_Registry__mdt entry : entries) {
            Integer order = entry.Execution_Order__c == null
                ? 999999
                : entry.Execution_Order__c.intValue();
            String sortKey = String.valueOf(1000000 + order) + '.' + entry.DeveloperName;
            bySortKey.put(sortKey, entry);
        }
        List<String> sortKeys = new List<String>(bySortKey.keySet());
        sortKeys.sort();
        List<Automation_Registry__mdt> sorted = new List<Automation_Registry__mdt>();
        for (String sortKey : sortKeys) {
            sorted.add(bySortKey.get(sortKey));
        }
        return sorted;
    }
}
