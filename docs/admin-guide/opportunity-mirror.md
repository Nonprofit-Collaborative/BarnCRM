# Opportunity Mirror

## What it does

Open Impact records money received as gifts. Salesforce's own sales object, the Opportunity,
is what NPSP, many fundraising apps and many online giving tools use for the same thing. The
Opportunity mirror keeps the two in step, in one direction you choose.

- **Gifts to Opportunities.** Every gift gets a matching Opportunity, kept up to date when the
  gift changes. Choose this when something in your org still reads Opportunities: NPSP
  rollups and soft credits during a move from NPSP, Campaign totals, or an app that only knows
  Opportunities.
- **Opportunities to Gifts.** Every won Opportunity becomes a gift. Choose this when your
  online giving tool writes Opportunities, so its donations arrive in Open Impact as gifts.

Only one direction can be on. Changing it later never copies anything twice, because each gift
remembers its Opportunity in its **Opportunity ID**, whichever side came first.

**Gifts to Opportunities** copies:

| On the gift | On the Opportunity |
|---|---|
| Amount | Amount |
| Gift Date | Close Date |
| Status | Stage: your won stage (`Closed Won`) for a Received, Refunded or Written off gift; your lost stage (`Closed Lost`) for a Cancelled gift; left as it is for a Pending gift, so linking a pledge to an open Opportunity never closes it |
| Donor Account, or the donor's Household | Account |
| Appeal (its Campaign, when Campaign sync gave it one and you can see Campaigns and the appeal's Campaign ID; otherwise the Opportunity's Campaign is left as it is) | Campaign |
| Donor | Primary Contact Role, with Role Donor |

A new Opportunity is named after the donor and the date, and uses the Donation record type
when your org has one. If that record type's sales process does not include your won or lost
stage, Salesforce refuses the Opportunity and the Error Log says so: add the stage to the sales
process. For a donor who is a contact, the Account is the Open Impact household; in an org
running NPSP alongside, that is not the NPSP household account, so NPSP's household totals do
not include these Opportunities. Pending and Cancelled gifts get no Opportunity. A refund or write-off,
which is its own gift with a negative amount, gets its own Opportunity with that negative
amount, so an NPSP total goes down exactly as the Open Impact total does. NPSP still counts that
Opportunity as one more gift, and counts an in-kind gift's Opportunity, whose amount is zero:
the totals agree, the counts are NPSP's own.

**Opportunities to Gifts** makes one gift from each won Opportunity closed on or after the start
date you set: the donor is the Opportunity's primary contact (or its Account when it has none),
the amount and date are the Opportunity's, the type is Other, the status Received, and the
appeal is the one whose Campaign is the Opportunity's Campaign. To make gifts from some kinds of
Opportunity only, list their record types' API names, separated by commas, in **Opportunity
mirror record types** (for example `Donation,Major_Gift`); left empty, every won Opportunity
after the start date counts, and a name your org does not have is named in a Warning in the
Error Log. The start date is read in your organization's default time zone. The gift then gets its fund,
household and thank-you status from your Giving settings, like any gift. A gift is never
changed afterwards, even if its Opportunity is: the reconciliation shows the difference.

Nothing is ever deleted. Deleting a gift leaves its Opportunity, and the Error Log gets one
Warning naming the gifts deleted and their Opportunities, for you to delete or close yourself.
In Opportunities to Gifts, the next run makes a new gift from an Opportunity that is still won,
so close it as lost or delete it if the gift should stay gone. Turning the mirror off leaves
every Opportunity and gift where it is.

## How to turn it on

You need the Connect module and a Salesforce edition with Opportunities (Sales Cloud, Service
Cloud, NPSP or Nonprofit Cloud). An org on Salesforce Platform licenses only has none, and the
Opportunity mirror page says so.

1. Give yourself the **Opportunity Mirror** permission set. Until the Module Manager arrives,
   module permission sets are assigned in Setup.
2. Open **Open Impact Settings**, choose **Giving**, and set **Opportunity mirror direction**.
   For **Opportunities to Gifts**, also set **Opportunity mirror start date**: only won Opportunities closed on or after it become gifts.
   Until it is set, no Opportunity becomes a gift, so that a switch in an org with years of
   Opportunities does not create, and thank donors for, a gift for every one of them.
3. Still in **Giving**, open **Opportunity mirror** (the row shows only to someone with the
   permission set). Click **Run now** once, to copy what you already have, and **Schedule
   nightly**, so the mirror catches up every night at 01:30. The page shows when the last run
   completed and what it did, and Health Check warns if two days pass without one.

**Whose access the copy uses.** Opportunities are written with the access of the person saving
the gift, and the nightly run with the access of the person who scheduled it. Saving a gift
needs Opportunity create and edit access, not the permission set: the permission set is for
seeing Opportunity ID and opening the page. Someone who cannot create and edit Opportunities
still saves gifts; the next run copies them, including a change to a gift that already has an
Opportunity. Give fundraising staff Opportunity create and edit access in Setup if you want the
Opportunity at once. The Error Log has one Warning when such a person creates or changes gifts;
imports add none, and the nightly run catches them up. That catch-up looks at every gift without
an Opportunity and every linked gift changed since the last run; with hundreds of thousands of
gifts the run takes longer to start, which does not matter at 01:30.

**Two switches, one of them in charge.** **Opportunity mirror direction** decides what the
mirror does. The **Opportunity mirror** row on the Automation page is the switch every Open
Impact automation has: switched off, it stops the copy made when a gift is saved and the runs.
While automation is paused, or the switch is off, a run does nothing and the Error Log says so
once: Giving's own rules are paused too, and a gift made then would never get its household or
fund.

**Very large saves.** The copy starts only while half of the save's Salesforce limits are still
unspent, because your own Opportunity automation runs inside the same save. When it does not,
the gifts save without their Opportunities and one Warning says so. The next run copies them. A load of 200 rows at a time, as Data Loader and the importer send, is
copied as usual.

## A five-minute walkthrough

Do this as Maria, in an org that has Opportunities, with the sample data loaded.

1. In **Open Impact Settings**, **Giving**, set **Opportunity mirror direction** to **Gifts to
   Opportunities** and save.
2. Open **Opportunity mirror** and click **Run now**. Wait a minute, then open the
   **Reconciliation** section, choose this year, and click **Compare**. The gift count and total
   match the won Opportunity count and total, and there are no differences.
3. Enter a gift of 100 from Luis Garcia with **Quick gift entry**. Open the App Launcher,
   search for **Opportunities**, and open the newest: Amount 100, Stage Closed Won, Close Date
   today, Luis as the primary contact.
4. Change the gift's amount to 150 and save. Reload the Opportunity: its Amount is 150.
5. On the Opportunity, change the Amount to 175. Back on the page, click **Compare** again: the
   gift and its Opportunity are listed with "Amount differs". Click **Copy these gifts again**;
   when it finishes, the Opportunity is back to 150.
6. Set the direction to **Opportunities to Gifts**, set the start date to today, and save. Create
   a won Opportunity of 60 for Luis, closed today, and click **Run now**. A gift of 60 for Luis
   appears on his record, and the gift's **Opportunity ID** names that Opportunity.

## Common mistakes

**A gift has no Opportunity.** The reconciliation lists it. Most often the person who entered it
cannot create Opportunities (see Whose access the copy uses): the next run copies it. Otherwise a
rule on Opportunity refused it, such as a validation rule or a required field your organization
added. The Error Log has a Warning with the platform's message and the gifts it refused. Fix the
cause, then click **Run now**.

**The Opportunity was changed by hand.** The next time the gift changes, its values replace
yours. Edit the gift instead. Fields that are not copied, such as Description, Next Step or your
own fields, are never touched.

**A won Opportunity with no gift visible to you, in Gifts to Opportunities.** It was not made by
the mirror: it was entered directly, came from another tool, or its gift was deleted. Or its gift
exists and you cannot see it: the reconciliation shows what your own access shows. The mirror never
deletes an Opportunity. Decide whether it should stay, and delete it yourself if not.

**A linked Opportunity was deleted, or is not visible to you.** The mirror does not make a
replacement, because it cannot tell a deleted Opportunity from one the person saving may not
see, and a replacement for one that still exists would count the gift twice. The Error Log says
so when the gift next changes. Check, as someone who sees every Opportunity, whether it exists.
If it was deleted, clear the gift's **Opportunity ID** in the **Gifts and their Opportunities**
list view and save: a new Opportunity is made.

**Linking a gift to an Opportunity you already had.** Open the **Gifts** tab and choose the
**Gifts and their Opportunities** list view, which the mirror adds. Double-click the gift's
**Opportunity ID** cell, paste the Opportunity's record ID (the 18-character code in its web
address, starting `006`), and save. Be sure it is the right one: in Gifts to Opportunities the gift's amount, date, stage,
account and campaign are written onto it at once. An Opportunity belongs to one gift only;
pasting an ID another gift holds fails the save with a duplicate value error.

**Choosing Opportunities to Gifts in an org that sells with Opportunities.** Every won
Opportunity after the start date becomes a gift, including a sale. Use this direction only when
won Opportunities in your org are donations.

**Gifts from Opportunities are thanked twice.** They are ordinary gifts, so your acknowledgment
rules apply. If your giving tool already sends the thank you, add an acknowledgment rule with
channel None for gifts of type Other (see [Acknowledgments](acknowledgments.md)).

**Turning the mirror off and expecting the copies to go.** They stay. Switching it off stops the
copying and deletes nothing.
