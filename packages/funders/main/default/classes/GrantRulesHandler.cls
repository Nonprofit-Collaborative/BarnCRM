/**
 * R-GN4 for Grant__c, run by the Core trigger dispatcher through the registry row `Grant_Rules`,
 * which always runs (ADR-0024): a grant's program is a record identifier of a program, stored in
 * its 18-character form.
 */
@NamespaceAccessible
public with sharing class GrantRulesHandler extends TriggerHandler {
    @NamespaceAccessible
    public GrantRulesHandler() {
        return;
    }

    public override String getName() {
        return 'GrantRulesHandler';
    }

    public override void beforeInsert() {
        GrantService.checkPrograms((List<Grant__c>) Trigger.new);
    }

    public override void beforeUpdate() {
        List<Grant__c> changed = new List<Grant__c>();
        Map<Id, Grant__c> oldById = (Map<Id, Grant__c>) Trigger.oldMap;
        for (Grant__c grant : (List<Grant__c>) Trigger.new) {
            if (grant.Program_Id__c != oldById.get(grant.Id).Program_Id__c) {
                changed.add(grant);
            }
        }
        GrantService.checkPrograms(changed);
    }
}
