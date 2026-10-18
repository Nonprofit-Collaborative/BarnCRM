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

This page covers installing the module, who gets which access, and its settings. Approving hours
on screen, the hour totals on people, the coordinator dashboard and recurring shifts each come
with a later part of the module, and this page will say so as each arrives.

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
**Volunteer Shifts**, **Volunteer Hours** and **Skills** for everyone with a Volunteers set,
**Volunteer Requirements** for Admins and Coordinators, and **Volunteer Settings** for admins
only.

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

## Skills and interests

The module keeps your own list of skills and interests, for example "Spanish", "Forklift
licence" or "Working with children". It ships none: you write the list.

**Build the list.** Open the **Skills** tab and create one record per skill, with an optional
description (for example which licence counts). **Active** is on by default. A skill's page
lists the people who hold it (**Volunteer Skills**).

**Give skills to people.** On a person (a Contact, or an Account where your people are person
accounts), add a **Volunteer Skill**: pick the skill and a **Type**. **Skill** means the person
can do it; **Interest** means they would like to. A volunteer skill belongs to one person:
fill in the contact or the account, never both.

**Say which skills a job needs.** On a job, add a **Job Skill** from the **Job Skills** list for
each skill the job needs. Deleting the job deletes its job skills.

**Retire a skill, do not delete it.** A skill that any person holds or any job needs cannot be
deleted. Untick **Active** instead: it stays on the people and jobs that have it, and it cannot
be given to anyone or any job new. Saving a new volunteer skill or job skill with a retired
skill is refused with a message, as is changing an existing one to it. Tick **Active** again
to bring it back. A skill nobody holds or needs can be deleted.

**Repeats do no harm.** Nothing stops the same skill being added to a person twice (an import,
for example), and it changes no answer: matching asks whether a person holds a skill, not how
many times.

Who can do what: Admins and Coordinators manage the list and anyone's skills. Team Members add
skills to people and remove the ones they added, and can read the list. Read Only users read.
Admins, Coordinators and Team Members all add and remove a job's skills.

Finding volunteers for a shift by skill and availability arrives with a later part of the
module; until then the records are the data it will use.

## Onboarding requirements

Each onboarding step a volunteer goes through is one **Volunteer Requirement** on the person (a
Contact, or an Account where your people are person accounts): an **Application**, a
**Background check** or an **Orientation**. You can add more types in Setup (the **Type** field's
picklist values). Fill in the contact or the account, never both.

**One row per step started.** Add a row when a person starts a step. When a step lapses and is
done again, add a new row rather than overwriting the old one, so the history stays.

| Field | What it means |
|---|---|
| Status | Not started, In progress, Completed or Not approved. |
| Completed Date | The day the step was done. Required when the status is Completed, and not in the future. |
| Expires | The day a completed step lapses, for example two years after a background check. Empty means it does not lapse. It cannot be before the completed date. |
| Notes | A short note for the coordinator, such as the reference of a check. Never write what a check found. |
| Is Current | Worked out for you: ticked when the status is Completed and the step has not expired. |

Open the **Volunteer Requirements** tab in the BarnCRM Volunteers app (Admins and Coordinators
only) and choose the **Not Current** list view to see every step that is not completed or has
lapsed, or **All Requirements** for every row.

**Show skills and requirements on the person.** BarnCRM Core's person page layout belongs to
Core, so the module cannot add its lists to it. Add them once, in Setup: **Object Manager**,
**Contact** (or **Account** where your people are person accounts), **Page Layouts**, open the
layout your people use, choose **Related Lists**, and drag **Volunteer Skills** and **Volunteer
Requirements** onto the layout. Save. Team Members and Read Only users never see the
requirements list's rows, whatever the layout shows.

**Readiness at a glance.** In the BarnCRM Volunteers app, a person opens on the **Volunteers
Contact Record Page** (or the **Volunteers Account Record Page** for a person account): BarnCRM
Core's person page plus a **Volunteer readiness** card. The card lists every requirement type
(Application, Background check, Orientation and any you added) with the person's most recently
added row for it: its status, completed date and expiry, and **Current** or **Not current**. A
type the person has no row for says **Not started**. Click a type to open its row. The card
only reads: it never stops a sign-up or hours. Admins and Coordinators see it; for Team
Members and Read Only users, and on a household or organization, the card shows nothing. After
adding a row, click the card's **Refresh** button to see it.

- **In the BarnCRM app, people open on Core's page, which has no readiness card.** To show it
  there too, open Setup, then **Lightning App Builder**, edit **Volunteers Contact Record
  Page**, choose **Activation**, then **App, Record Type, and Profile**, and assign it to the
  BarnCRM app on desktop and phone. Do the same for **Volunteers Account Record Page** where
  your people are person accounts.
- **On a record page of your own**, open it in the Lightning App Builder, drag the **Volunteer
  Readiness** component onto it, and save. To have both giving and readiness on one page, clone
  **Giving Contact Record Page** (a packaged page is replaced on upgrade), add the component to
  the copy, and assign the copy.

**Nothing is blocked.** A person whose steps are not current can still be signed up and log
hours. The coordinator decides.

**Who sees them.** Requirements are private. Only Volunteers Admin and Volunteers Coordinator
read and edit them, all of them, whoever created the row. Team Members and Read Only users
cannot see them at all. The result of a background check is kept on the requirement and nowhere
else.

**Erasing a person.** [Erasing a person](erase-a-person.md) deletes their requirements and
empties them from the Recycle Bin. The Erasure record lists them by Id only. The person erasing
must also hold Volunteers Admin or Volunteers Coordinator: otherwise the erasure is refused, so a
background check is never left behind.

**Deleting a person.** Deleting a person (or a household or organization, with the people in
it) deletes their requirements and volunteer skills too, whoever deletes them, even someone who
cannot see requirements. Unlike erasing, this leaves them in the Recycle Bin for its usual 15
days. Merging duplicates is not deleting: the person you keep gets the other's requirements and
skills, background checks included. Restoring a person from the Recycle Bin does **not** bring
their requirements and skills back: re-enter them. This cannot be switched off, because a
background check must never outlive its person.

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

## Common mistakes

**Assigning the Volunteers sets by hand instead of a role.** It works, but the person keeps the
set when their role changes. Give the role and let the module give the set.

**Looking for someone else's hours as a Team Member.** Hours are private; a Coordinator sees them
all.
