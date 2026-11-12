/**
 * One trigger for Data_Breach__c. It does nothing itself: the Core dispatcher reads the
 * automation registry and runs the handlers registered for this object, in order, each of them
 * bypassable from the settings console unless its row always runs (ADR-0017, ADR-0024).
 */
trigger DataBreachTrigger on Data_Breach__c(after insert) {
	TriggerDispatcher.run('Data_Breach__c');
}
