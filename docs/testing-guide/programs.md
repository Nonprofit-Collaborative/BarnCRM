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
| 2 | Open **Programs Dashboard**. | Period **This Month**; seven tiles (Active Programs, Open Enrollments, New Enrollments, People Served, Counted Without Names, Services Delivered, Attendance Rate) and a **By Program** table listing every Active program by name. |
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
| 1 | Open BarnCRM's import and upload the CSV. | **Program Roster** is offered as a template. |
| 2 | Choose it and preview. | Columns map to Program and the enrollment's fields with no manual mapping. |
| 3 | Load it. | 2 loaded, 3 not loaded: no program "No Such Program", no person with nobody@example.org, and the repeated first email refused as an open enrollment already in Test Pantry. |
| 4 | Open Test Pantry's **Program Roster** panel. | The first person Enrolled with your start date and Referral Source School; the second Enrolled from today. |
| 5 | Open the program record. | Its name is still "Test Pantry", not changed to capitals. |
| 6 | Undo the import. | Both enrollments are removed; the program stays. |

**Cleanup:** none after the undo.

## T-PRG-16: Only a Person Is Enrolled or Served

**Purpose:** confirm an organization or household account is refused on every path, and that Health Check reports Nonprofit Cloud Program Management when the org has it.
**Prerequisites:** the admin user; an Active program with a service; an organization account and a household account; for step 4, a person account org; for step 5, an org with Nonprofit Cloud Program Management (optional).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Enrollments** tab, click **New**, choose the program and the organization account as **Account**, and save. | The save is refused: "Choose a person. An organization or household account cannot be enrolled or receive a service." |
| 2 | Open the **Service Deliveries** tab, click **New**, choose the service, the household account, a Delivery Date and Attendance, and save. | The same message. |
| 3 | Enroll a contact, then edit the enrollment: clear **Contact** and choose the organization account. | The same message. |
| 4 | In a person account org, enroll a person account. | It saves. |
| 5 | In an org with Nonprofit Cloud Program Management, run **Health Check**. | An information finding says the org also has Nonprofit Cloud Program Management, with no fix. BarnCRM Settings, **Integrations** lists it under **Alternatives to BarnCRM Modules**. In barn-sales neither appears. |

**Cleanup:** delete the test enrollments.

## T-PRG-16: Count People Without Names

**Purpose:** confirm a drop-in count is added from the Service Delivery Log, totals for the day, and shows on the dashboard apart from named people.
**Prerequisites:** the admin user and the staff user; an Active program with an Active service and one enrolled test person with a Present delivery today (T-PRG-09).

| Step | Action | Expected result |
|---|---|---|
| 1 | As the staff user, open the program. Under the log's rows, find **People counted without names for this service and day**. | It reads 0, with **People Served, Not Named** and a disabled **Add to the Count**. |
| 2 | Enter 12 and click **Add to the Count**. | "Added 12 to the count." and the total reads 12. |
| 3 | Enter 8 and click **Add to the Count**. | The total reads 20 (each click adds a row). |
| 4 | Change the **Date** to yesterday. | The total reads 0. Change it back to today. |
| 5 | Open the **Service Counts** tab. | Two rows for today (12 and 8) in **All Service Counts**; **This Week** lists them too. |
| 6 | Edit one row to -3 and save. | Refused: People Served cannot be negative. |
| 7 | Open the **Programs Dashboard**, period **This Month**. | **Counted Without Names** shows 20 (more if earlier counts exist this month); **People Served** is unchanged and counts only named people. The program's row shows the same 20 in its own column. |
| 8 | As a Read Only user, open the program and the dashboard. | The log shows the total without the input and button; the dashboard shows the figure. |
| 9 | As the admin, try to delete the service. | Refused: a service with counts is kept. |

**Cleanup:** delete the two counts and the test delivery.

## T-PRG-17: Referrals In and Out

**Purpose:** confirm referrals record direction, status and outcome, are private, and are deleted when their person is erased.
**Prerequisites:** the admin user and a staff user with the Programs Staff set; a test person enrolled in a program.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the staff user, open the enrollment and, in **Referrals**, click **New**. | The form shows **Direction** (Out by default), **Referral Date** (today), **Status** (Open) and **Outcome**. |
| 2 | Save with neither **Contact** nor **Account**. | Refused: a referral is one person. |
| 3 | Pick the test person's contact, **Other Organization** "Legal Aid Clinic", and save. | The referral is listed on the enrollment. |
| 4 | Edit it: **Status** Closed, **Outcome** Service Received. | Saved. |
| 5 | Open the **Referrals** tab, **Open Referrals**. | The closed referral is not listed; **All Referrals** lists it. |
| 6 | Make a second referral as the admin, **Direction** In. As the staff user open **All Referrals**. | Only the staff user's own referral is listed. |
| 7 | As a Read Only user, look for the **Referrals** tab. | Not available. |
| 8 | As a staff user, try to delete a referral. | No Delete is offered. |
| 9 | As the admin, erase the test person (see [Erase a Person](../admin-guide/erase-a-person.md)). | The erasure result lists the person's **Referrals** as deleted; the enrollment is kept. |

**Cleanup:** delete the remaining test referrals and enrollment.

## T-PRG-18: Eligibility Screening Rules

**Purpose:** confirm rules are built and checked, the preview matches what screening saves, and a decision made by hand is not overwritten.
**Prerequisites:** the admin user and a staff user; a program with three open enrollments whose **Referral Source** is Self, School and Other.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the admin, open the program. Find the **Eligibility Rules** panel. | It says there are no rules yet; **Add a Rule** is offered. |
| 2 | Click **Add a Rule**. Condition: **Referral Source** equal to Self. **Result** Not Eligible, **Reason** "Self referral is not accepted", **Eligibility Basis** Referral. Add a second rule: **Referral Source** one of "School, Another Agency", **Result** Eligible, **Reason** "Referred by a partner". Leave **Default Result** at Review. | **Unsaved changes** shows; **Save Rules** is enabled. |
| 3 | Under **Preview and Screen**, pick each person in turn. | Self: "These rules would give Not Eligible: Self referral is not accepted"; School: Eligible with its reason; Other: Review with "No rule applied." |
| 4 | Click **Screen Open Enrollments** before saving. | "Save the rules first". Nothing changes. |
| 5 | Click **Save Rules**, then **Screen Open Enrollments**. | "Screened: 1 Eligible, 1 Not Eligible, 1 Review, 0 left alone." |
| 6 | Open each enrollment. | Self: **Not Eligible**, Basis Referral, the reason, **Eligibility Date** today. School: **Eligible** with its date. Other: **Review**, reason "No rule applied.", no date. |
| 7 | Set Other to **Eligible** by hand, then screen again. | "... 1 left alone." and Other is still Eligible. Tick **Also screen enrollments already Eligible or Not Eligible** and screen again: Other returns to Review. |
| 8 | Add a rule whose condition field is blank, or clear a rule's **Reason**, and **Save Rules**. | Refused with a sentence naming the rule; the saved rules are unchanged. |
| 9 | Move rule 2 above rule 1, save, and preview Self. | Unchanged result (the rules do not overlap); with a rule 1 of **Referral Source** not blank, moving it first decides every row. |
| 10 | As the staff user, open the program. | The rules show but cannot be changed; **Screen Open Enrollments** works. |

**Cleanup:** clear the rules (remove each rule and **Save Rules**) and reset the enrollments' eligibility.

## T-PRG-16: Keep a Service Plan With Goals, Steps, Reviews and Notes

**Purpose:** confirm staff keep a participant's goals and steps on the enrollment, that the dates fill in, that reviews and notes attach to a goal, that a plan is seen as its enrollment is, and that erasing the person deletes it.
**Prerequisites:** the admin user; a staff user with a BarnCRM role of Team Member (Programs Staff); the Read Only user; a program with a test person enrolled ("Test Person"). For step 9, Logic Models installed with a logic model for that program holding an outcome.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the staff user, open Test Person's enrollment. | The **Service Plan** panel is at the top, saying there are no goals yet, with **Add Goal**. |
| 2 | Click **Add Goal**, type "Find stable housing", Status In Progress, a Target Date next month, a Next Review date of yesterday. Save. | The goal is listed with "Target (the date)" and **Review due**. |
| 3 | Under the goal add the steps "Apply" and "Visit". Tick "Apply". | "1 of 2 steps done"; opening the step record shows today as Completed Date. Untick it: the Completed Date empties. |
| 4 | Click **Mark Reviewed**. | A date three months on is offered. Save Review: Last reviewed is today, Next review the date offered, **Review due** is gone. |
| 5 | Click **New Note** under the goal, write a Subject, Save, and go back to the enrollment. | The new note opened with Enrollment and Goal filled in; the goal lists it under **Case Notes**. |
| 6 | Create a case note on another of Test Person's enrollments and pick this goal. | Refused: choose a goal of this enrollment. |
| 7 | **Edit Goal**, set Status to Achieved. Save. | The goal moves below open goals with "Closed (today)"; **Mark Reviewed** is no longer offered. |
| 8 | As the staff user, try to delete the goal from its record page. | No Delete action. As the Read Only user, open the enrollment: the plan is shown with no Add Goal, Edit Goal, step boxes or New Note. |
| 9 | With Logic Models: as the staff user, **Edit Goal** and open **Outcome**. | "No outcome", then the program's model's outcomes, then the organization model's. Pick one and save: "Works toward (the outcome)". Without Logic Models there is no Outcome field. |
| 10 | Set Participant Privacy to **Private** and open the enrollment as a second staff user it is not shared with. | Neither the enrollment nor its goals are visible; the **Goals** tab does not list the goal. Set it back to Shared. |
| 11 | As the admin, erase Test Person. | The summary lists Goals as deleted; the goal and its steps are gone, the enrollment stays. |

**Cleanup:** delete the enrollments; remove the staff user's role.

## T-PRG-17: Cohorts, Mass Enrollment, Scheduled Sessions and Session Attendance

**Purpose:** confirm a cohort takes people already enrolled and enrolls new ones in one step, that sessions are scheduled over a date range, that attendance on a session is one service delivery per person and takes over a delivery already logged that day, and that a cancelled session takes no attendance.
**Prerequisites:** the admin user; a staff user with a BarnCRM role of Team Member (Programs Staff); the Read Only user; a program with an active service "Tutoring", two people enrolled in it ("Ana" and "Ben") and a third person not enrolled ("Cara").

| Step | Action | Expected result |
|---|---|---|
| 1 | As the staff user, open the program and, in **Cohorts**, click **New**. Name it "Spring", Start Date the first of next month, End Date two weeks later. Save. | The cohort opens with the **Cohort Members** panel ("Members (0)") and the **Schedule Sessions** panel. An End Date before the Start Date is refused. |
| 2 | Under **Add People**, tick Ana and Ben. Pick Cara under the person picker and click **Add to List**. Click **Add to Cohort**. | "3 people added." All three are members; Cara now has an Enrolled enrollment in the program, in the cohort. |
| 3 | Pick Ana again, add her to the list and click **Add to Cohort**. | Ana is listed under **Not Added** with the reason; nobody is added twice. |
| 4 | Click **Remove** by Ben. | Ben leaves the members and is offered again under the people to add; his enrollment stays, with no cohort. |
| 5 | On an enrollment in another program, set **Cohort** to Spring. | Refused: the cohort must belong to the enrollment's program. |
| 6 | In **Schedule Sessions**, pick Tutoring, keep the cohort's dates, tick Monday and Wednesday, set a Start Time. | The line under the form gives the number of sessions (4 for a range starting on a Monday). Click **Schedule**: "4 sessions scheduled.", listed under the cohort's **Sessions**, each named "Tutoring (date)". |
| 7 | Set **To** before **From**, then untick every day. | The line asks for dates, then for days; **Schedule** is off. |
| 8 | As the staff user, open the program's **Service Delivery Log**, pick Tutoring and the first session's date, mark Ana Present and save. Then open that session. | The session's log lists only the cohort members (Ana, Cara) with Ana already Present. |
| 9 | Mark Cara Present and save. | "2 service deliveries saved."; the session's Status is Held. The session's **Service Deliveries** list shows two, and the program has no second delivery for Ana that day. |
| 10 | Open another session and set its Status to Cancelled. | The log shows the session is cancelled with no controls; saving attendance on it is refused. |
| 11 | Try to delete the held session. | Refused while it has service deliveries. |
| 12 | As the Read Only user, open the cohort and a session. | Members, sessions and attendance are shown with no Add, Remove, Schedule or Save. |
| 13 | On the program, schedule a session in **Schedule Sessions** (no cohort). Open it. | The log lists everyone with an open enrollment in the program. |

**Cleanup:** delete the sessions without deliveries and the cohort; delete the enrollments; remove the staff user's role.
