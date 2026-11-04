/**
 * R-GN3 for Grant__c, run by the Core trigger dispatcher through the registry row `Grant_Dates`,
 * switchable from the Automation page (ADR-0017): it fills in an empty Submitted Date when a grant
 * reaches Applied and an empty Decision Date when it is decided. It does work for the user rather
 * than enforcing a rule, so an import of history can turn it off.
 */
@NamespaceAccessible
public with sharing class GrantDatesHandler extends TriggerHandler {
    @NamespaceAccessible
    public GrantDatesHandler() {
        return;
    }

    public override String getName() {
        return 'GrantDatesHandler';
    }

    public override void beforeInsert() {
        GrantService.fillStageDates((List<Grant__c>) newRecords(), null);
    }

    public override void beforeUpdate() {
        GrantService.fillStageDates(
            (List<Grant__c>) newRecords(),
            (Map<Id, Grant__c>) oldRecordsById()
        );
    }
}
