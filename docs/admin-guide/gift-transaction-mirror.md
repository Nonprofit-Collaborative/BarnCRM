# Gift Transaction Mirror

## What It Does

BarnCRM records money received as gifts. Nonprofit Cloud (Agentforce Nonprofit) records the
same thing as Gift Transactions, and everything it builds on top reads only those: donor gift
summaries on donor pages, giving levels, actionable lists and Agentforce actions. The Gift
Transaction mirror copies your BarnCRM gifts to Gift Transactions, so an organization that
enters gifts in BarnCRM still sees them in Nonprofit Cloud.

It copies in one direction only, from gifts to Gift Transactions. It is separate from the
[Opportunity Mirror](opportunity-mirror.md), which has its own setting. Each gift remembers its
Gift Transaction in its **Gift Transaction ID**, so nothing is ever copied twice.

The mirror works in runs: **Run Now**, and a step of [BarnCRM Nightly Jobs](nightly-jobs.md)
at 1:35 AM in the time zone of the person who scheduled it, switched on while the mirror is on. Saving a gift does not copy it at once. Nonprofit Cloud works out its donor summaries in
its own scheduled runs, so a gift copied at once would not show on a donor page any sooner.
A run in which a gift could not be copied is not counted as completed, so the next run tries that
gift again; the Error Log says why it failed.

A run copies each gift that is Received, has an amount above zero and is not in-kind, dated on
or after the start date you set:

| On the gift | On the Gift Transaction |
|---|---|
| Donor Account, or the donor's Household | Donor |
| Gift Date | Transaction Date |
| Amount | Original Amount, and Current Amount when it is created |
| (the paid status you set) | Status, when it is created |
| Gift number (for example G-000123) | Name, when it is created and your org lets it be set |
| Each allocation, for a fund linked to a Gift Designation | A Gift Transaction Designation for that designation, with the allocation's amount, when it is created |

When the gift changes, the next run updates the Donor, Transaction Date and Original Amount. It
never changes Status, Current Amount or designations afterwards: Nonprofit Cloud keeps those up
to date itself, for example when you record a refund there. Nothing else is written: no campaign,
source code, payment details or soft credits.

**Designations.** A fund is linked to a Nonprofit Cloud Gift Designation by its **Gift
Designation ID**, which you fill in on the fund. Funds are matched by that link only, never by
name, so renaming a fund never moves money to another designation. An allocation to a fund with
no link is left undesignated, and the run's summary counts it. If Nonprofit Cloud already gave
a new Gift Transaction a designation of its own (a default designation), the mirror adds none.

Refunds and write-offs are not copied. BarnCRM records a refund as a second gift with a negative
amount, and Nonprofit Cloud would count that as one more gift. A gift refunded after it was
copied keeps its Gift Transaction as it was. If Nonprofit Cloud's totals must show the refund,
record the refund on the Gift Transaction in Nonprofit Cloud too. The reconciliation lists every
such gift. Pending, Cancelled and in-kind gifts are not copied either.

Nothing is ever deleted. Deleting a gift leaves its Gift Transaction, and the Error Log gets one
Warning naming the gifts deleted and their Gift Transactions. Turning the mirror off leaves every
record where it is.

Gift Transactions to Gifts, the other way round, is not available yet.

## How to Turn It On

You need the Mirror module and Nonprofit Cloud fundraising: the Fundraising Access license, and
for you and whoever schedules the run, the Fundraising User permission. Without them the Gift
Transaction Mirror page says the mirror is not available, and nothing else happens.

1. Give yourself the **Salesforce Records Sync** permission set on the Access page, under Extra
   Permissions: the roles there do not include it.
2. Check the Status value that means paid in your org. In Nonprofit Cloud, open any paid Gift
   Transaction and note its Status. The mirror needs the value's API name, which is usually the
   same as what you see; Setup, Object Manager, Gift Transaction, Fields, Status lists both. The
   setting starts as `Paid`.
3. Open **BarnCRM Settings**, choose **Giving**, and set:
   - **Gift Transaction mirror paid status**, if your paid value is not `Paid` (a dropdown of
     your org's active Status values);
   - **Gift Transaction mirror start date**: only gifts dated on or after it are copied; while it
     says **Not set**, nothing is copied. If you
     loaded your Nonprofit Cloud gifts into BarnCRM, choose the day after the last load, so those
     gifts are not copied back as second Gift Transactions;
   - **Gift Transaction mirror direction** to **Gifts to Gift Transactions**.
   Until the start date is set, nothing is copied.
4. To have designations copied, open the **Funds** tab, choose the **Funds and Their Gift
   Designations** list view, and paste each fund's Gift Designation record ID (the 18-character
   code in its web address) into **Gift Designation ID**.
5. Still in **Giving**, open **Gift Transaction Mirror** (the row shows only to someone with the
   permission set). Click **Run Now** once, and **Schedule Nightly Run**, which switches the mirror's step
   on in [BarnCRM Nightly Jobs](nightly-jobs.md), so the mirror catches up every night. The page shows when the last run completed and what it did, and Health Check
   warns if two days pass without one.

**Whose access the run uses.** A run reads and writes with the access of the person who started
or scheduled it. That person needs the Manage BarnCRM Settings permission, the Gift Transaction
Mirror permission set, and, in Nonprofit Cloud, access to create and edit Gift Transactions and
to create Gift Transaction Designations. Gift entry staff need none of this: their gifts are
copied by the next run.

**Two switches, one of them in charge.** **Gift Transaction mirror direction** decides whether
the mirror copies. The **Gift Transaction mirror** row on the Automation page is the switch every
BarnCRM automation has: switched off, the runs stop. While automation is paused, or the switch is
off, a run does nothing and the Error Log says so once.

## A Five-Minute Walkthrough

Do this as Maria, in an org with Nonprofit Cloud fundraising and the sample data loaded.

1. In **BarnCRM Settings**, **Giving**, check **Gift Transaction mirror paid status** against
   your paid value, set **Gift Transaction mirror start date** to the first of this month, and
   set **Gift Transaction mirror direction** to **Gifts to Gift Transactions**. Save.
2. In the **Funds and Their Gift Designations** list view, paste a Gift Designation's record ID
   into the default fund's **Gift Designation ID**.
3. Enter a gift of 100 from Luis Garcia with **Quick Gift Entry**, dated today.
4. Open **Gift Transaction Mirror** and click **Run Now**. Wait a minute and reload the page: the
   last run says how many Gift Transactions were created, one for each received gift dated this
   month, Luis's included. Open Luis's gift: its **Gift Transaction ID** is filled in. Open that
   Gift Transaction: Original Amount 100, Transaction Date today, the donor is Luis's household,
   and it has one designation of 100.
5. Change the gift's amount to 150, click **Run Now** again, and reload the Gift Transaction:
   Original Amount 150.
6. Back on the page, under **Reconciliation**, choose this month and click **Compare**. The gift
   count and total match the Gift Transaction count and total, apart from any Gift Transactions
   your org had already, which are listed as having no gift.

## Common Mistakes

**The page says the mirror is not available.** You cannot see Gift Transactions: your user needs
the Fundraising User permission, or the org does not have Nonprofit Cloud fundraising. The same
message appears when your org's Gift Transaction fields differ from what this version expects.
Nothing is wrong with your data in that case, but the mirror cannot work in that org until
BarnCRM is corrected: report it on GitHub (see [Support](../../SUPPORT.md)).

**The page says the paid status is not one of your org's Status values.** The setting is a
dropdown of the active Status values, so this means the saved value was retired in Setup (it
still shows in the dropdown). Choose a current value. If the box is plain text, the org has no
Gift Transaction Status field; type the API name exactly, including capitals.

**Every gift from before the mirror was set up got a second Gift Transaction.** The start date was
set before the day you loaded your Nonprofit Cloud gifts. Delete the extra Gift Transactions in
Nonprofit Cloud (the reconciliation for that range lists them against their gifts), clear those
gifts' **Gift Transaction ID** in the **Gifts and Their Gift Transactions** list view, and set
the start date to the day after the load.

**A gift has no Gift Transaction.** The reconciliation lists it. Most often it is dated before the
start date, is not Received, is in-kind, or no run has happened since it was entered. Otherwise
Nonprofit Cloud refused it, for example because the donor has no account (a donor stored as a
contact with no household), or because of a validation rule or a required field your org added.
The Error Log has a Warning with Salesforce's message and the gifts it refused. Fix the cause,
then click **Run Now**.

**A Gift Transaction has no designation.** Its gift's fund has no **Gift Designation ID**, or
the ID does not name a Gift Designation you can see, or Nonprofit Cloud gave it a designation of
its own. Designations are written only when the Gift Transaction is created: add the missing one
in Nonprofit Cloud, and fill in the fund's link so the next gifts get theirs.

**A linked Gift Transaction was deleted, or is not visible to you.** The mirror does not make a
replacement, because it cannot tell a deleted Gift Transaction from one the person running may
not see, and a replacement for one that still exists would count the gift twice. Check, as
someone who sees every Gift Transaction, whether it exists. If it was deleted, clear the gift's
**Gift Transaction ID** in the **Gifts and Their Gift Transactions** list view, which the mirror
adds, and the next run makes a new one.

**Linking a gift to a Gift Transaction you already had.** In the **Gifts and Their Gift
Transactions** list view, paste the Gift Transaction's record ID into the gift's **Gift
Transaction ID** and save. The next run writes the gift's donor, date and amount onto it. A Gift
Transaction belongs to one gift only; pasting an ID another gift holds fails the save with a
duplicate value error.

**Turning the mirror off and expecting the copies to go.** They stay. Switching it off stops the
copying and deletes nothing.
