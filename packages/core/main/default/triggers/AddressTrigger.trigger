/**
 * The one trigger on Address__c. It routes every context through the dispatcher, which
 * reads the automation registry, honours the bypass and the global pause, and logs what
 * fails (plan Section 7.2, ADR-0017). No logic lives here.
 */
trigger AddressTrigger on Address__c(
	before insert,
	before update,
	before delete,
	after insert,
	after update,
	after delete,
	after undelete
) {
	TriggerDispatcher.run('Address__c');
}
