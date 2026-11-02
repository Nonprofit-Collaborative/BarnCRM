# Rollups

## What It Does

Rollups are the totals that appear on a household, a person, an organization, or another
record without anyone adding them up: a count, a sum, a first or last date, a largest
value. The rollup engine is its own module, **BarnCRM Rollup Builder**, offered in both
editions and needed by Giving; without it BarnCRM keeps no totals. The totals themselves are
shipped by the modules that own the records being counted, and with the Giving module installed they
include total giving, gift counts and dates, pledge balances and what a fund and an appeal
have raised.

The member count on a household is not one of them. It looks like a rollup and it is kept
up to date for you, but it is maintained by the household automation every time somebody
joins or leaves, so it is not in the Rollup Builder and Recalculate does not touch it. If a
member count looks wrong, the Households page is where to fix it.

BarnCRM calculates them for you and shows you when each one was last calculated, so
you never have to guess whether a number on a record is current. If the calculation has
not run recently, the BarnCRM home page says so rather than leaving a stale number
looking fresh.

## What BarnCRM Calculates for You (with Giving)

This section applies only when the Giving module is installed. The Rollup Builder module on
its own ships no totals, so without Giving it lists only rollups you add yourself.

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

## How to Turn It On

Install the **BarnCRM Rollup Builder** module after Core; Giving cannot be installed without
it. Installing it gives you, the installer, the **Rollup Builder Admin** permission set.

After that most of it is already on. Installing a module creates its rollups, active and ready
to calculate (with Giving, the giving totals), and an upgrade adds anything newly shipped
without touching a rollup you have changed. An org with the Rollup Builder and no Giving starts
with no shipped totals.

One step is left for you, and nothing in the app does it on your behalf:

1. From the App Launcher, open the **BarnCRM Admin** app and click the **Rollup
   Builder** tab. (In **BarnCRM Settings**, the **Rollups** section opens the same page.)
2. You should see every total listed above, one row each.
3. Click **Schedule nightly recalculation**. The page then shows "Nightly recalculation
   is scheduled for 2:00 AM." (or the hour you chose in **Time of the nightly run**).

Do that on the day you install. The Setup Assistant has no rollup step, so until you click
it nothing recalculates overnight and the home page tile stays in warning.

### If a Rollup Is Missing

**Restore Shipped Rollups** at the top of the page creates the shipped rollups this org
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

Two settings in the **Rollups** section of **BarnCRM Settings** change how every rollup
behaves. The Rollup Builder module has no settings tab of its own: open **BarnCRM Settings**
and choose **Rollups**.

Where "this year", "last year" and "two years ago" begin is not a BarnCRM setting: it is your
org's fiscal year in Salesforce Setup (**Setup, Company Settings, Fiscal Year**), the same one
every Salesforce report uses. The **General** section of **BarnCRM Settings** shows it, read
only, as **Fiscal year start month**. After changing it in Setup, click **Recalculate All** to
correct every year based total in **Every night** or **Both** mode, which is every year based
total the Builder saves (see [What the Builder will not save](#what-the-builder-will-not-save)).
BarnCRM follows the standard fiscal year: each year starts on the first day of the start
month. If your org uses a custom fiscal year, see
[Health Check](health-check.md#what-health-check-looks-at).

- **Default rollup mode** decides how a newly created rollup starts out: **Instantly**,
  **Every night**, or **Both (recommended)**. The next section says what each one means.
- **When instant totals are calculated** decides when a save updates the totals in
  **Instantly** and **Both** mode. See [After the save, or during
  it](#after-the-save-or-during-it) below. A fresh org shows **Both (recommended)** and
  **After the save (recommended)** here: they are the settings in use even before anyone has
  saved this section, and the fields are never left empty.

You need the **Manage BarnCRM Settings** permission to change any of this. Without it,
the Rollup Builder page still opens and still shows every total and its last calculated
time; the controls are simply read only.

## When a Total Is Recalculated: The Three Modes

Every rollup has a mode.

| Mode | What happens |
|---|---|
| **Instantly** | A gift saved by a person updates the totals a few seconds after the save: refresh the household a moment later and its total giving already includes it. A bulk change (an import, a data loader run, a big update) goes through the same queue and catches up within minutes, also when many batches or people save at the same moment. A change made by a background job is also queued, and the queue run starts as soon as that job's step is saved, so those totals catch up within minutes too. If that start fails, the next queue run or the nightly run picks them up. |
| **Every night** | Recalculated in the nightly run (2:00 AM unless you change **Time of the nightly run**), and when you click **Recalculate**. A gift entered this afternoon shows up tomorrow morning. |
| **Both (recommended)** | Instantly, and checked again every night. The nightly run is the safety net: if anything was missed during the day (an automation switched off, a record changed while automation was paused), the next morning's numbers are right. Every shipped total uses this mode. |

"Instantly" needs BarnCRM to see the change as it happens. It does for gifts, pledges and
other BarnCRM records. For a total that counts records from any other object (a standard
object such as opportunities, another app's object, or one your organization created), see
[Instant Totals on Other Objects](#instant-totals-on-other-objects) below; without that,
such a total is calculated every night and on demand only.

A save recalculates only the totals its change can move. Saving a soft credit recalculates the
soft credit totals on that person and household, not their gift or pledge totals, and an
**Every night** total waits for the nightly run even when a record it counts is saved.

### After the Save, or During It

**When instant totals are calculated** has two choices:

- **After the save (recommended)**, the default. The save notes which households,
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

### How the Nightly Run Works

The nightly run starts at 2:00 AM by default, in the time zone of the person who scheduled
it. To run it at another hour, open **BarnCRM Settings**, **Rollups** section, and choose
**Time of the nightly run** (any hour from 12:00 AM (midnight) to 11:00 PM). Saving a new
hour moves the scheduled run straight away; if the nightly run is not scheduled, the new hour
is used when you schedule it. Pick a quiet hour after the day's data entry and before the
morning's reports.

The nightly run, **Recalculate** and **Recalculate All** work
through every record a rollup writes, one kind of record at a time (all accounts, then all
contacts, then all funds), and calculate all of a record's totals together:

- **A record is saved only when one of its totals changed.** Its **Rollups last calculated**
  time then moves to the time of that run. A record whose totals were already right is not
  saved, so it keeps its earlier time: the run checked it and found nothing to change. The
  **Last Calculated** time in the Rollup Builder is what tells you the run happened.
- **The Rollup Builder marks a rollup calculated when the whole run has finished**, not when it
  starts. When the page shows a time, the totals from that run are on the records, except for
  records with a very large number of gifts (next bullet), whose totals follow a few minutes
  later.
- **Records with a very large number of gifts are calculated separately.** A record with
  about 20,000 or more gifts or allocations behind its totals (a General Fund most gifts go to,
  a catch-all donor such as "Anonymous") has more rows than one step of the run may read. The
  run hands it to the queue's separate background job for large records, which reads its rows
  a few thousand at a time, so it cannot hold up everyone else's totals. Its totals arrive a
  few minutes after the run finishes; until then it shows among the records waiting. A record
  that has grown since its count was last calculated (a large import into one fund) is caught
  while it is being recalculated and handed on the same way. Nothing to do.
- **A record that cannot be saved is tried again.** If someone was editing it, or a
  validation rule refused it, BarnCRM tries again automatically; after five tries it waits
  in the **Needs Attention** list. The next nightly run that saves it takes it off the list.
- **A part of the run the platform stops is tried again.** If Salesforce stops a group of
  records part way (for example because they had more gifts than one step can read), those
  records go to the queue and are recalculated within minutes, not left until the next night.
- **One full run at a time.** If you click **Recalculate All** or **Recalculate** while a run
  is still going (for example the nightly run), nothing new starts and the page says "A full
  recalculation is already running. Its totals will be on the records when it finishes, so
  try again after that." The nightly run does the same when a run you started is still going.
- **A run does nothing while all automation is paused.** The next night catches up.
- **If anything could not be saved, one summary goes to the Error Log**, so the Hub's error
  tile shows it.

## What a Rollup Can Calculate

Each rollup has a **calculation**, and the calculation decides what kind of field can show
the result. BarnCRM refuses to save a rollup whose field cannot hold its result, and says
which kind of field to choose instead. That check is the **Check rollups before saving**
automation on the **Automation** page; if it is switched off, such a rollup still saves, but
BarnCRM skips it on every run and the Error Log says why. It is part of the module, so it
also pauses while BarnCRM Rollup Builder is turned off on **Modules**. A rollup saved then is
not checked, but the engine still skips and logs one it cannot calculate, so the
recalculation **Turn On** starts never writes a wrong total.

| Calculation | What it gives you | Shown in |
|---|---|---|
| **Sum**, **Average** | The total or the average of a number or an amount. | A number, currency or percent field |
| **Minimum**, **Maximum** | The smallest or largest value, for example the largest gift or the latest date. | A number, currency, percent or date field |
| **Count** | How many records match. | A number field |
| **Count distinct** | How many different values a field holds, for example how many different funds a donor has given to. Blank values are not counted. | A number field |
| **First**, **Last** | The value from the earliest or latest record, by the field you choose to order by, for example the appeal of a donor's first gift. | A number, currency, percent, date, text or picklist field |
| **Any** | Checked when at least one record matches, for example "has ever given a gift over $1,000". | A checkbox field |
| **None** | Checked when no record matches, for example "has no open pledge". | A checkbox field |
| **Text list** | Every matching value in one field, for example the names of every program a person volunteers for. Blank values are left out. | A text or long text field |
| **Text list, each value once** | The same, with each value listed once. | A text or long text field |

What to know about them:

- **Any and None count the records your conditions describe.** They do not read a field of
  their own. For "has ever given a gift over $1,000", choose **Any** and the condition
  "Amount greater than 1000".
- **A text list is separated by a comma, a semicolon, a new line, a pipe, or your own
  characters.** Choose one with **Separate the values with**; a comma is used when you choose
  nothing. **Pipe** writes ` | ` between the values. **Custom** writes what you type in
  **Custom delimiter** (up to 10 characters, spaces included, such as ` - ` with a space on
  each side) exactly as typed, and cannot be
  saved empty. A value that contains the separator is not changed, so if your values contain
  commas (for example "Smith, Jane"), choose a semicolon, a new line or a pipe so the list
  still reads clearly. A new line suits a long text field.
- **A text list is in order.** If you choose a field to order by, the values follow it,
  oldest or smallest first, or with **Order** set to **Descending**, newest or largest first.
  Otherwise they are listed alphabetically (Z to A when descending). Records whose order field
  is blank come last either way.
- **Only the first N records.** **Sum**, **Average**, **Minimum**, **Maximum** and the text
  lists can count only the first few records, in the order you choose: enter a number in
  **Only the first N records** and choose the field to order by. For example, the sum of the 5
  largest gifts is **Sum** of Amount, 5, ordered by Amount, **Descending**; the last 3 gift
  amounts as a text list is **Text list** of Amount, 3, ordered by Gift Date, **Descending**.
  Records with a blank value are skipped, so N means N records that have one. **Text list,
  each value once** lists the first N different values. Count, Count distinct, Any, None, First
  and Last take no limit.
- **Order does not change First and Last.** First is always the record with the lowest value
  of the order field (the earliest date), and Last the one with the highest. For "the most
  recent", choose Last.
- **A text that is too long is cut.** A list longer than the field holds is cut at the
  field's length, so a 255 character field shows the first 255 characters. Use a long text
  field for a list that can grow.
- **Each value once means exactly once.** "Gold" and "gold" are two different values to
  **Text list, each value once** and to **Count distinct**.
- **First and Last take the first record even when its value is blank.** Add the condition
  "is not blank" on that field if you want the first record that has one. When two records
  share the same order value, the one with the lower record ID wins (usually the one created
  first), so the answer never changes from one run to the next.
- **A picklist gets one of its own values.** First and Last can fill a picklist field from
  a picklist or a text field, for example the channel of a donor's latest gift. If the field
  you copy is a picklist, every value it has must also be a value of the picklist you fill, or
  the Builder will not save. A text value the picklist does not have (or a value added to the
  source picklist later) is not written: the record keeps what it had and the Error Log names
  the value, so add it to the picklist and click **Recalculate**. Letter case does not matter:
  "mail" is written as the picklist's "Mail".
- **A number or date copied into text is written plainly**, for example `1250.00` or
  `2026-03-01`, without a currency symbol or your local date format. A date and time is
  written in UTC, for example `2026-03-01 14:05`, so it reads the same whoever saved the
  record.
- **They stay right as records change.** Like every rollup, these are worked out again from
  all the matching records each time, so a deleted record, a record moved to another parent,
  or a value changed back is reflected the next time the total is calculated, whatever its
  mode.
- **Deleted and archived records count only if you ask.** Tick **Include deleted and archived
  records** in step 4 to count records in the Recycle Bin and archived tasks and events, as
  if they were not deleted. Deleting a record then does not lower the total. A record counts
  until the Recycle Bin is emptied (or the platform removes it after its retention period);
  that fires nothing, so the total drops at the next nightly run or **Recalculate**. For a
  record with so many source records that BarnCRM has to read them in parts (tens of
  thousands), a rollup with this ticked is not recalculated and the Error Log says why.

## The Rollup Builder

Rollups are their own module, **BarnCRM Rollup Builder**, with one tab, **Rollup Builder**,
in the **BarnCRM Admin** and **BarnCRM Admin Console** apps (the module has no app of its
own). Its settings are in the **Rollups** section of **BarnCRM Settings**.

The **Rollup Builder** tab is where you create a new total and edit any existing one, shipped
or your own, without typing a query. It lists every rollup with its controls (mode, active,
**Recalculate**, the nightly schedule, **Recalculate All** and **Restore Shipped Rollups**),
and adds **New Rollup**, and **Edit**, **Copy** and **Delete** on each row. The tab comes with the
**Rollup Builder Admin** permission set (**Rollup Builder User** opens it read only), and
saving needs the **Manage BarnCRM Settings** permission. The Rollups section in BarnCRM
Settings opens it.

The same rules hold however a rollup is saved, from this tab, an import, the record page, a
data loader or the API: changing a rollup needs **Manage BarnCRM Settings**, the person saving
must be able to edit the field the total fills and see every field the rollup reads, and a total
never goes on users, setup records (profiles, permission sets, roles, groups) or BarnCRM's own
bookkeeping. A save that breaks one of these is refused with the reason. The rollups BarnCRM
ships, and the time each run stamps on a rollup, are the only saves exempt.

You do not assign these sets by hand for BarnCRM's roles. When the module is installed, each
time it is turned on on **Modules**, and with each nightly run once that is scheduled,
BarnCRM gives **Rollup Builder User** to everyone holding the **BarnCRM Staff** or **BarnCRM
Read Only** permission set, and **Rollup Builder Admin** to everyone holding **BarnCRM
Admin**, whether directly or through a role on the [Access](access.md) page, so someone given
a role today has the set after tonight's run. It never takes a set away, so one you give by
hand stays. While the module is turned off it gives nothing.

**A user who holds neither Rollup Builder set, such as an integration user.** Some saves have
to announce, once they are saved, that totals are waiting: saves that run inside a
background job (a Queueable), and ordinary saves made while a recalculation was already
asked for or could not be started. The announcement needs the **Rollup Builder User** or
**Rollup Builder Admin** set. Without one, the save still goes through and its totals are
queued, but they wait for the next queue run or the nightly run, and the Error Log gets a
Warning from `RollupQueue.announceReady`. To have them catch up within minutes, give that
user **Rollup Builder User**. People with a BarnCRM role get it at install, at each **Turn
on** and with each nightly run; until then the same wait applies to them.

The **Rollups** section of **BarnCRM Settings** holds the module's own settings: **Default
rollup mode**, **When instant totals are calculated**, **Time of the nightly run**, and a
button that opens the Builder.
The fiscal year is your org's, shown read only in the **General** section.

**Copy** is the quickest way to make a total like one you already have: it opens the Builder
with everything filled in from that rollup, under a new name, for you to change. Editing a
shipped rollup is fine: an upgrade never overwrites a rollup you have changed. To remove a
rollup you made, see [Deleting a Rollup](#deleting-a-rollup).

### Starter Templates

**Starter Templates**, above the rollup list, offers ready-made rollups for common totals.
Nothing is ever added for you: opening it adds nothing, no rollup is ticked, and only the
rollups you tick are added when you click **Add the Chosen Rollups**. Each is added
**switched off**, through the same checks as a save in the Builder, so switch it on once its
field shows what you expect. Only people with **Manage BarnCRM Settings** see the button.

The **Nonprofit Starter** (needs Giving) adds totals Giving does not ship, all from received
gifts (Received, Refunded or Written off, with an amount above zero, as the shipped giving
totals count them):

| Rollup | Shows on | What it is | Field type |
|---|---|---|---|
| Average Gift | Contact | Average gift amount | Currency |
| First Gift Amount | Contact | Amount of the earliest gift, by gift date | Currency |
| Last Gift Amount | Contact | Amount of the latest gift, by gift date | Currency |
| Smallest Gift | Contact | Smallest gift amount | Currency |
| Gifts This Fiscal Year | Contact | Number of gifts dated in the current fiscal year | Number |
| Appeal Average Gift | Appeal | Average gift amount for the appeal | Currency |
| Number of Donors | Appeal | Number of different donors who gave to the appeal | Number |

Each rollup shows its sentence and whether it can be added:

- **Needs a field labelled ... on ...**: BarnCRM does not ship these fields. Click **Open in
  Builder**: the Builder opens with the rollup filled in and **Create a Field** ready with
  the label and type, which writes the field for you to create (see step 1 of the Builder).
  Create the field, click **Refresh Fields**, and save there (it saves switched off), or come
  back here and tick it.
- **Already filled by ...**: another rollup fills that field, so this one is not added.
- **Needs ..., which this org does not have**: the module it needs (Giving) is not installed.
- **Ready to add, switched off.**

After **Add the Chosen Rollups**, each ticked rollup says **Added, switched off.** or why it
was not added, and the list shows the new rollups.

### Reading the Rollup List

- **One sentence per rollup.** The **What It Counts** column says what each rollup does in words,
  from your org's own field and object names: "Total of Amount from Gifts by Donor Contact,
  shown in Largest Gift on each Contact. Only records that meet its conditions count." A
  rollup with a time window or **Only the first N records** says that too. The API names
  stay underneath in small grey text for when you need them.
- **Grouped by the record that shows the total.** Rollups are grouped under a heading per
  object (Account, Contact, Fund and so on), with how many each has, in alphabetical order.
- **Search rollups** finds a rollup by any word of its name, description or sentence, or by
  an object or field API name (`Total_Giving__c`). Clear the box to see them all.
- **Status** says how each rollup's recalculation stands right now: **Switched off**;
  "2 records could not be saved: see Needs Attention"; **A full recalculation is running**
  (a run is going, which may or may not include this rollup); "12 records waiting" (saved
  records whose totals are queued and catch up within a minute); or **Nothing waiting**.
  Only someone with **Manage BarnCRM Settings** sees it.
- **Conflicts** are shown in red under a rollup's name:
  - "Writes the same field as ... for the same records": two active rollups keep
    overwriting each other's total. Switch one off, or give each **Only for some records**
    conditions that never meet. Saving in the Builder already refuses this; it can still
    arrive by **Restore Shipped Rollups** or an edit outside the Builder.
  - "Cannot be switched on while ... fills the same field for the same records": the rollup
    is off, and switching it on would be refused until the other one is off.
  - "Calculates the same total as ..., into another field": two active rollups do the same
    work. That is allowed, but usually one of them is left over.

  Two rollups that fill one field for different records (the household and the organization
  giving totals) are fine and are not listed.

The Builder walks you through five steps. **Next** checks the step you are on, and says what
to change, before it lets you go on.

Above the steps, the whole rollup is written as one sentence that fills in as you go: "Show
Sum (Amount) from Gift, by Donor, counting only those that meet its conditions (2), in Contact:
Total Giving. Updated: Both (recommended)." A part you have not chosen yet reads "(not chosen
yet)". Click any part you have already filled in to go straight to the step that sets it;
when you edit or copy a rollup, every part can be clicked. Choosing another object in step 1,
or other records in step 2, clears what the later steps chose, so those parts are filled in
again in order.

The Builder steers you away from choices it would refuse:

- In step 3, the calculations the field from step 1 cannot hold are not offered, and a line
  under **Calculation** names them: "Not available for Total Giving: Any, None, Text list. To
  use one of them, choose another field in step 1."
- **Field to calculate** lists only fields the calculation can read: for **Sum** and
  **Average**, number, currency and percent fields; for **Minimum** and **Maximum**, those
  and date fields. A line under it says why, and if the records have no such field it says
  so. Changing the calculation clears a field it cannot read.

1. **Where should the number appear?** The kind of record and the field that show the total.
   The list starts with the objects most often used: Account, Contact, BarnCRM's objects,
   your organization's own objects, and the common Salesforce objects your org has
   (Opportunity, Opportunity Product, Case, Campaign, Campaign Member, Lead, Task, Event,
   Asset, Order, Order Product and Contract). To use any other object you can see, type part
   of its name in **Find another object** and pick it from the list. Only fields BarnCRM can
   write are offered: numbers, amounts, percents, dates, checkboxes, text and picklists. A
   field another active rollup already fills is marked with that rollup's name. If the field
   does not exist yet, click **Create a Field**, type its label and choose its type (a
   Number or Currency field is right for most totals) and click **Write the Field**.
   BarnCRM cannot add the field to your org itself, since that takes a Metadata API deploy;
   instead it writes it for you: the exact Setup steps with the type, label and field name to
   enter, the field's source file to copy, and **Download Field Package** with the Salesforce
   CLI command to deploy it. A deployed field is visible to nobody until you give access to
   it in Setup. Read only is enough for most people; the person who sets up the rollup needs
   Edit on the field, or the Builder refuses to save it. When the field exists, click **Refresh Fields**: the Builder chooses it.
2. **What should be counted?** The records that feed the total and the field that links them
   to the record from step 1, in plain words: "Gift, by Donor" or "Opportunity, by Account
   ID". When the total lands on an account and the records point at a person, you can also
   choose that person's household, for example "Gift, by Donor (their household)".
3. **How should it be calculated?** Any calculation in
   [What a rollup can calculate](#what-a-rollup-can-calculate) that the field from step 1 can
   hold, the field it reads, for First and Last the field that decides which record comes
   first (**Which record comes first, by**), for a sum, an average, a minimum, a maximum or a
   text list **Only the first N records** if you want a limit, for a text list or a limit the
   **Order** (Ascending or Descending), and the time window: all time, this fiscal year, last fiscal year, or two fiscal
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
   exactly, so `%` and `_` are ordinary characters. **Include deleted and archived records**
   counts records in the Recycle Bin and archived tasks and events too (see
   [What a rollup can calculate](#what-a-rollup-can-calculate)).
   A condition can also read a field of a record the counted records point to, one lookup
   away: after the records' own fields, the list offers each lookup's fields, such as
   **Appeal > Type** for "gifts whose appeal is a mail appeal". One lookup only: a field of
   the appeal's campaign, two lookups away, is not offered. When you use one, step 4 says
   so: a change on that other record (the appeal's type) updates the totals at once only
   if its object has rollup triggers. BarnCRM ships them on contacts, gifts, gift
   allocations, soft credits, commitments, household members and volunteer hours and sign-ups,
   not on accounts or appeals; an object you created has them once you set up
   [instant totals](#instant-totals-on-other-objects). Otherwise the nightly run, or
   **Recalculate**, puts them right. A change on the counted record itself (a gift moved to
   another appeal) is always picked up as usual.
5. **Check and save.** The whole rollup read back as one sentence. Pick a real record to see
   what the total would be next to what the record shows now, and how many records the
   rollup will maintain. Under **Records Read for This Record**, up to ten of the records it
   reads for that record are listed, each linked, with **Counted** or why it is left out: the
   number of each condition it does not meet, outside the year the rollup counts, a blank
   field that orders the records, or beyond a row limit. A rollup that reads through a
   household does not list its records; the total still includes them. Rather than pick a
   record yourself, click **Pick Sample Records**: the Builder calculates the rollup on up to
   five records it would fill, choosing first records that recent counted records point to,
   and **Show Records Read** lists one sample's records. Nothing is saved. Then give it a name, choose its mode, and click **Save**, or **Save
   and calculate now** to start its recalculation straight away. When the records you count
   have no instant updates yet, for example Opportunities or your own objects, this step says
   "Instant totals are not available yet for ..." and offers only **Every night** and **Both
   (recommended)**: see [Instant Totals on Other Objects](#instant-totals-on-other-objects).
   Under **Mode**, **What Each Choice Means** says what each mode does to this field:
   - **Instantly, after the save**: the field changes within about a minute after one of the
     counted records is saved (the default **When instant totals are calculated** setting); or
     **Instantly, during the save** when that setting is **During the save**. When the counted
     records have no instant totals yet, it says Instantly is not available until they do.
   - **Every night**: the field is recalculated at the time of the nightly run (2:00 AM unless
     you changed **Time of the nightly run**), so a change made today shows tomorrow.
   - **Both (recommended)**: instantly, and the nightly run puts right anything a save
     missed; for records with no instant totals yet, every night until they have them.

   **Skip for people with this custom permission (optional)** is for a data migration user: see
   [Skipping a rollup for some people](#skipping-a-rollup-for-some-people).

### What the Builder Will Not Save

It says what to change instead of saving:

- A rollup with no name, or no field to show it.
- A field BarnCRM cannot write, such as a formula.
- A calculation the field cannot hold, for example a sum into a checkbox. The message says
  which kind of field to choose.
- A sum or average of something that is not a number or an amount, and a minimum or maximum
  of something that is not a number, an amount or a date.
- First or Last without the field that decides which record comes first.
- **Only the first N records** below 1, without a field to order by, or on a calculation that
  takes no limit (Count, Count distinct, Any, None, First, Last). Every save checks this, not
  only the Builder.
- A **Custom** separator with nothing typed in **Custom delimiter**. Every save checks this too.
- A fiscal year window without a date to measure it on, or measured on a date and time field.
  Choose a date field, such as the gift date.
- An **Instantly** total with a fiscal year window, or with an **is this year**, **is last year** or
  **is in the last N days** condition. Such a total changes when the date moves on, with no record
  saved, so only the nightly run can keep it right. Choose **Both (recommended)** or **Every
  night**. Changing the mode on the Rollups list refuses it too.
- An **Instantly** total of records that have no instant updates yet (records of a Salesforce
  object such as Opportunity or Task, or of your own object): "Instant totals are not
  available yet for Opportunities, so this total cannot be Instantly only." Choose **Both
  (recommended)** or **Every night**. Changing the mode on the Rollups list refuses it too. A
  rollup you saved as **Instantly** before keeps working; the next time you edit it, choose
  **Both (recommended)**, which stays instant if you use the Flow template.
- Conditions that name a field the records do not have, a field more than one lookup away,
  or a field of another record you cannot see.
- A picklist filled from anything but a picklist or a text field, or from a picklist with
  values the picklist you fill does not have. The message lists the missing values.
- A field another active rollup already fills for some of the same records. Two rollups may
  fill one field only when their **Only for some records** conditions never pick the same
  record, as the household and the organization giving totals do. The Builder checks your
  records, and says which rollup it overlaps.

### When Your Org Uses More Than One Currency

The Builder warns you on step 3:

- On a total of amounts into a currency field: "This Org Uses More Than One Currency. Totals
  are converted to each record's currency at today's rates, not the rate on the gift date."
- On a total of amounts into a number field: "This field is a number, not a currency, so the
  total is shown in the corporate currency."

After changing exchange rates, recalculate your money totals to bring them up to date.

### Needs Attention

Under the list, **Needs Attention** shows what the engine has not finished:

- **Records waiting**, for example "1,204 records waiting, oldest 3 minutes ago". These are
  totals from recent saves and bulk changes, queued and calculated within a minute or a few.
  Nothing to do unless the oldest is more than an hour old, which Health Check also reports.
  Then click **Start Now** to recalculate them now; the nightly run also picks them up.
  A long queue is worked through in a series of background runs. Salesforce limits how long
  such a series may be (five runs in Developer Edition, trial and scratch orgs), so at that
  point BarnCRM starts a fresh series. Nothing to do.
  A record with a very large number of gifts or allocations behind its totals (a General Fund
  most gifts go to, an organization with tens of thousands of gifts) has more rows than one
  background run may read. BarnCRM recalculates such a record in a separate background job that
  reads its rows a few thousand at a time, so its totals take a few minutes rather than seconds.
  One such job runs at a time. A record with fewer than about 20,000 rows behind its totals
  stays in the queue. BarnCRM sizes a record from its active count rollups (such as a fund's
  gift count), so switching off a count rollup on an object leaves it out of that sizing. A
  record that has grown since its count was last calculated (a large import into one fund) is
  caught while it is being recalculated and moved to that job, with nothing to do.
  While that job runs, the record shows among the records waiting. Nothing to do. If a run ever
  stops partway (often an automation of yours failing on one record), the records it was
  working on are counted as one try and retried in ever smaller groups, then one at a time,
  while the rest of the queue carries on. Only the record that keeps stopping its run appears
  under **Could Not Be Saved**, after five tries.
- **Could Not Be Saved**: each record whose totals failed five times, with a link to it,
  what went wrong in plain words, when, and how many tries. Fix the cause (often a validation
  rule or a record someone was editing), then click **Retry** for the ones you selected, or
  **Retry All**. They go back in the queue and are tried within minutes. The next nightly run
  that saves a record also takes it off the list.
- A warning when the nightly run is not scheduled, and how the last full run ended.

### Moving Rollups to Another Org

Build and check rollups in a sandbox, then move them to production with a file:

1. In the sandbox, on the **Rollup Builder** tab, tick **Include in the export** on the rollups
   to move, or tick none to move every rollup you made. Click **Export to a File**. Your
   browser saves `barncrm-rollups.json`.
2. In production, on the **Rollup Builder** tab, choose the file under **Import from a file**.
   A table says what would happen to each rollup: **New: will be created**, **Will replace the
   rollup here with the same Definition Key**, or **Not saved** with the reason. Nothing is
   saved yet.
3. Click **Import These Rollups** (or **Cancel**). The table then says what happened to each one.

What to know:

- **Rollups are matched by Definition Key.** A rollup moved once and changed in the sandbox
  replaces its copy in production when you import it again; nothing is duplicated.
- **Each rollup goes through the same checks as Save in the Builder**, against production's own
  objects, fields and rollups. One that fails is not saved at all and the table says why (for
  example, a field production does not have yet: create it in Setup and import again). The
  others are saved.
- **A rollup arrives switched on or off as it was in the file**, and only when every check
  passes. Nothing is recalculated by the import: the next nightly run does it, or click
  **Recalculate** on the row.
- **Rollups that came with BarnCRM are not moved.** Every org has them; use **Restore shipped
  rollups** if one is missing.
- **The file holds no record Ids or dates**, only how each rollup is calculated, so it works
  between any two orgs with BarnCRM Rollup Builder. A file from a newer version of BarnCRM is
  refused until this org is upgraded.
- **A very large file** may stop part way, saying **Not imported yet** on the rest; import the
  same file again to finish.

### Recalculate All, Now or Tonight

**Recalculate All** rebuilds every active rollup, whatever its mode: **Instantly** totals as
well as **Every night** and **Both** ones. The nightly run covers only **Every night** and
**Both**, because each save already keeps an **Instantly** total right; **Recalculate All** is
for when you want every total rebuilt from scratch, for example after loading data with
automation paused.

Before **Recalculate All** starts, the Builder says how many records it will go through and
roughly how long that takes, for example "About 41,200 records, roughly 25 minutes." The count
includes the records of every active rollup, **Instantly** ones too. During working hours
(8 AM to 6 PM, Monday to Friday, in your time zone) it suggests running it tonight instead,
because a long run competes with people saving records. When the nightly run is not
scheduled, **Run Tonight** sets up a single run of every active rollup at the next
**Time of the nightly run** (2:00 AM unless you changed it), and says "One recalculation of
every total is set for the next 2:00 AM." When it is scheduled, **Run Tonight** adds nothing:
the nightly run already recalculates the **Every night** and **Both** totals at that hour,
and a second run at the same moment would
only be turned away. To rebuild the **Instantly** totals as well, choose **Start Now**.

### Deleting a Rollup

**Delete** on a row opens a **Delete This Rollup** panel above the list, which asks what
happens to the values the rollup wrote:

- **Keep them on the records** (the default). Nothing updates them again, so choose this when
  the old numbers are still worth reading.
- **Clear them from every record it fills, in the background.** The field is blanked on every
  record that meets the rollup's **Only for some records** conditions (all records of that
  object when there are none). Records outside them keep their values. When it finishes, the
  Error Log says how many records were cleared and how many could not be saved. Clearing is
  refused while another active rollup fills the same field for the same records, since it
  would wipe that rollup's totals too: keep the values, or switch the other rollup off first.
- **It cannot be undone.** If you might want the rollup back, switch it off instead.
- **Rollups that came with BarnCRM cannot be deleted.** Delete says so and does nothing, since
  **Restore Shipped Rollups** would only bring them back. Switch them off instead.
- **Not during a full recalculation.** While **Recalculate All** or the nightly run is going,
  Delete says so; try again when it finishes. Totals already waiting to be recalculated for the
  deleted rollup are skipped, as they are for a rollup that is switched off.

### Explain These Totals on a Record Page

When someone asks "where does this number come from?", open the record: with Giving, the
contact and account record pages show **Explain These Totals** in the sidebar to people with
Manage BarnCRM Settings. To show it to staff too, or on another object's page, click the
gear, **Edit Page**, select the card (or drag **Explain These Totals** from the custom
components onto the page), change or remove its visibility filter, and save. It works on any
object a rollup fills. For each active rollup that fills a field on that record (and whose field the
person can read), it shows:

- the total and what it counts, in the same sentence as the Rollup List;
- how many records count and how many are left out, and when the record was last calculated;
- up to ten of the records read, linked, each **Counted** or why it is left out, as in the
  Builder's preview (a rollup that reads through a household lists none);
- for you (Manage BarnCRM Settings), what the rollup would calculate now, next to what the
  record holds, without saving.

It reads as the person looking: the counts and the list include only records they can open,
and they need the **Rollup Builder User** (or **Rollup Builder Admin**) permission set to read
the rollups.

## Instant Totals on Other Objects

BarnCRM can only ship automation for its own records. A rollup that counts records from any
other object (a standard object such as opportunities or tasks, another app's object, or one
your organization created, for example volunteer hours on a custom Shift object) is
calculated every night and when you click **Recalculate**, until you make it instant. Until
then the Builder says so on its last step, and such a rollup is **Every night** or **Both
(recommended)**, never **Instantly** alone. There are two ways to make it instant: a small
trigger the Rollup Builder writes for you (below), or the **Recalculate rollups** Flow
template, which needs no code. Once the object's generated trigger is on, **Instantly** is
offered too.

### With a Generated Trigger

The **Instant Totals** section at the bottom of the Rollup Builder lists every object an
**Instantly** or **Both (recommended)** rollup counts, and every object that still has a
BarnCRM trigger, with what each one does today:

| Shown | What it means |
|---|---|
| **Instant: BarnCRM updates these totals by itself.** | A BarnCRM object, or a person: nothing to do. |
| **Not set up** | Totals update every night and when you click **Recalculate**. **Turn On Instant Totals** shows how to add the trigger. |
| **On** | The trigger is in this org and running. |
| **Turned off** | The trigger is there but its switch is off: totals update every night until you click **Turn On Instant Totals**. |
| **Inactive** | The trigger is there but was deactivated in Setup. Activate it in a sandbox and deploy it again, or remove it. |
| **Salesforce allows no trigger on this object** | Its totals stay nightly. |

Step 5 of the Builder shows the same line for the object the rollup counts, with the same
buttons.

**Turn it on.** Click **Turn On Instant Totals**. The Builder shows a one-line trigger and its
test, named from the object (for opportunities, `BarnRollup_Opportunity` and
`BarnRollup_Opportunity_Test`), with a **Copy** button for each. Then:

1. In a sandbox (or a Developer Edition org) where BarnCRM is installed, open the Developer
   Console. Choose **File**, **New**, **Apex Trigger**, give it the trigger's name, pick the
   object, replace the code with the trigger from the Builder and save.
2. Choose **File**, **New**, **Apex Class**, give it the test's name, replace the code with
   the test from the Builder and save. Run it from **Test**, **New Run**: it passes.
3. In the sandbox's Setup, open **Outbound Change Sets**, add the trigger and the class, and
   upload the change set to production.
4. In production's Setup, open **Inbound Change Sets**, click **Deploy**, choose **Run
   specified tests** and enter the test's name. Only that test runs, so tests elsewhere in
   your org that already fail do not block it.
5. Back in the Rollup Builder, the object shows **On** as soon as the trigger is in the org.

If you use the Salesforce CLI, **Download deploy package** saves a zip with the trigger and
its test, and the Builder shows the command that deploys it, to a sandbox or straight to
production, running only the generated test.

What to know:

- **The trigger never needs changing.** It only tells BarnCRM which records changed; how each
  total is worked out stays in the rollup, so you can add, edit and remove rollups on that
  object without touching code. One trigger serves every rollup that counts the object.
- **The code is the same in every org.** The names come from the object's API name, so a
  sandbox's change set lands exactly what production's Builder looks for.
- **The test never depends on your data.** It saves one empty record, which your required
  fields or validation rules may refuse; the trigger has run by then, and that is all the
  test checks.
- **Deletes and restores are seen too**, unlike the Flow template, and pausing all automation
  or turning the Rollup Builder module off stops the trigger like any other BarnCRM automation.
- **Who can do it.** Creating Apex in a sandbox and deploying a change set use your
  Salesforce permissions (an administrator has them). BarnCRM needs no extra permission and
  deploys nothing itself.

**Turn it off.** Click **Turn Off Instant Totals**. Nothing is deployed: the trigger's switch
goes off at once, in production too, and the object's totals update every night and when you
click **Recalculate**. **Turn On Instant Totals** turns it back on. The switch is also on the
**Automation** page as **Instant rollups on** and the object's name.

**Remove it.** A switched-off trigger costs almost nothing, so you only need to remove it to
tidy up, and before uninstalling BarnCRM (the trigger refers to BarnCRM, so Salesforce will
not uninstall BarnCRM while it is there). Click **Remove the Trigger**:

1. In a sandbox, delete the trigger and its test class in Setup (**Apex Triggers**, **Apex
   Classes**).
2. Production does not allow deleting Apex in Setup. **Download removal package** saves a zip
   that deletes both, and the Builder shows the Salesforce CLI command that deploys it.

### With the Flow Template

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

If you prefer no code in your org, the Flow template does the same job, except for restores.

## Skipping a Rollup for Some People

A large data load can spend most of its time updating totals that the nightly run would
put right anyway. To have one person's saves leave a rollup alone:

1. In Setup, open **Custom Permissions** and create one, for example **Data Migration**
   (API name `Data_Migration`), or use one you already have.
2. Give it to that person through a permission set.
3. In the Rollup Builder, edit the rollup and, on the last step, enter the API name in **Skip
   for people with this custom permission (optional)**. Save.

What to know:

- **Saves by people who hold the permission do not update that total**, instantly or in the
  queue. Everyone else's saves update it as usual.
- **The nightly run still covers it** when the rollup runs **Every night** or **Both
  (recommended)**, and so do **Recalculate** and **Recalculate All**. A rollup set to
  **Instantly** is put right only when you click **Recalculate**, so prefer **Both** for a
  rollup you skip.
- **A name that does not exist is refused** when you save, with the name in the message.
  Enter it exactly as the API name in Setup. A custom permission from an installed package is
  written with its prefix, for example `prefix__Name`.
- Leave the field blank to have everyone's saves update the total.

## Recalculating From a Flow or From Apex

### Recalculate Totals on This Record (Flow)

The Flow action **Recalculate totals on this record** (category **BarnCRM**) recalculates the
totals a record shows, for example from a screen flow button on a household or from a
scheduled flow:

- **Record ID** (required): the record that shows the totals.
- **Rollup (optional)**: the **Definition Key** or the name of one rollup. Leave it empty to
  recalculate every active rollup on that record's object, whatever its mode.

The totals are recalculated straight away when the flow has room, and otherwise queued and
recalculated a minute or two later. A rollup name that matches no active rollup on the
record's object recalculates nothing and leaves a Warning in the Error Log; the flow carries
on. This action is not a save, so **Skip for people with this custom permission** does not
apply to it.

### For Developers: Apex

Code that used the DLRS Apex service can call `RollupApi` instead (prefix it with the
package namespace in a subscriber org):

- `RollupApi.recalculate(Set<Id> recordIds)`: the totals on these records, as the Flow action
  above does for every rollup.
- `RollupApi.recalculateChanges(List<SObject> records, Map<Id, SObject> oldRecords, Boolean deleting)`:
  the totals that changed records affect, exactly as the **Recalculate rollups** action and
  BarnCRM's own triggers work them out. Call it after the save with the records and their
  prior values (null for new records), or before a delete with `deleting` set to true, which
  queues the totals for after the delete. Records of several objects can go in one call.

Neither method throws for a total: a failure goes to the Error Log and the nightly run puts it
right. Pausing all automation stops `recalculateChanges`, as it stops the Flow action.

## DLRS and Rollup Helper in the Same Org

BarnCRM looks for two other rollup tools: DLRS (Declarative Lookup Rollup Summaries, managed
namespace `dlrs`) and Rollup Helper (managed namespace `rh2`). It finds each by its objects,
so nothing has to be set up. When either is installed, **Other Rollup Tools** appears with one
line per tool:

- at the top of the **Rollup Builder** tab;
- in the Setup Assistant, on the step that says what BarnCRM found in your org;
- in the **Modules** section of BarnCRM Settings, when Rollup Builder or Giving is installed.

The line reads, for DLRS: "This org also runs DLRS (Declarative Lookup Rollup Summaries). It is
a separate rollup tool; BarnCRM does not manage its rollups." An org without either tool sees
nothing.

What to know:

- **BarnCRM never changes the other tool.** It does not edit, switch off, delete or uninstall
  a DLRS or Rollup Helper rollup, or its triggers. You do that in the other tool, when you are
  ready.
- **Both can run side by side**, as long as they do not fill the same field. Two tools writing
  one field overwrite each other, and the value you see depends on which ran last.
- **Rollup Helper's rollups are not read.** BarnCRM only says Rollup Helper is here. To move
  its rollups, rebuild them by hand: see
  [Moving Rollups from Rollup Helper](moving-from-rollup-helper.md).

### When BarnCRM and DLRS Fill the Same Field

BarnCRM reads DLRS's rollups (never changes them) to stop the two tools filling one field:

- **Turning a rollup on asks first.** When an active DLRS rollup fills the field a rollup
  fills, saving it switched on in the Builder, or switching **Active** on in the list, opens
  **Switch Off the DLRS Rollup**: "The DLRS rollup ... also fills .... Two tools filling one
  field overwrite each other. Turn this rollup on only if you will switch the DLRS rollup off in
  DLRS." Click **OK** to turn it on, or **Cancel** to leave it off (in the Builder, nothing is
  saved and you stay on the last step).
- **Your answer is recorded.** **OK** writes a row to **Recent Changes** in BarnCRM Settings,
  named **Rollup Builder:** and the rollup's name, saying you confirmed the DLRS rollup will be
  switched off. Then switch it off in DLRS yourself; BarnCRM does not.
- **A file import cannot ask**, so **Import from a file** does not save a rollup that is on in
  the file when an active DLRS rollup fills its field, and says why. Import it switched off, or
  switch the DLRS rollup off first.
- **Switching off and saving a rollup switched off** never ask: a rollup that is off fills
  nothing.
- **Health Check** warns **BarnCRM and DLRS Fill the Same Field** when such a pair appears
  later, for example when a DLRS rollup is switched back on, and names each field and both
  rollups.

Only DLRS rollups that are active in DLRS count. Rollup Helper's rollups are not read, so
neither the question nor the Health Check finding sees them: check those yourself.

### Import From DLRS

When DLRS has at least one active rollup, **Other Rollup Tools** on the **Rollup Builder** tab
has an **Import From DLRS** button (you need Manage BarnCRM Settings). It copies DLRS rollups
into BarnCRM in four steps. BarnCRM never edits, switches off or deletes anything in DLRS.

1. **Choose.** Every active DLRS rollup is listed with the field it fills and its DLRS
   operation. Under **Can Be Copied**, each is ticked; untick any you want to leave. Under
   **Stays in DLRS**, each says why BarnCRM cannot hold it (see the table below). Click
   **Next**.
2. **Review.** Each chosen rollup says what it becomes ("Becomes a BarnCRM Count, filling
   Account.Member_Count__c, switched off.") and anything that works differently in BarnCRM, or
   "Copied as it is in DLRS." Click **Copy Switched Off**.
3. **Compare.** Each rollup says **Copied, switched off.**, **Copy updated, switched off.** (it
   was imported before) or **Not copied:** and the reason. Click **Compare** on a copy to see up
   to five records of its object: **Value Now (DLRS)** is what DLRS wrote, **BarnCRM Value** is
   what the copy calculates, and **Result** says **Same**, "Blank in one, zero in the other" or
   "The values differ." Nothing is written. Click **Next**.
4. **Turn On.** Click **Turn On** on each copy. **Switch Off the DLRS Rollup** asks first, as
   above; **OK** turns the copy on and records your answer in **Recent Changes**. **Finish** is
   available once every copy is on. Then switch each DLRS rollup off in DLRS.

**Close** leaves at any step. Copies already made stay switched off, and you can turn them on
later in the rollup list (which asks the same question). Importing again updates the same
copies rather than adding new ones: each copy's Definition Key is `DLRS_` and the DLRS
rollup's name. A copy already turned on is not offered again.

How each DLRS setting is copied:

| DLRS setting | In BarnCRM |
|---|---|
| Parent Object, Child Object, Relationship Field | The rollup's object, field and the records it counts, when the Builder offers those records by that lookup |
| Aggregate Operation | Sum, Max, Min, Avg, Count, Count Distinct, Concatenate (Text list), Concatenate Distinct (Text list, each value once), First, Last |
| Field to Aggregate | The field read. For Count, any field but Id becomes a filter "is not blank", since DLRS counts only records with it filled |
| Relationship Criteria | The filter, when it compares fields with values (equals, not equals, greater or less, blank or not, in a list, starts with, contains, this year, last year, last n days), joined by AND, OR and NOT |
| Field to Order By | One field, ascending or descending. A descending First becomes Last, and the other way round. BarnCRM lists blank values last |
| Row Limit | Kept for Sum, Avg, Min, Max and the text lists; left out of First, where it changes nothing |
| Concatenate Delimiter | Comma, Semicolon, Pipe or New line when it is one of those; otherwise Custom, up to 10 characters, a space at either end kept (DLRS's SP() and TB()). Blank becomes Comma |
| Aggregate All Rows | **Include deleted and archived records** |
| Bypass Permission | Kept |
| Calculation Mode | Realtime, Developer and Process Builder become **Both** (updated as records change and every night); Scheduled stays **Scheduled** |
| Calculation Sharing Mode | Not kept: BarnCRM counts every record, whoever saves |

A DLRS rollup stays in DLRS, and the wizard says why, when:

- its operation has no BarnCRM total;
- its Relationship Criteria uses anything the filter cannot hold, such as a subquery, a
  function like CALENDAR_YEAR, a comparison of two fields or another LIKE pattern (the reason
  quotes the part);
- it orders by more than one field, or puts blank values first (NULLS FIRST);
- it has a Row Limit on Last, Count or Count Distinct;
- its delimiter is longer than 10 characters or covers more than one line;
- the Builder does not offer its records by its lookup for its object;
- an active BarnCRM rollup already fills its field, or its copy is already on;
- or any other Builder check refuses it, with the Builder's own words.

Rebuild those by hand in the Builder if you want them in BarnCRM, or leave them running in
DLRS on a field BarnCRM does not fill.

## Current Limits

Fund totals and soft credit totals, including a household's soft credit totals, now update
instantly like every other giving total: saving a gift allocation or a soft credit moves them,
and so does changing a gift's status or deleting a gift. What is not here yet:

- **The Builder does not deploy the instant-totals trigger for you.** You add it in a sandbox
  and move it with a change set (or the Salesforce CLI), as in
  [With a Generated Trigger](#with-a-generated-trigger). A one-click deploy may come later.
- **The Builder does not create a field itself.** **Create a Field** in step 1 writes it (Setup
  steps, its source, and a package to deploy); you create it, then click **Refresh Fields**.
- **BarnCRM is checked against its previous rollup engine** before that engine is removed
  from the package. A developer runs the comparison on a test org; it changes nothing in your
  data.

## A Five-Minute Walkthrough

Do this as Maria, with the sample data loaded. Steps 2 to 5 use the giving totals, so they
need the Giving module; without it, do them on a rollup you have added.

1. Open the **BarnCRM** app. On the home page, find the **Rollups** tile. It reads
   "Rollups Last Completed" with a time. If it has been more than 36 hours, the tile turns
   into a warning and offers a link to the Rollups section of **BarnCRM Settings**, which
   opens the Rollup Builder. Click that link, or open the **Rollup Builder** tab in
   **BarnCRM Admin**.
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
   last calculated time moves to a moment ago when the run finishes. **Recalculate All**
   at the top does the same for every active rollup at once, **Instantly** ones included.
5. Open any household record. Its giving totals now match what you just recalculated. If
   any of them changed, the **Rollups last calculated** field on the record shows the time
   of that run; if none did, it keeps its earlier time, because the run found nothing to
   change. That field is
   the answer to "is this number current" for one record; the Rollup Builder answers it for
   the whole org.
6. Go back to the BarnCRM home page. The Rollups tile shows the time you just recalculated.

## Common Mistakes

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
[After the save, or during it](#after-the-save-or-during-it)).

**Expecting an import's totals the moment it finishes.** Totals from a bulk change are
queued and catch up within minutes, not in the same instant. Give it a few minutes before
checking. If a number still has not moved, look at **Needs Attention** in the Rollup Builder,
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

**Turning the module off and forgetting it.** **Turn Off** on the BarnCRM Rollup Builder row
of **BarnCRM Settings**, **Modules** stops every rollup at once, Giving's included: saves,
the Flow action, the queue, the nightly run and a recalculation already running all stop,
and nothing is processed while it is off. **Recalculate**, **Recalculate All** and **Run
tonight** say the module is off; a rollup you save in the Builder then is saved and calculated
once it is on. The values on your records stay. **Turn On** puts every total right: it starts
the totals that waited and a recalculation of every active rollup, which runs in the
background. **Check rollups before saving** pauses with the module, so a rollup saved while
it is off is not checked; the recalculation skips one whose field cannot hold its result and
the Error Log says why. See [Module Manager](module-manager.md).

**Turning a rollup off and expecting the number to clear.** Setting a rollup to inactive
stops it being recalculated; it does not erase the values already on the records. That is
deliberate, so that turning something off never destroys data. If you want the field
empty, clear it after you make the rollup inactive.

**Deleting a shipped rollup you do not want.** **Delete** refuses a rollup that came with
BarnCRM, because a shipped rollup that is gone would be created again (an upgrade or
**Restore Shipped Rollups** cannot tell it from one never created). Clear its **Active** box
instead. That is remembered, and it leaves the numbers already calculated on the records.

**Never starting the nightly schedule.** If nobody clicks **Schedule nightly
recalculation**, nothing recalculates overnight and the home page tile stays in warning. Nothing
schedules it for you. The tile is the only warning you get, so act on it.

**Changing the fiscal year in Setup and stopping there.** The year based totals are
recalculated with the new fiscal year at the next run, not the moment you save it in Setup.
After changing it, click **Recalculate All**, or wait for the nightly run.

## Field Reference

For report builders only. Nothing on this page requires you to know these.

| What you see | Field |
|---|---|
| Rollups last calculated, on a record | `Rollups_Last_Calculated__c` |
| Last calculated, in the Rollup Builder | `Last_Calculated__c` on Rollup Definition |
| Calculation, and the delimiter of a text list | `Aggregate__c` and `Delimiter__c` on Rollup Definition |
| Which record comes first, by; Order; Only the first N records | `Order_By_Field__c`, `Order_Direction__c` and `Row_Limit__c` on Rollup Definition |
| Custom delimiter; Include deleted and archived records | `Custom_Delimiter__c` and `Include_Deleted__c` on Rollup Definition |
| Skip for people with this custom permission | `Bypass_Permission__c` on Rollup Definition |
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
