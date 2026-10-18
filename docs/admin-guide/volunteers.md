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
4. Adds the two shipped letter templates, an hours letter and a certificate (see
   [Hour letters and certificates](#hour-letters-and-certificates)). An upgrade adds only a
   shipped template you do not have, and never changes one you edited.

Open the **BarnCRM Volunteers** app from the App Launcher. It has the tabs **Volunteer Jobs**,
**Volunteer Shifts** and **Volunteer Hours** for everyone with a Volunteers set, and
**Volunteer Letter Templates** and **Volunteer Settings** for admins only.

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
person Ids, a template Id and the period, and makes the letters in the background, ten people
at a time; each appears in that person's **Files** within a few minutes. To find a template's
Id, open the template: the Id is the 18-character code in the address, just before `/view`.
People with no approved hours in the period are skipped. The run sends no message when it ends;
if a letter you expected is missing, check the person's hours and the [Error Log](error-log.md).

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

**A letter shows fewer hours than expected.** A letter counts only Approved hours in the period.
Approve the Submitted entries first, and check the From and To dates.
