/**
 * R-LM1 and R-LM2 for Logic_Model__c, run by the Core trigger dispatcher through the registry row
 * `Logic_Model_Scope`, which always runs: it enforces a rule rather than doing work for anyone, so
 * no switch, pause or bypass reaches it (ADR-0024). It sets the scope key on every save and
 * refuses a second model for the organization or for one program.
 */
@NamespaceAccessible
public with sharing class LogicModelScopeHandler extends TriggerHandler {
    @NamespaceAccessible
    public LogicModelScopeHandler() {
        return;
    }

    public override String getName() {
        return 'LogicModelScopeHandler';
    }

    public override void beforeInsert() {
        LogicModelScope.apply((List<Logic_Model__c>) Trigger.new, null);
    }

    public override void beforeUpdate() {
        LogicModelScope.apply(
            (List<Logic_Model__c>) Trigger.new,
            (Map<Id, Logic_Model__c>) Trigger.oldMap
        );
    }
}
