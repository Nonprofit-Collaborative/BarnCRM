# Sample data

## 1. What it does

Sample data fills your org with a realistic demo dataset. Use it to see BarnCRM working
with real-looking names and addresses before you import your own list, to train a
new colleague, or to try a setting change (for example a household naming pattern) against
data that already has the variety your real list has. You can remove every sample record in
one action when you are done with it.

Sample data is never loaded for you. Installing or upgrading BarnCRM does not load it, the
Setup Assistant does not load it unless you choose to, and no scheduled job loads it. It
arrives only when someone with the **Manage BarnCRM Settings** permission selects **Load
sample data** (developers' scratch-org scripts load it too, in their own test orgs).

What loads, exactly:

| Records | How many | What is in them |
|---|---|---|
| Households | 200 | Shared surnames, different surnames, hyphenated names, single-person households, ten three-generation households, five with a deceased member, three with a custom name |
| People | 440 | Heads, partners, children, a few with preferred names |
| Organizations | 25 | Local businesses, schools and a college, Rotary clubs, two foundations and a church |
| Connections | 60 | Parents, siblings, friends, colleagues and grandparents in different households, a few marked Former; the other side of each one is created by the connection rules, as it would be for a connection you enter |
| Affiliations | 80 | Board members, employees, volunteers and owners, one primary each, a quarter of them Former |

### With Giving installed

With the **Giving** package installed, the same action also loads:

| Records | How many | What is in them |
|---|---|---|
| Funds | 8 | General Fund plus seven restricted funds, each with an accounting code. None of them is made your default fund. If your org already has a default fund (a new org starts with its own **General Fund**), the sample General Fund is not created and the gifts meant for it go to your fund, so you never have two funds of that name. Removing sample data deletes only funds, gifts and other records the set created; your own fund stays |
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

### With Volunteers installed

With the **Volunteers** package installed, the same action also loads, after Giving if it is
there:

| Records | How many | What is in them |
|---|---|---|
| Skills | 4 | First aid, Spanish, Forklift and Gardening, with the jobs that ask for them |
| Jobs | 3 | Food pantry sort, Front desk and Community garden, each with a description and a location |
| Shift schedule | 1 | **Saturday sorting**, every Saturday morning for the pantry. Like any schedule, it creates its shifts as far ahead as the **Shift horizon weeks** setting says |
| Shifts | 16, plus the schedule's | A morning shift for each job in each of the last four weeks, marked Completed, and four upcoming shifts on the front desk and in the garden |
| Sign-ups | 44 | Three people attended each past shift; two are booked on each upcoming shift, one Confirmed and one Signed up |
| Hours | 60 | One entry for each attendance and one garden entry for each of 24 sample people. The newest four wait for approval, the next two are Rejected with a reason, and the rest are Approved |
| Volunteer skills | 24 | One skill or interest on each of the 24 people |
| Requirements | 8 | Six completed background checks and two orientations in progress |

The hours get their statuses the way a coordinator gives them, so loading needs the **Manage
Volunteers** permission (Volunteers Admin includes it). Without it the hours keep the status
they were saved with: Submitted, or Approved when **Hours Require Approval** is off.

The set does not generate a letter, because a letter is a file. To see one, open any sample
volunteer with Approved hours and use the **Volunteer letter** action with the shipped Hours
letter template ([Hour letters and certificates](volunteers.md#hour-letters-and-certificates)). Remove the file yourself afterwards: it is yours, not the
loader's.

## 2. How to turn it on

1. Open **BarnCRM Settings**.
2. In the **General** section, find **Sample Data** and open it. If you do not see it,
   type "sample" in the settings search box.
3. Read the warning, then select **Load sample data**.
4. Confirm in the dialog. Loading runs in the background; the card shows progress and
   updates automatically until it finishes. With Giving installed there are several
   thousand records to write, so allow a few minutes rather than one. The load runs as
   background batch jobs (Setup > Apex Jobs lists them as SampleDataStageBatch), one step
   at a time, so it finishes in any org, Developer Edition, trial and scratch orgs included.
   If a step stops on an error, the load stops there: the card shows what did load, the
   error is in the [Error Log](error-log.md), and **Remove sample data** clears it for
   another try.
5. With Giving installed: when it says **Loaded**, give the totals a few minutes. Giving
   totals (total giving, this year, largest gift, fund and appeal totals) are shipped in
   **Both** mode, so they are worked out in the background queue as the gifts are saved, and
   a bulk load like this one catches up within minutes. If a total is still empty after that,
   open **BarnCRM Settings > Rollups** and select **Recalculate**; the nightly run would also
   correct it tonight.

If you came here from the Setup Assistant, the same **Sample data** step takes you to
this screen. Loading sample data is entirely optional; skipping it does not block any
other step.

You need the **Manage BarnCRM Settings** permission to load or remove sample data.
Without it, the card is read only and tells you who to ask.

Sample data loads whichever way your org tracks household membership. In the simple way,
each sample person carries their household on their own record. In the flexible way (one
membership record per person, which every org with Person Accounts uses), each sample person
is joined to their household by a household member record, exactly as your own people are,
and the card says so before you load.

One difference to expect in an org that stores people as accounts: the sample people arrive
as contacts. BarnCRM never creates person accounts, so the sample set shows you
households of contacts. Everything else behaves as it will with your own data: the same
household records, names, greetings, member counts, and Members panel.

## 3. A five-minute walkthrough (as Maria)

1. Open **BarnCRM Settings**, go to **Sample Data**, and select **Load sample data**.
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
6. With Giving installed, open the **Gifts** tab and sort by amount. Open the largest gift and look at its
   allocations: most gifts sit in one fund, some are split across two. Then filter the list
   view by **Status** equals Refunded to find the refunded gift, and open it: its own amount
   is unchanged and a linked negative gift reverses it, which is how a refund is recorded
   here and why the donor's total reads as zero for that gift rather than twice over.
7. With Giving installed, open the **Commitments** tab, sort by **Status**, and open an Active monthly commitment.
   Its installments are generated from the schedule and the ones a gift has paid are marked
   Paid. One monthly donor in the set has three installments marked Overdue: that is the
   lapsed recurring donor a fundraiser would want to call this week.
8. With Giving installed, open the **Giving Overview** dashboard. If the numbers are empty, go to **BarnCRM
   Settings > Rollups** and select **Recalculate**: the totals are worked out by the rollup
   run rather than as each gift is saved.
9. Return to **BarnCRM Settings**, **Sample Data**, and select **Remove sample data**.
   Confirm the dialog. The card shows **Removing** while it deletes the set in steps of
   about a hundred records, the same way it loaded, then returns to **Not loaded**. Every
   record the loader created is gone: households, contacts, organizations, connections, affiliations, and the
   gifts, allocations, soft credits, tributes, funds, appeals, commitments and installments
   too, along with the household member records that joined people to households if your
   org uses the flexible way. With Volunteers installed, its jobs, skills, schedule, shifts,
  sign-ups, hours, volunteer skills and requirements go first: Approved sample hours are
  reopened, then deleted, because an Approved entry cannot be deleted as it is. Anything you
  entered yourself is untouched; where it hangs off a sample job, shift or skill, that sample
  record stays too, the rest of the set is still removed, and one Warning in the
  [Error Log](error-log.md) names each sample record kept and why (see Common mistakes below).
  While a kept sample record is left, the card shows **Loaded** rather than **Not loaded**, so
  **Remove sample data** stays offered for when you have dealt with them.

## 4. Common mistakes

- **Loading sample data into a production org.** Sample data is meant for scratch orgs,
  sandboxes, and demos, never for the org your organization runs on day to day. The
  warning on the Sample Data card says so before you confirm; if you see real
  records in a report next to "Garcia Family" or "Staff Household," you loaded it by
  mistake. Remove it right away with **Remove sample data**, and audit any receipts,
  exports, or emails sent while it was present.
- **Trying to load twice.** Loading again while sample data is already present shows a
  message that it is already loaded. Remove it first if you want a fresh copy. While a
  load or a removal is still running, both **Load sample data** and **Remove sample data**
  are unavailable: removing halfway through would delete households the loader is still
  attaching people to.
- **Installing a module after loading sample data.** A load brings in the sample data of the
  modules installed at the time, so a module installed afterwards (Giving or Volunteers, for
  example) has none, and **Load sample data** refuses with the message that sample data is
  already loaded. Select **Remove sample data**, wait for **Not loaded**, then **Load sample
  data** again: the new load includes every module installed now.
- **Assuming removal is instant.** Removal deletes several thousand records with Giving
  installed and takes a minute or two; wait for the card to confirm **Not loaded** before
  assuming it is done. If it stops part way, a notification says so and the Error Log says
  why; deal with what it names, then select **Remove sample data** again to finish it.
- **Reading an Error Log entry from a load or removal that stopped.** The entry names the step
  that stopped, and its technical detail says what failed (for example, a validation rule or
  a required field your org added that refused a sample record). Fix or relax what it names,
  then finish: after a stopped removal, select **Remove sample data** again; after a stopped
  load, remove what loaded, then load again.
- **Expecting the giving totals to appear straight away (with Giving).** The gifts are all there the
  moment the load finishes, but the totals on households, people, funds and appeals are
  worked out in the background queue, which catches up within minutes. If they are still
  empty after that, Recalculate from **BarnCRM Settings > Rollups**, or wait for tonight.
- **Reporting on sample gifts as if the dates were fixed (with Giving).** Gift dates are counted back
  from the day you loaded the set, so two orgs loaded on different days hold different
  dates. That is deliberate: it keeps "this year" full whenever you load.
- **Expecting sample person accounts in an org that stores people as accounts.** The sample people
  are contacts even where your own people are stored as accounts. That is a limit of the
  sample set, not of households: the households, memberships, names, greetings, and counts
  all work the same way they will with your own records.
- **Recording your own people on sample jobs, shifts or skills (with Volunteers).** Removal
  takes only the hours, sign-ups and volunteer skills of sample people. Hours you recorded for
  a real person on a sample job stay, and so does a sample shift a real person is signed up
  for or has hours on, with that sign-up, and that job. A real person given a sample skill
  keeps it, and so does a job of your own that asks for one, so that skill stays too. Removal
  keeps only those sample records and removes everything else, Core's and Giving's sample data
  included. The Error Log then holds one Warning naming each one kept and why, for example
  "Sample data removal kept the sample shift Front desk: 13 Oct 2026 because Rita Real has
  hours and a sign-up on it." Move those hours, sign-ups and skills to a job, shift or skill
  of your own (or delete them), then select **Remove sample data** again: the card still shows
  **Loaded** while a kept sample record is left, and the second removal takes what is no longer
  in use. When more than 200 of your own records of one kind (sign-ups, hours, volunteer skills
  or job skills) point at sample data, the Warning may not name every kept record; nothing of
  yours is deleted either way, and running the removal again after you move them logs a new
  Warning naming whatever is still kept.
- **Not having the permission.** If the **Load sample data** button does not appear, you
  are missing **Manage BarnCRM Settings**. Ask an administrator to grant it from the
  **Access** page, not from Setup.

## Reference

| What you see | Underlying field or object |
|---|---|
| Sample Data checkbox on households, contacts, and organizations | `Sample_Data__c` on Account and Contact |
| Sample Data checkbox on connections and affiliations | `Sample_Data__c` on `Relationship__c` and `Affiliation__c` |
| Sample Data checkbox on gifts, funds, appeals and commitments (with Giving) | `Sample_Data__c` on `Gift__c`, `Fund__c`, `Appeal__c` and `Commitment__c` |
| Sample Data checkbox on volunteer jobs and skills (with Volunteers) | `Sample_Data__c` on `Volunteer_Job__c` and `Skill__c`; shifts, schedules, sign-ups and hours are found through their job |
| The key that ties a sample gift to the person who gave it | `Sample_Data_Key__c` on Account and Contact |
| The join between a sample person and their household, flexible mode only | `Household_Member__c`, removed with the household it belongs to |
| Allocations, soft credits and tributes on a sample gift | Details of the gift, removed with it; they carry no checkbox of their own |
| Installments on a sample commitment | Details of the commitment, removed with it |
| Sample Data settings entry | `Setting_Definition__mdt` record `Sample_Data` |
