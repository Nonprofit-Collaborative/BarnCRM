/**
 * One trigger for Fund__c. It does nothing itself: the Core dispatcher reads the automation
 * registry and runs the handlers registered for this object, in order, each of them
 * bypassable from the settings console (ADR-0017).
 */
trigger FundTrigger on Fund__c(
	before insert,
	before update,
	before delete,
	after insert,
	after update,
	after delete,
	after undelete
) {
	TriggerDispatcher.run('Fund__c');
}
