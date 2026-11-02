/**
 * One trigger for Goal_Step__c. It does nothing itself: the Core dispatcher reads the automation
 * registry and runs the handlers registered for this object, in order, each of them bypassable
 * from the settings console unless its row always runs (ADR-0017, ADR-0024).
 */
trigger GoalStepTrigger on Goal_Step__c(before insert, before update) {
    TriggerDispatcher.run('Goal_Step__c');
}
