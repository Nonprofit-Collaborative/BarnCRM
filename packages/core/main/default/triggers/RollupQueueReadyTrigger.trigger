/**
 * Starts the Rollup Queue processor when a save inside a Queueable job left entries waiting
 * (R-RQ3, ADR-NEXT). The event carries nothing: the entries are the record, and starting the
 * processor is safe to ask for twice, so one call covers however many events arrive together.
 *
 * Not routed through `TriggerDispatcher`: there is no record to act on, and the engine's switch
 * and the global pause are already checked where the processor starts.
 */
trigger RollupQueueReadyTrigger on Rollup_Queue_Ready__e(after insert) {
    RollupService.startQueuedRecalculation();
}
