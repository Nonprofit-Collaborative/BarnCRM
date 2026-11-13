/**
 * The one trigger on Project_Request__c: routes the saves through the Core dispatcher, which runs
 * the handlers in the automation registry (ADR-0017, ADR-0024). Request rules (D-201).
 */
trigger ProjectRequestTrigger on Project_Request__c(
	before insert,
	before update,
	after insert,
	after update
) {
	TriggerDispatcher.run('Project_Request__c');
}
