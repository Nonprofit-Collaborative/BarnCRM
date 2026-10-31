# Programs

Scripts for programs, services, enrollments, the Program Roster panel, the Service Delivery Log and Programs access. Setup detail: [Programs](../admin-guide/programs.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Programs deployed and sample data loaded unless a script says otherwise. T-PRG-02 creates the program T-PRG-03 to T-PRG-07 use; T-PRG-09 and T-PRG-10 use the Programs sample data, so run them before T-PRG-08, which removes it. Programs is offered in the **Nonprofit Edition** only: run every script here in that edition (see [Edition modes](before-you-test.md#edition-modes)). Leave the automation **Enrollment: fill in the stage dates** on (the default) unless a script says otherwise.

## T-PRG-01: Open the Programs App and Check Access

**Purpose:** confirm the app, its tabs and list views load, and that each role gets its Programs permission set.
**Prerequisites:** admin user and a staff user with no role yet (see [Test users](before-you-test.md#test-users)).
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | From the App Launcher, open **BarnCRM Programs**. | The tabs **Programs** and **Enrollments** show. |
| 2 | Open **Programs** and the list view menu. | **All Programs** and **Active Programs** are offered. |
| 3 | Open **Enrollments** and the list view menu. | **All Enrollments** and **Open Enrollments** are offered. |
| 4 | Open **BarnCRM Settings**. | There is no Programs section. |
| 5 | On the **Access** page, give the staff user the **Team Member** role. Wait a minute, then in Setup open the user's **Permission Set Assignments**. | The user holds **Programs Staff**. |
| 6 | Give a second test user the **Read Only** role and check the same way. | That user holds **Programs Read Only**. |

**Cleanup:** keep the roles for T-PRG-02 to T-PRG-05.

## T-PRG-02: Create a Program and a Service

**Purpose:** confirm staff can set up a program and its services, and a program that ends before it starts is refused.
**Prerequisites:** the staff user from T-PRG-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Programs**, click **New**. Enter **Program Name** "Test tutoring", **Start Date** today, **End Date** yesterday, and save. | The save is refused because the End Date is before the Start Date. |
| 2 | Clear **End Date** and save. | The program opens with **Status** Active. The **Program Roster** panel shows **Applied**, **Enrolled**, **Completed** and **Withdrawn**, each 0, and says no one is enrolled. |
| 3 | In the **Services** related list, click **New**. Enter **Service Name** "Tutoring hour", **Unit of Measure** "hours", and save. | The service is listed on the program, **Active** ticked. |
| 4 | Open the actions at the top of the program. | No **Delete** is offered (staff never deletes). |

**Cleanup:** keep "Test tutoring" for T-PRG-03 to T-PRG-05.

## T-PRG-03: Enroll People and Refuse a Second Open Enrollment

**Purpose:** confirm the Program Roster panel enrolls a person, fills the Start Date, and refuses a second open enrollment for the same person in the same program.
**Prerequisites:** the staff user; "Test tutoring" from T-PRG-02; any two people from the sample data.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open "Test tutoring". In **Program Roster**, click **Enroll Someone**. | A form with **Person** and **Stage** (set to **Enrolled**) opens, and focus moves to **Person**. **Save** is unavailable until a person is chosen. |
| 2 | Choose the first person and click **Save**. | "Enrollment added." shows under the figures. **Enrolled** is 1 and the person is listed with today as the Start Date. |
| 3 | Click **Enroll Someone**, choose the second person, set **Stage** to **Applied** and save. | **Applied** is 1 and both people are listed. The second has no Start Date. |
| 4 | Click **Enroll Someone**, choose the first person again and save. | The save is refused with a message naming "Test tutoring". The figures do not change. |
| 5 | On a person account org, click **Enroll Someone** and search for an organization account. | Organizations are not offered: only person accounts. (Skip on a Contact org.) |

**Cleanup:** keep the enrollments for T-PRG-04.

## T-PRG-04: Move People Through the Stages

**Purpose:** confirm a stage change saves at once, fills the dates, and that an ended enrollment leaves the list but lets the person enroll again.
**Prerequisites:** T-PRG-03 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | In the second person's row, set **Stage** to **Enrolled**. | "(the person) is now Enrolled." shows. **Applied** is 0, **Enrolled** is 2, and the Start Date is today. |
| 2 | In the first person's row, set **Stage** to **Completed**. | They leave the list. **Completed** is 1. |
| 3 | Turn on **Show Ended**. | The first person is listed again, at **Completed**, with today as the End Date. |
| 4 | Click the first person's name. | Their enrollment record opens, with the program, person, stage and both dates. |
| 5 | Go back to the program, click **Enroll Someone**, choose the first person and save. | It is accepted: their earlier enrollment has ended. **Enrolled** is 2 again. |
| 6 | On the **Automation** page, find **Enrollment: fill in the stage dates** and **Enrollment: one open per program**. | The dates automation has a switch. The one-open rule always runs and cannot be switched off. |

**Cleanup:** keep the data for T-PRG-05.

## T-PRG-05: Read Only Users and Deleting a Program

**Purpose:** confirm Read Only users see the roster but change nothing, and a program with enrollments cannot be deleted.
**Prerequisites:** T-PRG-04 done; the Read Only user from T-PRG-01; the admin user.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the Read Only user, open "Test tutoring". | The **Program Roster** panel shows the figures and the people, with no **Enroll Someone** button and no stage pickers. |
| 2 | As the admin, delete "Test tutoring" from its record page. | Salesforce refuses and lists the enrollments. |
| 3 | Set the program's **Status** to **Completed** and save. | The program saves. It is no longer in **Active Programs**, and its enrollments stay. |

**Cleanup:** keep the data for T-PRG-06 and T-PRG-07.

## T-PRG-06: A Person's Programs Card

**Purpose:** confirm a person's record page in the Programs app lists their enrollments, and that a household shows no card.
**Prerequisites:** T-PRG-05 done; the first person from T-PRG-03.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Programs**, open the first person from T-PRG-03. | A **Programs** card on the right lists "Test tutoring" twice: the open enrollment (Enrolled, green badge) first, then the completed one, with Started and Ended dates. |
| 2 | Click the first "Test tutoring". | The enrollment record opens. |
| 3 | Open the person's household (or, on a person account org, an organization account). | No **Programs** card shows. |
| 4 | As the Read Only user, open the same person in **BarnCRM Programs**. | The card shows the same list. |

**Cleanup:** none.

## T-PRG-07: Health Check Finds Enrollments Open After a Program Ended

**Purpose:** confirm Health Check reports open enrollments in a Completed program, and stops once they are ended.
**Prerequisites:** T-PRG-05 done ("Test tutoring" is Completed with open enrollments); the admin user.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the admin, run **Health Check**. | An Information finding says enrollments are still open in programs that have ended, with each open "Test tutoring" enrollment linked. |
| 2 | Open each linked enrollment and set its **Stage** to **Completed**. Run Health Check again. | The finding is gone. |

**Cleanup:** as the admin, delete the enrollments of "Test tutoring" on the **Enrollments** tab, then delete the program (its service goes with it). Remove the roles given in T-PRG-01, and the Programs sets in Setup.

## T-PRG-08: Programs Sample Data

**Purpose:** confirm the sample load adds the Programs set and the removal takes it away, keeping a sample program a real person is enrolled in.
**Prerequisites:** an org with Core and Programs deployed and no sample data loaded; the admin user. Run it last: it removes the sample data other pages use.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Sample Data**, select **Load Sample Data** and wait for **Loaded**. | The card lists **Program enrollments** with 18. |
| 2 | Open **Programs**, list view **All Programs**. | **After-school tutoring** and **Food pantry** (Active) and **Summer reading** (Completed) are listed. |
| 3 | Open **After-school tutoring**. | The roster shows **Applied** 1, **Enrolled** 4, **Withdrawn** 1, and the services Tutoring hour and Homework club session. Open **Tutoring hour**: its **Service Deliveries** list shows 8 deliveries of 2. |
| 4 | Create a contact "Rita Real" and enroll her in **Food pantry**. | Accepted. |
| 5 | Select **Remove Sample Data** and wait. | **Summer reading** and **After-school tutoring** are gone. **Food pantry** stays, with only Rita's enrollment, and the [Error Log](../admin-guide/error-log.md) holds one Warning naming it. The card still offers **Remove Sample Data**. |
| 6 | Delete Rita's enrollment, then select **Remove Sample Data** again. | **Food pantry** is gone. |
| 7 | Load the sample data again, add a case note to one sample enrollment in **Summer reading**, then select **Remove Sample Data**. | **Summer reading** stays with that enrollment, and the Error Log Warning names it: "Sample data removal kept the sample programs Summer reading, because people of your own are enrolled in them or have services recorded in them, or a sample enrollment in them has case notes. Move or delete those enrollments, service deliveries and case notes, then select Remove Sample Data again." |
| 8 | Delete that case note, then select **Remove Sample Data** again. | **Summer reading** is gone. |

Note: Core's sample set has more than 12 people, so every count above holds; with fewer sample people the set is smaller.

**Cleanup:** delete Rita Real.

## T-PRG-09: Take Attendance With the Service Delivery Log

**Purpose:** confirm the Service Delivery Log lists the open enrollments, records attendance for a whole group, and changes a day rather than adding to it.
**Prerequisites:** Programs sample data loaded (run before T-PRG-08); the staff user from T-PRG-01 (or any Programs Staff user); the Read Only user.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the staff user, open **Food pantry**. | A **Service Delivery Log** panel shows under the roster, with **Service** (Grocery bag and Hot meal offered) and **Date** (today). |
| 2 | Pick **Hot meal**. | The 8 people Enrolled in Food pantry are listed, each at **Not Recorded** with the quantity greyed out. |
| 3 | Click **Mark All Present**. | Everyone shows **Present** with a quantity of 1. |
| 4 | Set the first person to **Excused Absence** and the second person's quantity to 2. | The first person's quantity shows 0 and is greyed out. |
| 5 | Click **Save**. | "8 service deliveries saved." The rows keep their values. |
| 6 | Click **Save** again without changing anything. | "Nothing to save: no attendance was changed." |
| 7 | Set the first person to **Present**, click **Save**, then open **Hot meal** and its **Service Deliveries** list. | "1 service delivery saved." The list holds 8 deliveries for today (not 9), each linked to the person's enrollment. |
| 7a | With Participant Privacy at **Private**, as a second staff user who cannot see the first user's deliveries, save the same service and date for the same person. | Saved; the first user's delivery has the new Attendance and Quantity and there is still one delivery (not two). The second user still does not see it. |
| 8 | Back on Food pantry, change the **Date** to yesterday. | Everyone is back at **Not Recorded**. |
| 9 | In the Salesforce mobile app, open **Food pantry** and the log. | One person per card, with the attendance and quantity under the name; saving works the same. |
| 10 | As the Read Only user, open **Food pantry**. | The log shows what was recorded for today, with no attendance controls and no **Save**. |

**Cleanup:** keep the deliveries for T-PRG-10.

## T-PRG-10: Record a Service by Hand and the Delivery Rules

**Purpose:** confirm a delivery entered on the tab follows the rules: one person, the enrollment filled in, an absence counting 0, a negative quantity refused.
**Prerequisites:** T-PRG-09 done; the staff user.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Service Deliveries**, click **New**. Pick **Grocery bag**, an Enrolled Food pantry person as the **Contact**, and save. | Saved with today's date, **Present**, quantity 1, and **Enrollment** filled in with the person's Food pantry enrollment. |
| 2 | Edit it: set **Attendance** to **Unexcused Absence** and **Quantity** to 3, and save. | Saved with quantity 0. |
| 3 | Edit it: set **Attendance** to **Present** and **Quantity** to -1, and save. | Refused: the quantity cannot be negative. |
| 4 | Click **New** with both a **Contact** and an **Account** filled in. | Refused: one person per delivery. |
| 5 | Click **New** for a contact who is not enrolled in Food pantry, with **Hot meal**. | Saved with no enrollment. |
| 6 | In **BarnCRM Settings**, open **Automation** and find **Service Delivery: absences, enrollment**. | Listed as always on, with no switch. |
| 7 | Open **Hot meal** and try to delete it. | Refused: the service has deliveries. |

**Cleanup:** delete the deliveries made in steps 1 and 5. Run T-PRG-08 to remove the sample data.

## T-PRG-11: Intake and Eligibility, and the Programs Settings Page

**Purpose:** confirm the intake fields save, the Eligibility Date fills itself in, and an admin reaches the intake picklists from BarnCRM Settings.
**Prerequisites:** the admin user and the staff user from T-PRG-01; any program and a person not enrolled in it.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the staff user, enroll the person as **Applied** and open the enrollment. | An **Intake and Eligibility** section shows **Eligibility Status** **Not Screened** and the other fields empty. |
| 2 | Edit: set **Intake Date** to last week, **Referral Source** to **School**, **Eligibility Status** to **Awaiting Documents**. Save. | Saved; **Eligibility Date** stays empty. |
| 3 | Edit: set **Eligibility Status** to **Eligible** and **Eligibility Basis** to **Income**. Save. | **Eligibility Date** shows today. |
| 4 | As the admin, open **BarnCRM Settings**. | A **Programs** section is listed in the Programs group, above Volunteers if installed. |
| 5 | Open it and click **Open Programs Settings**. | The **Programs Settings** page lists **Referral Source**, **Eligibility Status** (Default: Not Screened) and **Eligibility Basis** with their choices. |
| 6 | Click **Change in Setup** beside **Referral Source**. | The enrollment's **Fields and Relationships** open in Setup in a new tab. Open **Referral Source**, add a choice "Library", save, and reload the Programs Settings page: "Library" is listed. |
| 7 | As the staff user, open the Programs Settings page by its address (copy it from step 5). | The tab is not available to them, or the page says only someone who can manage BarnCRM settings can change the Programs settings. |

**Cleanup:** remove the "Library" choice in Setup; delete the enrollment.

## T-PRG-12: Case Notes Are Private and Go When the Person Is Erased

**Purpose:** confirm a case note is seen only by its author and Programs Admin, and that erasing the person deletes it.
**Prerequisites:** the admin user; two staff users with a BarnCRM role of Team Member (Programs Staff), with no role above the other; the Read Only user; any program with a test person enrolled ("Test Person").

| Step | Action | Expected result |
|---|---|---|
| 1 | As the first staff user, open Test Person's enrollment and click **New** in **Case Notes**. Type **Home Visit**, Subject "First visit", a line of Note. Save. | Saved with today's Note Date; listed in the enrollment's Case Notes and in **My Case Notes**. |
| 2 | As the second staff user, open the same enrollment and the **Case Notes** tab, **All Case Notes**. | The note is not listed anywhere. |
| 3 | As the Read Only user, open the enrollment. | No Case Notes list, no Case Notes tab. |
| 4 | As the admin, open **All Case Notes**. | The note is listed; the admin can open, edit and delete it. |
| 5 | As the first staff user, try to delete the note. | No Delete action. |
| 6 | As the admin, try to delete the enrollment. | Refused: it has case notes. |
| 7 | As the second staff user (if they may erase people), erase Test Person. | Refused: the person has case notes only Programs Admin can delete; nothing is erased. |
| 8 | As the admin, erase Test Person. | Done; the summary lists the Case Notes as deleted and the Enrollments as kept. The note is gone; the enrollment stays, naming the anonymous record. For a person account, notes and enrollments on the account's own contact are found and counted too. |

**Cleanup:** delete the enrollment; remove the staff users' roles.

## T-PRG-13: Participant Privacy, Shared and Private

**Purpose:** confirm the Participant Privacy preset decides who sees enrollments and service deliveries, starts as Shared, and is audited.
**Prerequisites:** the admin user; two staff users with a BarnCRM role of Team Member (Programs Staff), with no role above the other; any active program with a service.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the admin, open **BarnCRM Settings**, the **Programs** section, then **Programs Settings**. | A **Participant Privacy** card with **Shared** chosen, "Default: Shared" under it, and **Save** greyed out. |
| 2 | As the first staff user, enroll a test person in the program on its **Program Roster** panel, then record one delivery for them in the **Service Delivery Log**. | Both saved. |
| 3 | As the second staff user, open the program and the **Enrollments** and **Service Deliveries** tabs, **All** lists. | The enrollment and the delivery are listed. |
| 4 | As the admin, choose **Private** on the Participant Privacy card and click **Save**. | "Saved. It applies to every enrollment and delivery within a minute." **Save** is greyed out again. |
| 5 | Wait a minute. As the second staff user, repeat step 3. | Neither record is listed, on the roster or the tabs. |
| 6 | As the first staff user, repeat step 3. | Both are listed: they own them. |
| 7 | As the admin, repeat step 3. | Both are listed. |
| 8 | As the admin, open **BarnCRM Settings**, **Recent Changes**. | A row for Programs_Settings__c.Private_Participants__c from Shared to Private. |
| 9 | As the admin, in Setup open **Public Groups**, **Programs Participant Records**. | All Internal Users is not a member. |
| 10 | Choose **Shared** and **Save**, wait a minute, then as the second staff user repeat step 3. | Both records are listed again, and All Internal Users is back in the group. |

**Cleanup:** delete the enrollment and delivery; leave the preset Shared; remove the staff users' roles.

## T-PRG-14: The Programs Dashboard and a Person's Last Service

**Purpose:** confirm the dashboard counts a period correctly and the person card shows the last service.
**Prerequisites:** the admin user; Programs sample data loaded (T-PRG-08), or any Active program with a service, two enrolled test people and today's deliveries recorded in the Service Delivery Log (one Present, one Unexcused Absence).

| Step | Action | Expected result |
|---|---|---|
| 1 | As the admin, open the **BarnCRM Programs** app. | **Programs Dashboard** is the first tab. |
| 2 | Open **Programs Dashboard**. | Period **This Month**; six tiles (Active Programs, Open Enrollments, New Enrollments, People Served, Services Delivered, Attendance Rate) and a **By Program** table listing every Active program by name. |
| 3 | Compare the program's row with its **Program Roster** panel and today's log. | Open Enrollments matches the roster's Applied plus Enrolled; Services Delivered counts the Present delivery only; Attendance Rate is 50%; People Served is 1. |
| 4 | Pick **Last Year**. | The figures reload for last year; a program with no activity then shows 0 and "None yet" for the rate. |
| 5 | Click a program's name. | The program opens. |
| 6 | Open the test person who attended, in the BarnCRM Programs app. | The **Programs** card starts with "Last service:" today's date and "(1 attended in all)". |
| 7 | Open the test person who was absent. | No Last service line (an absence is not a service). |
| 8 | On a phone, open the dashboard. | Tiles two to a row; the table stacks each program's figures with their names. |

**Cleanup:** delete the test deliveries if you made them.

## T-PRG-15: Import a Program Roster

**Purpose:** confirm the Program roster template enrolls people by program name and email, and reports rows it cannot load.
**Prerequisites:** the admin user; an Active program named "Test Pantry"; three test people with emails, none enrolled in it. A CSV with the columns Program, Email, Stage, Start Date, Referral Source and these rows: Test Pantry and the first email, Enrolled, a past date, School; TEST PANTRY and the second email, blank stage; No Such Program and the third email; Test Pantry and nobody@example.org; Test Pantry and the first email again.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open BarnCRM's import and upload the CSV. | **Program roster** is offered as a template. |
| 2 | Choose it and preview. | Columns map to Program and the enrollment's fields with no manual mapping. |
| 3 | Load it. | 2 loaded, 3 not loaded: no program "No Such Program", no person with nobody@example.org, and the repeated first email refused as an open enrollment already in Test Pantry. |
| 4 | Open Test Pantry's **Program Roster** panel. | The first person Enrolled with your start date and Referral Source School; the second Enrolled from today. |
| 5 | Open the program record. | Its name is still "Test Pantry", not changed to capitals. |
| 6 | Undo the import. | Both enrollments are removed; the program stays. |

**Cleanup:** none after the undo.
