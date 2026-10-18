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

This page covers installing the module, who gets which access, its settings and the **Approve
Hours** screen. The hour totals on people, the coordinator dashboard and recurring shifts each
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
**Volunteer Shifts** and **Volunteer Hours** for everyone with a Volunteers set, **Approve
Hours** for coordinators and admins, and **Volunteer Settings** for admins only.

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
saves as you change it. The first two settings are already in effect; the third takes effect
with recurring shifts, and until then changing it changes nothing.

| Setting | Default | What it does | Takes effect |
|---|---|---|---|
| Hours require approval | On | New hours wait as Submitted for a coordinator. Off means an entry counts as soon as it is saved. | Now |
| Attendance creates hours | On | Marking a sign-up **Attended** writes the hours for that shift, so nobody types them twice. | Now |
| Shift horizon weeks | 8 | How many weeks ahead recurring schedules keep their shifts created, from 1 to 26. Blank means 8. | With recurring shifts |

## Approving hours

Coordinators and admins (anyone holding **Manage Volunteers**) approve hours on the **Approve
Hours** tab of the BarnCRM Volunteers app. It lists hours entries oldest first, 50 to a page,
with the person, job, shift, date worked and hours of each.

- **Show** picks which entries are listed: **Submitted** (the default, the ones waiting for
  you), **Approved** or **Rejected**. **Job**, **From** and **To** narrow the list to one job and
  a range of dates worked. The list changes as you change a filter.
- Tick the entries to act on, or tick the box in the heading row to select the whole page.
- **Approve** approves the selected entries: they count in totals from now on, and record you
  and the time as who approved them.
- **Reject** asks for a reason, which is required, then rejects the selected entries with it. The
  person who entered them sees the reason on the entry.
- **Reopen**, on the Approved and Rejected lists, moves the selected entries back to Submitted, so
  they can be corrected, deleted or decided again. An approved entry cannot be edited or deleted
  until it is reopened.

A message under the buttons, also shown as a toast, says how many entries moved. An entry that
could not be moved (one you can see but not edit, for example) is named there with the reason,
and the others still move. **Previous** and **Next** move between pages.

Someone without Manage Volunteers who opens the screen sees a note saying approving needs that
permission, and the list without the buttons. Read Only users see no hours at all.

Approving here is the only way an entry's status changes: editing the Status field on the record
is refused, for everyone.

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
7. Open **Approve Hours**. The entry is listed under **Submitted**. Tick it and click
   **Approve**: the message says one entry was approved, and the list is empty.
8. Change **Show** to **Approved**, tick the entry and click **Reopen**. It is back under
   **Submitted**. Tick it, click **Reject**, type "Wrong date" as the reason and confirm.
9. Open **Volunteer Settings** and read the three settings. Leave them as they are.

## Common mistakes

**Assigning the Volunteers sets by hand instead of a role.** It works, but the person keeps the
set when their role changes. Give the role and let the module give the set.

**Looking for someone else's hours as a Team Member.** Hours are private; a Coordinator sees them
all.
