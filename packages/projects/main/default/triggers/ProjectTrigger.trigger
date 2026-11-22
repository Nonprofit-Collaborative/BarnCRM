/**
 * The one trigger on Project__c: routes the saves through the Core dispatcher, which runs the
 * handlers in the automation registry (ADR-0017, ADR-0024). Actual Cost (`ProjectCostHandler`).
 */
trigger ProjectTrigger on Project__c(before insert, before update) {
	TriggerDispatcher.run('Project__c');
}
