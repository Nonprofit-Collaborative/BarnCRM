# Ask Pipeline

## What It Does

An ask is a request you plan to make, or have made, to one donor: "ask the Garcia family for 5,000 for the new roof by March." The Ask Pipeline keeps every open ask in one place, shows which step each one is at, and records how it ended. Fundraisers see it as a board of cards, one column per step.

It does this without the Salesforce Opportunity object. Giving runs on a Salesforce Platform license, so BarnCRM keeps its own **Ask** record (numbered ASK-00000001, ASK-00000002 and so on).

Things to hold on to:

- **Stage and Outcome are different.** A stage is a step on the way (Identified, Qualified, Cultivating, Ask Planned, Asked). An outcome is how the ask ended: **Open**, **Won**, **Declined** or **Withdrawn**. Every ask starts **Open**. Won, Declined and Withdrawn are not stages.
- **Closing a Won ask can record the gift for you.** The Close Ask window can save the gift or the pledge, link it to the ask and set the outcome in one step, or all of it fails and nothing is saved.
- **Changes are kept.** Changes to **Stage**, **Outcome**, **Ask Amount** and **Target Date** are listed in the **Ask History** related list on the ask.
- **Dates fill in themselves.** **Stage Changed Date** and **Closed Date** are set automatically.

## How to Turn It On

It is part of Giving, so there is no separate switch. Give people one of these permission sets (BarnCRM Settings, **Access**):

- **Giving Staff**: creates and edits asks. Cannot delete.
- **Giving Admin**: also deletes asks.
- **Giving Read Only**: sees the board and the asks, and cannot change them.

Then set your stages, or leave the defaults.

1. Open **BarnCRM Settings** and choose the **Giving** section.
2. Find **Ask stages**. Type the stage names in order, separated by semicolons.
3. Save.

The default is `Identified;Qualified;Cultivating;Ask Planned;Asked`. Leaving it empty uses the default. This is one setting for the whole organization.

Leave **Won**, **Declined** and **Withdrawn** out of the list. They are outcomes.

How the list behaves:

- A new ask with no stage starts at the first stage.
- A stage that is not in the list is refused when an ask is created or moved.
- Renaming or removing a stage does not change asks already in it. They appear in a **Not in Your Stage List** column on the board until someone moves them, and other edits to them still save.
- The board shows stages in your list order. Reports group **Stage** alphabetically.

### Who Sees Which Asks

By default every fundraiser sees every ask (Public Read/Write), because a small team shares one pipeline. To keep each fundraiser's asks private, set **Ask** to **Private** in Setup, **Sharing Settings**. This is the one Setup step for this feature.

## What Fundraisers See

In the **Fundraising** app, the **Ask Pipeline** tab shows:

- Totals at the top: **Open Asks** (count), **Open Ask Total**, **Won This Fiscal Year** (count and ask amount) and **Declined This Fiscal Year** (count). The fiscal year is your org's fiscal year from Setup, counted by **Closed Date**. The totals are always exact.
- The **Board** (one column per stage with its count and total) and the **List**. The board draws up to 1,000 open ask cards and says so when there are more.
- **Everyone's Asks** and **My Asks** filters, and a **New Ask** button.

The **Asks** tab has the list views **Open Asks**, **My Open Asks** and **All Asks**. An **Asks** related list, with a **New** button, is on person, household and organization pages in the Fundraising app. The user guide page [The Ask Pipeline](../user-guide/ask-pipeline.md) covers the daily steps.

## A Five-Minute Walkthrough

1. Open **BarnCRM Settings**, **Giving**. Leave **Ask stages** empty to use the defaults.
2. Open the **Fundraising** app and the **Ask Pipeline** tab. The board shows five empty columns.
3. Choose **New Ask**. Pick a **Donor Contact**, type an **Ask Amount** of 1,000 and a **Target Date**, and save. The card is in **Identified**.
4. Drag the card to **Cultivating**. The column counts and totals change.
5. In the card's menu choose **Close Ask**. Under **How Did It End?** choose **Won**, then **Record the Gift Now**, and save.
6. The card leaves the board. **Won This Fiscal Year** shows 1, and the gift is on the donor's record.

## Common Mistakes

- **Putting Won or Declined in the stage list.** They are outcomes. Use the Close Ask window to end an ask.
- **Expecting a renamed stage to rename asks.** Asks already in the old name show in **Not in Your Stage List** until someone moves them.
- **Choosing two donors, or none.** An ask needs exactly one: **Donor Contact** for a person, or **Donor Account** for an organization or household. This is checked when the ask is created or its donor is changed.
- **Linking another donor's gift.** The **Link a Gift or Pledge Already Entered** choice refuses a gift or pledge that belongs to a different donor.
- **Expecting Next Ask Date to do something.** It records when to ask the donor again. This release does nothing else with it.
- **Expecting private asks without the Setup step.** Until **Ask** is set to **Private** in Sharing Settings, everyone sees every ask.
- **Looking for sample asks.** The sample data set does not include any in this release.

## Other Things Worth Knowing

- **Deleting a donor** keeps the ask, with no donor, and it can still be closed.
- **Erase a Person** clears **Next Step** on their asks and turns open ones into **Withdrawn**. The asks are kept, like gifts.
- **To reopen an ask,** edit it and set **Outcome** back to **Open**. **Closed Date** clears.

## What This Does Not Do Yet

- **Next Ask Date** has no "who is due" list yet. The planned ask cadence feature (G-29) will use it.
