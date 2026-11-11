/** The one trigger on Brand_Assignment__c; routes every context through the dispatcher (ADR-0017). */
trigger BrandAssignmentTrigger on Brand_Assignment__c(
	before insert,
	before update,
	after insert,
	after update,
	after delete,
	after undelete
) {
	TriggerDispatcher.run('Brand_Assignment__c');
}
