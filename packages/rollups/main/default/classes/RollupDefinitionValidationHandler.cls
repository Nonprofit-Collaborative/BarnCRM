/**
 * Refuses a rollup whose target attribute cannot hold its calculation (canonical model R-R10 and
 * R-R15): Any or None into anything but a checkbox, a text list into anything but text, a sum into
 * text, and so on, each with a message that says which kind of field to choose. The check is
 * `RollupPlanner.saveProblem`, the same rule the planner applies at run time, so a definition the
 * page lets through is one the engine can run.
 *
 * Only a save that could change the answer is checked: an insert, or an edit of the calculation,
 * the target, the source attribute, the order, the row limit or the delimiters (ADR-0136).
 * Switching a rollup on or off or changing its mode never trips over an older definition.
 *
 * It also refuses a Bypass Permission that names no custom permission in the org (R-R4a,
 * ADR-0136), on an insert and when the value changes, with one query for the whole save: a
 * mistyped name would otherwise bypass nobody and say nothing.
 */
@NamespaceAccessible
public with sharing class RollupDefinitionValidationHandler extends TriggerHandler {
    @NamespaceAccessible
    public RollupDefinitionValidationHandler() {
        return;
    }

    public override void beforeInsert() {
        validate((List<Rollup_Definition__c>) newRecords(), null);
    }

    public override void beforeUpdate() {
        validate((List<Rollup_Definition__c>) newRecords(), oldRecordsById());
    }

    private void validate(List<Rollup_Definition__c> records, Map<Id, SObject> previousById) {
        for (
            Rollup_Definition__c record : records == null
                ? new List<Rollup_Definition__c>()
                : records
        ) {
            if (previousById != null && !calculationChanged(record, previousById.get(record.Id))) {
                continue;
            }
            String problem = RollupPlanner.saveProblem(record);
            if (problem != null) {
                record.addError(problem);
            }
        }
        validateBypassPermissions(records, previousById);
    }

    /** R-R4a: each Bypass Permission set or changed in this save names a custom permission. */
    private static void validateBypassPermissions(
        List<Rollup_Definition__c> records,
        Map<Id, SObject> previousById
    ) {
        List<Rollup_Definition__c> checked = new List<Rollup_Definition__c>();
        Set<String> developerNames = new Set<String>();
        for (
            Rollup_Definition__c record : records == null
                ? new List<Rollup_Definition__c>()
                : records
        ) {
            String name = record.Bypass_Permission__c;
            SObject previous = previousById == null ? null : previousById.get(record.Id);
            if (
                String.isBlank(name) ||
                (previous != null &&
                name == (String) previous.get(Rollup_Definition__c.Bypass_Permission__c))
            ) {
                continue;
            }
            checked.add(record);
            developerNames.add(developerName(name));
        }
        if (checked.isEmpty()) {
            return;
        }
        Set<String> existing = RollupSelector.customPermissionNames(developerNames);
        for (Rollup_Definition__c record : checked) {
            String name = record.Bypass_Permission__c.trim();
            if (!existing.contains(name.toLowerCase())) {
                record.addError(
                    Rollup_Definition__c.Bypass_Permission__c,
                    String.format(
                        System.Label.Core_Rollups_ErrorUnknownBypassPermission,
                        new List<String>{ name }
                    )
                );
            }
        }
    }

    /** The Developer Name in a value written `Name` or `prefix__Name`. */
    private static String developerName(String value) {
        String name = value.trim();
        return name.contains('__') ? name.substringAfterLast('__') : name;
    }

    private static Boolean calculationChanged(Rollup_Definition__c record, SObject previous) {
        if (previous == null) {
            return true;
        }
        for (
            Schema.SObjectField field : new List<Schema.SObjectField>{
                Rollup_Definition__c.Aggregate__c,
                Rollup_Definition__c.Target_Object__c,
                Rollup_Definition__c.Target_Field__c,
                Rollup_Definition__c.Source_Field__c,
                Rollup_Definition__c.Order_By_Field__c,
                Rollup_Definition__c.Row_Limit__c,
                Rollup_Definition__c.Delimiter__c,
                Rollup_Definition__c.Custom_Delimiter__c
            }
        ) {
            if (record.get(field) != previous.get(field)) {
                return true;
            }
        }
        return false;
    }
}
