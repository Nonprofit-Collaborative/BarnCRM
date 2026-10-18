# Volunteers

## What it does

The BarnCRM Volunteers module keeps track of the work volunteers do: the **jobs** your
organization needs help with, the dated **shifts** of each job, who **signed up** for a shift,
and the **hours** each person gave. A volunteer is a person you already have in BarnCRM, so
there is no separate volunteer record: the module adds a few volunteer details to people (status,
volunteer since, emergency contact, availability) and links their sign-ups and hours to them.

Hours are entered by staff. When **Hours require approval** is on, a new entry waits as
**Submitted** until a coordinator approves or rejects it, and only approved hours count in any
total. Marking a sign-up **Attended** creates its hours for you (the **Attendance creates hours**
setting, on by default), so nobody types them twice. While automation is paused, attendance
creates no hours and nothing catches up later: enter those hours by hand. There is no volunteer
portal: volunteers do not log in.

This page covers installing the module, who gets which access, its settings and recurring
shifts. Approving hours on screen, the hour totals on people and the coordinator dashboard each
come with a later part of the module, and this page will say so as each arrives.

## Before you install

- Volunteers is offered in the **Nonprofit Edition** only (see [Editions](editions.md)).
- It needs the **BarnCRM Rollup Builder** module installed first: the volunteer totals are
  rollups. Install order is BarnCRM Core, BarnCRM Rollup Builder, then BarnCRM Volunteers.
- Giving is not needed.

## Installing

Install it from **Module Manager** (see [Module Manager](module-manager.md)). When the install
finishes, BarnCRM does three things on its own:

1. Creates the switch rows for the module's automations on the **Automation** page.
2. Gives you, the person who installed it, the **Volunteers Admin** permission set.
3. Gives everyone who already has a BarnCRM role the Volunteers permission set for that role
   (next section). This runs in the background and takes a minute or two in a large org.

Open the **BarnCRM Volunteers** app from the App Launcher. It has the tabs **Volunteer Jobs**,
**Volunteer Shifts** and **Volunteer Hours** for everyone with a Volunteers set, and
**Volunteer Settings** for admins only.

## Roles and permission sets

You never assign the Volunteers permission sets by hand. Give people their BarnCRM role on the
[Access](access.md) page as usual, and the module gives each role its Volunteers set:

| BarnCRM role | Volunteers set they get | What they can do |
|---|---|---|
| Admin (anyone holding BarnCRM Admin) | Volunteers Admin | Everything, including deleting a record entered by accident and the Volunteer Settings tab |
| Coordinator | Volunteers Coordinator | Everything Staff does, plus see and correct everyone's hours to approve or reject them |
| Team Member | Volunteers Staff | Set up jobs and shifts, sign people up, enter hours; never deletes |
| Read Only | Volunteers Read Only | Look at jobs, shifts, sign-ups and volunteer details; sees no hours entries (see below) |

The Coordinator and Team Member roles give the same access to people and households, so the
module tells them apart by the role itself.

When it happens:

- **At install**, for everyone who already has a role.
- **When you give a role on the Access page**, within a minute.
- **When you turn the module back on** in Module Manager, for anyone given a role while it was off.
- **Every night**, with BarnCRM's nightly access check (one o'clock), for anyone given a role in
  Setup rather than on the Access page.

The module only ever gives a set: it never takes one away. If someone leaves a role, remove
their Volunteers set too, in Setup under **Users**, **Permission Set Assignments**.

**Volunteer Hours are private by default.** A Team Member sees the hours they entered
themselves; a Coordinator or Admin sees everyone's. A Read Only user enters none, so sees no
hours entries at all. The totals on a person (when they arrive) count every approved entry
whoever entered it, and everyone who can see the person sees them.

## Settings

As an admin, open the **Volunteer Settings** tab in the BarnCRM Volunteers app, or the
**Volunteers** section of **BarnCRM Settings**: both show the same three settings, and each
saves as you change it.

| Setting | Default | What it does | Takes effect |
|---|---|---|---|
| Hours require approval | On | New hours wait as Submitted for a coordinator. Off means an entry counts as soon as it is saved. | Now |
| Attendance creates hours | On | Marking a sign-up **Attended** writes the hours for that shift, so nobody types them twice. | Now |
| Shift horizon weeks | 8 | How many weeks ahead recurring schedules keep their shifts created, from 1 to 26. Blank means 8. | A longer horizon at the next nightly run or schedule save; a shorter one removes no shift already created |

## Recurring shifts

Most volunteer work repeats. Instead of adding each Saturday's shift by hand, add a **shift
schedule** to the job: on the job, in the **Shift Schedules** list, click **New** and fill in:

| Field | What to enter |
|---|---|
| Schedule Name | What you call it, for example "Saturday sorting". |
| Weekdays | The days a shift falls on. Pick several for "Tuesdays and Thursdays". |
| Every N Weeks | 1 for every week, 2 for every other week, counted from the week of the start date. |
| Start Time, End Time | The times of each shift, in your organization's time zone (Setup, **Company Information**). A 9:00 shift stays at 9:00 when the clocks change. |
| Start Date, End Date | The first and last days a shift may fall on. Leave End Date empty to keep it running. |
| Volunteers Needed | The places on each shift. |
| Location | Copied to each shift. Leave it empty to use the job's location. |
| Active | Untick to end the schedule. |

When you save, BarnCRM creates the schedule's shifts from today up to the **Shift horizon
weeks** ahead (8 by default), usually within a minute. Each is an ordinary shift: people sign up,
attend and log hours on it as on any other. It appears in the job's **Shifts** list and shows the
schedule it came from. Every night
at 3:00 AM BarnCRM adds the next days, so the schedule always reaches the horizon. **Created
Through** on the schedule shows the last day it has created shifts for.

**Changing a schedule changes only future shifts nobody is using.** When you change the days,
Every N Weeks, times, start date, places or location, BarnCRM removes the schedule's future
shifts that have no sign-ups, no hours and are not cancelled, and creates them again from the
new pattern. Past shifts, shifts with a sign-up or hours, and cancelled shifts are kept as they
are, and no day gets a second shift. **Shifts Kept** on the schedule then says how many future
shifts were kept: check those by hand, because they still have the old times. Changing only the
name changes no shift.

**Ending a schedule.** Untick **Active**, or set an earlier **End Date**: the future shifts it no
longer covers that have no sign-ups or hours and are not cancelled are removed, and the rest
stay. Tick **Active** again, or set a later **End Date**, and the missing days are created again.
An admin can delete a schedule: its future shifts with no sign-ups or hours go with it, and the
shifts that stay lose their link to it.

**Taking one day off.** Open that day's shift and set its **Status** to Cancelled. Do not delete
it: a deleted shift comes back the next time you change or restart the schedule, a cancelled one
does not.

**Coordinators and Team Members** create and change schedules; only an admin deletes one. The
shifts a change removes are removed for them, although they cannot delete shifts themselves.
Read Only users see schedules and change nothing.

**The nightly run** is one of BarnCRM's nightly jobs. If **Health Check** says "Volunteer shift
schedules" is not scheduled, use its **Schedule all nightly jobs** fix. While Volunteers is turned
off, no shifts are created; the first night after you turn it back on catches up.

## Turning it off

Turning Volunteers off in Module Manager stops its automations; the records stay. Hours saved
while it is off are not totalled until it is back on and the next nightly run has finished. No
Volunteers set is given while it is off.

## A five-minute walkthrough

Do this as Maria, who holds the Admin role, with a second user, Priya, who has none yet.

1. On the [Access](access.md) page, give Priya the **Coordinator** role.
2. In Setup, open Priya's user record and look at **Permission Set Assignments**. Within a
   minute she holds **Volunteers Coordinator**.
3. Open the **BarnCRM Volunteers** app. On **Volunteer Jobs**, create a job called "Food
   pantry" with yourself as **Coordinator**.
4. On the job, add a shift for next Saturday from 9:00 to 12:00 with **Volunteers Needed** 3.
5. On the shift, add a sign-up for any person in your sample data.
6. Change the sign-up's status to **Attended**. On **Volunteer Hours**, a 3-hour entry for that
   person on that shift now exists. It is **Submitted** and appears in the **Hours awaiting
   approval** list view (or **Approved** if Hours require approval is off). You can also enter
   hours by hand there.
7. Open **Volunteer Settings** and read the three settings. Leave them as they are.

## Importing volunteer hours

To bring in hours kept in a spreadsheet, use the **Volunteer hours** template on the Import tab.
It is added when Volunteers is installed and appears only where Volunteers is. It loads one
Volunteer Hours record per row, using the Core import's **Load one object** (see
[Importing](importing.md), section 9), so the preview, results, exceptions download and undo
all work as they do for any import.

### The columns

Use these headings in the first row of a CSV or Excel file. Order does not matter.

| Column | Required | What it does |
|---|---|---|
| Email | Yes | Finds the volunteer by email address (the Contact's **Email**, or **Email** on a person account). |
| Job | Yes | Finds the Volunteer Job by its exact name (capitals and surrounding spaces are ignored). |
| Date | Yes | The **Date Worked**, for example `2026-03-14`. |
| Hours | Yes | **Hours**, greater than zero, to two decimal places. |
| Notes | No | What the person did. |

There is no Status column, and a file cannot approve its own hours. While **Hours require
approval** is on in Volunteer Settings (the default), every row starts **Submitted** and waits in
the **Hours awaiting approval** list view for a coordinator; a template changed to name any other
status has those rows rejected. When it is off, rows are **Approved** at once, by the person who
runs the import, as for hours entered by hand. There is no Shift column, because shift names
repeat; the hours still count toward the job.

### Walkthrough

1. Make a file with the columns above, for example `volunteer@example.org, Food pantry,
   2026-03-14, 3, Sorted donations`. Every job named must already exist under **Volunteer
   Jobs**, and every email must belong to someone already in BarnCRM.
2. Open the **Import** tab, select **Volunteer hours**, then **Next**, and upload the file.
3. Check that each column is matched to its field, then select **Preview**. Nothing is written.
4. Read the counts. A row whose email matches nobody, or whose job matches no job, is
   **rejected** and named in the table with the reason; select **Download exceptions**, correct
   those rows in your spreadsheet and import them again. An email shared by several people is
   handled by the **Several matches** choice (**Reject the row** unless you change it).
5. Select **Import**. Open **Volunteer Hours** to see the new entries.

Approved hours are locked: the import only adds new entries and never changes an existing one,
so it cannot alter hours a coordinator has approved. Importing a file twice adds the hours
twice. To take back a wrong import, use **Undo** on its results (see [Importing](importing.md),
section 5). Undo removes only entries that are still **Submitted**, and only when the person
undoing holds the Volunteers Coordinator or Admin role; approved hours are never deleted, so
they are kept and listed in the import's journal. With **Hours require approval** off every
imported entry is Approved at once, so check the file before you import: taking one back means
a coordinator reopens it (back to Submitted) and then deletes it.

To import, a person needs the BarnCRM Admin role (for the Import tab) and a Volunteers role
that enters hours (Team Member, Coordinator or Admin), since the load runs with that person's
own permissions.

## Common mistakes

**Importing hours twice.** Each row becomes a new entry whether or not an identical one exists.
Check **Volunteer Hours** before re-running a file, or undo the first import.

**Assigning the Volunteers sets by hand instead of a role.** It works, but the person keeps the
set when their role changes. Give the role and let the module give the set.

**Looking for someone else's hours as a Team Member.** Hours are private; a Coordinator sees them
all.
