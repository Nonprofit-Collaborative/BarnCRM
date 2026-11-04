# ADR-NEXT: A handler failure refuses only its own records, and one Automation Control setting pauses or bypasses automation per org, profile or user

**Status:** Proposed (owner decisions, Brandon, 2026-11-04)
**Date:** 2026-11-04
**Source:** v1.0 architect review, runtime slice: RT-05 (one bad row fails the whole 200-row
chunk) and RT-13 (no per-user or per-integration automation bypass); owner decisions 2 and 4 of
2026-11-04. Amends ADR-0017 (decision 3, trigger dispatch) and ADR-0024 (what an always-run
automation is exempt from). Plan Section 7.2 (trigger framework), Section 4.8 (settings).

## Context

**Failures.** `TriggerDispatcher` logged a handler's exception and then, in a before context,
put the error on every record in `Trigger.new`; in an after context it rethrew, rolling the
chunk back. A Data Loader, Bulk API, NPSP data import or online giving integration load sends
200 records per chunk with a partial save (allOrNone false), and BarnCRM's own import saves the
same way. One record that tripped a handler (a value it could not use, a lookup it could not
follow) cost the other 199 their save, with the same message on all 200 and nothing saying which
record was at fault.

**Pausing for some people only.** The Automation page has one switch per automation (org-wide),
a timed pause of 1 to 24 hours (org-wide), and a code-only per-transaction bypass. An
integration user or a migration consultant who needs BarnCRM automation off for their loads
only, and not for staff saving records at the same time, had nothing. Admins' own flows,
triggers and validation rules had no shared signal to honour either, so every org built its
own bypass checkbox. Work skipped during a pause is not replayed.

## Decision

### 1. The dispatcher error contract

1. **Only the records a failure belongs to are refused; the rest of the save goes ahead,** in
   before and after contexts alike. Each refused record carries the existing friendly message
   (`Core_Automation_UnexpectedError`) through `addError`, so a partial save saves the others
   and an all-or-nothing save names only the failing rows.
2. **How the records are found.** With more than one record inside a trigger, the dispatcher
   takes a savepoint before the first handler. When a handler (or work deferred to the end of
   the run) throws, it rolls back to the savepoint, puts back the recursion guard's claims, and
   runs every handler again over each half of the records, keeping a half that succeeds and
   halving one that fails, until the failure is pinned on single records. A record a handler
   refused itself with its own message keeps that message and is not run again. One failing
   record in 200 costs about 16 extra runs over ever smaller halves.
3. **Handlers read their records only through the `TriggerHandler` accessors** (`newRecords()`,
   `newRecordsById()`, `oldRecords()`, `oldRecordsById()`), which the dispatcher points at the
   half being run. Reading `Trigger.new` and its companions directly is no longer allowed in a
   handler: every shipped handler was moved to the accessors in the same change. Running a
   handler again over records it already worked on is what the platform's partial-save retry
   already does, so the existing rule stands unchanged: handler work must be safe to repeat.
4. **Room is measured, never assumed.** The cost of the failed attempt (queries, DML
   statements, DML rows, CPU time) is measured; a narrowing attempt runs only when the same
   again, its savepoint and rollback, and a margin still fit. Otherwise the records not yet
   cleared are refused together: a limit exception would refuse everything and log nothing.
5. **Always-run rules keep their strictness.** A failure in an automation whose registry row
   carries `Always_Runs__c` (ADR-0024) is not narrowed: every record in front of it is
   refused, as before, because an integrity rule that could not be checked lets nothing
   through.
6. **Errors are still logged (R-E1).** The failure is logged once with its technical detail,
   as before, and each record refused while narrowing gets its own Warning entry naming its row
   in the save (and its record when it has an Id), in one write. The text is in Core's help JSON
   (`Core_Automation_RecordRefused`).
7. **Unchanged:** one record is refused without being run again; outside a trigger (a handler
   run directly from a test or a bulk operation) the dispatcher throws the friendly message as
   before; a single-record save takes no savepoint, so ordinary record pages cost nothing extra.
   A multi-record trigger run costs one DML statement for the savepoint.

### 2. The BarnCRM Automation Control setting

1. **One hierarchy custom setting, `BarnCRM_Automation_Control__c`, with `Pause_All__c` and
   `Bypass__c`** (checkboxes, both off by default), set at the org default, a profile or a user.
   The value that applies to a save is the running user's, as the platform resolves a hierarchy
   setting (user, then profile, then org default).
   - **Bypass** is for the people whose saves should skip automation while everyone else's
     run as normal: an integration user (or its profile), a migration consultant.
   - **Pause All** is the long pause: set at the org default it stops automation for everyone
     until it is turned off, for a migration window longer than the timed pause allows. Set at
     a profile or user it means the same as Bypass for BarnCRM's automation; the two are kept
     apart so an admin's own automation can tell "this user is an integration" from "everything
     is paused".
2. **Read by the dispatcher alongside, not instead of, the existing controls.** A handler that
   is not an always-run rule is skipped when the running user's Automation Control has Pause
   All or Bypass, in addition to the per-transaction bypass, the timed pause and the
   per-automation switch, which all stay. Read once per trigger run with `getInstance()`, which
   costs no query.
3. **Always-run rules still run** whatever the setting says (ADR-0024 extended to this setting).
4. **Every shipped flow template checks it first** (`packages/*/flows/Template_*` and
   `Recalculate_Rollups_Template`): a decision on `$Setup.BarnCRM_Automation_Control__c` ends
   the flow when either box applies to the running user.
5. **Documented for admins' own automation.** Flows, triggers and validation rules an org
   builds itself read the same setting (`$Setup.BarnCRM_Automation_Control__c.Pause_All__c` in
   a formula or validation rule, the same in a flow, `BarnCRM_Automation_Control__c.getInstance()`
   in Apex), so one place pauses or bypasses everything the org has.
6. **Managed in the BarnCRM Settings console** (plan Section 4.8): the Automation page shows
   whether Pause All is on for everyone, lists the profiles and users with Bypass or Pause All,
   and adds and removes them. The setting is public, not protected, because admins' own flows,
   formulas and validation rules must read it through `$Setup` once BarnCRM is a managed
   package; that is the deliberate exception to ADR-0017 decision 2's protected settings.
7. **Admins can list their own flows on the Automation page.** A listed flow gets a switch row
   (`Automation_Setting__c`, named `Flow:` plus the flow's API name, not a package default). The
   switch is honoured by the flow calling the invocable action **Check BarnCRM Automation**,
   which answers whether to run given the Automation Control setting, the timed pause and the
   switch; a flow that does not call it is listed for the record only. Listing a flow never
   activates, deactivates or edits it.
8. **Catching up.** BarnCRM keeps no record of the saves it skipped, so nothing is replayed per
   save. Resuming the timed pause (by hand or when it ends) queues the household catch-up (a
   household for every person added without one) and starts the waiting rollups, as resuming
   already did for rollups. The Automation page has a **Catch Up Now** action for after a long
   pause or a bypassed load: it queues the household catch-up, the household names recompute
   and the waiting rollups. Other skipped work (a preferred email, an address capture, a
   reciprocal relationship) is caught up by saving the records again; the admin guide says
   which.

## Alternatives considered

- **Refuse the whole chunk and document it** (the review's minimum). Rejected: the owner
  decided the rest of the chunk saves.
- **Handlers report their own per-record failures.** Rejected as the only route: it needs
  every handler and every service it calls to catch and attribute every exception, and an
  unexpected exception is exactly the one nobody attributed. Handlers that can already refuse
  a record with their own message keep doing so; narrowing covers everything else.
- **Retry each record on its own.** Rejected: 200 runs of a bulkified handler would exceed the
  query limit; halving costs about 2 log2(n) runs per failing record.
- **A custom permission "Bypass BarnCRM Automation"** (the review's suggestion). Rejected for
  the owner's hierarchy setting: a hierarchy setting reaches profiles and users without a
  permission set, is readable by `$Setup` in admins' own formulas, validation rules and flows,
  and carries the org-wide long pause in the same place.
- **Replace the timed pause and the switches with the setting.** Rejected by the owner: the
  timed pause ends by itself and the switches are per automation; the setting adds per-person
  control and the untimed pause beside them.
- **Replay skipped saves after a pause.** Rejected: it needs a journal of every skipped save,
  which is storage and code out of proportion; the catch-ups cover the work that matters
  (households, names, totals).

## Consequences

- ADR-0017 decision 3 reads: dispatch runs each handler through the bypass, the Automation
  Control setting, the pause, the switch and the error contract above. ADR-0024's always-run
  automations are exempt from the Automation Control setting too, and are not narrowed.
- A new handler reads its records through the accessors; code review (plan 9.4) checks it,
  and the dispatcher tests cover narrowing in before and after contexts with a real trigger.
- A failing multi-record save costs extra queries, DML and CPU while narrowing, bounded by the
  room check; a clean save costs one savepoint statement per multi-record trigger run.
- An org can leave Pause All on at the org default and forget it: the Automation page shows it
  in the same yellow box as the timed pause, with its own Turn Off.
- Canonical model: Section 10 gains the setting and rules R-A6 (error contract) and R-A7
  (Automation Control); Section 12 is unchanged (the setting is its own object).
- Built in order: the error contract, then the setting, the dispatcher read, the flow
  templates, the Check BarnCRM Automation action and the catch-up on resume; then, in their
  own change, managing the setting on the Automation page (2.6), listing an org's own flows
  there (2.7) and the **Catch Up Now** action (2.8) (canonical model R-A8). The setting is
  written in system mode by `AutomationSettingsWriter` after the Manage BarnCRM Settings check
  (ADR-0021), because a custom setting takes no field permissions a BarnCRM Admin could hold.
