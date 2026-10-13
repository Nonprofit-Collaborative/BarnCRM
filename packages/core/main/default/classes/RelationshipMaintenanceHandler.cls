/**
 * Maintenance of the other side of a relationship, registered as "Keep both sides of a
 * relationship in step" in the automation registry at execution order 30, so it runs after the
 * validation handler has settled the record and refused anything that should not be saved.
 *
 * After insert and after undelete it gives the relationship its other side. After update it
 * keeps that other side equal to this one. After delete it takes the other side with it. It
 * touches no before context: everything a record needs done to itself is done by
 * RelationshipValidationHandler.
 *
 * The service stands this automation down by name, together with the validation one, while it
 * writes the other side, so nothing here runs against the package's own writes. That is the
 * whole recursion story: there is no flag to reason about and no depth counter, because the
 * write never reaches the trigger.
 *
 * Switching this one off leaves relationships one sided. It does not switch off any rule: the
 * checks live in their own registry row.
 *
 * Every context method takes no arguments and reads the trigger collections through the
 * accessors on TriggerHandler, which is the contract every packaged handler is written to.
 */
public with sharing class RelationshipMaintenanceHandler extends TriggerHandler {
    public override void afterInsert() {
        ensure((List<Relationship__c>) newRecords(), 'RelationshipMaintenanceHandler.afterInsert');
    }

    public override void afterUpdate() {
        List<Relationship__c> records = (List<Relationship__c>) newRecords();
        if (records == null || records.isEmpty()) {
            return;
        }
        try {
            RelationshipService.syncReciprocals(records, oldRecordsById());
        } catch (Exception thrown) {
            reportFailure(
                thrown,
                records,
                'RelationshipMaintenanceHandler.afterUpdate',
                Label.Core_Relationship_SyncFailed
            );
        }
    }

    public override void afterDelete() {
        List<Relationship__c> deleted = (List<Relationship__c>) oldRecords();
        if (deleted == null || deleted.isEmpty()) {
            return;
        }
        try {
            RelationshipService.deleteReciprocals(deleted);
        } catch (Exception thrown) {
            reportFailure(
                thrown,
                deleted,
                'RelationshipMaintenanceHandler.afterDelete',
                Label.Core_Relationship_SyncFailed
            );
        }
    }

    public override void afterUndelete() {
        List<Relationship__c> restored = (List<Relationship__c>) newRecords();
        if (restored == null || restored.isEmpty()) {
            return;
        }
        try {
            RelationshipService.restoreReciprocals(restored);
        } catch (Exception thrown) {
            report(thrown, restored, 'RelationshipMaintenanceHandler.afterUndelete');
        }
    }

    private void ensure(List<Relationship__c> records, String context) {
        if (records == null || records.isEmpty()) {
            return;
        }
        try {
            RelationshipService.ensureReciprocals(records);
        } catch (Exception thrown) {
            reportFailure(thrown, records, context, Label.Core_Relationship_SyncFailed);
        }
    }
}
