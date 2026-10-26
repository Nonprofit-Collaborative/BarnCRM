/**
 * The one trigger on Stewardship_Plan__c. Every packaged automation for this object is registered
 * in Automation_Registry__mdt and run by the dispatcher, so nothing is ever added here (ADR-0017).
 */
trigger StewardshipPlanTrigger on Stewardship_Plan__c(
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    TriggerDispatcher.run('Stewardship_Plan__c');
}
