/** The one trigger on Brand__c; routes every context through the dispatcher (ADR-0017). */
trigger BrandTrigger on Brand__c(
	before insert,
	before update,
	after insert,
	after update,
	after delete,
	after undelete
) {
	TriggerDispatcher.run('Brand__c');
}
