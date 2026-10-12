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
                Delimiter__c,
                Target_Field__c,
                Filter_JSON__c,
                Target_Filter_JSON__c,
                Fiscal_Year_Aware__c,
                Fiscal_Year_Offset__c,
                Fiscal_Date_Field__c,
                Mode__c,
                Last_Calculated__c,
                Is_Package_Default__c,
                Active__c
            FROM Rollup_Definition__c
            WITH USER_MODE
            ORDER BY Target_Object__c, Name
            LIMIT 2000
        ];
    }

    /** Every definition, read as the package, for the engine. */
    public static List<Rollup_Definition__c> selectAll() {
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
                Delimiter__c,
                Target_Field__c,
                Filter_JSON__c,
                Target_Filter_JSON__c,
                Fiscal_Year_Aware__c,
                Fiscal_Year_Offset__c,
                Fiscal_Date_Field__c,
                Mode__c,
                Last_Calculated__c,
                Is_Package_Default__c,
                Active__c
            FROM Rollup_Definition__c
            WITH SYSTEM_MODE
            ORDER BY Target_Object__c, Name
            LIMIT 2000
        ];
    }

    /** The active definitions whose source entity is the one that just changed. */
    public static List<Rollup_Definition__c> selectActiveForSource(
        String sourceObject,
        Set<String> modes
    ) {
        if (String.isBlank(sourceObject) || modes == null || modes.isEmpty()) {
            return new List<Rollup_Definition__c>();
        }
        List<Rollup_Definition__c> matching = new List<Rollup_Definition__c>();
        for (Rollup_Definition__c definition : selectAll()) {
            if (
                definition.Active__c == true &&
                sourceObject.equalsIgnoreCase(definition.Source_Object__c) &&
                modes.contains(definition.Mode__c)
            ) {
                matching.add(definition);
            }
        }
        return matching;
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
                Delimiter__c,
                Target_Field__c,
                Filter_JSON__c,
                Target_Filter_JSON__c,
                Fiscal_Year_Aware__c,
                Fiscal_Year_Offset__c,
                Fiscal_Date_Field__c,
                Mode__c,
                Last_Calculated__c,
                Is_Package_Default__c,
                Active__c
            FROM Rollup_Definition__c
            WHERE Id = :definitionId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
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
