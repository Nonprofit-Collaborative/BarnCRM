/**
 * Queues the records of a full rollup recalculation chunk the platform stopped (R-R14).
 *
 * Not routed through `TriggerDispatcher`, like `ErrorLogEventTrigger`: `RollupRecalcErrorHandler`
 * explains why.
 */
trigger RollupRecalcErrorTrigger on BatchApexErrorEvent(after insert) {
    RollupRecalcErrorHandler.handle(Trigger.new);
}
