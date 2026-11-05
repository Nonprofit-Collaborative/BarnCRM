# Adopting Your NPSP Households

**Feature:** X-05 Adopt NPSP households
**Package:** Core
**Iteration:** release 0.17

This page applies only to an org with the Nonprofit Success Pack (NPSP). In any other org,
BarnCRM shows nothing described here.

## What It Does

NPSP keeps each family as a household account, with its people as contacts on that account.
BarnCRM keeps households the same way, so it can take over the households you already have
rather than build a second one for every family. Adopting turns each NPSP household account
into a BarnCRM household in place: the same record, the same people, the same Opportunities,
activities and files. Nothing is copied and nothing is created twice.

For each household, BarnCRM:

- makes the account a BarnCRM household (its record type becomes Household);
- copies NPSP's formal and informal greetings into BarnCRM's greetings;
- makes NPSP's primary contact the household's primary contact, when that person is still in
  the household;
- keeps NPSP's household name and greetings as they are (you can choose to let BarnCRM name
  them instead, see below);
- counts the members.

BarnCRM never changes an NPSP field. NPSP's rollups, Opportunities and reports keep working on
the same accounts.

You see what will be adopted before anything changes, you confirm the number, and you can undo
a whole adoption later.

## How to Turn It On

There is nothing to turn on. The **Adopt NPSP Households** section appears on the **General**
page of BarnCRM Settings when BarnCRM detects NPSP in your org, when the coexistence mode is
NPSP coexistence, or when households were adopted before (so an undo is never hidden).

Before you adopt:

1. **Set Household membership to Contact** (BarnCRM Settings, **General**). NPSP keeps people
   on their contact's account, which is BarnCRM's Contact membership. Adoption is refused while
   membership is set to membership records, and the section says so.
2. **Turn off NPSP's automatic household naming** (NPSP Settings, **People**, **Households**,
   uncheck **Automatic Household Naming**). Otherwise NPSP and BarnCRM both name the same
   households. BarnCRM cannot change NPSP's settings for you.
3. You need the **Manage BarnCRM Settings** permission. Everyone with the BarnCRM Admin role has
   it. Each household is adopted only if you can edit its account; the rest are skipped and
   counted.

There is nothing to do in Salesforce Setup.

## A Five-Minute Walkthrough

Maria's org has had NPSP for six years and holds 3,214 household accounts. She has just
installed BarnCRM.

1. Maria opens the **BarnCRM Admin** app, clicks the **BarnCRM Settings** tab, and chooses
   **General** in the left navigation.
2. Coexistence mode shows **NPSP coexistence**. Below it, the **Adopt NPSP Households** section
   says **3,214 NPSP households can be adopted** and lists the first ten: each household's name,
   its NPSP formal and informal greetings, its primary contact and how many contacts it has.
3. **Keep NPSP's names and greetings** is ticked. Maria leaves it ticked: her team has typed
   many greetings by hand over the years.
4. She clicks **Adopt Households**. A window asks her to type **3214** to confirm. She types it
   and clicks **Adopt**.
5. The section says the adoption is running and updates itself. A few minutes later it reads
   **Last adoption: 3,214 adopted**, with the date and time. The Error Log has one Info entry
   with the same counts.
6. She opens the Garcia household. It is the same record as before, with its Opportunities and
   activities. It now has the BarnCRM household page, its member count is 3, and its greetings
   are the ones NPSP had.

Total time: about five minutes, most of it waiting for the run.

To take it back, Maria clicks **Undo This Adoption**, types the number shown, and clicks
**Undo**. Each household goes back to the record type it had, and BarnCRM's greetings, primary
contact and custom name go back to what they were.

## Then Turn On Household Upkeep

While NPSP households are in use, BarnCRM's **Household Upkeep** cannot be turned on: its row
on **General** (and in first-run setup) says why, and **Turn On** is not offered. Otherwise a
new person could get a BarnCRM household and an NPSP household at once, and NPSP's household
rollups, soft credits and Opportunity accounts would drift apart from BarnCRM's.

BarnCRM counts NPSP households as in use while either is true:

- NPSP still creates household accounts: NPSP's **Account Model** is **Household Account**
  (NPSP's own default when it was never changed);
- NPSP household accounts exist that are not adopted yet.

When you are ready for BarnCRM to keep your households:

1. Adopt every NPSP household (above), until the section says none are left.
2. In NPSP Settings, **People**, **Account Model**, set **Account Model** to **One-to-One** or
   **Individual**, and save. BarnCRM cannot change NPSP's settings for you.
3. In BarnCRM Settings, **General**, choose **Turn On** in the **Household Upkeep** row.

An org upgraded with Household Upkeep already on keeps it on, and its row shows the same
explanation until both are done, so you know to finish them.

## Names and Greetings

**Keep NPSP's names and greetings** (ticked unless you clear it) marks every adopted household
**Custom name, do not recompute**. Its name and greetings stay exactly as NPSP had them; a
greeting NPSP left blank is filled from the members by BarnCRM's naming settings.

With it cleared, BarnCRM names each household from its own naming settings
([Household names and greetings](household-naming.md)), except households where NPSP recorded
that staff typed the name or a greeting by hand: those keep their wording either way.

## Undo

Each run can be undone as a whole from the same section. Undo puts back, on each household:
the record type it had before, BarnCRM's two greetings, the primary contact and the custom name
setting. It does not put back the member count, which NPSP does not use.

A household is not put back when it was deleted since, when it is no longer a BarnCRM household,
or when you cannot edit it. Each adopted account has a **Household Adoption** record (BarnCRM
Admin can report on them), which says **Undone** or **Not Restored** with the reason.

## Common Mistakes

**Leaving NPSP's automatic household naming on.** NPSP may rename a household it still counts
as its own when its people change, which undoes the names BarnCRM keeps. Turn it off before
adopting.

**Expecting Household Upkeep to turn on right after adopting.** It also waits until NPSP's
Account Model is no longer Household Account. Change it in NPSP Settings, then turn Household
Upkeep on.

**Adopting while membership is set to membership records.** The section refuses and tells you
to set Household membership to Contact first.

**Expecting addresses, relationships or affiliations to come across.** Adoption takes the
household and its people only. NPSP's addresses, relationships and affiliations stay in NPSP;
[Migrating From NPSP](migrating-from-npsp.md) says how to load them.

**More than 48,000 households.** One run adopts up to 48,000. The section says when there are
more; run it again for the rest. Each run is undone on its own.

**Expecting it in an org without NPSP.** The section is not shown, and there is nothing to
adopt.

## What Cannot Be Proven Without NPSP

BarnCRM is tested in orgs without NPSP, through a stand-in for NPSP's fields. The [Testing
Guide](../testing-guide/people-and-households.md) lists what to check in a real NPSP org: which
accounts are found, and whether NPSP still renames an adopted household.
