/**
 * The one trigger on Installment__c. Handlers come from Automation_Registry__mdt through
 * the Core dispatcher (ADR-0017, plan Section 7.2).
 */
trigger InstallmentTrigger on Installment__c(
	before insert,
	before update,
	before delete,
	after insert,
	after update,
	after delete,
	after undelete
) {
	TriggerDispatcher.run('Installment__c');
}
