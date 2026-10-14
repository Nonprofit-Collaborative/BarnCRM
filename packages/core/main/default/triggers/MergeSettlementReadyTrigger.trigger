/**
 * Queues the tidy-up of merge survivors whose merge could not queue it itself (PEOPLE-15,
 * ADR-NEXT): a merge inside a Queueable job, or in a transaction with no queueable job left.
 * The event is delivered after that merge commits, so the job reads what the merge saved.
 *
 * Not routed through `TriggerDispatcher`: there is no record to act on, and the tidy-up is
 * the merge's own bookkeeping, not an automation an administrator switches off.
 */
trigger MergeSettlementReadyTrigger on Merge_Settlement_Ready__e(after insert) {
    MergeSettlement.settlePublished(Trigger.new);
}
