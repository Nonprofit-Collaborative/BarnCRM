# ADR-0157: The Gift Transaction mirror copies gifts one way, in runs, with designations from each fund's link

**Status:** Accepted (builder decision)
**Date:** 2026-11-02
**Source:** plan Section 4.12 (Gift Transaction mirror), Section 4.5, Section 5.6 X-07, Section
6.0a release 0.17; builds on ADR-0058 (the Opportunity mirror)

## Context

Plan Section 4.12 asks for a one-way copy of gifts to Nonprofit Cloud's `GiftTransaction` "plus
designation", so native donor summaries and Agentforce actions still see gifts, in dynamic Apex
only and hidden where the objects are absent. Section 4.5 has it off by default in Agentforce
Nonprofit coexistence. It shares most of its design with the Opportunity mirror (ADR-0058,
canonical model Section 29C), and a design for it was written on the salvage branch
`claude/openimpact-barncrm-status-ft0c1x` (2026-09-27) as an amendment of ADR-0058, before the
Connect to Mirror rename. That amendment never landed. This record takes it over, with two
changes, so ADR-0058 stays as it was. Canonical model Section 29C1 holds the rules (R-GT1 to
R-GT10).

Seven constraints differ from the Opportunity mirror's.

1. **Every Nonprofit Cloud object is optional and license gated.** `GiftTransaction` appears in
   the describe only with the Fundraising Access license and, per user, the Fundraising User
   permission (`docs/architecture/reference/nonprofit-cloud-data-model.md` Section 2). The CI
   gate `check-standard-objects.sh` refuses the name outside Mirror, and in Mirror's metadata.
2. **The field list is corroborated, not verified.** The reference has the field API names from
   two channels but marks their types as inferred, and verifies no Status value, no required flag
   and no `referenceTo`. The test org the build uses (`barn-sales`) has no Nonprofit Cloud.
3. **What the mirror is for is calculated in batch.** Donor Gift Summary and the Gift Designation
   totals are Data Processing Engine outputs, produced by a schedule the administrator builds
   (reference Section 8, items 1 and 2), and must never be written by us.
4. **Refunds are modelled differently.** BarnCRM records a refund as a negative gift (R-G3);
   Nonprofit Cloud records it on the transaction, so a negative Gift Transaction would count as
   one more gift (reference Section 8 item 5).
5. **The first customers migrate from Nonprofit Cloud in the same org.** The Nonprofit Cloud
   import templates (C-14) load Gift Transactions as gifts; every such gift already has its Gift
   Transaction.
6. **Designations need a mapping the model does not have.** `GiftTransactionDesignation` names a
   `GiftDesignation`, and nothing in BarnCRM says which designation a fund is.
7. **The reverse direction is an open owner question.** Gift Transactions to Gifts (O-7, plan
   Section 11.2 item 32) is deferred with the other integration decisions (D-125).

## Decision

1. **The link is its own attribute on Gift.** `Gift__c.Gift_Transaction_Id__c`, Text(18),
   unique, external ID, case sensitive, shipped by Mirror, for the reasons of ADR-0058 decision
   1. It is separate from `Opportunity_Id__c`: an org running NPSP alongside Nonprofit Cloud
   during a move could mirror a gift to both, and one field holding either would make a gift's
   link mean two things.
2. **One way, off until chosen, independent of the Opportunity mirror.**
   `Mirror_Settings__c.Gift_Transaction_Mirror_Direction__c`, `Off` or `GiftsToGiftTransactions`,
   empty read as Off, shown in the Giving section of BarnCRM Settings. It is a list rather than a
   checkbox so the reverse direction can be added if O-7 is approved, without a model change. The
   salvage design's Gift Transactions to Gifts direction is not built (constraint 7).
3. **Runs only; saving a gift copies nothing.** Run Now and a nightly run at 01:35, in the shape
   of ADR-0058 decision 5 and ADR-0038, in the runner's user mode, respecting the pause and the
   `Gift_Transaction_Mirror` switch as ADR-0058 decision 6a says. A copy on save is not chosen:
   what it is for is calculated in Nonprofit Cloud's own scheduled runs (constraint 3), so it would
   be seen no sooner; a saver without the Fundraising User permission (constraint 1) could not
   make it; and it would put Nonprofit Cloud's fundraising automation inside every gift save. The
   `Gift_Transaction_Mirror` automation on Gift only checks a typed or changed link and, after a
   delete, reports the Gift Transactions left behind.
4. **The mirror checks the shape it relies on, and the paid status is a setting** (constraint 2).
   The mirror is available only when the running person's describe has `GiftTransaction` with
   `DonorId` a reference to Account, `TransactionDate` a date, `OriginalAmount` an amount and
   `Status` a picklist; otherwise the page says it is unavailable and nothing queries the object.
   `CurrentAmount` and `Name` are optional. The Status value that means paid is
   `Gift_Transaction_Mirror_Status__c`, shipped as `Paid` so the setting is never blank, and
   checked against the org's active Status values before a run does anything: a wrong value would
   fail every insert or create transactions Nonprofit Cloud does not count as paid.
5. **A start date, required, with no default** (constraint 5). Gifts dated before
   `Gift_Transaction_Mirror_Start__c` are not copied, so the gifts imported from Nonprofit Cloud
   are not copied back as a second transaction each. Until it is set the mirror moves nothing. A
   default (install day, say) is not shipped: it would be wrong for exactly the org that loaded
   its history the week after installing.
6. **Which gifts, and what is copied** (constraint 4). Received gifts above zero that are not
   in-kind. A refund or write-off is never copied, and an original later refunded keeps its Gift
   Transaction unchanged, listed by the reconciliation. The copy writes Donor (the Donor Account,
   else the Household), Transaction Date and Original Amount, and on creation only Current
   Amount, Status and Name. A later run updates the first three and never Status or Current
   Amount, which Nonprofit Cloud maintains.
7. **Designations come from an explicit link on the fund** (constraint 6). Mirror adds
   `Fund__c.Gift_Designation_Id__c`, Text(18), not unique, typed by the administrator. When a
   run creates a Gift Transaction that has no designation yet, it writes one
   `GiftTransactionDesignation` per allocation whose fund names a `GiftDesignation`, with the
   allocation's amount. Designations are written at creation only and never changed afterwards:
   once the transaction exists Nonprofit Cloud and its users own its designations, and rewriting
   them would undo their edits. An allocation without a linked fund is counted in the run summary,
   not warned about, since an org may designate only some funds. Where the designation objects are
   absent or the runner cannot create them, gifts are copied without designations.
8. **Everything else follows the Opportunity mirror.** Refusals are grouped by message through
   `MirrorSync.Warnings`; a Gift Transaction made for a gift whose link could not be stored is
   deleted in the same run; nothing the org had is deleted; a linked record that cannot be found
   is "deleted or not visible to you"; a typed link is checked and stored in its 18 character
   form; each chunk checks the headroom ADR-0058 decision 3 sets; the last completed run is
   recorded through `MirrorSettingsWriter`, a stale nightly run is a Health Check finding in
   `MirrorHealthCheckExtension`, and the nightly run joins `MirrorNightlyJobProvider` (ADR-0075);
   the reconciliation is a page with the caps of ADR-0058 decision 9, gated by the custom
   permission `Use_Gift_Transaction_Mirror` on the `Gift_Transaction_Mirror` permission set,
   which is offered on the Access page through an `Access_Add_On__mdt` row.
9. **The Nonprofit Cloud names live in one class, and tests point it at stand-ins.**
   `GiftTransactionMirrorSchema` holds every object and field name. A test seam replaces them
   with Gift, Gift Allocation and Fund, which have the same shape (an Account reference, a date,
   an amount and a picklist; a master reference, a lookup and an amount; a name), so the copy,
   the designations and the reconciliation run their real dynamic queries and DML in an org
   without Nonprofit Cloud. The absent path is tested by hiding the object.

## Alternatives considered

- **Amend ADR-0058, as the salvage branch did.** Not chosen: ADR-0058 is settled and landed, and
  this design changes the salvage amendment in two ways (one direction, designations), so a
  record of its own is clearer.
- **Build Gift Transactions to Gifts from the salvage code.** Not chosen: O-7 is open and
  deferred (D-125). The salvage code is kept in that branch's history for when it is decided.
- **Copy on save, as Gifts to Opportunities does.** Rejected for the reasons in decision 3.
- **Mirror designations by fund name.** Rejected: a name is not a key, and a renamed fund would
  move money between designations.
- **Rewrite designations on every run.** Rejected: it would undo changes made in Nonprofit
  Cloud, and the donor summaries that justify X-07 read the transaction, not its designations.
- **A fake store interface for tests instead of stand-in objects.** Not chosen: it would leave
  the real dynamic queries and DML untested in every org without Nonprofit Cloud, which is every
  test org but `barn-npc`.

## Consequences

- Mirror ships a second link attribute on Gift, one attribute on Fund, five Mirror Settings
  keys, a registry row, a scheduled job, a page, a permission set, a custom permission, an access
  add-on row and two list views. Core gains only names in its settings layout and the module's
  admin tab list.
- Until the start date is set, choosing the direction does nothing but make the page say what is
  missing.
- Nonprofit Cloud's summaries lag BarnCRM by up to a day plus however often its own Data
  Processing Engine runs are scheduled.
- A refunded gift still counts at its full amount in Nonprofit Cloud until the refund is recorded
  there. The reconciliation lists every such gift.
- The design is written against the reference file. Running the tests and the admin guide's
  walkthrough on `barn-npc`, and correcting the reference from a describe there, is the
  integrator's step before a customer turns it on.
