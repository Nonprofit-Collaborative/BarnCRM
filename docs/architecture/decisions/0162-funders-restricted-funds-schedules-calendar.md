# ADR-0162: Funders restricted funds, award schedules and the deadline calendar, with no Giving dependency

**Status:** Proposed (built as recommended for releases 0.16 and 0.17, F-03, F-05 and F-08; awaits
owner confirmation)
**Date:** 2026-11-02
**Source:** plan Section 5.5 (F-03, F-05, F-08), Section 6.0a releases 0.16 and 0.17, Section 9.9
(portability); amends ADR-0161 `0161-funders-module.md` decision 1; builds on ADR-0013, ADR-0014,
ADR-0017, ADR-0024 and ADR-0154.

## Context

ADR-0161 `0161-funders-module.md` built the grant and its requirements (F-01, F-02) and kept Giving
as a package dependency because F-03 (a fund ledger on Giving's `Fund__c`) and F-05 (award
schedules on Giving's `Commitment__c` and `Installment__c`, plan note "Reuses Commitment and
Installment") were expected to need it. The integrator ruled (2026-11-02) that Funders must not
hard-depend on Giving: Giving is linked the way a program is, by record identifier, or the ADR
says why not.

What the three features need:

- **F-03 Restricted fund tracking** (Major): money a funder limited to a purpose, recorded as
  received, released or spent entries with a balance. Plan note: "Simple ledger, not accounting."
- **F-05 Multi-year award schedules** (Minor): when each part of a multi-year award is expected and
  whether it came.
- **F-08 Deadline calendar view** (Minor): the deadlines the Grant Pipeline already lists, on a
  month calendar.

## Decision

1. **Funders depends on Core only; Giving and Rollup Builder are dropped.** Amends decision 1 of
   ADR-0161 `0161-funders-module.md`. Nothing in Funders references a Giving object or class; a
   Giving fund is named by record identifier (decision 4). Nothing in Funders uses a Rollup
   Builder definition, class or object either: every total is a platform roll-up summary
   (decision 3). `sfdx-project.json` lists Core only, and Core's catalog row
   `BarnCRM_Module.Funders` requires nothing, so an org can install Funders without Giving or
   Rollup Builder (pre-batch review, landing batch B). A Fundraising Staff holder still gets Funders Staff
   where Giving is installed: the role is matched by permission set name.
2. **The restricted ledger is the grant's own.** Restricted Fund Entry (`Grant_Fund_Entry__c`,
   canonical model 29ZL) is a detail of the grant: a type (Received, Spent or Released), a positive
   amount, a date and a description. Received is restricted money that came in; Spent is money
   spent on the purpose; Released is restriction the funder lifted, or that lapsed, without the
   money being spent on it. The grant gains **Restricted** (a checkbox, off by default) and four
   totals: Restricted Received, Restricted Spent and Restricted Released (roll-up summaries) and
   Restricted Balance (Received minus Spent minus Released, a formula). It is a ledger, not
   accounting: no accounts, periods or postings, and a balance below zero is shown, not refused,
   because a reimbursement grant is spent before the money arrives. Per grant rather than per
   Giving fund, because a restriction is the award's, it is reported to that funder per award,
   and Funders installs without Giving.
3. **Totals are platform roll-up summaries.** The entries are details of the grant, so the
   platform's own summaries are exact, immediate and need no Rollup Builder definition (the Logic
   Models precedent, `Indicator_Count__c`).
4. **The Giving fund is named by record identifier, never looked up.** `Fund_Id__c` holds a Giving
   fund's record identifier as text, exactly as `Program_Id__c` holds a program (ADR-0161
   `0161-funders-module.md` decision 6): the always-running `Grant_Rules` automation stores its
   18-character form and refuses text that is not a record identifier, or one of another object
   where an object named `Fund__c` exists. A **Giving Fund** card on the grant's page lists the
   active funds where Giving is installed, read by describe in user mode, and says so where it is
   not. The fund names where the organization books the money in Giving; Funders reads nothing
   from it but its name.
5. **An award schedule is Grant Payments, not Giving commitments.** Grant Payment
   (`Grant_Payment__c`, canonical model 29ZM) is a detail of the grant: due date, amount, status
   (Expected, Received or Cancelled) and received date. The grant gains Amount Scheduled (payments
   not Cancelled) and Amount Received (roll-up summaries). Giving's Commitment and Installment are
   not reused: they would make Funders depend on Giving (decision 1), and a commitment is a
   donor's promise that feeds donor rollups, pledge reminders to the donor and installment
   matching, none of which a funder's payment schedule should touch.
6. **A schedule is built in one step and edited as rows.** The **Award Schedule** card on the
   grant's page builds a schedule when the grant is awarded, has an amount awarded and award
   dates, and has no Expected or Received payment yet: the amount awarded split evenly at a chosen
   frequency (Once, Annual, Semiannual, Quarterly or Monthly), the first payment on the award start
   date, every later one a period apart while on or before the award end date, and the last one
   taking the cents left by rounding. The split is a framework-free JavaScript module
   (`grantScheduleModel`, plan 9.9) the card previews before saving; `GrantScheduleController`
   checks the rows again and inserts them in user mode, keeping the frequency in the grant's new
   **Payment Frequency** picklist. The card's headings and frequency choices are field labels read
   by describe, so it adds few custom labels (the org limit of 5,000 is close). **Mark Received** on an expected payment
   sets it Received; anything else is edited in the Payments related list.
7. **A received payment on a restricted grant writes its Received entry.** A switchable automation
   (registry row `Grant_Payment_Received`) fills an empty Received Date with today when a payment
   becomes Received, and keeps one Received entry per received payment of a restricted grant in
   step: added when the payment is received, changed with its amount or date, removed when the
   payment leaves Received or is deleted. Entries typed by hand, which name no payment, are never
   touched. Switchable so an import of past payments and entries can turn it off.
8. **The calendar shows the pipeline's deadlines.** A **Grant Calendar** tab draws a month at a
   time: application deadlines of open grants before submitting, due dates of open requirements,
   and expected payments, for Everyone or Mine. `GrantDeadlineSelector` reads the rows for both
   the Grant Pipeline's Upcoming Deadlines and the calendar, so the two cannot disagree; the
   browser module `grantCalendarModel` lays the rows (through `grantPipelineModel.deadlineRows`)
   into weeks. Expected payments appear on the calendar only: the pipeline's list is for work
   staff must do.
9. **Access follows the requirements.** Funders Admin manages payments and entries; Funders Staff
   creates, edits and deletes them, as for requirements; Funders Read Only reads them. Every set
   sees the Grant Calendar tab. The new controllers are `GrantFundController`,
   `GrantScheduleController` and `GrantCalendarController`.

## Alternatives Considered

- **Keep the Giving dependency and put the ledger on `Fund__c`.** Rejected by the integrator
  (decision 1), and a fund pools many donors' gifts, so a grant's balance could not be told apart.
- **Payments as Giving installments.** Rejected (decision 5).
- **A Gift identifier on each payment.** Deferred: nothing in Funders reads it yet; a later
  release can add it the same way as the fund.
- **Rollup Builder definitions for the totals.** Rejected: summaries on a master-detail are exact
  and need no setup (decision 3).
- **Refusing a negative balance.** Rejected (decision 2).
- **Payments on the pipeline's Upcoming Deadlines.** Rejected: they are the funder's to make, not
  staff work (decision 8).

## Consequences

- Two more custom objects for a Funders user (Lightning Platform Starter object count, ADR-0121),
  and five summary fields on Grant (the platform allows 25 per object).
- An org with Funders and no Giving has no Giving Fund card choices and loses nothing else.
- Turning `Grant_Payment_Received` off leaves the ledger to staff; turning it on again does not
  go back over payments received meanwhile. Ticking **Restricted** on a grant whose payments were
  already received adds no entries for them either: staff add those by hand.
- The Programs and Giving links share one pattern; `GrantService` keeps the program code and
  `GrantFundService` the fund code, and both could later share one helper.
