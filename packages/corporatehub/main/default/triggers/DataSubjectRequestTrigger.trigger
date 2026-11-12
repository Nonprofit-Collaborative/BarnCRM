/**
 * One trigger for Data_Subject_Request__c. It does nothing itself: the Core dispatcher reads the
 * automation registry and runs the handlers registered for this object, in order, each of them
 * bypassable from the settings console unless its row always runs (ADR-0017, ADR-0024).
 */
trigger DataSubjectRequestTrigger on Data_Subject_Request__c(before insert, before update) {
	TriggerDispatcher.run('Data_Subject_Request__c');
}
