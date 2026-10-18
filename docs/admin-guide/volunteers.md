# Volunteers

## What it does

The BarnCRM Volunteers module keeps track of the work volunteers do: the **jobs** your
organization needs help with, the dated **shifts** of each job, who **signed up** for a shift,
and the **hours** each person gave. A volunteer is a person you already have in BarnCRM, so
there is no separate volunteer record: the module adds a few volunteer details to people (status,
volunteer since, emergency contact, availability) and links their sign-ups and hours to them.

**Where the volunteer details show.** In the BarnCRM Volunteers app a person opens on the
**Volunteers Contact Record Page** (or **Volunteers Account Record Page**), which has a
**Volunteer Profile** section: status, volunteer since, availability and emergency contact,
which you edit there, and the approved hour totals and first and last volunteer dates, which
BarnCRM calculates and you only read. The section shows once a person has a Volunteer Status
(Prospective, Active or Inactive; a status value you add yourself also needs adding to the
section's visibility rule in the Lightning App Builder) or approved hours. Admins and Coordinators (who hold Manage Volunteers) always see it, so they can
set the status of someone new. On an account, the person details show only on a person
account; a household or organization shows its hour totals once it has some. Other apps keep
their own person page (see Readiness at a glance, under Onboarding requirements).

Hours are entered by staff. When **Hours require approval** is on, a new entry waits as
**Submitted** until a coordinator approves or rejects it, and only approved hours count in any
total. Marking a sign-up **Attended** creates its hours for you (the **Attendance creates hours**
setting, on by default), so nobody types them twice. While automation is paused, attendance
creates no hours and nothing catches up later: enter those hours by hand. There is no volunteer
portal: volunteers do not log in.

This page covers installing the module, who gets which access, its settings, the volunteer
totals, the coordinator dashboard, the **Sign-ups** panel on a shift, the **Approve Hours**
screen and recurring shifts.

## Before you install

- Volunteers is offered in the **Nonprofit Edition** only (see [Editions](editions.md)).
- It needs the **BarnCRM Rollup Builder** module installed first: the volunteer totals are
  rollups. Install order is BarnCRM Core, BarnCRM Rollup Builder, then BarnCRM Volunteers.
- Giving is not needed.

## Installing

Install it from **Module Manager** (see [Module Manager](module-manager.md)). When the install
finishes, BarnCRM does five things on its own:

1. Creates the switch rows for the module's automations on the **Automation** page.
2. Creates the volunteer totals on the **Rollups** page (see [Volunteer totals](#volunteer-totals)).
3. Gives you, the person who installed it, the **Volunteers Admin** permission set.
4. Gives everyone who already has a BarnCRM role the Volunteers permission set for that role
   (next section). This runs in the background and takes a minute or two in a large org.
5. Adds the two shipped letter templates, an hours letter and a certificate (see
   [Hour letters and certificates](#hour-letters-and-certificates)). An upgrade adds only a
   shipped template you do not have, and never changes one you edited.

Open the **BarnCRM Volunteers** app from the App Launcher. It has the tabs **Volunteer Jobs**,
**Volunteer Shifts**, **Volunteer Hours** and **Skills** for everyone with a Volunteers set,
**Approve Hours** and **Volunteer Requirements** for coordinators and admins, and **Volunteer
Letter Templates** and **Volunteer Settings** for admins only.

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
hours entries at all. The totals on a person count every approved entry whoever entered it, and
everyone who can see the person sees them.

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

- **In the BarnCRM app, people open on Core's page, which has neither the readiness card nor
  the Volunteer Profile section (see What it does).** To show them there too, open Setup, then **Lightning App Builder**, edit **Volunteers Contact Record
  Page**, choose **Activation**, then **App, Record Type, and Profile**, and assign it to the
  BarnCRM app on desktop and phone. Do the same for **Volunteers Account Record Page** where
  your people are person accounts.
- **On a record page of your own**, open it in the Lightning App Builder, drag the **Volunteer
  Readiness** component onto it, add a field section with the volunteer fields, and save. To
  have both giving and volunteering on one page, clone
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

## Hour letters and certificates

A coordinator can give a volunteer a PDF letter stating their hours (for a school service
requirement, court ordered service or an employer's matching program) or a certificate of
service. Each one counts only **Approved** hours with a **Date Worked** in the period chosen, and
only the hours the coordinator can see. It is saved as a file on the person's record (the
**Files** list), and that file is the record that it was given. Giving is not needed.

**Who can.** Making a letter needs the **Manage Volunteers** permission, which the Volunteers
Coordinator and Volunteers Admin sets give. Only Volunteers Admin edits templates.

**Templates.** On the **Volunteer Letter Templates** tab, each template has a **Type** (Hours
letter or Certificate), a **Body** of HTML and an **Active** box. One template per type is
active: ticking **Active** on one clears it on the others of its type. Edit the shipped
templates or write your own. The body can use these tokens, each filled in when the letter is
made:

| Token | Filled with |
|---|---|
| `{OrganizationName}`, `{OrganizationAddress}` | The organization's legal name and address from BarnCRM Settings |
| `{PersonName}`, `{FirstName}` | The person's name, and their preferred name (or first name) |
| `{Hours}` | Their approved hours in the period |
| `{JobList}` | A list of each job with its hours in the period |
| `{FromDate}`, `{ToDate}`, `{Today}` | The period and the day the letter was made |

A token spelled wrong is printed as typed, so a test letter shows the mistake. Names and job
titles are printed as plain text, so a person or job name can never change the layout. Keep the
HTML simple (paragraphs, headings, lists, inline styles): the PDF service does not run scripts.
Fill in your legal name and address in the Organization section of BarnCRM Settings first;
until you do, those tokens print nothing.

The shipped templates come back at every upgrade if you delete them (inactive when their type
already has an active template). To stop using one, clear its **Active** box rather than
deleting it.

**One person.** The **Volunteer letter** action is on no page until you add it. In Setup, go to
**Object Manager**, **Contact**, **Page Layouts**, open each layout your people use, choose
**Mobile & Lightning Actions** in the palette, and drag **Volunteer letter** into the
**Salesforce Mobile and Lightning Experience Actions** section. If that section says its actions
are predefined, click **override the predefined actions** first. If your people are held as
person accounts, do the same under **Object Manager**, **Person Account**, **Page Layouts**.

On a person, click **Volunteer letter**, choose the template and the period, click **Preview**
to read it, then **Generate**. The action offers the active template of each type, so make a
new template active to try it. A person with no approved hours in the period gets no letter,
and the action says so. On a household or organization account the action says that letters
are for people.

**A list of people.** In Flow Builder, the **Generate volunteer letters** action takes a list of
person Ids, a letter **Type** and the period, and makes the letters in the background, ten people
at a time; each appears in that person's **Files** within a few minutes. The Type is the picklist
value as written on the template, **Hours letter** or **Certificate**, and the action uses that
type's active template. If the type has no active template, or the period is missing or
reversed, the action stops before anything starts and its fault path carries a message saying
why. Several requests in one transaction (for example a record-triggered flow on 200 records)
run as one job.

**When it ends.** The person who started the job gets one notification (the bell, and the mobile
app) with how many letters were made, how many people were skipped and why (for example no
approved hours in the period), and how many failed; for failures it points to the
[Error Log](error-log.md). It is the BarnCRM job notification, so the **Job notifications**
option in BarnCRM Settings turns it off.

## Signing people up for a shift

Open a shift (from **Volunteer Shifts**, or from its job). The **Sign-ups** panel at the top
of the page shows how many **volunteers are needed**, how many **slots are filled** and how many
**remain**, and lists who is signed up. A cancelled sign-up frees its slot; slots remaining goes
below zero when more people are booked than were asked for, which is allowed.

- **Add sign-up** opens a short form: choose the **Person** (in an org where people are person
  accounts, only person accounts are offered), pick a **Status** if it is not **Signed up**, and
  click **Save**. Signing the same person up twice for one shift is refused, with a message
  naming the shift: change the sign-up that is there instead.
- Change a sign-up's **Status** in its row: Signed up, Confirmed, Attended, No show or
  Cancelled. The change saves at once.
- **Attended** and **No show** in each row mark attendance in one click. When **Attendance
  creates hours** is on, marking someone Attended records their hours for the length of the
  shift, waiting for approval like any other entry, and the panel says so. Marking attendance a
  second time records nothing more, and changing it back deletes nothing.
- Click a person's name to open their sign-up record. The shift page also has a **Sign-ups**
  related list below the details: use it to edit a sign-up's **Notes** (row menu, **Edit**) or to
  remove one (row menu, **Delete**, which asks you to confirm). To keep the record but free the
  slot, set its **Status** to Cancelled instead of deleting it.

A message under the figures, also shown as a toast, says what changed. Read Only users see the
panel without the button, pickers or attendance buttons.

## Approving hours

Coordinators and admins (anyone holding **Manage Volunteers**) approve hours on the **Approve
Hours** tab of the BarnCRM Volunteers app. It lists hours entries oldest first, 50 to a page,
with the person, job, shift, date worked and hours of each.

- **Show** picks which entries are listed: **Submitted** (the default, the ones waiting for
  you), **Approved** or **Rejected**. **Job**, **From** and **To** narrow the list to one job and
  a range of dates worked. The list changes as you change a filter. A **From** date later than
  the **To** date is refused with a message on the field, and the list stays as it was.
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
and the others still move. **Previous** and **Next** move between pages; when one of them has
nowhere left to go, keyboard focus moves to the other, or to the page number.

Someone without Manage Volunteers who opens the screen sees a note saying approving needs that
permission, and the list without the buttons. Read Only users see no hours at all.

Approving here is the only way an entry's status changes: editing the Status field on the record
is refused, for everyone.

## Volunteer totals

The module adds totals of approved hours to people, households, jobs and shifts. They are
ordinary rollups on the **Rollups** page (see [Rollups](rollups.md)), created at install, each
of which you can edit or switch off there. Only **Approved** hours count: a Submitted or Rejected
entry adds nothing, and reopening an approved entry takes it back out of every total until it is
approved again.

| Where | Total | What it shows |
|---|---|---|
| Person and household | Volunteer Hours Total | Every approved hour this person or household has given. |
| Person and household | Volunteer Hours This Year | Approved hours in the current fiscal year, by Date Worked. |
| Person and household | Volunteer Hours Last Year | Approved hours in the previous fiscal year. |
| Person and household | First Volunteer Date | The first day they gave time, which a service award counts from. |
| Person and household | Last Volunteer Date | The most recent day they gave time, which a lapsed volunteer report counts from. |
| Volunteer job | Total Hours, Last Volunteer Date | Approved hours on the job, and the most recent day anybody worked it. |
| Volunteer shift | Total Hours | Approved hours on the shift. |
| Volunteer shift | Slots Filled | Sign-ups that are not Cancelled. Slots Remaining is Volunteers Needed less this. |

The fiscal year follows the fiscal year start month in **BarnCRM Settings**. A total moves when
the hours or sign-up is saved, by anyone who saves it (a total is read only for every role, so
nobody types one), and the nightly run checks every total again.

**No "last calculated" line on people without Giving.** The line that says when a person's or a
household's totals were last worked out comes from the Giving module. In an org without Giving,
volunteer totals on people are still right, but no such line shows. Jobs and shifts always have
their own **Rollups Last Calculated**.

**While the module is off.** While Volunteers is off (next section), saving hours or sign-ups
does not move any total at once. The nightly run still brings every volunteer total up to date,
on or off, so they catch up by the next morning. To bring them up to date at once, open the
**Rollups** page and click **Recalculate all**.

## The Volunteers dashboard and reports

The module ships one dashboard, **Volunteers**, and four reports it reads, in folders named
**BarnCRM Volunteers**. Nothing has to be built: open the **BarnCRM Volunteers** app, choose
**Dashboards**, open the **BarnCRM Volunteers** folder and open **Volunteers**.

| Chart | What it shows |
|---|---|
| Approved hours this year, by job | One bar per job: the approved hours with a Date Worked this calendar year. Submitted and Rejected hours are not counted. |
| Hours awaiting approval | Every entry still **Submitted**, oldest first, with the date it was entered and the **Days Waiting** since. Ten rows show; click the title for the whole list. |
| Unfilled shifts, next 14 days | **Open** shifts starting in the next 14 days with **Slots Remaining** above zero, soonest first. Cancelled and completed shifts are left out. |
| Lapsing volunteers | People whose **Last Volunteer Date** (last approved hours) was between six and twelve months ago, longest gap first. It reads the Last Volunteer Date total on the person, so it follows approved hours only. |

The reports are ordinary Salesforce reports in the same folder, built on four report types the
module ships (**Volunteer Hours with Job and Shift**, **Volunteer Shifts with Job**, **Volunteer
Sign-ups** and **Volunteers**). Anyone can open one, change a filter and save a copy of their own
without changing what everyone else sees. The Volunteers report type reads people on Contact; an
org whose people are person accounts builds the lapsing report on its own account-based type.

**Who sees what.** The dashboard reads as **The dashboard viewer**, so each person sees only
the hours and sign-ups they are allowed to see: hours are private, so a Coordinator sees them all
and a Team Member sees the hours they can open. The folders ship public read only, and all four
Volunteers permission sets can run and view the reports and dashboards. Only **Volunteers Admin**
can also create and edit them.

**How to change the running user.** If your edition does not offer the dashboard viewer, or your
org has used up its allowance of dashboards that read that way, open the dashboard, choose
**Edit**, and in **View dashboard as** choose a person who can see all volunteer hours, for
example a coordinator. Everyone then sees that person's view, so choose carefully. Save.

**How to add it to the home page.** Open the Home page, choose the gear and **Edit Page**, drag a
**Dashboard** component on, choose **Volunteers** in the BarnCRM Volunteers folder, and save and
activate the page for the BarnCRM Volunteers app.

**Subscribing.** With the dashboard open, choose **Subscribe** to have it emailed to you on a
schedule you pick.

## Turning it off

Turning Volunteers off in Module Manager stops its automations; the records stay. Hours and
sign-ups saved while it is off are counted in the totals at the next nightly run, or when you
click **Recalculate all** on the Rollups page. No Volunteers set is given while it is off.

## A five-minute walkthrough

Do this as Maria, who holds the Admin role, with a second user, Priya, who has none yet.

1. On the [Access](access.md) page, give Priya the **Coordinator** role.
2. In Setup, open Priya's user record and look at **Permission Set Assignments**. Within a
   minute she holds **Volunteers Coordinator**.
3. Open the **BarnCRM Volunteers** app. On **Volunteer Jobs**, create a job called "Food
   pantry" with yourself as **Coordinator**.
4. On the job, add a shift for next Saturday from 9:00 to 12:00 with **Volunteers Needed** 3.
5. Open the shift. In the **Sign-ups** panel click **Add sign-up**, choose any person in your
   sample data and click **Save**. **Slots filled** is 1 and **Slots remaining** is 2.
6. Click **Attended** on that sign-up's row. The panel says an hours entry was recorded. On
   **Volunteer Hours**, a 3-hour entry for that person on that shift now exists. It is
   **Submitted** and appears in the **Hours awaiting approval** list view (or **Approved** if
   Hours require approval is off). You can also enter hours by hand there.
7. Choose **Dashboards**, open the **BarnCRM Volunteers** folder and open **Volunteers**. The
   hours from step 6 show under **Hours awaiting approval** with their days waiting, and the
   shift from step 4 shows under **Unfilled shifts, next 14 days** until it has three sign-ups.
8. Open **Approve Hours**. The entry is listed under **Submitted**. Tick it and click
   **Approve**: the message says one entry was approved, and the list is empty.
9. Change **Show** to **Approved**, tick the entry and click **Reopen**. It is back under
   **Submitted**. Tick it, click **Reject**, type "Wrong date" as the reason and confirm.
10. Open **Volunteer Settings** and read the three settings. Leave them as they are.

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

**A letter shows fewer hours than expected.** A letter counts only Approved hours in the period.
Approve the Submitted entries first, and check the From and To dates.
