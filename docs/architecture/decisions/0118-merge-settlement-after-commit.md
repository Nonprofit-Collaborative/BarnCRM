# ADR-0118: A merge that cannot queue its tidy-up asks for it after commit

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
per event, in a transaction that is not the merge's. A packaged `PlatformEventSubscriberConfig`
(`MergeSettlementReadyTriggerConfig`, no running user named) sets its batch size to 50, so one
delivery fits the 50 jobs a transaction may queue. As a guard, should the jobs still run out,
it sets a resume checkpoint after each event it queued and stops; the platform sends the events
after the checkpoint in a new call. That is the documented use of `setResumeCheckpoint` to cap
a batch: a normal exit resumes from the checkpoint, not only an uncaught exception, and
`MergeSettlementTest` proves on `oi-test` that later deliveries carry the rest. If not even the
first event could be queued there is no checkpoint, so it throws `EventBus.RetryableException`
(nothing was queued, so nothing is undone); on the last retry the platform allows, it names the
survivors in the Error Log instead.

The Warning stays for two cases: the platform refusing the publish, with the platform's
message, and that last retry. Both name the survivors.

The event carries identifiers, unlike `Rollup_Queue_Ready__e`. ADR-0100 kept identifiers off
that event because the Rollup Queue already stores them durably. Survivors have no such store,
and the settlement needs to know them, so the event is the record.

What each piece prevents:

- The event: survivors of a background merge left unsettled until someone notices.
- Publish After Commit: a settlement of a merge that rolled back, or one that reads the
  records before the merge's changes are visible.
- The 200 identifier chunk: a field too small for a bulk merge (200 identifiers of 18
  characters and a separator fit 32,768 characters with room to spare).
- The batch size of 50: a delivery holding more events than the subscriber may queue jobs for
  (the default batch is 2,000).
- The checkpoint and the retry: events lost if the jobs run out anyway.

## Alternatives considered

- **Leave the Warning.** Every background merge needs hand correction. Rejected: the point of
  PEOPLE-15 is that nobody has to.
- **Take the running Queueable's chained job.** Breaks the caller's own chain with "Too many
  queueable jobs", as the sample data load showed for rollups (ADR-0100).
- **Attach a finalizer to the running Queueable.** A job may have only one finalizer; taking it
  breaks a caller that attaches its own.
- **A scheduled job a minute later.** Uses one of the org's 100 scheduled job slots per merge
  transaction and still lags.
- **Settle in the subscriber directly.** Even 50 events can name 10,000 survivors per list,
  more than one transaction can settle; one queued job per event keeps each settlement within
  its limits.
- **Name a running user in the subscriber config.** A username is org-specific and cannot ship
  in a package; the Automated Process user already settles correctly.

## Consequences

- One or more platform events per background merge transaction, counted against the daily
  publish allocation ADR-0100 accepted.
- The subscriber runs as the Automated Process user, and the job it queues runs as that user,
  not as whoever ran the merge. Its user mode reads and writes succeed for that user:
  `MergeSettlementTest` on `oi-test` checks that the job was created by the Automated Process
  user, completed, and settled the survivor's addresses, relationships, household count, name
  and primary affiliation. Records it changes show the Automated Process user as Last Modified
  By.
- `PlatformEventSubscriberConfig` is listed among the components available in
  second-generation managed packages; the package developer owns its batch size, and a
  subscriber may set only its user.
- The three packaged permission sets grant Read and Create on the event, as on
  `Rollup_Queue_Ready__e` (the org refuses Create on a platform event without Read).
