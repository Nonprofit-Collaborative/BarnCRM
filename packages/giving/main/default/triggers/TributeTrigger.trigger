/**
 * The one trigger on Tribute. Every packaged automation for this object is registered in
 * Automation_Registry__mdt and run by the dispatcher, so nothing is ever added here (ADR-0017).
 */
trigger TributeTrigger on Tribute__c(
	before insert,
	before update,
	before delete,
	after insert,
	after update,
	after delete,
	after undelete
) {
	TriggerDispatcher.run('Tribute__c');
}
