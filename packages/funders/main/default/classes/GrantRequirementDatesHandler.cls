/**
 * R-GQ2 for Grant_Requirement__c, run by the Core trigger dispatcher through the registry row
 * `Grant_Requirement_Dates`, switchable from the Automation page (ADR-0017): it fills in an empty
 * Submitted Date when a requirement becomes Submitted or Accepted. It does work for the user
 * rather than enforcing a rule, so an import of history can turn it off.
 */
@NamespaceAccessible
public with sharing class GrantRequirementDatesHandler extends TriggerHandler {
    @NamespaceAccessible
    public GrantRequirementDatesHandler() {
        return;
    }

    public override String getName() {
        return 'GrantRequirementDatesHandler';
    }

    public override void beforeInsert() {
        GrantRequirementService.fillSubmittedDates((List<Grant_Requirement__c>) newRecords(), null);
    }

    public override void beforeUpdate() {
        GrantRequirementService.fillSubmittedDates(
            (List<Grant_Requirement__c>) newRecords(),
            (Map<Id, Grant_Requirement__c>) oldRecordsById()
        );
    }
}
