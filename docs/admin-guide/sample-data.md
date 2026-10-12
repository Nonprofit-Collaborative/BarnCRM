# Sample data

## 1. What it does

Sample data fills your org with a realistic demo dataset. Use it to see Open Impact working
with real-looking names, addresses and giving before you import your own list, to train a
new colleague, or to try a setting change (for example a household naming pattern) against
data that already has the variety your real list has. You can remove every sample record in
one action when you are done with it.

What loads, exactly:

| Records | How many | What is in them |
|---|---|---|
| Households | 200 | Shared surnames, different surnames, hyphenated names, single-person households, ten three-generation households, five with a deceased member, three with a custom name |
| People | 440 | Heads, partners, children, a few with preferred names |
| Organizations | 25 | Foundations, local businesses, churches, a school district |
| Connections | 60 | Parents, siblings, friends, colleagues and grandparents in different households, a few marked Former; the other side of each one is created by the connection rules, as it would be for a connection you enter |
| Affiliations | 80 | Board members, employees, volunteers and owners, one primary each, a quarter of them Former |

With the **Giving** package installed, the same action also loads:

| Records | How many | What is in them |
|---|---|---|
| Funds | 8 | General Fund plus seven restricted funds, each with an accounting code. None of them is made your default fund |
| Appeals | 7 | An Annual Fund with three appeals under it, a gala, an emergency appeal, a legacy circle, each with a goal and a cost |
| Gifts | About 700 | Three years of giving: checks, cards, ACH, cash, stock, grants and about twenty in-kind gifts, weighted the way a real list is (most under 500, a few above 10,000). The in-kind gifts carry no amount, as every in-kind gift does, so they are in the In-kind value total on their donor and in none of the cash totals ([In-kind gifts](in-kind-gifts.md)) |
| Gift allocations | About 750 | One fund for most gifts, two for the gifts a donor designated twice |
| Commitments | 24 | 14 monthly recurring gifts and 10 pledges, with the installments the schedule implies and the gifts that have paid them |
| Soft credits | 30 entered by hand | Solicitors and influencers on the larger gifts, on top of the household member credits the automatic rule writes for every gift |
| Tributes | 24 | In memory of and in honour of, with a message, notified to somebody other than the person being remembered |

The giving history is shaped so the reports have something to say: donors who have given in
each of the last three years, donors who lapsed more than eighteen months ago, donors whose
first gift arrived in the last few months, a few major donors, and about a fifth of
households who have never given. It also holds two refunded gifts and one written-off gift,
each recorded as a refund is recorded here (the original keeps its amount and takes the
reversed status, and a linked negative gift carries the money back out), and one monthly
donor whose last three installments are overdue.

Gift dates are counted back from the day you load the set, not fixed in the file. Load it
today or in two years and there are still gifts this year, last year and the year before.

No sample gift has a receipt number. Receipted gifts cannot be deleted, and everything here
has to stay removable.

## 2. How to turn it on

1. Open **Open Impact Settings**.
2. In the **General** section, find **Sample Data** and open it. If you do not see it,
   type "sample" in the settings search box.
3. Read the warning, then select **Load Sample Data**.
4. Confirm in the dialog. Loading runs in the background; the card shows progress and
   updates automatically until it finishes. With Giving installed there are several
   thousand records to write, so allow a few minutes rather than one.
5. When it says **Loaded**, open **Open Impact Settings > Rollups** and select
   **Recalculate**. Giving totals (total giving, this year, largest gift, fund and appeal
   totals) are worked out by the nightly rollup run rather than as each gift is saved, so
   until you recalculate, or until tonight, those fields are empty while the gift records
   themselves are all there.

If you came here from the Setup Assistant, the same **Sample Data** step takes you to
this screen. Loading sample data is entirely optional; skipping it does not block any
other step.

You need the **Manage Open Impact Settings** permission to load or remove sample data.
Without it, the card is read only and tells you who to ask.

Sample data loads whichever way your org tracks household membership. In the simple way,
each sample person carries their household on their own record. In the flexible way (the
Agentforce Nonprofit coexistence mode, which Nonprofit Cloud orgs get), each sample person
is joined to their household by a household member record, exactly as your own people are,
and the card says so before you load.

One difference to expect in an org that stores people as accounts: the sample people arrive
as contacts. Open Impact never creates person accounts, so the sample set shows you
households of contacts. Everything else behaves as it will with your own data: the same
household records, names, greetings, member counts, and Members panel.

## 3. A five-minute walkthrough (as Maria)

1. Open **Open Impact Settings**, go to **Sample Data**, and select **Load Sample Data**.
   Confirm the dialog. Wait for the card to show **Loaded**, with counts for households,
   contacts, organizations, connections, affiliations, and, with Giving installed, gifts.
2. Open the **Households** tab. Use the list view search to find "Garcia" and open
   **The Garcia Family**.
3. On the household record, check the formal and informal greeting fields. They read
   naturally, for example "Mr. and Mrs." followed by the names, and a first-names-only
   informal greeting, because they were computed by the naming rules from the sample
   household's members. The names and greetings are computed by household automation as
   the people are added, so they only appear if household naming is turned on.
4. Still on the Garcia household, look at the **Gifts** related list (Giving installed).
   The family has given in each of the last three years, which is what a renewing donor
   looks like in the retention report.
5. Still on **Households**, search for "Staff Household". This is the sample data's own
   staff family: Maria, David, Priya, Tom, Jen, and Sam appear here as contacts, so you
   can find a familiar name while you are learning the app.
6. Open the **Gifts** tab and sort by amount. Open the largest gift and look at its
   allocations: most gifts sit in one fund, some are split across two. Then filter the list
   view by **Status** equals Refunded to find the refunded gift, and open it: its own amount
   is unchanged and a linked negative gift reverses it, which is how a refund is recorded
   here and why the donor's total reads as zero for that gift rather than twice over.
7. Open the **Commitments** tab, sort by **Status**, and open an Active monthly commitment.
   Its installments are generated from the schedule and the ones a gift has paid are marked
   Paid. One monthly donor in the set has three installments marked Overdue: that is the
   lapsed recurring donor a fundraiser would want to call this week.
8. Open the **Giving Overview** dashboard. If the numbers are empty, go to **Open Impact
   Settings > Rollups** and select **Recalculate**: the totals are worked out by the rollup
   run rather than as each gift is saved.
9. Return to **Open Impact Settings**, **Sample Data**, and select **Remove Sample Data**.
   Confirm the dialog. The card returns to **Not loaded** and every record the loader
   created is gone: households, contacts, organizations, connections, affiliations, and the
   gifts, allocations, soft credits, tributes, funds, appeals, commitments and installments
   too, along with the household member records that joined people to households if your
   org uses the flexible way. Anything you entered yourself is untouched.

## 4. Common mistakes

- **Loading sample data into a production org.** Sample data is meant for scratch orgs,
  sandboxes, and demos, never for the org your organization runs on day to day. The
  warning on the Sample Data card says so before you confirm; if you see real donor
  records in a report next to "Garcia Family" or "Staff Household," you loaded it by
  mistake. Remove it right away with **Remove Sample Data**, and audit any receipts,
  exports, or emails sent while it was present.
- **Trying to load twice.** Loading again while sample data is already present shows a
  message that it is already loaded. Remove it first if you want a fresh copy. While a
  load is still running, both **Load Sample Data** and **Remove Sample Data** are
  unavailable: removing halfway through would delete households the loader is still
  attaching people to.
- **Assuming removal is instant.** Removal deletes several thousand records with Giving
  installed and takes a few seconds; wait for the card to confirm **Not loaded** before
  assuming it is done.
- **Expecting the giving totals to appear straight away.** The gifts are all there the
  moment the load finishes, but the totals on households, people, funds and appeals are
  worked out by the rollup run. Recalculate from **Open Impact Settings > Rollups**, or wait
  for tonight.
- **Reporting on sample gifts as if the dates were fixed.** Gift dates are counted back
  from the day you loaded the set, so two orgs loaded on different days hold different
  dates. That is deliberate: it keeps "this year" full whenever you load.
- **Expecting sample person accounts in an Agentforce Nonprofit org.** The sample people
  are contacts even where your own people are stored as accounts. That is a limit of the
  sample set, not of households: the households, memberships, names, greetings, and counts
  all work the same way they will with your own records.
- **Not having the permission.** If the **Load Sample Data** button does not appear, you
  are missing **Manage Open Impact Settings**. Ask an administrator to grant it from the
  **Access** page, not from Setup.

## Reference

| What you see | Underlying field or object |
|---|---|
| Sample Data checkbox on households, contacts, and organizations | `Sample_Data__c` on Account and Contact |
| Sample Data checkbox on connections and affiliations | `Sample_Data__c` on `Relationship__c` and `Affiliation__c` |
| Sample Data checkbox on gifts, funds, appeals and commitments | `Sample_Data__c` on `Gift__c`, `Fund__c`, `Appeal__c` and `Commitment__c` |
| The key that ties a sample gift to the person who gave it | `Sample_Data_Key__c` on Account and Contact |
| The join between a sample person and their household, flexible mode only | `Household_Member__c`, removed with the household it belongs to |
| Allocations, soft credits and tributes on a sample gift | Details of the gift, removed with it; they carry no checkbox of their own |
| Installments on a sample commitment | Details of the commitment, removed with it |
| Sample Data settings entry | `Setting_Definition__mdt` record `Sample_Data` |
