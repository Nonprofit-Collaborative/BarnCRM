/**
 * The one trigger on Time_Entry__c: routes the saves through the Core dispatcher, which runs the
 * handlers in the automation registry (ADR-0017, ADR-0024). Rate snapshot and Open status
 * (PM-06, PM-07), both off unless their setting is on.
 */
trigger TimeEntryTrigger on Time_Entry__c(before insert, before update) {
	TriggerDispatcher.run('Time_Entry__c');
}
