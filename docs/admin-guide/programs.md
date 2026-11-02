# Programs

## What It Does

The BarnCRM Programs module records the **programs** your organization runs (a food pantry, an
after-school tutoring program, a job readiness course), the **services** each program offers (a
hot meal, a tutoring hour, a bag of groceries) and who takes part, as **enrollments**. A
participant is a person you already have in BarnCRM, so there is no separate participant record:
an enrollment links a person to a program with a **stage** (Applied, Enrolled, Completed or
Withdrawn) and its start and end dates. Each time a service is given, or a person misses it, is a
**service delivery**: attendance and what was received, in one record.

Each enrollment also carries the person's **intake and eligibility**: when they were first seen,
who referred them, and whether they qualify, and staff keep private **case notes** on it and a
**service plan**: the person's goals, the steps toward each, and when each is next reviewed.
A program can group its participants into **cohorts** (the spring class, the Tuesday group),
add many people to a cohort at once, schedule **sessions** of a service, and take attendance
per session. A **program dashboard** counts enrollments, people served and attendance for a period. A roster
import comes in a later release (P-06). Who sees enrollments
and service deliveries is the **Participant Privacy** preset on the Programs settings page:
everyone with a Programs permission set (the default), or only the people who need to.

## Before You Install

- Programs is offered in the **Nonprofit Edition** only (see [Editions](editions.md)).
- It needs BarnCRM Core and nothing else: not Giving, not Rollup Builder.
- If the Program Management Module (PMM) is installed in your org, BarnCRM lists it on the
  **Integrations** page as an alternative. Use one or the other for the same programs, not both.
  BarnCRM's programs, services and enrollments are laid out so a later PMM migration template
  can move PMM's records across without new fields.

## Installing

Install it from **Module Manager** (see [Module Manager](module-manager.md)). When the install
finishes, BarnCRM does four things on its own:

1. Creates the switch rows for the module's automations on the **Automation** page.
2. Gives you, the person who installed it, the **Programs Admin** permission set.
3. Gives everyone who already has a BarnCRM role their Programs permission set (see below).
4. Applies the Participant Privacy preset (Shared until you change it) and shares any
   enrollments and service deliveries already in the org (see Participant Privacy).

Then open the **BarnCRM Programs** app from the App Launcher. Its tabs are **Programs
Dashboard**, **Programs**, **Enrollments**, **Service Deliveries** and **Case Notes**. These tabs also join the BarnCRM apps.

## Programs Settings

The module adds a **Programs** section to BarnCRM Settings (in the Programs group). Its
**Programs Settings** row opens the module's own settings page, for anyone who can manage BarnCRM
settings (BarnCRM Admin). Everything on it applies to the whole organization: the intake
picklists and Participant Privacy.

**Intake and Eligibility Picklists.** The page lists the three intake picklists on an enrollment
(**Referral Source**, **Eligibility Status** and **Eligibility Basis**) with the choices each
offers now and its default. They ship with:

| Picklist | Choices it ships with | Default |
|---|---|---|
| Referral Source | Self, Family or Friend, Another Agency, School, Health Care Provider, Faith Community, Other | None |
| Eligibility Status | Not Screened, Awaiting Documents, Eligible, Not Eligible | Not Screened |
| Eligibility Basis | Income, Age, Residence, Referral, Other | None |

To make them your own, click **Change in Setup** beside a picklist: it opens the enrollment's
fields in Setup (Object Manager, Enrollment) in a new tab. Click the picklist's name; there you add, rename, reorder or deactivate a choice (Salesforce keeps picklist choices on the
field itself, so this one step happens in Setup). A deactivated choice stays on the enrollments
that already have it, and a renamed one is renamed on them too. Keep **Eligible** and **Not
Eligible** in Eligibility Status: choosing either fills in the Eligibility Date (see Enrollment
Rules). The lists are restricted: an import or another system can only save a choice the list
holds.

### Participant Privacy

Who can see enrollments and service deliveries. Program membership can be sensitive (a recovery
group, a housing program), so you choose:

| Preset | Who sees enrollments and service deliveries |
|---|---|
| **Shared** (the default) | Everyone with a Programs permission set, as before this setting existed. |
| **Private** | The person who created the record (its owner), the people above them in the role hierarchy, and Programs Admin. |

Choose one under **Participant Privacy** and click **Save**. The change applies within a minute,
to every enrollment and delivery, old and new, and is listed under **Recent Changes** in BarnCRM
Settings. Case notes are private whichever you choose (see Case Notes).

**How it works, for admins who know Salesforce sharing.** Enrollments and service deliveries
have a Private organization-wide default. Each one is shared, Read/Write, with the public group
**Programs Participant Records**. Shared puts **All Internal Users** in that group; Private
takes them out. To let a few people see every record while the preset is Private (for example a
program manager outside the role hierarchy), add them, their role or another group to
**Programs Participant Records** in Setup under **Public Groups**. BarnCRM only ever adds or
removes All Internal Users there, so your own members stay. With the hourly access check it puts
All Internal Users back, or takes them out, if the group was changed by hand against the preset.

What Private means day to day:

- A staff member sees on the **Program Roster** panel and in the **Service Delivery Log** only the
  enrollments they can see. Decide who owns enrollments: the person who enrolls someone owns that
  enrollment, and a Programs Admin can change the owner.
- Reports and list views show each person only the records they can see.
- Program counts that BarnCRM keeps (the rules that stop a second open enrollment, for example)
  still count every record, whoever can see it.

## Roles and Permission Sets

You never assign the Programs permission sets by hand. Give people their BarnCRM role on the
[Access](access.md) page as usual, and the module gives each role its Programs set:

| BarnCRM role | Programs set they get | What they can do |
|---|---|---|
| Admin (anyone holding BarnCRM Admin) | Programs Admin | Everything, including deleting a record entered by accident |
| Coordinator | Programs Staff | Set up programs, services, cohorts and sessions, enroll people and move them through the stages, take attendance, keep service plans; never deletes |
| Team Member | Programs Staff | The same as Coordinator |
| Read Only | Programs Read Only | Look at programs, services, cohorts, sessions, enrollments and service plans |

When it happens:

- **At install**, for everyone who already has a role.
- **When you give a role on the Access page**, within a minute.
- **When you turn the module back on** in Module Manager, for anyone given a role while it was off.
- **Every hour**, with BarnCRM's hourly access check, for anyone given a role in Setup rather
  than on the Access page.

The module only ever gives a set: it never takes one away. If someone leaves a role, remove
their Programs set too, in Setup under **Users**, **Permission Set Assignments**.

## Programs and Services

On the **Programs** tab click **New**. A program has a **Program Name**, a **Status** (Planned,
Active or Completed; new programs start Active), a **Description**, a **Target Population**
(who the program is for, in a sentence a funder report can quote), **Start Date** and **End
Date**, and a **Coordinator** (the staff member who runs it). An End Date before the Start Date
is refused.

Add the program's services from the **Services** related list on the program: a **Service
Name**, a **Description**, a **Unit of Measure** (what one delivery counts: meals, hours,
sessions, bags) and **Active**. Clear Active when a service is no longer offered; it keeps its
history. A service with deliveries cannot be deleted: clear **Active** instead.

**A program with enrollments cannot be deleted.** Salesforce refuses and lists the enrollments.
Set its Status to **Completed** instead: a completed program keeps its enrollments and services
and can still take enrollments, so history entered later is recorded as it happened. A program
with no enrollments can be deleted, and its services go with it.

The list views are **All Programs** and **Active Programs**.

## Enrolling People: the Program Roster Panel

Open a program. The **Program Roster** panel at the top of the page shows how many people are
**Applied**, **Enrolled**, **Completed** and **Withdrawn**, and lists the people whose enrollment
is open (Applied or Enrolled). Turn on **Show Ended** to list the completed and withdrawn ones
too.

- **Enroll Someone** opens a short form: choose the **Person** (in an org where people are person
  accounts, only person accounts are offered), pick a **Stage** if it is not **Enrolled**, and
  click **Save**.
- Change a person's **Stage** in their row: the change saves at once.
- Click a person's name to open their enrollment, to correct its dates.

A message under the figures says what changed. Read Only users see the
panel without the button or the stage pickers. The panel lists up to 200 people; the
**Enrollments** tab lists them all.

You can also create and edit enrollments on the **Enrollments** tab and from the **Enrollments**
related list on the program. The list views are **Open Enrollments** and **All Enrollments**.

### Importing a Roster

To enroll many people at once, use BarnCRM's import (see [Importing](importing.md)) with the
shipped **Program roster** template, which Programs adds at install. It is an upload of several
objects: each row finds its program by name and enrolls the person found by email. Columns:

| Column | Loads | Notes |
|---|---|---|
| Program | The program | Found by its exact name, any capitals. Required. A program is never created or renamed. |
| Email | The person | Found by email (contacts) or person email (person accounts). Required. |
| Stage | Stage | Applied, Enrolled, Completed or Withdrawn. Blank means Enrolled. |
| Start Date, End Date | Start Date, End Date | Blank dates are filled as for an enrollment made by hand (Enrollment Rules). |
| Intake Date, Referral Source, Eligibility Status, Eligibility Basis, Eligibility Date | The intake fields | Choices must be ones the picklist holds (see Programs Settings). |

A row is reported and not loaded when its program or email finds nothing, or when the person
already has an open enrollment in that program. Undo removes the enrollments one import made.
Create the programs first, on the **Programs** tab. To load old enrollments with their own dates,
switch off **Enrollment: fill in the stage dates** on the Automation page while the import runs.
The importing user needs Programs Staff or Programs Admin as well as the import.

## Attendance and Services: the Service Delivery Log

A **service delivery** records one service given to one person on one day: its **Service**, the
person, the **Delivery Date**, the **Attendance** (Present, Excused Absence or Unexcused Absence)
and the **Quantity**, counted in the service's unit of measure (two tutoring hours, one bag).
The program comes from the service. Each delivery is linked to the person's enrollment in that
program.

Staff record them for a whole group at once on the program, in the **Service Delivery Log**
panel under the roster:

1. Pick the **Service** (only Active ones are offered) and the **Date** (today to start with).
2. Everyone with an open enrollment (Applied or Enrolled) is listed, with what is already
   recorded for them that day. Set each person's **Attendance** and **Quantity**, or click
   **Mark All Present**.
3. Click **Save**. One delivery per person is saved for that service and day; saving again
   changes those rows rather than adding new ones. If a delivery for that person, service and
   day already exists but you cannot see it (under Private, one another staff member logged),
   saving changes its Attendance and Quantity instead of adding a second row, and it is still
   not shown to you. This needs update access to Service Delivery Attendance and Quantity.

People left at **Not Recorded** get no delivery. The same panel sits on each **session** page,
for attendance at one scheduled session (see [Cohorts and Sessions](#cohorts-and-sessions)). The
panel works the same in the Salesforce mobile app, one person per card, so attendance can be
taken in the room. Read Only users see
what is recorded without the controls. The panel lists up to 200 people.

You can also enter a delivery by hand on the **Service Deliveries** tab, for example for a person
who is not enrolled. The list views are **All Service Deliveries** and **This Week**.

Rules:

- **One person per delivery**, a contact or an account, as for enrollments.
- **An absence delivers nothing.** Saving an Excused or Unexcused Absence sets Quantity to 0, so
  totals count only what people received. A negative quantity is refused.
- **The enrollment fills itself in.** A delivery saved without one is linked to the person's open
  enrollment in the program, or else the one that started last. Someone with no enrollment is
  still recorded.

Both run as the automation **Service Delivery: absences, enrollment** on the Automation
page. It always runs (it keeps totals right), so it cannot be switched off.

## Case Notes

A **case note** is a dated, typed note about a participant, written on their enrollment: a
check-in, a phone call, a home visit, an assessment. Staff add one from the **Case Notes** related
list on the enrollment (or the **Case Notes** tab): a **Note Date** (today to start with), a
**Type** (Check-in, Phone Call, Home Visit, Office Visit, Assessment, Referral or Other), a
**Subject** and the **Note** itself.

**Case notes are private.** A note is seen only by:

- the person who wrote it (its owner), who can also edit it;
- people above the owner in your role hierarchy;
- Programs Admins, who see, edit and delete every note.

Colleagues with Programs Staff do not see each other's notes, and Read Only users have no access
to case notes at all. This holds whatever you choose for Participant Privacy. To let a
colleague see a note, its owner clicks **Sharing** on the note, or you add a sharing rule in Setup
(**Sharing Settings**, Case Note) for a team that works together. To hand a caseload to someone
else, change the notes' owner.

The **Type** choices are yours to change on the field in Setup, as for the intake picklists. An
enrollment with case notes cannot be deleted: delete its notes first. The list views are **All
Case Notes** (every note you can see) and **My Case Notes**.

A note can be about one of the person's goals: pick it in the note's **Goal** field, or click
**New Note** under the goal on the Service Plan panel, which fills in the enrollment and goal.
Only a goal on the note's own enrollment can be picked. The note stays private to its author.

## Service Plans and Goals

A participant's **service plan** is the set of **goals** on their enrollment: find stable
housing, pass the high school equivalency test, open a bank account. Each goal has **steps**, the
actions that lead to it. Staff keep the plan on the **Service Plan** panel at the top of the
enrollment page.

A goal has:

| Field | What it holds |
|---|---|
| **Goal** | The goal, in a line the participant would recognize |
| **Description** | What success looks like and anything agreed about it |
| **Status** | Not Started, In Progress, Achieved or Not Achieved. Achieved and Not Achieved close the goal |
| **Target Date** | When it should be reached |
| **Assigned To** | The staff member responsible for it |
| **Last Reviewed**, **Next Review** | When it was last reviewed with the person, and when it is next due |
| **Closed Date** | Filled in with today when the goal is Achieved or Not Achieved, emptied if it reopens |
| **Outcome** | With Logic Models installed: the outcome the goal works toward (below) |

A step has a name, a **Status** (Not Started, In Progress or Done), **Assigned To**, a **Target
Date** and a **Completed Date**, filled in when it is Done.

**On the panel**, staff can:

- **Add Goal** and **Edit Goal**;
- add a step under a goal, and tick a step to mark it Done (untick to reopen it);
- **Mark Reviewed**: records today as Last Reviewed and asks for the next review date, offered
  three months on (change it, or leave it blank for none);
- **New Note**: a case note about the goal, with the enrollment and goal filled in. The goal lists
  its three latest notes that you can see, and how many there are in all.

A goal whose Next Review has passed shows **Review due**. The **Goals** tab lists every goal you
can see; its **Reviews Due** list view is the week's review list, and **Open Goals** the open
caseload. Add Assigned To as a filter to see one person's.

**Who sees a plan.** Goals and steps belong to the enrollment: whoever can see the enrollment
sees its goals, and whoever can edit it can change them, so **Participant Privacy** covers service
plans too. Programs Staff add and change goals and steps but never delete them (set a goal to Not
Achieved instead); Programs Admins also delete; Read Only users see plans and change nothing.
Deleting an enrollment deletes its goals and steps.

**Linking a goal to an outcome (Logic Models).** Where the [Logic Models](logic-models.md)
module is installed, Edit Goal also offers **Outcome**: the outcomes of the logic model for the
enrollment's program, then those of your organization's model. This says which change in your
logic model the goal contributes to. Programs does not need Logic Models: without it the choice
is not shown. If the outcome is later deleted from the logic model, the goal says so; edit it to
choose another.

**Turning off the dates.** The Closed Date and Completed Date are filled in by two automations,
**Goal: fill in the closed date** and **Goal Step: fill in the completed date**, on the
[Automation](automation.md) page. Switch them off while you load history whose dates you type
yourself.

## Cohorts and Sessions

### Cohorts

A **cohort** is a group of participants who go through a program together: the spring class of
a job readiness course, the Tuesday group of a tutoring program. Create one from the **Cohorts**
tab or the **Cohorts** related list on the program, with a **Cohort Name**, its **Program**, a
**Status** (Planned, Active or Completed; Active to start with) and optional **Start Date** and
**End Date** (the end cannot be before the start).

A person is in a cohort when their enrollment in the program names it, in the enrollment's
**Cohort** field. There is no separate membership record: the enrollment already carries the
person, the stage and the privacy. Since a person has one open enrollment per program, they are in
one cohort of a program at a time. Only a cohort of the enrollment's own program can be chosen.

A cohort holds no participant details, so every user with a Programs permission set sees every
cohort, as for programs. Who is in it is seen through the enrollments, so **Participant
Privacy** still decides which members each user sees. Deleting a cohort (Programs Admin) keeps
its enrollments and sessions and empties their Cohort.

### Adding People: the Cohort Members Panel

The cohort page opens on the **Cohort Members** panel. It lists the cohort's members, with
their stage, and a **Remove** button on each (the enrollment is kept, out of the cohort). Under
**Add People**:

- **Enrolled in the program, not in a cohort:** the program's open enrollments that have no
  cohort, each with a box. Tick the ones to add, or **Select All**.
- **Someone else:** pick a person and click **Add to List**. Repeat for as many as you need.

Click **Add to Cohort**. A ticked enrollment, or a picked person who already has an open
enrollment in the program, is moved into the cohort. A picked person with no open enrollment is
enrolled, at stage **Enrolled**, in the cohort, through the usual enrollment rules. Each person is
added or refused on their own: the panel says how many were added and lists anyone refused, with
the reason (for example an open enrollment in the program you cannot see under Private). At most
200 people are added in one go.

### Sessions

A **session** is one scheduled occurrence of a service: the 6 pm class on 3 March. It has a
**Session Name**, its **Service**, an optional **Cohort** (a cohort of the service's program;
empty means everyone enrolled in the program), a **Session Date**, a **Start Time** and a
**Status**: **Scheduled**, **Held** (set when attendance is saved) or **Cancelled**. The
**Sessions** tab lists them (**All Sessions**, **Upcoming Sessions**); a service, a cohort and the
program's services list their sessions too.

Sessions, like cohorts, hold no participant details and are seen by every Programs user.
Programs Staff create and edit them; Programs Admins also delete them. A session with attendance
cannot be deleted: set it to **Cancelled** instead. A service with sessions cannot be deleted:
clear its **Active** box.

### Scheduling Sessions

The **Schedule Sessions** panel, on the cohort page (sessions for that cohort) and the program
page (sessions with no cohort), creates many sessions at once:

1. Pick the **Service** (only Active ones are offered).
2. Choose the **From** and **To** dates (a cohort's own dates to start with), the **Days of the
   Week**, and a **Start Time** if you want one.
3. The panel shows how many sessions that makes. Click **Schedule**. One Scheduled session is
   created for each chosen weekday between the two dates, named after the service and the date.

At most 200 sessions are created at a time. Nothing keeps the pattern: each session is then
edited or cancelled on its own, and scheduling again adds more.

### Taking Attendance on a Session

Open the session. The **Service Delivery Log** panel shows its service and day, and lists the
cohort's open enrollments (or the program's, when the session has no cohort), with what is
recorded for each at that session. Set attendance and click **Save**, as on the program.

- Each person gets one delivery for the session, naming it; saving again changes it.
- A delivery already recorded for that person, service and day with no session (for example from
  the program's log) is taken over by the session rather than doubled. This also applies to one
  you cannot see under Private, as on the program.
- Saving on a **Scheduled** session marks it **Held**.
- A **Cancelled** session shows what was recorded and takes no attendance.

Attendance taken on a session is an ordinary service delivery, so the program dashboard, a
person's Programs card, the delivery rules and Participant Privacy all count it as before.

## Program Dashboard

The **Programs Dashboard** tab in the BarnCRM Programs app answers how your programs are doing,
for everyone with a Programs permission set. Pick a period at the top (**This Month**, the
default, **Last Month**, **This Year**, **Last Year** or **Last 12 Months**). Tiles show:

| Tile | What it counts |
|---|---|
| Active Programs | Programs with Status Active. |
| Open Enrollments | Enrollments at Applied or Enrolled, now. |
| New Enrollments | Enrollments whose Start Date falls in the period. |
| People Served | Different people (contacts plus accounts) with a Present delivery in the period, counted as people rather than by scanning every delivery. |
| Services Delivered | Service deliveries marked Present in the period. |
| Attendance Rate | Present deliveries as a share of all deliveries in the period, absences included. |

Below the tiles, a table gives the same figures for each program, plus **Completed** (enrollments
completed in the period); click a program's name to open it. It lists every Active program and
any other program with activity in the period.

Each person sees figures for the records they can see. With Participant Privacy set to Private,
a staff member's dashboard counts only their own enrollments and deliveries, while Programs Admin
sees the whole organization. Nothing is stored: the figures are counted each time the page opens
or the period changes. Salesforce counts at most 50,000 records in one go, so an organization with
more enrollments or deliveries than that in a period sees a message saying the dashboard could not
load: pick a shorter period. For a report you can schedule or email, build a standard Salesforce
report on Enrollments or Service Deliveries.

## A Person's Programs

In the **BarnCRM Programs** app, a person's record page carries a **Programs** card listing
every enrollment they have: the program (a link), the stage and the dates, open ones first. It is
read only: enroll people and change stages from the program's **Program Roster** panel. Above
the list, **Last service** gives the date of the person's latest service they attended and how
many services they have attended in all (absences are not counted). On an
account the card shows only for a person account, never on a household or an organization. A
user without a Programs permission set sees no card.

The card is on the Programs app's own Contact and Account record pages, **Programs Contact
Record Page** and **Programs Account Record Page**: BarnCRM's person pages plus the card. In the
other BarnCRM apps the person page stays as it was. To show the card there too, add the
**Person Enrollments** component to that app's page in the Lightning App Builder.

## Enrollment Rules

- **One person per enrollment.** An enrollment names a contact or, where people are person
  accounts, an account: never both and never neither.
- **One open enrollment per person per program.** Enrolling someone who already has an Applied
  or Enrolled enrollment in the same program is refused, with a message naming the program:
  change the one that is there instead. Once their enrollment is Completed or Withdrawn, they can
  be enrolled again, for example in next year's intake. The check counts every enrollment, also
  ones the person saving cannot see. It is an automation that always runs (it enforces a rule),
  so it cannot be switched off on the Automation page.
- **Dates fill themselves in.** Moving an enrollment to **Enrolled** fills an empty Start Date
  with today; moving it to **Completed** or **Withdrawn** fills an empty End Date with today. A
  date someone already typed is kept. An End Date before the Start Date is refused. Setting
  **Eligibility Status** to **Eligible** or **Not Eligible** fills an empty **Eligibility Date**
  with today the same way. This automation is **Enrollment: fill in the stage dates** on the
  Automation page; switch it off while you load history whose dates you are typing yourself.

## Intake and Eligibility

Each enrollment has an **Intake and Eligibility** section: **Intake Date** (when the person was
first seen or applied), **Referral Source**, **Eligibility Status** (new enrollments start **Not
Screened**), **Eligibility Basis** (the main reason they qualify, or do not) and **Eligibility
Date**. The choices are yours to change (see Programs Settings). They hold choices and dates
only, never typed notes, so erasing a person leaves nothing on the enrollment to empty; write
notes about a person in case notes. Add the fields to list views and reports as you need them,
for example an **Awaiting Documents** list view to chase missing paperwork.

## People: Merging, Deleting and Erasing

- **Merging two people** moves their enrollments to the person kept. If both had an open
  enrollment in the same program, both stay; the next change of stage, person or program on
  either is refused until you set the other to Withdrawn or Completed.
  Their service deliveries move too.
- **Deleting a person** keeps their enrollments and service deliveries, with no person named, so
  program counts stand.
- **Erasing a person** (see [Erase a Person](erase-a-person.md)) keeps their enrollments and
  service deliveries, credited to the anonymous record. Neither holds typed notes, so there is
  nothing on them to empty. Their **case notes are deleted**, whoever wrote them. Only someone
  with Programs Admin can delete every note, so anyone else erasing a person who has case notes
  is refused, with that reason, and nothing is erased. Their **goals and steps are deleted** too,
  for the same reason and with the same rule. Erasing a person account also finds the
  case notes, and counts the enrollments, recorded on that person account's own contact.
- **Deleting a person** keeps their case notes on the enrollment, which no longer names anyone.
  To remove what was written about someone, erase them rather than delete them.

## Health Check

With Programs installed, [Health Check](health-check.md) asks one more question, shown only to
people who can manage BarnCRM Settings and not while Programs is turned off:

| Finding | Severity | What it means | What to do |
|---|---|---|---|
| **Enrollments are still open in programs that have ended** | Information | Enrollments at Applied or Enrolled in a program whose Status is Completed or whose End Date is past. They still count as open, so the person cannot be enrolled again, and they stay on the roster. | Open each linked enrollment and set its Stage to Completed or Withdrawn. If the program is still running, set its Status back to Active or move its End Date. |

## Sample Data

**Load Sample Data** in BarnCRM Settings also loads three sample programs, five services, 18
enrollments and 40 service deliveries, and **Remove Sample Data** takes them away again, keeping
a sample program that has real enrollments or service deliveries, or a sample enrollment with a
case note. See
[Sample data](sample-data.md#with-programs-installed).

## Turning It Off

Turning Programs off in Module Manager stops its automations; the records stay. No Programs set
is given while it is off.

## A Five-Minute Walkthrough

Do this as Maria, who holds the Admin role, with a second user, Priya, who has none yet.

1. On the [Access](access.md) page, give Priya the **Team Member** role.
2. In Setup, open Priya's user record and look at **Permission Set Assignments**. Within a
   minute she holds **Programs Staff**.
3. Open the **BarnCRM Programs** app. On **Programs**, create a program called "After-School
   Tutoring" with yourself as **Coordinator**.
4. On the program, in the **Services** related list, add a service "Tutoring hour" with **Unit
   of Measure** "hours".
5. In the **Program Roster** panel click **Enroll Someone**, choose any person in your sample
   data and click **Save**. **Enrolled** is 1. Open the enrollment: its Start Date is today.
6. Click **Enroll Someone** again and choose the same person. The save is refused, naming the
   program.
7. Change the person's **Stage** to **Completed** in their row. They leave the list and
   **Completed** is 1. Turn on **Show Ended**: they are listed, with today as the End Date.
8. Enroll the same person again. It is accepted: their first enrollment has ended.
9. Try to delete the program from its record page. Salesforce refuses and lists the enrollments.
   Set **Status** to **Completed** instead.

## Common Mistakes

- **Expecting enrollments to be private straight after install.** The Participant Privacy
  preset starts as Shared: anyone with a Programs set sees every enrollment. Choose Private on the
  Programs settings page before you record sensitive program membership.
- **Choosing Private without deciding who owns enrollments.** A staff member then sees only the
  enrollments they own or that people below them own. Decide owners first, or add the program's
  staff to the Programs Participant Records group in Setup.
- **Deleting a finished program.** Set Status to Completed; the platform will not delete a
  program people were enrolled in.
