/** The one trigger on Legal_Entity__c; routes every context through the dispatcher (ADR-0017). */
trigger LegalEntityTrigger on Legal_Entity__c(after insert, after update, after undelete) {
	TriggerDispatcher.run('Legal_Entity__c');
}
