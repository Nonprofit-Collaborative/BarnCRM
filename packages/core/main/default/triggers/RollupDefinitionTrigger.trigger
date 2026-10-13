/**
 * The one trigger on Rollup_Definition__c. It routes every context through the dispatcher, which
 * reads the automation registry, honours the bypass and the global pause, and logs what fails
 * (plan Section 7.2, ADR-0017). No logic lives here.
 */
trigger RollupDefinitionTrigger on Rollup_Definition__c(before insert, before update) {
    TriggerDispatcher.run('Rollup_Definition__c');
}
