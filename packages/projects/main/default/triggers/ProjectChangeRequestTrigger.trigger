/**
 * The one trigger on Project_Change_Request__c: routes the saves through the Core dispatcher,
 * which runs the handlers in the automation registry (ADR-0017, ADR-0024). New change requests
 * need Track change requests on (`ProjectChangeRequestHandler`, PM-12).
 */
trigger ProjectChangeRequestTrigger on Project_Change_Request__c(before insert) {
	TriggerDispatcher.run('Project_Change_Request__c');
}
