/**
 * The one trigger on Project_Invoice__c: routes the deletes through the Core dispatcher, which
 * runs the handlers in the automation registry (ADR-0017, ADR-0024). Only a Draft can be deleted
 * (PM-10).
 */
trigger ProjectInvoiceTrigger on Project_Invoice__c(before delete) {
	TriggerDispatcher.run('Project_Invoice__c');
}
