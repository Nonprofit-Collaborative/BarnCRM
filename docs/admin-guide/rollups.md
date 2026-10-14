# Rollups

## What it does

Rollups are the totals that appear on a household, a person, an organization, or another
record without anyone adding them up: a count, a sum, a first or last date, a largest
value. BarnCRM Core runs the rollup engine; the totals themselves are shipped by the
modules that own the records being counted, and with the Giving module installed they
include total giving, gift counts and dates, pledge balances and what a fund and an appeal
have raised.

The member count on a household is not one of them. It looks like a rollup and it is kept
up to date for you, but it is maintained by the household automation every time somebody
joins or leaves, so it is not on the Rollups page and Recalculate does not touch it. If a
member count looks wrong, the Households page is where to fix it.

BarnCRM calculates them for you and shows you when each one was last calculated, so
you never have to guess whether a number on a record is current. If the calculation has
not run recently, the BarnCRM home page says so rather than leaving a stale number
looking fresh.

## What BarnCRM calculates for you (with Giving)

This section applies only when the Giving module is installed. Core on its own ships no
totals, so its Rollups page lists only rollups you add yourself.

Every total below is created when you install the module that owns it, switched on and
ready to calculate, and every one of them can then be switched to another mode, made
inactive, or recalculated on its own. Three of the giving totals exist once for each kind of record, because a household,
an organization or person account, and a person each reach their gifts differently. You see the household one on a household, the account one
on an organization, and the contact one on a person, so on any one record there is a
single number.

**On a household, an organization, and a person**

| Total | What it counts |
|---|---|
| Total giving | Every gift received from this donor. |
| Gift count | How many gifts this donor has given. A gift that was later refunded still counts as one gift. |
| First gift date | The date of the donor's first gift, which is what new donor reporting counts from. |
| Last gift date | The date of the donor's most recent gift, which is what lapsed donor reporting counts from. |
| Largest gift | The largest single gift this donor has given. |
| Giving this year | Given in the fiscal year you are in now. |
| Giving last year | Given in the fiscal year before it, which is the LY in LYBUNT. |
| Giving two years ago | Given the year before that, used by SYBUNT and retention reporting. |
| Pledge balance | Promised and not yet paid. |
| Total soft credits | What this donor is recognized for without being hard credited. |
| Soft credit count | How many gifts this donor is recognized on. |
| In-kind value | What this donor's gifts of goods and services were worth. Never added into total giving. |
| In-kind gift count | How many gifts of goods and services this donor has given. |

**On a fund, an appeal, a pledge, and a scheduled payment**

| Record | Total | What it counts |
|---|---|---|
| Fund | Total raised | Everything ever designated to this fund. |
| Fund | Total raised this year | Designated to this fund in the fiscal year you are in now. |
| Fund | Gift count | How many gifts have been designated to this fund, counting a gift once even if it was later refunded. |
| Fund | Last gift date | The date of the most recent gift to this fund. |
| Appeal | Total raised | What this appeal brought in. |
| Appeal | Gift count | How many gifts responded to this appeal. |
| Commitment | Paid to date | What has been paid against this pledge or recurring gift. |
| Installment | Paid amount | What has been paid against this scheduled payment. |

Four things are true of all of them, and they explain most of the questions staff ask
about a number that looks wrong:

- **A pending gift is not in any total.** A promise is not money, so a gift counts only
  once its status is Received, Refunded, or Written off: the three statuses that mean the
  money actually moved. Refunded and Written off are in that list on purpose, and the next
  point says why.
- **A refunded gift stays in the count and leaves the total.** BarnCRM records a
  refund as a second gift for a negative amount rather than editing or deleting the
  original, so the two cancel out. A donor who gave $250 and had all of it back shows
  **1 gift** and **$0 total giving**. That is deliberate: they did give, once, and the
  organization is holding none of it. The consequence is that dividing total giving by
  gift count is not a meaningful average gift for a donor with refunds. A gift recorded at
  $0 is not counted either.
- **In-kind gifts are in none of the money totals.** A gift of goods carries no amount, so
  it adds nothing to total giving, to a gift count, to a fund or appeal total, or to a
  donor level. It has two totals of its own, In-kind value and In-kind gift count, kept by
  this same engine. Total giving is cash and in-kind value is goods: two answers to two
  questions, not two halves of one. See [In-kind gifts](in-kind-gifts.md).
- **Soft credits are never added into a giving total.** A soft credit is recognition, not
  money the organization received, so it is counted only in Total soft credits and Soft
  credit count. If it were in Total giving as well, every household gift would be counted
  twice.
- **The year based totals use the gift date.** Which fiscal year a gift lands in is
  decided by its **Gift Date**, not by the day it was entered, so a December gift entered
  in January still counts in the right year.

## How to turn it on

Most of it is already on. Installing a module creates its rollups, active and ready to
calculate (with Giving, the giving totals), and an upgrade adds anything newly shipped
without touching a rollup you have changed. An org with Core alone starts with no shipped
totals.

One step is left for you, and nothing in the app does it on your behalf:

1. Open the **BarnCRM** app and choose the **BarnCRM Settings** tab.
2. Choose **Rollups** in the left navigation. You should see every total listed above, one
   row each.
3. Click **Schedule nightly recalculation**. The page then shows "Nightly recalculation
   is scheduled for 2:00 AM."

Do that on the day you install. The Setup Assistant has no rollup step, so until you click
it nothing recalculates overnight and the home page tile stays in warning.

### If a rollup is missing

**Restore shipped rollups** at the top of the page creates the shipped rollups this org
does not have and leaves every other rollup exactly as it is, including ones you have
edited or switched off. A shipped rollup whose target field one of your own active rollups
already writes is not created, so the two never overwrite each other's total. Press it if the page is empty on a fresh install, which means the
install-time step failed and the Error Log will say why, or if a rollup you need is not
listed.

It is also the reason to switch a rollup off rather than delete it. BarnCRM cannot
tell a rollup you deleted on purpose from one that has never existed, so a deleted rollup
comes back the next time the package is upgraded or the next time somebody presses this
button. Clearing the **Active** box is the durable way to say no to a total: an inactive
rollup stays inactive across every upgrade, and the values it has already calculated stay
on the records.

Three settings on the same page change how every rollup behaves:

- **Fiscal year start month** decides where "this year", "last year", and "two years ago"
  begin. Choose the month your fiscal year starts from the list. Changing it and clicking
  **Recalculate all** corrects every year based total in **Every night** or **Both** mode,
  which is every year based total the Builder saves (see
  [What the Builder will not save](#what-the-builder-will-not-save)).
- **Default rollup mode** decides how a newly created rollup starts out: **Instantly**,
  **Every night**, or **Both (recommended)**. The next section says what each one means.
- **When instant totals are calculated** decides when a save updates the totals in
  **Instantly** and **Both** mode. See [Just after the save, or during
  it](#just-after-the-save-or-during-it) below.

You need the **Manage BarnCRM Settings** permission to change any of this. Without it,
the Rollups page still opens and still shows every total and its last calculated time; the
controls are simply read only.

## When a total is recalculated: the three modes

Every rollup has a mode.

| Mode | What happens |
|---|---|
| **Instantly** | A gift saved by a person updates the totals a few seconds after the save: refresh the household a moment later and its total giving already includes it. A bulk change (an import, a data loader run, a big update) goes through the same queue and catches up within minutes, also when many batches or people save at the same moment. A change made by a background job is also queued, and the queue run starts as soon as that job's step is saved, so those totals catch up within minutes too. If that start fails, the next queue run or the nightly run picks them up. |
| **Every night** | Recalculated in the nightly run at 2:00 AM, and when you click **Recalculate**. A gift entered this afternoon shows up tomorrow morning. |
| **Both (recommended)** | Instantly, and checked again every night. The nightly run is the safety net: if anything was missed during the day (an automation switched off, a record changed while automation was paused), the next morning's numbers are right. Every shipped total uses this mode. |

"Instantly" needs BarnCRM to see the change as it happens. It does for gifts, pledges and
other BarnCRM records. For a total that counts records from one of your own objects, see
[Instant totals on your own objects](#instant-totals-on-your-own-objects) below;
without that, such a total is calculated every night and on demand only.

A save recalculates only the totals its change can move. Saving a soft credit recalculates the
soft credit totals on that person and household, not their gift or pledge totals, and an
**Every night** total waits for the nightly run even when a record it counts is saved.

### Just after the save, or during it

**When instant totals are calculated** has two choices:

- **Just after the save (recommended)**, the default. The save notes which households,
  people, organizations, appeals, funds and pledges it changed, and returns. BarnCRM
  recalculates them in the background a few seconds later, usually within a minute. Every
  save stays fast, and a save can never fail because the rollups ran out of room: with the
  shipped totals, recalculating a gift's totals takes more than half of what one save is
  allowed to do.
- **During the save**. A normal save recalculates its totals before it returns, so the totals
  are already right when the page refreshes. Each gift save is slower. When a save has too
  little room left (because your own Flows or triggers on gifts already used most of it), or
  is a bulk change, its totals are queued instead, just as with the first choice.

Either way the numbers end up the same: every total is recalculated from all of its records,
never added to. Choose **During the save** only if your team relies on seeing a total change
the moment a gift is saved and your org has little automation of its own on gifts.

### How the nightly run works

The nightly run, **Recalculate** and **Recalculate all** work
through every record a rollup writes, one kind of record at a time (all accounts, then all
contacts, then all funds), and calculate all of a record's totals together:

- **A record is saved only when one of its totals changed.** Its **Rollups last calculated**
  time then moves to the time of that run. A record whose totals were already right is not
  saved, so it keeps its earlier time: the run checked it and found nothing to change. The
  **Last calculated** time on the Rollups page is what tells you the run happened.
- **The Rollups page marks a rollup calculated when the whole run has finished**, not when it
  starts. When the page shows a time, the totals from that run are already on the records.
- **Records with a very large number of gifts are calculated separately.** A catch-all
  donor such as "Anonymous" is calculated on its own after the others, so it cannot hold up
  everyone else's totals.
- **A record that cannot be saved is tried again.** If someone was editing it, or a
  validation rule refused it, BarnCRM tries again automatically; after five tries it waits
  in the **Needs attention** list. The next nightly run that saves it takes it off the list.
- **A part of the run the platform stops is tried again.** If Salesforce stops a group of
  records part way (for example because they had more gifts than one step can read), those
  records go to the queue and are recalculated within minutes, not left until the next night.
- **One full run at a time.** If you click **Recalculate all** or **Recalculate** while a run
  is still going (for example the nightly run), nothing new starts and the page says "A full
  recalculation is already running. Its totals will be on the records when it finishes, so
  try again after that." The nightly run does the same when a run you started is still going.
- **A run does nothing while all automation is paused.** The next night catches up.
- **If anything could not be saved, one summary goes to the Error Log**, so the Hub's error
  tile shows it.

## What a rollup can calculate

Each rollup has a **calculation**, and the calculation decides what kind of field can show
the result. BarnCRM refuses to save a rollup whose field cannot hold its result, and says
which kind of field to choose instead. That check is the **Check rollups before saving**
automation on the **Automation** page; if it is switched off, such a rollup still saves, but
BarnCRM skips it on every run and the Error Log says why.

| Calculation | What it gives you | Shown in |
|---|---|---|
| **Sum**, **Average** | The total or the average of a number or an amount. | A number, currency or percent field |
| **Minimum**, **Maximum** | The smallest or largest value, for example the largest gift or the latest date. | A number, currency, percent or date field |
| **Count** | How many records match. | A number field |
| **Count distinct** | How many different values a field holds, for example how many different funds a donor has given to. Blank values are not counted. | A number field |
| **First**, **Last** | The value from the earliest or latest record, by the field you choose to order by, for example the appeal of a donor's first gift. | A number, currency, percent, date or text field |
| **Any** | Checked when at least one record matches, for example "has ever given a gift over $1,000". | A checkbox field |
| **None** | Checked when no record matches, for example "has no open pledge". | A checkbox field |
| **Text list** | Every matching value in one field, for example the names of every program a person volunteers for. Blank values are left out. | A text or long text field |
| **Text list, each value once** | The same, with each value listed once. | A text or long text field |

What to know about them:

- **Any and None count the records your conditions describe.** They do not read a field of
  their own. For "has ever given a gift over $1,000", choose **Any** and the condition
  "Amount greater than 1000".
- **A text list is separated by a comma, a semicolon, or a new line.** Choose one with
  **Delimiter**; a comma is used when you choose nothing. A value that contains the
  separator is not changed, so if your values contain commas (for example "Smith, Jane"),
  choose a semicolon or a new line so the list still reads clearly. A new line suits a long
  text field.
- **A text list is in order.** If you choose a field to order by, the values follow it,
  oldest or smallest first. Otherwise they are listed alphabetically.
- **A text that is too long is cut.** A list longer than the field holds is cut at the
  field's length, so a 255 character field shows the first 255 characters. Use a long text
  field for a list that can grow.
- **Each value once means exactly once.** "Gold" and "gold" are two different values to
  **Text list, each value once** and to **Count distinct**.
- **First and Last take the first record even when its value is blank.** Add the condition
  "is not blank" on that field if you want the first record that has one. When two records
  share the same order value, the one with the lower record ID wins (usually the one created
  first), so the answer never changes from one run to the next.
- **A number or date copied into text is written plainly**, for example `1250.00` or
  `2026-03-01`, without a currency symbol or your local date format. A date and time is
  written in UTC, for example `2026-03-01 14:05`, so it reads the same whoever saved the
  record.
- **They stay right as records change.** Like every rollup, these are worked out again from
  all the matching records each time, so a deleted record, a record moved to another parent,
  or a value changed back is reflected the next time the total is calculated, whatever its
  mode.

## The Rollup Builder

The **Rollup Builder** tab in the **BarnCRM** app is where you create a new total and edit any
existing one, shipped or your own, without typing a query. It lists every rollup with the same
controls as the Rollups page (mode, active, **Recalculate**, the nightly schedule and
**Recalculate all**), and adds **New rollup**, and **Edit** and **Copy** on each row. The tab
comes with the **BarnCRM Admin** permission set, and saving needs the **Manage BarnCRM
Settings** permission. The Rollups page in BarnCRM Settings links to it.

**Copy** is the quickest way to make a total like one you already have: it opens the Builder
with everything filled in from that rollup, under a new name, for you to change. Editing a
shipped rollup is fine: an upgrade never overwrites a rollup you have changed.

The Builder walks you through five steps. **Next** checks the step you are on, and says what
to change, before it lets you go on.

1. **Where should the number appear?** The kind of record and the field that show the total.
   Only fields BarnCRM can write are offered: numbers, amounts, percents, dates, checkboxes
   and text. A field another active rollup already fills is marked with that rollup's name. If
   the field does not exist yet, create it in Setup (a Number or Currency field is right for
   most totals) and come back.
2. **What should be counted?** The records that feed the total and the field that links them
   to the record from step 1, in plain words: "Gift, by Donor". When the total lands on an
   account and the records point at a person, you can also choose that person's household,
   for example "Gift, by Donor (their household)".
3. **How should it be calculated?** Any calculation in
   [What a rollup can calculate](#what-a-rollup-can-calculate) that the field from step 1 can
   hold, the field it reads, for First and Last the field that decides which record comes
   first, and the time window: all time, this fiscal year, last fiscal year, or two fiscal
   years ago, with the date that decides which year a record falls in (a date field, not a
   date and time field).
4. **Which records count?** Conditions you pick from lists (a field, a comparison and a
   value), read back as a sentence: "Gifts whose Status is Received, Refunded or Written off".
   Add a condition for each thing that must be true; to mix "and" and "or", type the
   condition numbers in **Combine conditions**, for example `1 AND (2 OR 3)`. **Only for
   some records** holds the same kind of conditions on the record that shows the total, for
   two rollups that fill one field for different records. The comparisons **is this year** and
   **is last year** in a condition mean the calendar year (January to December); for your fiscal
   year, use the time window in step 3. **Contains** and **starts with** match what you type
   exactly, so `%` and `_` are ordinary characters.
5. **Check and save.** The whole rollup read back as one sentence. Pick a real record to see
   what the total would be next to what the record shows now, and how many records the
   rollup will maintain. Then give it a name, choose its mode, and click **Save**, or **Save
   and calculate now** to start its recalculation straight away.

### What the Builder will not save

It says what to change instead of saving:

- A rollup with no name, or no field to show it.
- A field BarnCRM cannot write, such as a formula.
- A calculation the field cannot hold, for example a sum into a checkbox. The message says
  which kind of field to choose.
- A sum or average of something that is not a number or an amount, and a minimum or maximum
  of something that is not a number, an amount or a date.
- First or Last without the field that decides which record comes first.
- A fiscal year window without a date to measure it on, or measured on a date and time field.
  Choose a date field, such as the gift date.
- An **Instantly** total with a fiscal year window, or with an **is this year**, **is last year** or
  **is in the last N days** condition. Such a total changes when the date moves on, with no record
  saved, so only the nightly run can keep it right. Choose **Both (recommended)** or **Every
  night**. Changing the mode on the Rollups list refuses it too.
- Conditions that name a field the records do not have.
- A field another active rollup already fills for some of the same records. Two rollups may
  fill one field only when their **Only for some records** conditions never pick the same
  record, as the household and the organization giving totals do. The Builder checks your
  records, and says which rollup it overlaps.

### When your org uses more than one currency

The Builder warns you on step 3:

- On a total of amounts into a currency field: "This org uses more than one currency. Totals
  are converted to each record's currency at today's rates, not the rate on the gift date."
- On a total of amounts into a number field: "This field is a number, not a currency, so the
  total is shown in the corporate currency."

After changing exchange rates, recalculate your money totals to bring them up to date.

### Needs attention

Under the list, **Needs attention** shows what the engine has not finished:

- **Records waiting**, for example "1,204 records waiting, oldest 3 minutes ago". These are
  totals from recent saves and bulk changes, queued and calculated within a minute or a few.
  Nothing to do unless the oldest is more than an hour old, which Health Check also reports.
  Then click **Start now** to recalculate them now; the nightly run also picks them up.
  A long queue is worked through in a series of background runs. Salesforce limits how long
  such a series may be (five runs in Developer Edition, trial and scratch orgs), so at that
  point BarnCRM starts a fresh series. Nothing to do.
  A record with a very large number of gifts or allocations behind its totals (a General Fund
  most gifts go to, an organization with tens of thousands of gifts) has more rows than one
  background run may read. BarnCRM recalculates such a record in a separate background job that
  reads its rows a few thousand at a time, so its totals take a few minutes rather than seconds.
  One such job runs at a time. A record a single run can still read stays in the queue.
  While that job runs, the record shows among the records waiting. Nothing to do. If a run ever
  stops partway (often an automation of yours failing on one record), the records it was
  working on are counted as one try and retried in ever smaller groups, then one at a time,
  while the rest of the queue carries on. Only the record that keeps stopping its run appears
  under **Could not be saved**, after five tries.
- **Could not be saved**: each record whose totals failed five times, with a link to it,
  what went wrong in plain words, when, and how many tries. Fix the cause (often a validation
  rule or a record someone was editing), then click **Retry** for the ones you selected, or
  **Retry all**. They go back in the queue and are tried within minutes. The next nightly run
  that saves a record also takes it off the list.
- A warning when the nightly run is not scheduled, and how the last full run ended.

### Recalculate all, now or tonight

**Recalculate all** rebuilds every active rollup, whatever its mode: **Instantly** totals as
well as **Every night** and **Both** ones. The nightly run covers only **Every night** and
**Both**, because each save already keeps an **Instantly** total right; **Recalculate all** is
for when you want every total rebuilt from scratch, for example after loading data with
automation paused.

Before **Recalculate all** starts, the Builder says how many records it will go through and
roughly how long that takes, for example "About 41,200 records, roughly 25 minutes." The count
includes the records of every active rollup, **Instantly** ones too. During working hours
(8 AM to 6 PM, Monday to Friday, in your time zone) it suggests running it tonight instead,
because a long run competes with people saving records. When the nightly run is not
scheduled, **Run tonight** sets up a single run of every active rollup for 2:00 AM tonight.
When it is scheduled, **Run tonight** adds nothing: the nightly run already recalculates the
**Every night** and **Both** totals at 2:00 AM, and a second run at the same moment would
only be turned away. To rebuild the **Instantly** totals as well, choose **Start now**.

## Instant totals on your own objects

BarnCRM can only ship automation for its own records. A rollup that counts records from an
object your organization created (for example volunteer hours on a custom Shift object) is
calculated every night and when you click **Recalculate**, until you make it instant. Today
the way to do that is the **Recalculate rollups** Flow template, which needs no code.

### With the Flow template

1. In Setup, open **Flows** and find **Recalculate rollups (template)**. Open it and click
   **Save As**, choosing **A New Flow**, so you have a copy of your own. The template itself
   is never active and an upgrade may change it; your copy is yours.
2. In your copy, open the **Start** element and change the object from **Contact** to your
   object, for example **Shift**. Leave it on **A record is created or updated** and
   **Actions and Related Records**. Leave its entry condition as it is: the formula is met by
   every saved record, so no change a rollup depends on is missed.
3. Open the **Recalculate rollups** action and set its object to the same object. Leave
   **Record** set to the triggering record and **Record before the change** set to the
   prior values of the triggering record.
4. Save and activate.

What to know:

- **Every rollup that counts that object is kept up to date**, instantly or queued for a
  minute or two exactly as for BarnCRM's own records: one flow per object, however many
  rollups count it.
- **A record moved to another parent** leaves the old total and joins the new one, because
  the action is given the record as it was before the change.
- **A deleted record** is not seen by this flow. Either keep such rollups in **Both
  (recommended)**, so the nightly run removes it, or make a second copy that starts when **A
  record is deleted** and set the action's **Record is being deleted** to true. That copy
  puts the totals in the queue, and they are right a minute or two after the delete.
- **A record restored from the recycle bin** is never seen by a flow, so keep such rollups in
  **Both (recommended)**.
- **Pausing all automation** stops the action as well; the nightly run catches up.

### One click (coming)

The Rollup Builder will offer to make such a total instant by adding a small piece of
automation for you:

- One click deploys a one-line trigger on your object and a test for it. The trigger only
  tells BarnCRM which records changed; how the total is calculated stays in the rollup, so
  editing the rollup later never changes the code.
- It runs only its own test while deploying, so tests elsewhere in your org that already
  fail do not block it. If the deploy does fail, the Builder says why in plain words and what
  to do next.
- You need the **Customize Application** and **Modify All Data** permissions and the
  BarnCRM permission to deploy rollup triggers, and you authorize the connection once. If you
  do not have them, the Builder says "Ask a Salesforce admin, or use the Flow template."
- Try it in a sandbox first. The trigger has the same name in every org, so moving it to
  production with a change set gives the same result as deploying it from the Builder there.
- When you remove the last rollup on that object, the Builder offers to remove the trigger
  too. Health Check reports a BarnCRM trigger that no rollup uses any more. Remove these
  triggers before uninstalling BarnCRM.

If you prefer no code in your org, the Flow template above does the same job.

## Current limits

Fund totals and soft credit totals, including a household's soft credit totals, now update
instantly like every other giving total: saving a gift allocation or a soft credit moves them,
and so does changing a gift's status or deleting a gift. What is not here yet:

- **One-click instant totals on your own objects** are coming. Until then, use the
  [Flow template](#with-the-flow-template); without it, a rollup that counts records from an
  object your organization created is calculated every night and when you click
  **Recalculate**.
- **The Builder cannot create a field.** Create it in Setup first, then pick it in step 1.
- **BarnCRM is checked against its previous rollup engine** before that engine is removed
  from the package. A developer runs the comparison on a test org; it changes nothing in your
  data.

## A five-minute walkthrough

Do this as Maria, with the sample data loaded. Steps 2 to 5 use the giving totals, so they
need the Giving module; with Core alone, do them on a rollup you have added.

1. Open the **BarnCRM** app. On the home page, find the **Rollups** tile. It reads
   "Rollups last completed" with a time. If it has been more than 36 hours, the tile turns
   into a warning and offers a link to the Rollups page. Click that link, or open
   **BarnCRM Settings** and choose **Rollups**.
2. You are looking at every total the rollup engine maintains, a little over forty rows.
   Each row says what the number means in plain language, what it counts ("Sum Amount__c
   on Gift__c", or for a text list "Text list Name on Program__c, separated by semicolon"),
   where it shows ("Account.Total_Giving__c"), its mode, and when it was
   last calculated. The names begin with the kind of record the number lands on, so
   **Household total giving**, **Account total giving**, and **Contact total giving** sit
   next to each other.
3. Find **Household total giving** and change its **Mode** from **Both (recommended)** to
   **Every night**. The change saves as you make it and the row shows the new mode. That total will now be recalculated
   in the nightly run rather than the moment a gift is saved. Change it back to **Both
   (recommended)** when you have looked at it; it is the setting that keeps the number
   visibly right.
4. Click **Recalculate** on that row. The page says "Recalculation started" and the row's
   last calculated time moves to a moment ago when the run finishes. **Recalculate all**
   at the top does the same for every active rollup at once, **Instantly** ones included.
5. Open any household record. Its giving totals now match what you just recalculated. If
   any of them changed, the **Rollups last calculated** field on the record shows the time
   of that run; if none did, it keeps its earlier time, because the run found nothing to
   change. That field is
   the answer to "is this number current" for one record; the Rollups page answers it for
   the whole org.
6. Go back to the BarnCRM home page. The Rollups tile shows the time you just recalculated.

## Common mistakes

**Typing over a total by hand.** The totals are calculated fields, and so is the
member count, though that one is maintained by the household automation rather than here. If you edit one on a record, the next calculation overwrites what you typed and
your change disappears without a message. If a total looks wrong, the records behind
it are wrong; fix those and recalculate. If you need a number the rollups do not
calculate, add your own field rather than borrowing one of these.

**Expecting a soft credit to show in total giving (with Giving).** It never will. A spouse recognized on
a household gift has it in **Total soft credits**, and the person who actually gave has it
in **Total giving**. Adding the two together double counts the gift, which is why they are
two numbers and not one. Report on whichever answers your question, and say which one you
used.

**Expecting a nightly total to change immediately.** A rollup in **Every night** mode is
recalculated once a night, so a record entered this afternoon does not move it until
tomorrow morning. That is what the last calculated time is there to tell you. If a total
needs to be right the moment a record is saved, set it to **Instantly** or **Both
(recommended)**.

**Expecting the total on the page the instant you click Save.** By default, Instantly and
Both totals are recalculated a few seconds after the save, so the donor's page you are looking
at may still show the old total. Refresh it a moment later. If your team needs the total in
the save itself, change **When instant totals are calculated** to **During the save** (see
[Just after the save, or during it](#just-after-the-save-or-during-it)).

**Expecting an import's totals the moment it finishes.** Totals from a bulk change are
queued and catch up within minutes, not in the same instant. Give it a few minutes before
checking. If a number still has not moved, look at **Needs attention** in the Rollup Builder,
which shows how many records are still waiting and which could not be saved.

**Switching off a rollup automation and forgetting it (with Giving).** Instantly and Both
work because Giving runs an automation each time a gift, a commitment, a gift allocation or
a soft credit is saved. They are listed on the **Automation** page as **Update rollups when
a gift changes**, **Update rollups when a commitment changes**, **Update rollups for gift
allocations** and **Update rollups for soft credits**. Switching one off,
or pausing all automation for a data load, leaves the totals it feeds where they were. A
rollup in **Both (recommended)** mode is put right by the nightly run; one in **Instantly**
mode stays behind until you click **Recalculate** on its row. Switch the automation back on
afterwards.

**Turning a rollup off and expecting the number to clear.** Setting a rollup to inactive
stops it being recalculated; it does not erase the values already on the records. That is
deliberate, so that turning something off never destroys data. If you want the field
empty, clear it after you make the rollup inactive.

**Deleting a rollup you do not want.** Deleting it works until the next upgrade, which
creates it again, because a rollup that is gone is indistinguishable from one that was
never created. Clear its **Active** box instead. That is remembered, and it leaves the
numbers already calculated on the records.

**Never starting the nightly schedule.** If nobody clicks **Schedule nightly
recalculation**, nothing recalculates overnight and the home page tile stays in warning. Nothing
schedules it for you. The tile is the only warning you get, so act on it.

**Changing the fiscal year start month and stopping there.** The year based totals are
recalculated with the new fiscal year at the next run, not the moment you save the
setting. After changing it, click **Recalculate all**, or wait for the nightly run.

## Field reference

For report builders only. Nothing on this page requires you to know these.

| What you see | Field |
|---|---|
| Rollups last calculated, on a record | `Rollups_Last_Calculated__c` |
| Last calculated, on the Rollups page | `Last_Calculated__c` on Rollup Definition |
| Calculation, and the delimiter of a text list | `Aggregate__c` and `Delimiter__c` on Rollup Definition |
| Member count on a household, maintained by the household automation rather than by a rollup | `Member_Count__c` |

With Giving installed:

| What you see | Field |
|---|---|
| Total giving, on an account or a contact | `Total_Giving__c` |
| Gift count, on an account or a contact | `Gift_Count__c` |
| First gift date | `First_Gift_Date__c` |
| Last gift date | `Last_Gift_Date__c` |
| Largest gift | `Largest_Gift__c` |
| Giving this year, last year, two years ago | `Giving_This_Year__c`, `Giving_Last_Year__c`, `Giving_Two_Years_Ago__c` |
| Pledge balance | `Pledge_Balance__c` |
| Total soft credits, soft credit count | `Total_Soft_Credits__c`, `Soft_Credit_Count__c` |
| In-kind value, in-kind gift count | `In_Kind_Value__c`, `In_Kind_Gift_Count__c` |
| Total raised, on a fund or an appeal | `Total_Raised__c` |
| Total raised this year, on a fund | `Total_Raised_This_Year__c` |
| Paid to date, on a commitment | `Paid_To_Date__c` |
| Paid amount, on a scheduled payment | `Paid_Amount__c` |
