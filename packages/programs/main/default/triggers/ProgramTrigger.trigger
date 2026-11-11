/**
 * One trigger for Program__c. It does nothing itself: the Core dispatcher reads the automation
 * registry and runs the handlers registered for this object, in order (ADR-0017, ADR-0024).
 */
trigger ProgramTrigger on Program__c(
	before insert,
	before update,
	before delete,
	after insert,
	after update,
	after delete,
	after undelete
) {
	TriggerDispatcher.run('Program__c');
}
