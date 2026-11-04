/**
 * R-GQ6 for Grant_Requirement__c, run by the Core trigger dispatcher through the registry row
 * `Grant_Requirement_Rules`, which always runs (ADR-0024): a requirement's Logic Model Outcome is
 * a record identifier of a logic model element, stored in its 18-character form.
 */
@NamespaceAccessible
public with sharing class GrantRequirementRulesHandler extends TriggerHandler {
    @NamespaceAccessible
    public GrantRequirementRulesHandler() {
        return;
    }

    public override String getName() {
        return 'GrantRequirementRulesHandler';
    }

    public override void beforeInsert() {
        GrantOutcomeService.checkOutcomes((List<Grant_Requirement__c>) newRecords());
    }

    public override void beforeUpdate() {
        List<Grant_Requirement__c> changed = new List<Grant_Requirement__c>();
        Map<Id, Grant_Requirement__c> oldById = (Map<Id, Grant_Requirement__c>) oldRecordsById();
        for (Grant_Requirement__c requirement : (List<Grant_Requirement__c>) newRecords()) {
            if (requirement.Outcome_Id__c != oldById.get(requirement.Id).Outcome_Id__c) {
                changed.add(requirement);
            }
        }
        GrantOutcomeService.checkOutcomes(changed);
    }
}
