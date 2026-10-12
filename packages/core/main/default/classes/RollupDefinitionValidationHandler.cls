/**
 * Refuses a rollup whose target attribute cannot hold its calculation (canonical model R-R10 and
 * R-R15): Any or None into anything but a checkbox, a text list into anything but text, a sum into
 * text, and so on, each with a message that says which kind of field to choose. The check is
 * `RollupPlanner.saveProblem`, the same rule the planner applies at run time, so a definition the
 * page lets through is one the engine can run.
 *
 * Only a save that could change the answer is checked: an insert, or an edit of the calculation,
 * the target or the source attribute. Switching a rollup on or off or changing its mode never
 * trips over an older definition.
 */
public with sharing class RollupDefinitionValidationHandler extends TriggerHandler {
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
                Rollup_Definition__c.Source_Field__c
            }
        ) {
            if (record.get(field) != previous.get(field)) {
                return true;
            }
        }
        return false;
    }
}
