/**
 * Maintenance of the primary affiliation, registered as "Keep one primary affiliation per
 * person" in the automation registry at execution order 30, so it runs after the validation
 * handler has settled the record and refused anything that should not be saved.
 *
 * After every context that can change who is primary, including delete and undelete, it settles
 * the primary affiliation of every person involved. It touches no before context: everything a
 * record needs done to itself is done by AffiliationValidationHandler.
 *
 * The service stands this automation down by name, together with the validation one, while it
 * clears the primary flag from a person's other affiliations, so nothing here runs against the
 * package's own writes.
 *
 * Switching this one off leaves the Primary Affiliation field on a person unattended, and lets
 * two affiliations both claim to be primary. It does not switch off any rule: the checks live in
 * their own registry row.
 *
 * Every context method takes no arguments and reads the trigger collections through the
 * accessors on TriggerHandler, which is the contract every packaged handler is written to.
 */
public with sharing class AffiliationMaintenanceHandler extends TriggerHandler {
    public override void afterInsert() {
        refresh(
            (List<Affiliation__c>) newRecords(),
            null,
            'AffiliationMaintenanceHandler.afterInsert'
        );
    }

    public override void afterUpdate() {
        refresh(
            (List<Affiliation__c>) newRecords(),
            (List<Affiliation__c>) oldRecords(),
            'AffiliationMaintenanceHandler.afterUpdate'
        );
    }

    public override void afterDelete() {
        refresh(
            null,
            (List<Affiliation__c>) oldRecords(),
            'AffiliationMaintenanceHandler.afterDelete'
        );
    }

    public override void afterUndelete() {
        refresh(
            (List<Affiliation__c>) newRecords(),
            null,
            'AffiliationMaintenanceHandler.afterUndelete'
        );
    }

    private void refresh(
        List<Affiliation__c> records,
        List<Affiliation__c> previous,
        String context
    ) {
        Boolean nothingToDo =
            (records == null || records.isEmpty()) && (previous == null || previous.isEmpty());
        if (nothingToDo) {
            return;
        }
        try {
            AffiliationService.refreshPrimaries(records, previous);
        } catch (Exception thrown) {
            reportFailure(
                thrown,
                records == null || records.isEmpty() ? previous : records,
                context,
                Label.Core_Affiliation_PrimaryFailed
            );
        }
    }
}
