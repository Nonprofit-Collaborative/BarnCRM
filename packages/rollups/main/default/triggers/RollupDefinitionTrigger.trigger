/**
 * The one trigger on Rollup_Definition__c. It routes every context through the dispatcher, which
 * reads the automation registry, honours the bypass and the global pause, and logs what fails
 * (plan Section 7.2, ADR-0017). No logic lives here, with one exception: any save or delete of a
 * definition clears the engine's per-transaction cache of definitions (`RollupSelector`), here
 * and not in a handler, because a handler can be switched off, bypassed or paused, and a stale
 * definition would then be calculated for the rest of the transaction.
 */
trigger RollupDefinitionTrigger on Rollup_Definition__c(
    before insert,
    before update,
    before delete
) {
    RollupSelector.clearCache();
    TriggerDispatcher.run('Rollup_Definition__c');
}
