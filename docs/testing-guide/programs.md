# Programs

Scripts for programs, services, enrollments, the Program Roster panel and Programs access. Setup detail: [Programs](../admin-guide/programs.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Programs deployed and sample data loaded unless a script says otherwise. Programs has no sample data of its own: T-PRG-02 creates the program later scripts use. Programs is offered in the **Nonprofit Edition** only: run every script here in that edition (see [Edition modes](before-you-test.md#edition-modes)). Leave the automation **Enrollment: fill in the stage dates** on (the default) unless a script says otherwise.

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
| 3 | Open **After-school tutoring**. | The roster shows **Applied** 1, **Enrolled** 4, **Withdrawn** 1, and the services Tutoring hour and Homework club session. |
| 4 | Create a contact "Rita Real" and enroll her in **Food pantry**. | Accepted. |
| 5 | Select **Remove Sample Data** and wait. | **Summer reading** and **After-school tutoring** are gone. **Food pantry** stays, with only Rita's enrollment, and the [Error Log](../admin-guide/error-log.md) holds one Warning naming it. The card still offers **Remove Sample Data**. |
| 6 | Delete Rita's enrollment, then select **Remove Sample Data** again. | **Food pantry** is gone. |

Note: Core's sample set has more than 12 people, so every count above holds; with fewer sample people the set is smaller.

**Cleanup:** delete Rita Real.
