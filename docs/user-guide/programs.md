# Programs, Services and Enrollments

This page covers the everyday side of programs: the programs your organization runs, the
services each one offers, and who takes part. A participant is a person you already have in
BarnCRM. There is no separate participant record: an **enrollment** links the person to the
program, with a **stage** (Applied, Enrolled, Completed or Withdrawn).

**Before you start:** open the **BarnCRM Programs** app from the App Launcher. You need a
Programs permission set, which comes with your BarnCRM role (Team Member, Admin or
Read Only; Fundraising Staff alone does not include it). If the app is missing, ask your admin (see the
[Programs admin guide](../admin-guide/programs.md#roles-and-permission-sets)). Read Only users
can look at programs and enrollments but change nothing.

**Which enrollments you see** depends on your organization's Participant Privacy choice. With
**Shared** (the usual) you see every enrollment and service delivery. With **Private** you see
the ones you created, the ones created by people who report to you, and any your admin opened to
you; a roster or list may then show fewer people than are enrolled. If you are missing someone
you work with, ask your admin (see
[Participant Privacy](../admin-guide/programs.md#participant-privacy)).

## To Find a Program or an Enrollment

1. Click the **Programs** tab, or the **Enrollments** tab.
2. Open the list view menu at the top left and pick a list:
   - Programs: **All Programs** or **Active Programs**.
   - Enrollments: **All Enrollments** or **Open Enrollments** (Applied or Enrolled).
3. Click a name to open the record.

You should see: a program page with tabs: **People** (the **Program Roster** panel, open
first), **Attendance** (the **Service Delivery Log**), **Sessions** (**Schedule Sessions**),
**Eligibility** (the **Eligibility Rules**) and **Details**. The **Services**, **Enrollments**,
**Cohorts** and **Session Schedules** lists are at the side (below the tabs on a phone).

## To Create a Program and Its Services

1. On the **Programs** tab, click **New**.
2. Fill in **Program Name**, and if you like **Description**, **Target Population**, **Start
   Date**, **End Date** and **Coordinator**. **Status** starts as **Active**.
3. Click **Save**.
4. On the program, in the **Services** list, click **New**, fill in **Service Name** and **Unit
   of Measure** (for example "meals" or "hours") and click **Save**.

You should see: the program page with its service listed. An End Date before the Start Date is
refused.

When a program ends, set its **Status** to **Completed**. A program people were enrolled in
cannot be deleted.

## To Enroll Someone

1. Open the program.
2. In the **Program Roster** panel, click **Enroll Someone**.
3. Choose the **Person**. Leave **Stage** as **Enrolled**, or pick **Applied** for someone who
   has applied but not started.
4. Click **Save**.

You should see: "Enrollment added." under the figures, the count for the stage goes up by one,
and the person is listed with today as the Start Date (for Enrolled).

Enrolling someone who already has an Applied, Enrolled or Waitlisted enrollment in the same
program is refused, with a message naming the program. Change the enrollment that is there
instead.

**When the program is full.** If the program has a **Capacity** and your admin turned on
**Waitlist when full**, an enrollment into a full program is saved as **Waitlisted** instead of
Enrolled. When someone completes or withdraws, or the capacity is raised, the person waiting
longest moves to **Enrolled** by itself, with today as the Start Date. Without the setting,
Capacity only shows on the program.

## To Import a Roster

1. Make a spreadsheet with a row per person and the columns **Program** (the program's exact
   name) and **Email**, plus any of **Stage**, **Start Date**, **End Date**, **Intake Date**,
   **Referral Source**, **Eligibility Status**, **Eligibility Basis** and **Eligibility Date**.
2. Open BarnCRM's import, upload the file and choose the **Program Roster** template.
3. Check the preview, then load it.

You should see: one enrollment per row. Rows whose program or email finds nothing, or whose
person already has an open enrollment in that program, are listed as not loaded with the reason.
Programs are never created by an import: create them on the **Programs** tab first.

## To Record Intake and Eligibility

1. Open the program and click the person's name in the **Program Roster** panel (or open the
   enrollment from the **Enrollments** tab).
2. Click **Edit**. In **Intake and Eligibility**, fill in the **Intake Date** and **Referral
   Source**, then set the **Eligibility Status** (Not Screened, Awaiting Documents, Eligible or
   Not Eligible) and the **Eligibility Basis**.
3. Click **Save**.

You should see the values saved. Choosing **Eligible** or **Not Eligible** fills an empty
**Eligibility Date** with today. The choices in each list are your organization's; if one you
need is missing, ask your admin. Write anything longer about the person in a case note, not
here.

## To Move Someone to Another Stage

1. Open the program.
2. In the person's row of the **Program Roster** panel, pick the new **Stage**: Applied,
   Enrolled, Completed or Withdrawn.

You should see: "(the person's name) is now (the stage)." The change saves at once. Moving
someone to **Enrolled** fills an empty Start Date with today; moving them to **Completed** or
**Withdrawn** fills an empty End Date and takes them off the list.

To see everyone who has completed or withdrawn, turn on **Show Ended**. To correct a date,
click the person's name to open the enrollment and edit it there.

## To Take Attendance or Record Services

1. Open the program.
2. On the **Attendance** tab, in the **Service Delivery Log** panel, pick the **Service** and the
   **Date** (today to start with).
3. Everyone with an open enrollment is listed. Set each person's **Attendance** (Present,
   Excused Absence or Unexcused Absence) and **Quantity**, or click **Mark All Present** to set
   everyone not yet recorded to Present with a quantity of 1.
4. Click **Save**. While marks are not saved, a hint beside **Save** says "1 unsaved change" (or
   "N unsaved changes").

If you change the **Service** or the **Date** with marks not saved, **Save Attendance First?**
asks: "You have unsaved attendance for (service) on (date). Changing the service or date
reloads the list, so save it first or discard it." Choose **Save** (the default) or **Discard**,
then **Continue**, to save or drop the marks and load the new service and day. **Cancel** keeps
the marks and puts the **Service** and **Date** back.

You should see: "(number) service deliveries saved." Anyone left at **Not Recorded** gets
nothing. An absence always counts a quantity of 0. To correct a day, pick the same service and
date again: what was saved shows, and saving changes it rather than adding a second delivery.
The panel works the same in the Salesforce mobile app, one person per card. Read Only users see
what was recorded without the controls.

## To Count People Without Naming Them

For a drop-in service where nobody is recorded by name (a walk-in meal, a pantry line):

1. On the program's **Attendance** tab, in the **Service Delivery Log** panel, pick the
   **Service** and the **Date**.
2. Under the rows, find **People counted without names for this service and day**. Type how many
   people you served in **People Served, Not Named**.
3. Click **Add to the Count**.

You should see: "Added (number) to the count." and the day's total go up. Each click adds to
the total, so you can add a second count later the same day. To correct one, open the
**Service Counts** tab or the **Service Counts** list on the service and edit the row. These
people show on the dashboard as **Counted Without Names**, apart from the people you named.

## To Record a Referral

1. Open the person's enrollment (click their name in the **Program Roster** panel) and, in the
   **Referrals** list, click **New**. Or open the **Referrals** tab and click **New**.
2. Pick the **Direction**: **Out** if you sent the person to another organization, **In** if
   another organization sent them to you.
3. Name the person (a **Contact** or an **Account**, not both) and fill in **Other
   Organization**, the **Referral Date** and any **Notes**.
4. Click **Save**. The **Status** starts as **Open**.

As it moves on, change the **Status** (Open, Accepted or Closed) and, when it ends, pick an
**Outcome** such as Service Received or Declined by Person. Only you, people above you in your
organization's roles and Programs Admins can see a referral you make. The **Open Referrals** list
on the **Referrals** tab shows everything not yet closed.

## To Check Whether Someone Is Eligible

If your admin has set up eligibility rules, the program page's **Eligibility** tab has an
**Eligibility Rules** panel.
Under **Preview and Screen**, choose a person from **Open Enrollment** to see what the rules
would decide (Eligible, Not Eligible or Review) and why, then click **Screen This Enrollment** to
save that result, or **Screen Open Enrollments** to do everyone. Screening sets the person's
**Eligibility Status**, **Eligibility Basis** and **Eligibility Reason** on the enrollment.
Someone already marked Eligible or Not Eligible is left alone unless you tick **Also screen
enrollments already Eligible or Not Eligible**. **Review** means a person should look at the
case. Only a Programs Admin changes the rules; you can still edit an enrollment's eligibility
by hand.

## To Record a Service by Hand

For someone who is not enrolled, or a one-off, the quickest way is **Record Service** at the
top of the person's page (in the **BarnCRM Programs** app) or of their enrollment:

1. Click **Record Service**. The **Person** is filled in (from an enrollment, the program's
   services are offered and the delivery is linked to that enrollment).
2. Pick the **Service**, check the **Delivery Date** (today), the **Attendance** (Present) and
   the **Quantity** (1), and click **Save**.

You should see "Service recorded." One **Person** picker covers everyone, so there is no
Contact or Account to choose between.

Or, the standard way:

1. Open the **Service Deliveries** tab and click **New**.
2. Pick the **Service**, then a **Contact** or an **Account** (not both; an Account must be a
   person, or you see "Choose a person. An organization or household account cannot be enrolled
   or receive a service."), the **Delivery Date**,
   the **Attendance** and the **Quantity**.
3. Click **Save**.

You should see the new delivery. If the person has an enrollment in the program, it is filled in
for you.

## To Write a Case Note

1. Open the person's enrollment (click their name in the **Program Roster** panel).
2. In the **Case Notes** related list, click **New**.
3. Check the **Note Date** (today to start with), pick the **Type** (Check-in, Phone Call, Home
   Visit, Office Visit, Assessment, Referral or Other), and write a **Subject** and the **Note**.
4. Click **Save**.

You should see the note in the enrollment's **Case Notes** list. Only you, people above you in
your organization's roles, and Programs Admins can see it; your colleagues cannot unless you
share it with **Sharing** on the note. You can edit your own notes but not delete them; ask a
Programs Admin to remove one written by mistake. The **My Case Notes** list on the **Case Notes**
tab gathers everything you have written.

A note can be about one of the person's goals: pick the goal in the note's **Goal** field, or
start the note with **New Note** under the goal (see below).

## To Keep Someone's Service Plan

A person's service plan is their goals, each with the steps toward it, kept on their enrollment.

1. Open the person's enrollment (click their name in the **Program Roster** panel).
2. On the **Service Plan** tab, click **Add Goal**. Write the **Goal** (for example, "Find stable
   housing"), and fill in what you know: a **Description**, the **Status**, who it is **Assigned
   To**, a **Target Date** and the **Next Review** date. Where your organization uses Logic Models
   you can also pick the **Outcome** the goal works toward.
3. Click **Save**.
4. Under the goal, type a step (for example, "Fill in the housing application") and click **Add
   Step**. Add as many as you need.

You should see the goal on the panel with its steps and "0 of 2 steps done" (or however many).
Open goals come first, soonest target date first.

**As the work goes on:**

- **Tick a step** when it is done; it records today as its completed date. Untick it to reopen it.
- **Edit Goal** to change the goal, or to set its Status to **Achieved** or **Not Achieved** when
  it is finished. Its closed date is filled in for you.
- **Mark Reviewed** after you go over the goal with the person: it records today and offers the
  next review three months on. Change the date, or clear it for no further review, and click
  **Save Review**. A goal past its next review shows **Review due**.
- **New Note** opens a new case note about the goal with the enrollment and goal already filled
  in. The goal lists its three latest notes you can see.

The **Goals** tab lists every goal you can see; its **Reviews Due** list shows the goals waiting
for a review. You can add and change goals and steps but not delete them: set a goal you are
dropping to **Not Achieved**, or ask a Programs Admin to remove one entered by mistake. Read Only
users see plans but change nothing.

## To Put People in a Cohort

A cohort is a group that goes through a program together, such as the spring class.

1. Open the program and, in the **Cohorts** list, click **New**. Give the cohort a **Cohort
   Name**, and a **Start Date** and **End Date** if it has them. Click **Save**.
2. On the cohort's **Members** tab, the **Cohort Members** panel lists who is in it. Under **Add People**:
   - tick the people already enrolled in the program who are not in a cohort, or click **Select
     All**;
   - for anyone else, pick the person and click **Add to List**, as many times as you need.
3. Click **Add to Cohort**.

Or drag a person from **Enrolled in the program, not in a cohort** onto the member list by the
handle beside their name: dragging someone who is ticked adds everyone ticked. On a phone, press
and hold the handle first; by keyboard, focus the handle, press Space, then Left Arrow to the
member list and Space again (Escape cancels).

You should see: "(number) people added." Someone already enrolled in the program is moved into
the cohort; someone who was not is enrolled, as Enrolled, in the cohort. Anyone who could not be
added is listed under **Not Added**, with the reason. To take someone out, click **Remove** by
their name: their enrollment stays, out of the cohort. You can also change a person's cohort in
the **Cohort** field on their enrollment.

## To Schedule Sessions

1. Open the cohort (for its sessions) or the program (for sessions open to everyone enrolled).
2. In the **Schedule Sessions** panel, pick the **Service**, the **From** and **To** dates and
   the **Days of the Week**, and a **Start Time** and **End Time** if you like (the end after
   the start).
3. Check the line under the form, for example "12 sessions will be scheduled", and click
   **Schedule**.

Running it twice does not duplicate: a day that already has a session of the same service for
the same cohort (on a program, a session with no cohort), other than a **Cancelled** one, is
skipped. The line says, for example, "2 sessions will be scheduled. Days that already have a
session are skipped: 2." If every chosen day already has a session, **Schedule** is disabled.

You should see: "12 sessions scheduled." (with the skipped count when there is one, for example
"2 sessions scheduled. Days that already have a session are skipped: 2."). The sessions are in the cohort's **Sessions** list and
on the **Sessions** tab. To move or call off one session, open it and edit its date or set its
**Status** to **Cancelled**.

## To Keep Sessions Coming Every Week

For a class that runs until you stop it, save the pattern as a repeating schedule instead.

1. Fill in the **Schedule Sessions** panel as above and click **Save as Repeating Schedule**.
   (Or click **New** in the **Session Schedules** list on the program or cohort, and set
   **Repeat Every (Weeks)** to 2 for every other week.)
2. Open the schedule from **Session Schedules**. Its panel says, for example, "Every session is
   created through 26 Apr 2027. BarnCRM adds more each night."

BarnCRM keeps sessions created eight weeks ahead (your admin can change how many). To change the days or times, edit the
schedule: the change applies after the last day already created. To end it, untick **Active**
or set an **End Date**; the sessions already made stay. An admin can click **Remove Future
Sessions** on the schedule to replace the upcoming sessions that have no attendance yet.

You should see: "Repeating schedule saved. Sessions created: 12. ..." under the panel, and the
new sessions in the **Sessions** list.

## To Take Attendance at a Session

1. Open the session (from the **Sessions** tab or the cohort's **Sessions** list).
2. On the **Attendance** tab, the **Service Delivery Log** panel shows the session's service and day and lists the
   cohort's members (everyone enrolled in the program for a session with no cohort). Set each
   person's **Attendance** and **Quantity**, or click **Mark All Present**.
3. Click **Save**.

You should see: "(number) service deliveries saved." and the session's **Status** becomes
**Held**. Saving again changes what you recorded. A delivery already recorded for that person and
day on the program's log is taken over by the session, not counted twice. A **Cancelled**
session takes no attendance.

## To See Which Programs Someone Is In

1. In the **BarnCRM Programs** app, open the person.
2. Look at the **Programs** card on the right.

You should see: **Last service**, the date the person last attended a service and how many
services they have attended, then every program the person has an enrollment in, open ones
first, with the stage and the dates. Click a program name to open that enrollment. The card is
read only: enroll people and change stages on the program. On a household or an organization
there is no card.

## To See How Your Programs Are Doing

1. In the **BarnCRM Programs** app, click the **Programs Dashboard** tab.
2. Pick a period at the top: **This Month** (the default), **Last Month**, **This Year**,
   **Last Year** or **Last 12 Months**.

You should see: tiles for active programs, open and new enrollments, people served, people
counted without names, services delivered and the attendance rate, then a **Tools** tile for
each Programs tab you can open, then a table with the same figures for each program (the
attendance rate also as a bar). Click a program's name to open it. The figures count only the
records you can see.

## To Enroll Someone Again

Once a person's enrollment has ended (Completed or Withdrawn), enroll them again with **Enroll
Someone**, for example for next year's intake. The old enrollment stays as history.
