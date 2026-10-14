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
    /**
     * Set by a test to make the upkeep fail, so the report a person sees can be exercised:
     * the upkeep runs in system mode (PEOPLE-26), so no user's access makes it fail.
     */
    @TestVisible
    private static Exception upkeepFailureForTest;

    public override void afterInsert() {
        refresh(
            (List<Affiliation__c>) newRecords(),
            null,
            'AffiliationMaintenanceHandler.afterInsert'
        );
    }

    /**
     * Only the rows whose change can move who is primary: the flag, the status or dates that
     * decide eligibility, or either end. A role or description edit settles nothing (PEOPLE-39).
     */
    public override void afterUpdate() {
        List<Affiliation__c> records = (List<Affiliation__c>) newRecords();
        if (records == null) {
            return;
        }
        List<Affiliation__c> changed = new List<Affiliation__c>();
        List<Affiliation__c> before = new List<Affiliation__c>();
        Map<Id, SObject> previousById = oldRecordsById();
        for (Affiliation__c record : records) {
            Affiliation__c previous = previousById == null
                ? null
                : (Affiliation__c) previousById.get(record.Id);
            if (previous == null || mayMovePrimary(record, previous)) {
                changed.add(record);
                if (previous != null) {
                    before.add(previous);
                }
            }
        }
        refresh(changed, before, 'AffiliationMaintenanceHandler.afterUpdate');
    }

    private static Boolean mayMovePrimary(Affiliation__c record, Affiliation__c previous) {
        return record.Is_Primary__c != previous.Is_Primary__c ||
            record.Status__c != previous.Status__c ||
            record.Start_Date__c != previous.Start_Date__c ||
            record.End_Date__c != previous.End_Date__c ||
            record.Contact__c != previous.Contact__c ||
            record.Person_Account__c != previous.Person_Account__c ||
            record.Organization__c != previous.Organization__c;
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
            if (upkeepFailureForTest != null) {
                throw upkeepFailureForTest;
            }
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
