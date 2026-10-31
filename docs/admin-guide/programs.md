# Programs

## What It Does

The BarnCRM Programs module records the **programs** your organization runs (a food pantry, an
after-school tutoring program, a job readiness course), the **services** each program offers (a
hot meal, a tutoring hour, a bag of groceries) and who takes part, as **enrollments**. A
participant is a person you already have in BarnCRM, so there is no separate participant record:
an enrollment links a person to a program with a **stage** (Applied, Enrolled, Completed or
Withdrawn) and its start and end dates.

Recording each time a service is given, attendance, case notes, a program dashboard, a roster
import and intake fields come in later releases (P-02 and P-04 to P-08). Until the participant
privacy preset (P-08) arrives, everyone who holds a Programs permission set can see every
enrollment.

## Before You Install

- Programs is offered in the **Nonprofit Edition** only (see [Editions](editions.md)).
- It needs BarnCRM Core and nothing else: not Giving, not Rollup Builder.
- If the Program Management Module (PMM) is installed in your org, BarnCRM lists it on the
  **Integrations** page as an alternative. Use one or the other for the same programs, not both.
  BarnCRM's programs, services and enrollments are laid out so a later PMM migration template
  can move PMM's records across without new fields.

## Installing

Install it from **Module Manager** (see [Module Manager](module-manager.md)). When the install
finishes, BarnCRM does three things on its own:

1. Creates the switch rows for the module's automations on the **Automation** page.
2. Gives you, the person who installed it, the **Programs Admin** permission set.
3. Gives everyone who already has a BarnCRM role their Programs permission set (see below).

Then open the **BarnCRM Programs** app from the App Launcher. Its tabs are **Programs** and
**Enrollments**. The Programs and Enrollments tabs also join the BarnCRM apps.

Programs has no settings yet, so it adds no section to BarnCRM Settings.

## Roles and Permission Sets

You never assign the Programs permission sets by hand. Give people their BarnCRM role on the
[Access](access.md) page as usual, and the module gives each role its Programs set:

| BarnCRM role | Programs set they get | What they can do |
|---|---|---|
| Admin (anyone holding BarnCRM Admin) | Programs Admin | Everything, including deleting a record entered by accident |
| Coordinator | Programs Staff | Set up programs and services, enroll people and move them through the stages; never deletes |
| Team Member | Programs Staff | The same as Coordinator |
| Read Only | Programs Read Only | Look at programs, services and enrollments |

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
history.

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

## A Person's Programs

In the **BarnCRM Programs** app, a person's record page carries a **Programs** card listing
every enrollment they have: the program (a link), the stage and the dates, open ones first. It is
read only: enroll people and change stages from the program's **Program Roster** panel. On an
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
  date someone already typed is kept. An End Date before the Start Date is refused. This
  automation is **Enrollment: fill in the stage dates** on the Automation page; switch it off
  while you load history whose dates you are typing yourself.

## People: Merging, Deleting and Erasing

- **Merging two people** moves their enrollments to the person kept. If both had an open
  enrollment in the same program, both stay; the next change of stage, person or program on
  either is refused until you set the other to Withdrawn or Completed.
- **Deleting a person** keeps their enrollments, with no person named, so program counts stand.
- **Erasing a person** (see [Erase a Person](erase-a-person.md)) keeps their enrollments,
  credited to the anonymous record. An enrollment holds no typed notes, so there is nothing on it
  to empty.

## Health Check

With Programs installed, [Health Check](health-check.md) asks one more question, shown only to
people who can manage BarnCRM Settings and not while Programs is turned off:

| Finding | Severity | What it means | What to do |
|---|---|---|---|
| **Enrollments are still open in programs that have ended** | Information | Enrollments at Applied or Enrolled in a program whose Status is Completed or whose End Date is past. They still count as open, so the person cannot be enrolled again, and they stay on the roster. | Open each linked enrollment and set its Stage to Completed or Withdrawn. If the program is still running, set its Status back to Active or move its End Date. |

## Sample Data

**Load Sample Data** in BarnCRM Settings also loads three sample programs, five services and 18
enrollments, and **Remove Sample Data** takes them away again. See
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

- **Looking for a Programs section in BarnCRM Settings.** There is none yet: Programs has no
  settings until intake fields and the privacy preset arrive.
- **Expecting enrollments to be private.** Until the participant privacy preset (P-08), anyone
  with a Programs set sees every enrollment. Do not record sensitive program membership for
  people outside your program staff until then.
- **Deleting a finished program.** Set Status to Completed; the platform will not delete a
  program people were enrolled in.
