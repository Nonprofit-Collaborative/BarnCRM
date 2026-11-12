# Households You Already Have in Nonprofit Cloud

**Feature:** X-09 Nonprofit Cloud household guards; MIG-02b Household Model and conversion (D-196)
**Package:** Core (guards, Household Model, the conversion section); Mirror (the conversion's source, its Migration Assistant kit and the drift report)
**Iteration:** release 1.20 (conversion); guards since v0.4

This page applies only to an org with Salesforce Nonprofit Cloud. In any other org, BarnCRM
shows nothing described here.

## What It Does

Salesforce Nonprofit Cloud has its own way of grouping people into a household (a Party
Relationship Group of type Household on an account, with the people on account contact
relationships), and BarnCRM has its own way. One account has exactly one household model, and
BarnCRM gives you three things to keep it that way.

**The guards.** BarnCRM looks for the households Nonprofit Cloud built and stays out of their
way automatically: it never renames such a household, never rewrites its formal or informal
greeting, never writes its address, and never creates a second, duplicate BarnCRM household for
someone already grouped by Nonprofit Cloud. Each guard only ever leaves a record alone.

**Household Model.** Every account has a **Household Model** field that says which model owns
it:

| Value | What it means |
|---|---|
| **Automatic** (the default) | BarnCRM decides from what it finds, exactly as the guards always have. |
| **Nonprofit Cloud** | This account is a Nonprofit Cloud household and stays one. The guards leave it alone even where BarnCRM cannot see its group, and the conversion never picks it. |
| **Converted** | BarnCRM owns this household now. It was converted from Nonprofit Cloud; its Nonprofit Cloud group is still there, untouched, but BarnCRM names, greets and addresses it like any BarnCRM household. |

**Convert Nonprofit Cloud Households.** A supervised, one-time conversion that makes each
Nonprofit Cloud household a BarnCRM household on the same account: the same record, its name,
gifts, activities and files. For each household, BarnCRM:

- makes the account a BarnCRM household (its record type becomes Household) and sets
  Household Model to **Converted**;
- keeps the household's name as your team typed it (you can choose to let BarnCRM name it
  instead);
- with household membership set to membership records (Junction), adds each member as a
  BarnCRM household member, marking Nonprofit Cloud's primary member as primary and carrying
  over the role (Husband and Wife become Spouse or Partner, Son and Daughter become Child,
  Father and Mother become Head, Other stays Other) and the start and end dates. A former
  member with no end date is left out. A person account joins as itself;
- fills the greetings from the members and counts them.

With household membership set to Contact, nobody is moved: a person belongs to the household
their contact names, which in most Nonprofit Cloud orgs without person accounts is already the
household.

BarnCRM never deletes, changes or creates a Nonprofit Cloud group, membership relationship or
account. Merging and the empty-household tidy-up still leave converted households alone,
because their Nonprofit Cloud group would be deleted with them. There is no sync afterwards in
either direction.

**The drift report.** Health Check lists accounts whose Household Model and Nonprofit Cloud
group disagree, so you can settle each one. It changes nothing for you.

## How to Turn It On

There is nothing to turn on. The guards and the Household Model field work in every org. The
**Convert Nonprofit Cloud Households** section appears on the **General** page of BarnCRM
Settings when BarnCRM Mirror is installed and your org has Nonprofit Cloud's household objects,
or when households were converted before (so an undo is never hidden). It is also a step of the
**NPC Households** kit in the Migration Assistant (see [Migration Assistant](migration-assistant.md)).

Before you convert:

1. **Choose household membership** (BarnCRM Settings, **General**). Membership records
   (Junction) is the usual choice for Nonprofit Cloud, where people can belong to more than one
   account and are often person accounts; members are added only in that mode.
2. **Turn off Nonprofit Cloud's automatic household naming** if your org has it, so the two do
   not both name the same households. BarnCRM cannot change Nonprofit Cloud's settings for you.
3. **Mark any household you want to keep in Nonprofit Cloud**: open the account and set
   **Household Model** to **Nonprofit Cloud**. The conversion passes it over.
4. You need the **Manage BarnCRM Settings** permission, and read access to Nonprofit Cloud's
   household groups and memberships (the Group Membership permission set). Each household is
   converted only if you can edit its account; the rest are skipped and counted.

There is nothing to do in Salesforce Setup.

Health Check's **What We Found in Your Org** card (BarnCRM Settings, **Health**) says how many
Nonprofit Cloud households BarnCRM found, as information. If it cannot count them, it says that
instead, and BarnCRM assumes they are there and stays out of their way.

**Contacts to Multiple Accounts.** With this Salesforce setting on, every contact gets an
account relationship record, and moving a person to another household leaves an indirect one
behind. In an org without Nonprofit Cloud households, BarnCRM does not read those records as
a Nonprofit Cloud household: naming, greetings, addresses and memberships work as usual.

- **Moving people.** When BarnCRM moves a person to another household, it removes the
  indirect relationship that move left on the old household, but only if nobody added roles
  or start or end dates to it. Empty households are then tidied away as usual.
- **Merging.** Merging moves everyone first, with the same tidy-up. If someone is still
  related to both households afterwards (a relationship somebody added, or one with roles or
  dates), BarnCRM does not delete it: the merge stops, nothing changes, and you are told the
  households could not be combined. Remove or edit that relationship and merge again.
- **Kept households.** A household emptied some other way (for example by changing a
  contact's account on the contact record), or one that still has a relationship somebody
  added, is kept and noted in the Error Log at Info severity. Import undo also keeps an
  imported household that still has such relationships. Check these and delete any you no
  longer need.

## A Five-Minute Walkthrough

Maria has installed BarnCRM into an org that has been running Nonprofit Cloud for two years.
Her colleagues have grouped 1,240 families there.

1. Maria opens the **BarnCRM Admin** app, clicks the **BarnCRM Settings** tab, and chooses
   **General** in the left navigation. Household membership is already set to membership
   records.
2. Two families should stay in Nonprofit Cloud for now. She opens each account and sets
   **Household Model** to **Nonprofit Cloud**.
3. In **Convert Nonprofit Cloud Households** she reads "1,238 Nonprofit Cloud households can be
   converted" and the first ten, with each household's primary member and how many members it
   has. She leaves **Keep Nonprofit Cloud's household names** checked.
4. She clicks **Convert Households**, types **1238** and clicks **Convert**. The section says it
   has started and updates by itself.
5. When it finishes, **Last conversion** shows 1,238 converted. She opens the Lee household:
   it is a BarnCRM household with Sam Lee as its primary member and greetings filled in, and
   Household Model reads Converted.
6. She opens **Health** and sees no **Household Model Disagrees With Nonprofit Cloud** warning.
7. In the Migration Assistant she marks the **NPC Households** step done and ticks the retire
   checklist.

Total time: about five minutes, plus the conversion's own run.

## Undoing a Conversion

**Undo This Conversion** under **Last conversion** puts each household back: its record type,
Household Model, name setting, greetings and primary contact as they were, and it removes the
household member records the conversion added. Type the number to confirm. A household that has
gained another member since, or that you can no longer edit, is not put back; the reason is on
its Household Adoption record. Remove that member and undo again.

## The Drift Report

Health Check shows **Household Model Disagrees With Nonprofit Cloud** when any account is:

- a BarnCRM household with a Nonprofit Cloud household group, not marked **Converted** (both
  models claim it);
- marked **Nonprofit Cloud** with no Nonprofit Cloud household group;
- marked **Converted** but no longer a BarnCRM household.

It names up to ten of them. Settle each one: set Household Model to the model that owns it, run
the conversion, or undo it. The warning goes when nothing disagrees.

## Common Mistakes

**Expecting the conversion to keep running.** It is one-time. A household created in Nonprofit
Cloud after the conversion stays a Nonprofit Cloud household, guarded as before, until you run
the conversion again. Running it again is safe: converted households and members already added
are left as they are.

**Expecting changes to flow back to Nonprofit Cloud.** They do not, and Nonprofit Cloud's
changes do not flow into BarnCRM. A converted household's Nonprofit Cloud group still lists its
old members; ask staff to keep households in BarnCRM from then on.

**Converting with Contact membership in a person account org.** A person account cannot belong
to a household by reference, so nobody is added. Set membership to membership records first.

**Running both models on the same family.** The drift report exists to catch it. Pick one model
per household; Household Model records the choice.

**Expecting the guard to catch every native household.** On an account marked Automatic it
only recognizes an account that already carries a Nonprofit Cloud household group, or, in an
org that has Nonprofit Cloud households, native membership rows. A person who belongs to a
Nonprofit Cloud household only through membership data BarnCRM cannot see can still be given a
BarnCRM household. Setting Household Model to **Nonprofit Cloud** on that household's account
makes the guards leave it alone whatever they can see.

**Reading a missing number as a zero.** If Health Check cannot count Nonprofit Cloud households,
nobody could count them, not that there are none. Ask a colleague with fuller access to look.
