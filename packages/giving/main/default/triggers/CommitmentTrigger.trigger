/**
 * The one trigger on Commitment__c. Every handler is registered in
 * Automation_Registry__mdt and run by the Core dispatcher, so nothing is added here
 * (ADR-0017, plan Section 7.2).
 */
trigger CommitmentTrigger on Commitment__c(
	before insert,
	before update,
	before delete,
	after insert,
	after update,
	after delete,
	after undelete
) {
	TriggerDispatcher.run('Commitment__c');
}
