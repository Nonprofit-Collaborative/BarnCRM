# ADR-NEXT: A merge that cannot queue its tidy-up asks for it after commit

**Status:** Accepted (builder decision)
**Date:** 2026-10-14
**Source:** PEOPLE-15 merge settlement; Core v1.0 correctness review; extends the pattern of
ADR-0100 and ADR-0117

## Context

The platform's merge moves the merged record's children onto the survivor without running
their triggers, and refuses a trigger's write to the records being merged. So the account and
contact handlers name the survivors from `after delete`, and `MergeSettlement`, a Queueable
queued there, settles them just after the save: one membership per person, the household's
count, name and primary, one default address, no self relationships or second copies, and the
primary affiliation.

Two cases queued nothing. A merge inside a Queueable did not take the running job's one
chained job, which the job's own work may need (RollupQueue keeps it free for the same
reason). A merge in a transaction with no queueable job left could not queue one. Both only
wrote a Warning to the Error Log naming the survivors, and an administrator had to correct
each by hand. Merges from integrations and deduplication apps commonly run in background jobs,
so this was the normal path for them, not an edge.

## Decision

In those two cases the merge publishes `Merge_Settlement_Ready__e`, publish behavior Publish
After Commit, naming its survivors in three lists (households folded together, address owners,
people), up to 200 identifiers per list per event; more survivors make more events. The event
is delivered only if the merge commits, and after it does, so the settlement reads what the
merge saved. Its subscriber, `MergeSettlementReadyTrigger`, queues one `MergeSettlement` job
per event, in a transaction that is not the merge's, and sets a resume checkpoint after each,
so a delivery larger than its job allowance continues in a new call.

The Warning stays for one case: the platform refusing the publish. It names the survivors and
the platform's message.

The event carries identifiers, unlike `Rollup_Queue_Ready__e`. ADR-0100 kept identifiers off
that event because the Rollup Queue already stores them durably. Survivors have no such store,
and the settlement needs to know them, so the event is the record.

What each piece prevents:

- The event: survivors of a background merge left unsettled until someone notices.
- Publish After Commit: a settlement of a merge that rolled back, or one that reads the
  records before the merge's changes are visible.
- The 200 identifier chunk: a field too small for a bulk merge (200 identifiers of 18
  characters and a separator fit 32,768 characters with room to spare).
- One job per event with a checkpoint: a large delivery queuing more jobs than the
  subscriber's transaction may.

## Alternatives considered

- **Leave the Warning.** Every background merge needs hand correction. Rejected: the point of
  PEOPLE-15 is that nobody has to.
- **Take the running Queueable's chained job.** Breaks the caller's own chain with "Too many
  queueable jobs", as the sample data load showed for rollups (ADR-0100).
- **Attach a finalizer to the running Queueable.** A job may have only one finalizer; taking it
  breaks a caller that attaches its own.
- **A scheduled job a minute later.** Uses one of the org's 100 scheduled job slots per merge
  transaction and still lags.
- **Settle in the subscriber directly.** A delivery can hold up to 2,000 events, more than one
  transaction can settle; one queued job per event keeps each settlement within its limits.

## Consequences

- One or more platform events per background merge transaction, counted against the daily
  publish allocation ADR-0100 accepted.
- The subscriber runs as the Automated Process user, and the job it queues runs as that user,
  not as whoever ran the merge. Its user mode reads and writes succeed for that user:
  `MergeSettlementTest` on `oi-test` checks that the job was created by the Automated Process
  user, completed, and settled the survivor's addresses and relationships.
- The three packaged permission sets grant Read and Create on the event, as on
  `Rollup_Queue_Ready__e` (the org refuses Create on a platform event without Read).
