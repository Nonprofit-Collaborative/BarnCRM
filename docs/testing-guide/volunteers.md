# Volunteers

Scripts for jobs, shifts, sign-ups, hours approval, skills and Volunteers access. Setup detail: [Volunteers](../admin-guide/volunteers.md).

Before you start: an org from [Before you test](before-you-test.md), with Core, BarnCRM Rollup Builder and Volunteers deployed and sample data loaded unless a script says otherwise. Volunteers is offered in the **Nonprofit Edition** only: run every script here in that edition (see [Edition modes](before-you-test.md#edition-modes)). Leave **Hours require approval** and **Attendance creates hours** on (the defaults) unless a script says otherwise.

## T-VOL-01: Open the Volunteers App

**Purpose:** confirm the app, its tabs and its list views load for an admin.
**Prerequisites:** admin user (see [Test users](before-you-test.md#test-users)); sample data loaded.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | From the App Launcher, open **BarnCRM Volunteers**. | The tabs **Volunteer Jobs**, **Volunteer Shifts**, **Volunteer Sign-ups**, **Volunteer Hours**, **Approve Hours**, **Volunteer Letter Templates**, **Skills**, **Volunteer Requirements**, **Dashboards** and **Reports** show. There is no **Volunteer Settings** tab. |
| 2 | Open **Volunteer Jobs**, list view **All Jobs**. | **Food pantry sort**, **Front desk** and **Community garden** are listed. |
| 3 | Open **Volunteer Shifts**, list view **Shifts Needing Volunteers**. | Upcoming Open shifts of **Front desk** and **Community garden** are listed, each named from its job and start (for example "Front desk: 28 Oct 2026, 9:00 AM"). |
| 3a | Open **Volunteer Sign-ups**, list view **All Sign-Ups**. | The sample sign-ups are listed with their shift, person and status. |
| 4 | Open **Volunteer Hours**, list view **Awaiting Approval**. | Four sample entries with Status **Submitted** are listed. |
| 5 | Open **Skills**, list view **All Skills**. | **First aid**, **Spanish**, **Forklift** and **Gardening** are listed, each **Active**. |

**Cleanup:** None.

## T-VOL-02: Create a Job and a Shift

**Purpose:** confirm staff can set up a job and a dated shift, and a shift that ends before it starts is refused.
**Prerequisites:** staff user.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Volunteer Jobs**, click **New**. Enter **Job Name** "Test sorting", **Location** "Warehouse", leave **Active** ticked, and save. | The job opens. **Total Hours** is empty or 0. The related lists **Shifts**, **Shift Schedules** and **Job Skills** show. |
| 2 | In the **Shifts** list, click **New**. Enter **Shift Name** "Test shift", **Start Time** next Saturday 9:00 AM, **End Time** the same Saturday 8:00 AM, **Volunteers Needed** 2, and save. | The save is refused: "This shift ends before it starts. Check the start and end times." |
| 3 | Change **End Time** to 12:00 PM and save. | The shift saves with **Status** Open, **Slots Filled** 0 and **Slots Remaining** 2. |
| 4 | On the shift, open the actions at the top of the record. | No **Delete** is offered (staff never deletes). |

**Cleanup:** keep "Test sorting" and "Test shift" for T-VOL-03 to T-VOL-07.

## T-VOL-03: Sign People Up and Cancel a Sign-Up

**Purpose:** confirm the Sign-ups panel adds people, refuses a second sign-up for the same person, and frees a slot on cancel.
**Prerequisites:** staff user; "Test shift" from T-VOL-02.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open "Test shift". | The **Sign-Ups** card shows **Volunteers needed** 2, **Slots filled** 0, **Slots remaining** 2 and "Nobody is signed up for this shift yet." |
| 2 | Click **Add sign-up**. | A form shows a **Person** picker, a **Status** box set to **Signed up**, and **Save** and **Cancel**. **Save** is disabled until a person is chosen. |
| 3 | Choose a sample person from **The Garcia Family** and click **Save**. | "Sign-up added." shows under the figures and as a toast. **Slots filled** is 1, **Slots remaining** 1. The table **Sign-ups for Test shift** lists the person with Status **Signed up** and **Attended** and **No show** buttons. |
| 4 | Click **Add sign-up**, choose the same person again and click **Save**. | Refused: "This person is already signed up for Test shift. Change the sign-up that is there instead of adding another." **Slots filled** stays 1. |
| 5 | Add a second person from the same household. | **Slots filled** 2, **Slots remaining** 0. |
| 6 | In the second person's row, change **Status** to **Cancelled**. | A message "(the person's name): Cancelled." shows. **Slots filled** 1, **Slots remaining** 1. The row stays in the table. |
| 7 | Change the same row back to **Signed up**. | **Slots filled** 2, **Slots remaining** 0. |
| 8 | Click the first person's name. | Their **Volunteer Sign-up** record opens, linked to "Test shift". |

**Cleanup:** keep both sign-ups for T-VOL-04.

## T-VOL-04: Mark Attendance and Get Hours

**Purpose:** confirm marking a sign-up Attended writes one Submitted hours entry for the shift's length.
**Prerequisites:** staff user; "Test shift" (9:00 AM to 12:00 PM) with two sign-ups from T-VOL-03.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open "Test shift". In the first person's row click **Attended**. | Status shows **Attended**, the **Attended** button goes, and the message says "(the person's name): Attended. An hours entry was recorded for this attendance." |
| 2 | In the second person's row click **No show**. | Status shows **No show**. No hours message shows. |
| 3 | Open **Volunteer Hours**, list view **Awaiting Approval**. | One new entry for the first person: **Hours** 3, **Date Worked** the shift's date, **Job** "Test sorting", **Volunteer Shift** "Test shift", **Status** Submitted. |
| 4 | Back on the shift, change the first person's Status to **Confirmed**, then click **Attended** again. | No second hours entry is created: **Awaiting Approval** still shows one entry for this shift. |

**Cleanup:** keep the 3-hour entry for T-VOL-06.

## T-VOL-05: Enter Hours by Hand, Bad Input Refused

**Purpose:** confirm hand-entered hours start Submitted and the validation rules refuse bad entries.
**Prerequisites:** staff user; job "Test sorting".

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Volunteer Hours**, click **New**. Choose a sample person in **Contact**, leave **Job** and **Volunteer Shift** empty, enter **Date Worked** yesterday and **Hours** 2, and save. | Refused: "Choose the volunteer job or the shift these hours were given to." |
| 2 | Choose **Job** "Test sorting" and change **Hours** to 0. Save. | Refused, on **Hours**: "Hours must be more than zero." |
| 3 | Change **Hours** to 2, also fill **Account** with any household, and save. | Refused: "Enter a contact or an account, not both. An hours entry is one person." |
| 4 | Clear **Account** and save. | The entry saves with **Status** Submitted (read only on the page) and **Household** filled from the person. |
| 5 | Open the entry's action menu. | **Delete** is not offered to staff. |

**Cleanup:** keep the 2-hour entry for T-VOL-06.

## T-VOL-06: Approve, Reject and Reopen Hours

**Purpose:** confirm the Approve Hours tab filters, approves, rejects with a required reason, and reopens.
**Prerequisites:** admin user; the Submitted entries from T-VOL-04 and T-VOL-05.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Approve Hours**. | The card **Approve Volunteer Hours** shows, **Show** set to **Submitted**, with columns **Person**, **Job**, **Shift**, **Date worked** and **Hours**. **Approve** and **Reject** are disabled. |
| 2 | Set **From** to today and **To** to yesterday. | The field says "From must be on or before To." and the list does not change. |
| 3 | Clear both dates. In **Job**, choose "Test sorting". | Only the two "Test sorting" entries are listed. |
| 4 | Tick the 3-hour entry and click **Approve**. | "Entries approved: 1." shows under the buttons and as a toast. The entry leaves the list. |
| 5 | Tick the 2-hour entry and click **Reject**. Leave **Reason for rejecting** empty and click **Reject selected**. | Nothing is rejected; the field says "Say why these hours are rejected, so the person who entered them knows what to fix." |
| 6 | Type "Wrong date" and click **Reject selected**. | "Entries rejected: 1." The list says "No hours match these filters." |
| 7 | Set **Show** to **Rejected**. | The 2-hour entry is listed with **Rejection Reason** "Wrong date". Only **Reopen** shows. |
| 8 | Tick it and click **Reopen**. | "Entries reopened: 1." It is back under **Submitted**. |
| 9 | Open the job "Test sorting". | **Total Hours** is 3 (only the Approved entry counts). |

**Cleanup:** keep the Approved 3-hour entry for T-VOL-07.

## T-VOL-07: Approved Hours Are Locked

**Purpose:** confirm an Approved entry cannot be edited or deleted until reopened, and its status moves only through Approve Hours.
**Prerequisites:** admin user; the Approved 3-hour entry from T-VOL-06.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Approved 3-hour entry. Edit **Hours** to 4 and save. | Refused: "Approved hours are locked. Move the entry back to Submitted to change the person, the date or the hours, then approve it again." |
| 2 | Cancel the edit. Delete the entry. | Refused: "Approved hours count in totals, so they cannot be deleted. Reopen them first (move them back to Submitted, which needs the Manage Volunteers permission), then delete them." |
| 3 | Edit **Rejection Reason** to "Test" and save. | Refused: "The status of volunteer hours changes only when a coordinator approves, rejects or reopens them. New hours start as Submitted." |
| 4 | On **Approve Hours**, set **Show** to **Approved**, tick the entry and click **Reopen**. | "Entries reopened: 1." The job's **Total Hours** drops to 0. |
| 5 | Open the entry, set **Hours** to 4 and save. | Saves. Status is Submitted. |
| 6 | Approve it again on **Approve Hours**. | "Entries approved: 1." The job's **Total Hours** is 4. |

**Cleanup:** reopen and delete the hours entries, delete the sign-ups, "Test shift" and "Test sorting" (or leave them for T-VOL-11).

## T-VOL-08: Hours Without Approval

**Purpose:** confirm turning **Hours require approval** off makes new hours Approved at once, and back on restores Submitted.
**Prerequisites:** admin user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Volunteers**. | The section shows **Hours require approval**, **Attendance creates hours** and the shift horizon setting (8 weeks). |
| 2 | Turn **Hours require approval** off. | The change saves at once. |
| 3 | Create an hours entry for a sample person on job **Front desk**, 1 hour, yesterday. | It saves with **Status** Approved and **Reviewed By** you. |
| 4 | Turn **Hours require approval** back on. Create a second entry the same way. | It saves with **Status** Submitted. |

**Cleanup:** reopen the Approved entry on **Approve Hours**, then delete both entries. Confirm **Hours require approval** is on.

## T-VOL-09: Skills, and Retiring a Skill

**Purpose:** confirm skills are given to people and jobs, a retired skill cannot be given, and a held skill cannot be deleted.
**Prerequisites:** admin user.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Skills**, click **New**, enter **Skill Name** "Test driving" and save. | The skill saves with **Active** ticked and an empty **Volunteer Skills** list. |
| 2 | Open a sample person (Contact) from the Volunteers app. In **Volunteer Skills**, click **New**, choose **Skill** "Test driving", **Type** Interest, and save. | Saves. The skill's **Volunteer Skills** list shows the person. |
| 3 | On "Test driving", untick **Active** and save. | Saves. The person keeps the skill. |
| 4 | Add another **Volunteer Skill** with "Test driving" to a different person. | Refused, on **Skill**: "This skill is retired (not Active). Choose an active skill, or make this one active again on the Skills tab." |
| 5 | On job **Community garden**, add a **Job Skill** with "Test driving". | Refused with the same message. |
| 6 | Delete "Test driving". | Refused by Salesforce, because a volunteer skill uses it. The skill stays. |
| 7 | Tick **Active** again and save. Repeat step 4. | Saves. |

**Cleanup:** delete both volunteer skills, then delete "Test driving" (it deletes once nobody holds it).

## T-VOL-10: Coordinator Role Gives Approval

**Purpose:** confirm a Team Member cannot approve hours, and giving the Coordinator role gives Volunteers Coordinator with approval.
**Prerequisites:** staff user and admin user; at least one Submitted entry the staff user did not enter (sample data has four).

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open **BarnCRM Volunteers**. | No **Approve Hours**, **Volunteer Requirements**, or **Volunteer Letter Templates** tab. |
| 2 | Open **Volunteer Hours**, list view **All Hours**. | Only entries the staff user entered show; the sample entries do not. |
| 3 | As admin, open **BarnCRM Settings**, **Access**. Find the staff user in **Find a person**, choose **Coordinator** and click **Give Access**, then confirm. | The staff user shows on the Coordinator card, still also on Team Member. |
| 4 | Wait a minute. In Setup, open the staff user's **Permission Set Assignments**. | **Volunteers Coordinator** is assigned. |
| 5 | As staff, reload the app and open **Approve Hours**. | The tab shows with **Approve** and **Reject**; the four sample Submitted entries are listed. |
| 6 | Tick one and click **Approve**. | "Entries approved: 1." |

**Cleanup:** as staff, reopen that entry. As admin, click **Remove** for the staff user on the Coordinator card, then remove **Volunteers Coordinator** in Setup (the module never takes a set away).

## T-VOL-11: Read-Only User Sees and Changes Nothing

**Purpose:** confirm Volunteers Read Only shows jobs, shifts and sign-ups with no way to change them, and no hours.
**Prerequisites:** read-only user; sample data loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Volunteers**. | Tabs **Volunteer Jobs**, **Volunteer Shifts**, **Volunteer Hours** and **Skills** show. No **Approve Hours**, **Volunteer Requirements**, or **Volunteer Letter Templates**. |
| 2 | Open **Volunteer Jobs**. | Jobs list; no **New** button. Opening a job shows no **Edit**. |
| 3 | Open an upcoming **Front desk** shift. | The **Sign-Ups** card shows the figures and the people with their status as plain text. No **Add sign-up**, no status boxes, no **Attendance** column. |
| 4 | Open **Volunteer Hours**, list view **All Hours**. | No entries are listed (hours are private, and this user entered none). |
| 5 | Open **Skills**. | Skills list; no **New** button. |

**Cleanup:** None.

## T-VOL-12: A Job in Use Cannot Be Deleted

**Purpose:** confirm a job with shifts or hours is refused on delete and can be deactivated instead.
**Prerequisites:** admin user; sample data loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open job **Community garden** and delete it. | Refused: "This job has shifts or volunteer hours, so it cannot be deleted: its hours would lose their job. Clear Active instead to stop offering it." |
| 2 | Untick **Active** and save. | Saves. **Community garden** leaves the **Active Jobs** list view and stays in **All Jobs**. |
| 3 | Tick **Active** again and save. | It is back in **Active Jobs**. |

**Cleanup:** None (step 3 restores the job).

## T-VOL-13: Inactive List Views for Jobs, Skills and Letter Templates

**Purpose:** jobs, skills and letter templates open with All, Active and Inactive views.
**Prerequisites:** volunteer coordinator or admin, sample data loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Volunteer Jobs** tab and the list view menu. | **All Jobs**, **Active Jobs** and **Inactive Jobs** are listed. **Inactive Jobs** is empty. |
| 2 | Untick **Active** on a sample job that has no shifts or hours and save. | The job shows in **Inactive Jobs** and has left **Active Jobs**. Tick **Active** again. |
| 3 | Open the **Skills** tab and the list view menu. | **All Skills**, **Active Skills** and **Inactive Skills** are listed. |
| 4 | Open **Volunteer Letter Templates** and the list view menu. | **All Volunteer Letter Templates**, **Active Volunteer Letter Templates** and **Inactive Volunteer Letter Templates** are listed. A shipped template that is switched off shows under the Inactive view. |

**Cleanup:** tick **Active** on anything you switched off.

## T-VOL-14: Shift Reminders Go Out Once

**Purpose:** confirm a signed-up volunteer gets one reminder email before their shift, and nobody is emailed twice or against their wishes.
**Prerequisites:** admin user; a contact with your own email address; a second contact with **Email Opt Out** checked; Volunteers nightly jobs scheduled (Health Check, **Schedule all nightly jobs**).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Volunteers**. | **Send shift reminders** is off by default and **Days before a shift to remind** reads 1. |
| 2 | Create a shift that starts tomorrow in 3 hours' time or later. Sign up both contacts. Open one sign-up. | **Reminder Sent On** is empty and read-only for a Team Member, editable for a Coordinator. |
| 3 | Switch **Send shift reminders** on. In the Developer Console, run `VolunteerReminderBatch.startMorning();` as the admin. | The run starts. |
| 4 | Check the mailbox of the first contact and open each sign-up. | One email naming the job, day and time (and place, if the shift has one). The first sign-up now holds **Reminder Sent On**. The opted-out contact received nothing and has no stamp. |
| 5 | Run `VolunteerReminderBatch.startMorning();` again. | No second email. |
| 6 | Clear **Reminder Sent On** on the first sign-up and run it once more. | The email is sent again and the field is filled. |
| 7 | Set the sign-up to **Cancelled**, clear **Reminder Sent On**, run it again. | No email. |

**Cleanup:** switch **Send shift reminders** off; cancel the test shift.

## T-VOL-15: Suggested Volunteers Rank and Sign Up

**Purpose:** confirm the Suggested Volunteers card lists the right people in a sensible order and signs them up through the normal save.
**Prerequisites:** admin or coordinator; a job with a required skill (a **Job Skill**); an open shift on a Saturday; three contacts with **Volunteer Status** Active: Ana (holds the skill, **Availability Days** Saturday), Ben (no skill, availability Monday only), Cleo (no skill, none recorded); one Prospective contact.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the shift. | **Suggested Volunteers** is under the Sign-Ups panel. |
| 2 | Read the list. | Ana is first ("Has 1 of the 1 skills this job needs", "Available on Saturdays"), then Cleo ("No available days recorded"), then Ben ("Does not list Saturdays as an available day"). The Prospective contact is not listed. |
| 3 | Click **Sign up** on Ana's row. | "Ana is signed up for this shift." Ana leaves the list and appears in the Sign-Ups panel as Signed up, without a page refresh. |
| 4 | Add a Cancelled sign-up for Cleo in the Sign-Ups panel. | Cleo leaves the list (a cancelled sign-up still counts as signed up). |
| 5 | Set the shift's status to **Cancelled** and reload. | The card is gone. |
| 6 | Open a shift as a Read Only user. | No Suggested Volunteers card. |

**Cleanup:** delete the test sign-ups and restore the shift's status.
