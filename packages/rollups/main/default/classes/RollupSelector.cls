/**
 * Every query the rollup engine makes against its own configuration.
 *
 * Rollup Definitions are configuration an administrator manages, so the console reads them in
 * user mode. The engine itself reads them in system mode: a nightly batch and a trigger both run
 * for whoever happened to save a record, and a total that depends on who saved the gift is not a
 * total (plan Section 4.13, the same reasoning ADR-0015 records for the vendored writes).
 */
public with sharing class RollupSelector {
    /**
     * Custom metadata cannot be inserted by a test, so tests put in-memory rows here and every
     * read in the package sees them.
     */
    @TestVisible
    private static List<Rollup_Definition_Default__mdt> defaultsOverride;

    /** Every definition, whatever its mode or state, for the console list. */
    public static List<Rollup_Definition__c> selectAllAsUser() {
        return [
            SELECT
                Id,
                Name,
                Description__c,
                Definition_Key__c,
                Source_Object__c,
                Target_Object__c,
                Relationship_Path__c,
                Aggregate__c,
                Source_Field__c,
                Order_By_Field__c,
                Order_Direction__c,
                Row_Limit__c,
                Delimiter__c,
                Custom_Delimiter__c,
                Include_Deleted__c,
                Target_Field__c,
                Filter_JSON__c,
                Target_Filter_JSON__c,
                Fiscal_Year_Aware__c,
                Fiscal_Year_Offset__c,
                Fiscal_Date_Field__c,
                Mode__c,
                Last_Calculated__c,
                Is_Package_Default__c,
                Active__c,
                Bypass_Permission__c
            FROM Rollup_Definition__c
            WITH USER_MODE
            ORDER BY Target_Object__c, Name
            LIMIT 2000
        ];
    }

    /**
     * The engine's read of every definition, kept for the rest of the transaction (ROLLUPS-5):
     * one gift save used to read the definitions about six times, once per target entity and
     * once per trigger. Every save or delete of a definition clears it (`RollupDefinitionTrigger`,
     * whatever automation is switched off), so a definition saved earlier in a transaction is
     * the one a later record save in it runs.
     */
    private static List<Rollup_Definition__c> cachedAll;

    /** Forgets the cached definitions; the next engine read queries them again. */
    public static void clearCache() {
        cachedAll = null;
    }

    /**
     * Every definition, read as the package, for the engine. Read once per transaction; each
     * caller gets its own list, and no caller changes the records in it.
     */
    public static List<Rollup_Definition__c> selectAll() {
        if (cachedAll == null) {
            cachedAll = queryAll();
        }
        return cachedAll.clone();
    }

    private static List<Rollup_Definition__c> queryAll() {
        return [
            SELECT
                Id,
                Name,
                Description__c,
                Definition_Key__c,
                Source_Object__c,
                Target_Object__c,
                Relationship_Path__c,
                Aggregate__c,
                Source_Field__c,
                Order_By_Field__c,
                Order_Direction__c,
                Row_Limit__c,
                Delimiter__c,
                Custom_Delimiter__c,
                Include_Deleted__c,
                Target_Field__c,
                Filter_JSON__c,
                Target_Filter_JSON__c,
                Fiscal_Year_Aware__c,
                Fiscal_Year_Offset__c,
                Fiscal_Date_Field__c,
                Mode__c,
                Last_Calculated__c,
                Is_Package_Default__c,
                Active__c,
                Bypass_Permission__c
            FROM Rollup_Definition__c
            WITH SYSTEM_MODE
            ORDER BY Target_Object__c, Name
            LIMIT 2000
        ];
    }

    /** The active definitions whose target entity is this one, for a merge of its records. */
    public static List<Rollup_Definition__c> selectActiveForTarget(
        String targetObject,
        Set<String> modes
    ) {
        if (String.isBlank(targetObject) || modes == null || modes.isEmpty()) {
            return new List<Rollup_Definition__c>();
        }
        List<Rollup_Definition__c> matching = new List<Rollup_Definition__c>();
        for (Rollup_Definition__c definition : selectAll()) {
            if (
                definition.Active__c == true &&
                targetObject.equalsIgnoreCase(definition.Target_Object__c) &&
                modes.contains(definition.Mode__c)
            ) {
                matching.add(definition);
            }
        }
        return matching;
    }

    /**
     * The active definitions among these, for a queue entry that names the definitions that
     * queued it; one switched off or deleted since is left out.
     */
    public static List<Rollup_Definition__c> selectActiveByIds(Set<Id> definitionIds) {
        List<Rollup_Definition__c> matching = new List<Rollup_Definition__c>();
        if (definitionIds == null || definitionIds.isEmpty()) {
            return matching;
        }
        for (Rollup_Definition__c definition : selectAll()) {
            if (definition.Active__c == true && definitionIds.contains(definition.Id)) {
                matching.add(definition);
            }
        }
        return matching;
    }

    /** The active definitions the nightly batch runs. */
    public static List<Rollup_Definition__c> selectActiveForModes(Set<String> modes) {
        List<Rollup_Definition__c> matching = new List<Rollup_Definition__c>();
        for (Rollup_Definition__c definition : selectAll()) {
            if (
                definition.Active__c == true &&
                modes != null &&
                modes.contains(definition.Mode__c)
            ) {
                matching.add(definition);
            }
        }
        return matching;
    }

    /** One definition by its record id, or null when the id names nothing. */
    public static Rollup_Definition__c selectById(Id definitionId) {
        if (definitionId == null) {
            return null;
        }
        List<Rollup_Definition__c> found = [
            SELECT
                Id,
                Name,
                Description__c,
                Definition_Key__c,
                Source_Object__c,
                Target_Object__c,
                Relationship_Path__c,
                Aggregate__c,
                Source_Field__c,
                Order_By_Field__c,
                Order_Direction__c,
                Row_Limit__c,
                Delimiter__c,
                Custom_Delimiter__c,
                Include_Deleted__c,
                Target_Field__c,
                Filter_JSON__c,
                Target_Filter_JSON__c,
                Fiscal_Year_Aware__c,
                Fiscal_Year_Offset__c,
                Fiscal_Date_Field__c,
                Mode__c,
                Last_Calculated__c,
                Is_Package_Default__c,
                Active__c,
                Bypass_Permission__c
            FROM Rollup_Definition__c
            WHERE Id = :definitionId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }

    /** True when at least one definition is active, so there is something that should have run. */
    public static Boolean hasActiveDefinition() {
        for (Rollup_Definition__c definition : selectAll()) {
            if (definition.Active__c == true) {
                return true;
            }
        }
        return false;
    }

    /** The most recent completed calculation across the active definitions, for the Hub tile. */
    public static Datetime lastCalculatedAcrossActive() {
        Datetime latest;
        for (Rollup_Definition__c definition : selectAll()) {
            if (definition.Active__c != true || definition.Last_Calculated__c == null) {
                continue;
            }
            if (latest == null || definition.Last_Calculated__c > latest) {
                latest = definition.Last_Calculated__c;
            }
        }
        return latest;
    }

    /**
     * The custom permissions in the org among these names, each as `name` and, for one in a
     * namespace, `prefix__name` too, lower case, so a Bypass Permission can be checked whichever
     * way it is written (R-R4a). Read as the package: whether a name exists is all it tells,
     * and the person saving a rollup need not be able to see setup.
     *
     * @param developerNames the Developer Names to look for, without any prefix
     */
    public static Set<String> customPermissionNames(Set<String> developerNames) {
        Set<String> found = new Set<String>();
        if (developerNames == null || developerNames.isEmpty()) {
            return found;
        }
        for (CustomPermission permission : [
            SELECT DeveloperName, NamespacePrefix
            FROM CustomPermission
            WHERE DeveloperName IN :developerNames
            WITH SYSTEM_MODE
            LIMIT 2000
        ]) {
            String name = permission.DeveloperName.toLowerCase();
            found.add(name);
            if (String.isNotBlank(permission.NamespacePrefix)) {
                found.add(permission.NamespacePrefix.toLowerCase() + '__' + name);
            }
        }
        return found;
    }

    /** Every shipped default, whichever package ships it. */
    public static List<Rollup_Definition_Default__mdt> selectShippedDefaults() {
        if (defaultsOverride != null) {
            return defaultsOverride;
        }
        return [
            SELECT
                DeveloperName,
                MasterLabel,
                Description__c,
                Definition_Key__c,
                Source_Object__c,
                Target_Object__c,
                Relationship_Path__c,
                Aggregate__c,
                Source_Field__c,
                Order_By_Field__c,
                Target_Field__c,
                Filter_JSON__c,
                Target_Filter_JSON__c,
                Fiscal_Year_Aware__c,
                Fiscal_Year_Offset__c,
                Fiscal_Date_Field__c,
                Mode__c,
                Default_Active__c,
                Package__c
            FROM Rollup_Definition_Default__mdt
            WITH SYSTEM_MODE
            ORDER BY Definition_Key__c
            LIMIT 1000
        ];
    }
}
