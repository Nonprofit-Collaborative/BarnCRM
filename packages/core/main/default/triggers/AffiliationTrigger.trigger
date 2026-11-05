/**
 * The one trigger on Affiliation__c. It routes every context through the dispatcher, which
 * reads the automation registry, honours the bypass and the global pause, and logs what
 * fails (plan Section 7.2, ADR-0017). No logic lives here.
 */
trigger AffiliationTrigger on Affiliation__c(
	before insert,
	before update,
	after insert,
	after update,
	after delete,
	after undelete
) {
	TriggerDispatcher.run('Affiliation__c');
}
