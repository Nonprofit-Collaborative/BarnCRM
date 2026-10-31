# ADR-0153: The Solicitation Pipeline Is a Giving Ask Object, Not Opportunity

**Status:** Accepted (D-156 approved G-26 for release 0.13)
**Date:** 2026-10-31
**Source:** plan Section 6.0a (release 0.13, G-26) and Section 6.1.5 (competitive research,
D-156); ADR-0013 (Core runs on a Platform-only org, standard objects only in Mirror); canonical
model Section 25R, rules R-SO1 to R-SO8

## Context

Every donor tool a small development team compares BarnCRM with (Little Green Light, DonorPerfect,
NPSP, Nonprofit Cloud) tracks asks: who is being asked, for how much, by when, and where it stands.
NPSP and Nonprofit Cloud use the standard Opportunity object for it. BarnCRM cannot: Giving must
run on a Salesforce Platform license, which has no Opportunity, and only the Mirror package may
reference it (ADR-0013). The competitive research (plan 6.1.5) ranked this the largest fundraising
gap.

Questions to settle: what the record is, how an organization sets its own stages, how a closed ask
is told apart from an open one, where stage history lives, what a win does, and what the planned
ask cadence (G-29) needs from it.

## Decision

1. **One new Giving object, `Ask__c` (label Ask).** Donor (the Contact and Account pair of
   canonical model Section 4), Stage, Outcome, Ask Amount, Target Date, owner as Assigned To, Next
   Step, Next Ask Date, Fund, Appeal, Resulting Gift, Resulting Commitment, Stage Changed Date and
   Closed Date. Nothing is added to Gift or Commitment: the link runs from the ask to its result,
   so the hot gift objects, their triggers and their imports are untouched. The name is an auto
   number, so no personal data sits in it.
2. **Stages are one org-wide text setting, not a picklist and not a configuration object.**
   `Ask_Stages__c` on Giving Settings holds the ordered list, separated by semicolons, with a
   shipped default (Identified, Qualified, Cultivating, Ask Planned, Asked) and shown in the
   console's Giving section. A picklist would put the list in Setup, which no admin setting may
   need; a stage object would be a second record family, a page and permissions for what is five
   words in order. `Stage__c` is text, checked against the list only when an ask is created or its
   stage changes (R-SO2), so removing a stage never locks the asks still in it.
3. **Outcome is a separate restricted picklist: Open, Won, Declined, Withdrawn.** Stages then
   describe progress only, every organization's list ends the same way, and a closed ask keeps the
   stage it reached, which is what "where do we lose asks" needs.
4. **Stage history is the platform's field history** on Stage, Outcome, Ask Amount and Target
   Date, plus a Stage Changed Date field for "days in this stage" on the board. A history object
   of our own would duplicate what every edition already provides.
5. **A win creates or links the result in the same transaction.** The board's Won dialog records
   the gift now through Quick Gift Entry's save (so every gift rule applies), records a pledge as a
   Commitment of type Pledge, links an existing gift or commitment of the same donor, or leaves the
   result for later. A failure takes the outcome back with it.
6. **Sharing is Public Read/Write.** The audience is a team of one to five fundraisers working one
   pipeline, and the board's "Everyone" view is pointless if each person sees only their own asks.
   An organization that wants portfolios kept private sets the object to Private in Setup, as for
   any object; the admin guide says how.
7. **Next Ask Date is the hook for ask cadence (G-29).** It is set by a person, usually as the ask
   closes. The pipeline does nothing with it; G-29 reads it for its "who is due" list and needs no
   change to this object.
8. **Board logic that can run in a browser is a framework-free JavaScript module**
   (`askPipelineModel`: cards into columns, days in stage). Apex keeps the data access, the
   totals and every write (plan Section 9.9).

## Consequences

- Giving gains one object, one trigger, one setting key and one Setting Definition, and the Module
  Manager's Giving object list grows by one.
- Reports group the text stage alphabetically, not in list order; the board shows the list order.
- Renaming a stage in the setting does not rename it on existing asks: they appear in the board's
  "not in the stage list" column until moved. The admin guide says so.
- The Giving sample data includes a handful of asks across the stages and outcomes, flagged
  Sample Data and removed with the rest of the set.

## Alternatives considered

- **Mirror Opportunity.** Rejected: it fails on a Platform license and would make the pipeline a
  Mirror feature (ADR-0013).
- **A Solicitation Stage object, like Donor Level.** Rejected for now: more metadata and a page for
  an ordered list of words. Revisit if stages need attributes (a probability, a default task).
- **Asks as a kind of Commitment.** Rejected: a commitment is a promise the books track; an ask is
  work that may never become one, and mixing them would change every pledge total.
