/**
 * The one trigger on Project_Expense__c: routes the saves through the Core dispatcher, which runs
 * the handlers in the automation registry (ADR-0017, ADR-0024). Open status with approvals on
 * (PM-07, PM-08).
 */
trigger ProjectExpenseTrigger on Project_Expense__c(before insert, before update) {
	TriggerDispatcher.run('Project_Expense__c');
}
