# Programs, Services and Enrollments

This page covers the everyday side of programs: the programs your organization runs, the
services each one offers, and who takes part. A participant is a person you already have in
BarnCRM. There is no separate participant record: an **enrollment** links the person to the
program, with a **stage** (Applied, Enrolled, Completed or Withdrawn).

**Before you start:** open the **BarnCRM Programs** app from the App Launcher. You need a
Programs permission set, which comes with your BarnCRM role (Team Member, Coordinator, Admin or
Read Only). If the app is missing, ask your admin (see the
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

You should see: a program page with the **Program Roster** panel at the top, then its details
and the **Services** and **Enrollments** lists.

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

Enrolling someone who already has an Applied or Enrolled enrollment in the same program is
refused, with a message naming the program. Change the enrollment that is there instead.

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
2. In the **Service Delivery Log** panel under the roster, pick the **Service** and the
   **Date** (today to start with).
3. Everyone with an open enrollment is listed. Set each person's **Attendance** (Present,
   Excused Absence or Unexcused Absence) and **Quantity**, or click **Mark All Present** to set
   everyone not yet recorded to Present with a quantity of 1.
4. Click **Save**.

You should see: "(number) service deliveries saved." Anyone left at **Not Recorded** gets
nothing. An absence always counts a quantity of 0. To correct a day, pick the same service and
date again: what was saved shows, and saving changes it rather than adding a second delivery.
The panel works the same in the Salesforce mobile app, one person per card. Read Only users see
what was recorded without the controls.

## To Record a Service by Hand

For someone who is not enrolled, or a one-off:

1. Open the **Service Deliveries** tab and click **New**.
2. Pick the **Service**, then a **Contact** or an **Account** (not both), the **Delivery Date**,
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

You should see: tiles for active programs, open and new enrollments, people served, services
delivered and the attendance rate, then a table with the same figures for each program. Click a
program's name to open it. The figures count only the records you can see.

## To Enroll Someone Again

Once a person's enrollment has ended (Completed or Withdrawn), enroll them again with **Enroll
Someone**, for example for next year's intake. The old enrollment stays as history.
