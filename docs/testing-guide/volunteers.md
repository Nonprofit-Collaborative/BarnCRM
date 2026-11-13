# Volunteers

Scripts for jobs, shifts, sign-ups, hours approval, skills and Volunteers access. Setup detail: [Volunteers](../admin-guide/volunteers.md).

Before you start: an org from [Before you test](before-you-test.md), with Core, BarnCRM Rollup Builder and Volunteers deployed and sample data loaded unless a script says otherwise. Volunteers is offered in the **Nonprofit Edition** only: run every script here in that edition (see [Edition modes](before-you-test.md#edition-modes)). Leave **Require hours approval** and **Create hours from attendance** on (the defaults) unless a script says otherwise.

## T-VOL-01: Open the Volunteers App

**Purpose:** confirm the app, its tabs and its list views load for an admin.
**Prerequisites:** admin user (see [Test users](before-you-test.md#test-users)); sample data loaded.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | From the App Launcher, open **BarnCRM Volunteers**. | It opens on **Volunteers Home** with three figures: **Hours This Month** (badge **Approved**), **Volunteer Hours** (badge **Submitted**, 4) and **Shifts Needing Volunteers**, and the **Approved Hours This Year by Job** chart. Clicking **Volunteer Hours** opens **Approve Hours**; clicking **Shifts Needing Volunteers** opens that list view. The tabs **Volunteers Home**, **Volunteer Jobs**, **Volunteer Shifts**, **Volunteer Sign-Ups**, **Volunteer Hours**, **Approve Hours**, **Volunteer Letter Templates**, **Skills**, **Volunteer Requirements**, **Dashboards** and **Reports** show. There is no **Volunteer Settings** tab. |
| 2 | Open **Volunteer Jobs**, list view **All Jobs**. | **Food pantry sort**, **Front desk** and **Community garden** are listed. |
| 3 | Open **Volunteer Shifts**, list view **Shifts Needing Volunteers**. | Upcoming Open shifts of **Front desk** and **Community garden** are listed, each named from its job and start (for example "Front desk: 28 Oct 2026, 9:00 AM"). |
| 3a | Open **Volunteer Sign-Ups**, list view **All Sign-Ups**. | The sample sign-ups are listed with their shift, person and status. |
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

**Purpose:** confirm the Sign-Ups panel adds people, refuses a second sign-up for the same person, and frees a slot on cancel.
**Prerequisites:** staff user; "Test shift" from T-VOL-02.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open "Test shift". | The **Sign-Ups** card shows **Volunteers needed** 2, **Slots filled** 0, **Slots remaining** 2 as figures, an empty bar for places filled, and "Nobody is signed up for this shift yet." with an **Add Sign-Up** button. |
| 2 | Click **Add Sign-Up**. | A form shows a **Person** picker, a **Status** box set to **Signed up**, and **Save** and **Cancel**. **Save** is disabled until a person is chosen. |
| 3 | Choose a sample person from **The Garcia Family** and click **Save**. | "Sign-up added." shows under the figures and as a toast. **Slots filled** is 1, **Slots remaining** 1. The table **Sign-ups for Test shift** lists the person with a **Status** picker set to **Signed up**. The shift has not started, so there are no **Attended** or **No Show** buttons and no **Close Shift**. |
| 4 | Click **Add Sign-Up**, choose the same person again and click **Save**. | Refused: "This person is already signed up for Test shift. Change the sign-up that is there instead of adding another." **Slots filled** stays 1. |
| 5 | Add a second person from the same household. | **Slots filled** 2, **Slots remaining** 0. |
| 6 | In the second person's row, change **Status** to **Cancelled**. | A message "(the person's name): Cancelled." shows. **Slots filled** 1, **Slots remaining** 1. The row stays in the table. |
| 7 | Change the same row back to **Signed up**. | **Slots filled** 2, **Slots remaining** 0. |
| 8 | Click the first person's name. | Their **Volunteer Sign-Up** record opens, linked to "Test shift". |

**Cleanup:** keep both sign-ups for T-VOL-04.

## T-VOL-04: Mark Attendance and Get Hours

**Purpose:** confirm marking a sign-up Attended writes one Submitted hours entry for the shift's length.
**Prerequisites:** staff user; "Test shift" (9:00 AM to 12:00 PM) with two sign-ups from T-VOL-03.

| Step | Action | Expected result |
|---|---|---|
| 1 | Edit "Test shift": set **Start Time** to yesterday 9:00 AM and **End Time** to yesterday 12:00 PM, and save. | The **Sign-Ups** rows now show the status as a badge with a **Change** link, and **Attended** and **No Show** buttons. **Close Shift** shows at the top of the panel. |
| 2 | In the first person's row click **Attended**. | The badge shows **Attended** (green), the **Attended** button goes, and the message says "(the person's name): Attended. An hours entry was recorded for this attendance." |
| 3 | In the second person's row click **No Show**. | The badge shows **No show** (amber). No hours message shows. |
| 4 | Open **Volunteer Hours**, list view **Awaiting Approval**. | One new entry for the first person: **Hours** 3, **Date Worked** the shift's date, **Job** "Test sorting", **Volunteer Shift** "Test shift", **Status** Submitted. |
| 5 | Back on the shift, click **Change** in the first person's row and pick **Confirmed**, then click **Attended** again. | No second hours entry is created: **Awaiting Approval** still shows one entry for this shift. |

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
| 1 | Open **Approve Hours**. | The page **Approve Volunteer Hours** shows, **Show** set to **Submitted**, with columns **Person**, **Job**, **Shift**, **Date worked**, **Hours** and **Notes**. **Approve** and **Reject** are disabled. Each person's name is a link; clicking one opens that hours entry. |
| 2 | Set **From** to today and **To** to yesterday. | The field says "From must be on or before To." and the list does not change. |
| 3 | Clear both dates. In **Job**, choose "Test sorting". | Only the two "Test sorting" entries are listed. |
| 4 | Tick the 3-hour entry and click **Approve**. | "Entries approved: 1." shows under the buttons and as a toast. The entry leaves the list. |
| 5 | Tick the 2-hour entry and click **Reject**. Leave **Reason for rejecting** empty and click **Reject Selected**. | Nothing is rejected; the field says "Say why these hours are rejected, so the person who entered them knows what to fix." |
| 6 | Type "Wrong date" and click **Reject Selected**. | "Entries rejected: 1." The list shows an all-clear picture with "No hours match these filters." |
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

**Purpose:** confirm turning **Require hours approval** off makes new hours Approved at once, and back on restores Submitted.
**Prerequisites:** admin user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Volunteers**. | The section shows **Require hours approval**, **Create hours from attendance** and **Weeks ahead to create shifts** (8 weeks). |
| 2 | Turn **Require hours approval** off. | The change saves at once. |
| 3 | Create an hours entry for a sample person on job **Front desk**, 1 hour, yesterday. | It saves with **Status** Approved and **Reviewed By** you. |
| 4 | Turn **Require hours approval** back on. Create a second entry the same way. | It saves with **Status** Submitted. |

**Cleanup:** reopen the Approved entry on **Approve Hours**, then delete both entries. Confirm **Require hours approval** is on.

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

## T-VOL-10: Volunteers Coordinator Gives Approval

**Purpose:** confirm a Team Member cannot approve hours, and giving Volunteers Coordinator as an extra permission on the Access page gives approval.
**Prerequisites:** staff user and admin user; at least one Submitted entry the staff user did not enter (sample data has four).

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open **BarnCRM Volunteers**. | No **Approve Hours**, **Volunteer Requirements**, or **Volunteer Letter Templates** tab. |
| 2 | Open **Volunteer Hours**, list view **All Hours**. | Only entries the staff user entered show; the sample entries do not. |
| 3 | As admin, open **BarnCRM Settings**, **Access**. Under **Extra Permissions**, give the staff user **Volunteers Coordinator**, then confirm. The **Role** list does not offer Coordinator. | The staff user shows beside **Volunteers Coordinator**, still also on the Team Member card. |
| 4 | In Setup, open the staff user's **Permission Set Assignments**. | **Volunteers Coordinator** is assigned. |
| 5 | As staff, reload the app and open **Approve Hours**. | The tab shows with **Approve** and **Reject**; the four sample Submitted entries are listed. |
| 6 | Tick one and click **Approve**. | "Entries approved: 1." |

**Cleanup:** as staff, reopen that entry. As admin, under **Extra Permissions**, click **Remove** beside the staff user for **Volunteers Coordinator**.

## T-VOL-11: Read-Only User Sees and Changes Nothing

**Purpose:** confirm Volunteers Read Only shows jobs, shifts and sign-ups with no way to change them, and no hours.
**Prerequisites:** read-only user; sample data loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Volunteers**. | Tabs **Volunteer Jobs**, **Volunteer Shifts**, **Volunteer Hours** and **Skills** show. No **Approve Hours**, **Volunteer Requirements**, or **Volunteer Letter Templates**. |
| 2 | Open **Volunteer Jobs**. | Jobs list; no **New** button. Opening a job shows no **Edit**. |
| 3 | Open an upcoming **Front desk** shift. | The **Sign-Ups** card shows the figures and the people with their status as plain text. No **Add Sign-Up**, no status boxes, no **Attendance** column. |
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
**Prerequisites:** admin user; a contact with your own email address; a second contact with **Email Opt Out** checked; the nightly run scheduled (Volunteers' jobs are steps of [BarnCRM Nightly Jobs](../admin-guide/nightly-jobs.md); Health Check, **Schedule all nightly jobs**).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Volunteers**. | **Send shift reminders** is off by default and **Days before a shift to remind** reads 1. |
| 2 | Create a shift that starts tomorrow in 3 hours' time or later. Sign up both contacts. Open one sign-up. | **Reminder Sent On** is empty and read-only for a Team Member, editable for a Coordinator. |
| 3 | Switch **Send shift reminders** on. In the Developer Console, run `VolunteerReminderBatch.startMorning();` as the admin. | The run starts. |
| 4 | Check the mailbox of the first contact and open each sign-up. | One email naming the job, day and time (and place, if the shift has one). The first sign-up now holds **Reminder Sent On**. The opted-out contact received nothing and has no stamp. |
| 5 | Run `VolunteerReminderBatch.startMorning();` again. | No second email. |
| 6 | Clear **Reminder Sent On** on the first sign-up and run it once more. | The email is sent again and the field is filled. |
| 7 | Set the sign-up to **Cancelled**, clear **Reminder Sent On**, run it again. | No email. |
| 8 | Make a new sign-up for a shift that starts later today, after the run in step 6, and run it again with the lead time at 1. | The run stamps and emails only bookings whose shift starts after the run and before the end of the lead time; a booking made after a morning's run for a shift starting before the next morning's run gets no reminder from that run (tell such volunteers directly). |
| 9 | Check the sender of the email from step 6. | It comes from the user who scheduled the morning reminder job, and replies go to that user. |

**Cleanup:** switch **Send shift reminders** off; cancel the test shift.

## T-VOL-15: Suggested Volunteers Rank and Sign Up

**Purpose:** confirm the Suggested Volunteers card lists the right people in a sensible order and signs them up through the normal save.
**Prerequisites:** admin or coordinator; a job with a required skill (a **Job Skill**); an open shift on a Saturday; three contacts with **Volunteer Status** Active: Ana (holds the skill, **Availability Days** Saturday), Ben (no skill, availability Monday only), Cleo (no skill, none recorded); one Prospective contact.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the shift. | **Suggested Volunteers** is under the Sign-Ups panel. |
| 2 | Read the list. | Ana is first ("Has 1 of the 1 skills this job needs", "Available on Saturdays"), then Cleo ("No available days recorded"), then Ben ("Does not list Saturdays as an available day"). The Prospective contact is not listed. |
| 3 | Click **Sign Up** on Ana's row. | "Ana is signed up for this shift." Ana leaves the list and appears in the Sign-Ups panel as Signed up, without a page refresh. |
| 4 | Add a Cancelled sign-up for Cleo in the Sign-Ups panel. | Cleo leaves the list (a cancelled sign-up still counts as signed up). |
| 5 | Set the shift's status to **Cancelled** and reload. | The card is gone. |
| 6 | Open a shift as a Read Only user. | No Suggested Volunteers card. |

**Cleanup:** delete the test sign-ups and restore the shift's status.

## T-VOL-16: Person Accounts Are Reminded and Suggested as Accounts

**Purpose:** confirm that in an org that stores people as person accounts, a booking on the account gets its reminder and a suggested volunteer is signed up on the account, not the contact behind it.
**Prerequisites:** a person account org (not barn-sales); admin; **Send shift reminders** on; Volunteers nightly jobs scheduled; an open shift that starts tomorrow in 3 hours' time or later; a person account, Dana, with your own email address, **Volunteer Status** Active and Email Opt Out unchecked.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the shift. Read **Suggested Volunteers**. | Dana is listed. |
| 2 | Click **Sign Up** on Dana's row, then open the new sign-up. | The sign-up names Dana's **Account**, and **Contact** is empty. Dana leaves the suggestions. |
| 3 | In the Developer Console, run `VolunteerReminderBatch.startMorning();` as the admin. Reopen the sign-up. | **Reminder Sent On** has a date and time; the mailbox received one reminder greeting Dana by first name. |
| 4 | Check Email Opt Out on Dana's account, clear **Reminder Sent On** and run it again. | No email, and **Reminder Sent On** stays empty. |

**Cleanup:** cancel the sign-up, uncheck Email Opt Out, and switch **Send Shift Reminders** off if it was off before.

## T-VOL-17: Close a Shift From the Sign-Ups Panel

**Purpose:** confirm Close Shift completes a started shift and can mark the people still booked as no shows.
**Prerequisites:** coordinator; a shift that started yesterday, Status Open, with three sign-ups: one Attended, one Signed up, one Confirmed.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the shift and click **Close Shift**. | A dialog **Close Shift** asks "Close this shift? 2 people are still Signed up or Confirmed. Mark them No Show?" with **Mark No Show and Close** chosen and **Close Without Changing Them** offered. |
| 2 | Click **Cancel**. | Nothing changes; the shift is still Open. |
| 3 | Click **Close Shift**, keep **Mark No Show and Close**, and click **Close Shift**. | "Shift closed. Everyone still Signed up or Confirmed is now No Show." The two rows show **No show**, the Attended row is unchanged, **Close Shift** is gone, and the shift's **Status** is **Completed**. |
| 4 | As a Read Only user, open a started Open shift. | No **Close Shift** button. |

**Cleanup:** set the shift back to Open if it is reused.

## T-VOL-18: Volunteer Letter Periods

**Purpose:** confirm the Volunteer Letter action offers This Year, Last Year and Custom.
**Prerequisites:** coordinator; a person with approved hours last year; an active Hours letter template.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the person in the BarnCRM Volunteers app and click **Volunteer Letter**. | **Period** shows **This Year**, and no date fields. |
| 2 | Choose **Last Year** and click **Preview**. | The preview counts last year's approved hours only. |
| 3 | Choose **Custom**. | **From** and **To** show, filled with last year's dates. A From after the To is refused on Preview. |

**Cleanup:** none.

## T-VOL-19: Log Hours From a Shift, a Job and a Person

**Purpose:** confirm the Log Hours action prefills from the record and saves like New.
**Prerequisites:** Team Member; a shift from 9:00 to 12:00 with a job; a person.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the shift and click **Log Hours**. | A **Log Hours** form with **Person** empty, and **Job**, **Volunteer Shift**, **Date Worked** (the shift's day) and **Hours** 3 filled. |
| 2 | Choose the person and click **Save**. | "Hours logged." The form closes; the new entry is **Submitted**, on the shift and the job. |
| 3 | Open the job and click **Log Hours**. | Only **Job** is filled. Click **Save** without a person: **Person** is required. |
| 4 | Open the person and click **Log Hours**. | **Person** is filled with them. Fill in a job, a date and 2 hours and save: the entry is theirs. |
| 5 | As a Read Only user, open the shift and click **Log Hours**. | A note says your role cannot enter volunteer hours; no form. |
| 6 | Sign the person up for a shift that starts today, open the person and click **Log Hours**. | **Person**, **Job**, **Volunteer Shift**, **Date Worked** (today) and **Hours** (the shift's length) are filled. Cancel the sign-up and repeat: only **Person** is filled. |

**Cleanup:** delete the hours entries.

## T-VOL-20: Create Shifts Now on a Shift Schedule

**Purpose:** confirm the schedule page previews the next run and Create Shifts Now fills it at once.
**Prerequisites:** coordinator; a job; Weeks Ahead to Create Shifts at 8.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the job, in **Shift Schedules**, click **New**. | The form shows **Days of the Week**, **Repeat Every (Weeks)**, **Start Time** and **End Time**. |
| 2 | Pick Saturday, 1 week, 9:00 to 12:00, Start Date today, Volunteers Needed 4; save; open the schedule at once. | **Details** and **Related** tabs, and a **Volunteer Shifts** card beside them saying how many shifts will be created through a day 8 weeks ahead (or, if the save's own run already finished, that every shift is created through that day). |
| 3 | Set **Weeks Ahead to Create Shifts** to 10 in BarnCRM Settings and reopen the schedule. | The card says 2 shifts (the two new Saturdays) will be created through a day 10 weeks ahead, and **Create Shifts Now** is enabled. |
| 4 | Click **Create Shifts Now**. | "Shifts created: 2." The card says every shift is created through that day and the button is disabled; the two shifts are in **Related**. |
| 5 | Untick **Active** and save. | The card says the schedule is not active and creates no shifts; no button. |

**Cleanup:** set Weeks Ahead to Create Shifts back to 8; delete the schedule and its shifts.

## T-VOL-21: Shift Schedule Form Preview

**Purpose:** confirm New Shift Schedule and Edit Schedule say how many shifts the pattern makes as the fields change (modules-24, D-183).
**Prerequisites:** coordinator; a job; Weeks Ahead to Create Shifts at 8.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the job and click **New Shift Schedule**. | A form with the schedule fields, **Job** filled with this job, and a line asking you to choose at least one day of the week. |
| 2 | Pick Saturday and Sunday. | The line asks for a start date. |
| 3 | Set **Start Date** to today. | About 16 shifts "will be created through" a day 8 weeks from today. |
| 4 | Set **Repeat Every (Weeks)** to 2. | About half as many shifts. |
| 5 | Set **End Date** before **Start Date**. | The line asks for an end date on or after the start date. Clear **End Date**. |
| 6 | Fill in a name and times and click **Save**. | "Shift schedule saved." The form closes; the schedule is in **Shift Schedules** and its shifts appear within a minute. |
| 7 | Open the schedule and click **Edit Schedule**. | The saved values, and "With these settings the schedule has" a number of shifts "from today through" the horizon day. Untick **Active**: the line says the schedule creates no shifts. Cancel. |

**Cleanup:** delete the schedule and its shifts.

## T-VOL-22: Volunteer Letters for Many People

**Purpose:** confirm Volunteer Letters on Approve Hours makes letters for everyone with approved hours, or for chosen people, without Flow Builder.
**Prerequisites:** coordinator; two people with approved hours this year and one with none; an active Hours letter template.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Approve Hours**. | A **Volunteer Letters** button at the top right. As a Read Only user there is none. |
| 2 | Click it. Keep **This Year** and **Everyone with approved hours in the period**; click **Make Letters**. | The dialog closes and a toast says letters are being made for 2 people. Within a few minutes each of the two has a PDF in **Files**, and a notification says 2 letters were made. |
| 3 | Open it again, choose **People I choose**, and click **Make Letters** with nobody picked. | "Choose at least one person." Nothing starts. |
| 4 | Pick the person with no hours, then pick them again. | One name shows, once. Click **Make Letters**: a toast for 1 person; the notification says 1 was skipped with no approved hours. |
| 5 | Choose **Custom** with a From a year before anyone worked and a To a month later; choose **Everyone**; click **Make Letters**. | "Nobody has approved hours in this period, so no letters were started." |

**Cleanup:** delete the letter files.

## T-VOL-23: Unfilled Shift Nudges Go Out Once

**Purpose:** confirm an unfilled shift writes once to the job's regular volunteers, and nobody is emailed twice or against their wishes.
**Prerequisites:** admin user; three active contacts with approved hours on one job: one with your own email address, one with **Email Opt Out** checked, one already signed up to the shift below; the nightly run scheduled (Health Check, **Schedule all nightly jobs**).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Volunteers**. | **Send unfilled shift nudges** is off by default and **Days before a shift to nudge** reads 3. |
| 2 | Create a shift for that job that starts in 2 days and needs 2 people. Sign up the third contact. Open the shift. | **Slots Remaining** is 1. **Nudge Sent On** is empty and read-only for a Team Member, editable for a Coordinator. |
| 3 | Switch **Send unfilled shift nudges** on. In the Developer Console, run `VolunteerNudgeBatch.startMorning();` as the admin. | The run starts. |
| 4 | Check the mailbox of the first contact and open the shift. | One email naming the job, day and time. The opted-out and the already booked contacts received nothing. The shift now holds **Nudge Sent On**. |
| 5 | Run `VolunteerNudgeBatch.startMorning();` again. | No second email. |
| 6 | Clear **Nudge Sent On** and run it once more. | The email is sent again and the field is filled. |
| 7 | Sign up one more person so the shift is full, clear **Nudge Sent On**, run it again. | No email: a full shift is never nudged. |

**Cleanup:** switch **Send unfilled shift nudges** off; cancel the test shift.

## T-VOL-24: Value of Volunteer Time

**Purpose:** confirm the hour value shows on Volunteers Home and in letters, and 0 hides it.
**Prerequisites:** admin user; sample data loaded (approved hours this month).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Volunteers**. | **Value of one volunteer hour** reads 34.79. |
| 2 | Open **Volunteers Home**. | A **Value of Hours This Month** figure shows this month's approved hours times 34.79, in your currency. |
| 3 | Add `{HoursValue}` and `{HourValue}` to the Hours letter template and preview a letter for a person with approved hours. | The letter shows their hours times 34.79 and 34.79. |
| 4 | Set the value to 0 and reload **Volunteers Home**; preview the letter again. | The figure is gone; both tokens are empty. |

**Cleanup:** set the value back to 34.79; remove the tokens from the template.

## T-VOL-25: Thank-You Tasks for Milestones and Anniversaries

**Purpose:** confirm one task per milestone and anniversary, and none while the setting is off.
**Prerequisites:** admin user; contact A with 30 approved hours and no Last Hour Milestone; contact B with Volunteer Since exactly two years ago today.

| Step | Action | Expected result |
|---|---|---|
| 1 | In the Developer Console run `VolunteerRecognitionJob.startMorning();`. | Nothing happens: **Send thank-you tasks** is off by default. |
| 2 | Turn **Send thank-you tasks** on and run it again. | Contact A has one open task for 25 hours, due today, owned by A's owner; A's **Last Hour Milestone** is 25. Contact B has one anniversary task. |
| 3 | Run it again. | No new task for A or B: a person gets one anniversary task a day. |
| 4 | Approve hours so A reaches 120, run again. | One task, for 100; Last Hour Milestone is 100. |

**Cleanup:** turn the setting off; delete the tasks.

## T-VOL-26: Waitlist and Minimum on a Shift

**Purpose:** confirm a full shift waitlists and promotes oldest first, and the minimum only shows.
**Prerequisites:** coordinator; a future Open shift with Volunteers Needed 2 and Minimum Volunteers 2; four people.

| Step | Action | Expected result |
|---|---|---|
| 1 | Sign up person 1. Open **Shifts Below Minimum**. | The shift is listed with **Below Minimum** ticked. |
| 2 | Try Minimum Volunteers 3. | Refused: the minimum can't be more than Volunteers Needed. |
| 3 | With **Waitlist when full** off, sign up persons 2 and 3. | All three are Signed up; Slots Remaining is -1. Cancel person 3. |
| 4 | Turn **Waitlist when full** on. Sign up person 4, then person 3 again (reopen the cancelled row to Signed up). | Both are saved as **Waitlisted**; Slots Filled stays 2. |
| 5 | Cancel person 2. | Person 4 (waitlisted first) becomes **Signed up**; person 3 stays Waitlisted. |
| 6 | Raise Volunteers Needed to 3. | Person 3 becomes **Signed up**. |

**Cleanup:** turn **Waitlist when full** off; cancel the shift.

## T-VOL-27: Group and Standing Sign-Ups

**Purpose:** confirm a group takes its places and a standing sign-up repeats on a schedule.
**Prerequisites:** coordinator; an active weekly shift schedule with shifts for the next 8 weeks; a shift with Volunteers Needed 10.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the 10-place shift, sign up a leader and set **Group Size** 6, **Group Name** "Acme team". | **Places** is 6; the shift's Slots Filled is 6. |
| 2 | With **Waitlist when full** on, sign up a group of 5 there. | Saved as **Waitlisted** (4 places left). A single person signed up next is Signed up. |
| 3 | On the schedule's first shift, sign up a person and tick **Standing**. | Within seconds the person is Signed up, Standing, on every later shift of the schedule. |
| 4 | Click **Create Shifts Now** after raising the horizon to 10 weeks. | The new shifts also have the standing person. |
| 5 | Cancel the person's sign-ups from week 5 on, then create shifts again. | No new sign-ups for them. |

**Cleanup:** cancel the test sign-ups; set the horizon back to 8.

## T-VOL-28: Guardian Consent for a Young Volunteer

**Purpose:** confirm a minor's sign-up is flagged and gets one consent step, and nothing is refused.
**Prerequisites:** coordinator; a contact with a Birthdate 15 years ago; a future shift.

| Step | Action | Expected result |
|---|---|---|
| 1 | With **Guardian consent required** off, sign them up. | Saved; **Consent Needed** unticked; no new onboarding step. Delete the sign-up. |
| 2 | Turn it on and sign them up again. | Saved, **Consent Needed** ticked; their **Volunteer Readiness** card shows **Guardian consent**, Not started. |
| 3 | Sign them up for a second shift. | Flagged again, and still one Guardian consent step. |
| 4 | Complete the step with a **Guardian**, today's Completed Date and an Expires a year out; sign them up for a third shift. | Not flagged. |
| 5 | Set **Minor age** to 14 and sign up another 15-year-old with no consent. | Not flagged. |

**Cleanup:** turn the setting off; set Minor age back to 18.

## T-VOL-29: Background Check Details

**Purpose:** confirm provider details are kept on the step and only coordinators see them.
**Prerequisites:** coordinator and staff users; a person with a Background check step.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the coordinator, edit the step: Provider "Acme Screening", Reference ID "AS-123". | Saved; **Entry Source** reads Entered. |
| 2 | Load a row with Load One Object with Entry Source Imported. | The row shows Imported. |
| 3 | As the staff user, look for the step. | Not visible (requirements are kept to coordinators). |

**Cleanup:** delete the loaded row.

## T-VOL-30: Public Volunteer Sign-Up and Personal Page

**Purpose:** confirm a guest can sign up on a public shift page, is matched to their record, and reaches only their own personal page.
**Prerequisites:** admin; BarnCRM Forms on a Salesforce Site ([Forms testing](forms.md)); a published public sign-up form (first name, last name, email) and a published public profile form (`availabilityDays`, `emergencyContactName`); a job with two future Open shifts; an existing contact C with a known email; shift reminders on.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open `<site>/FormsPublic?list=volunteers` in a private window. | "No shifts" or a list without this job: it is not public yet. |
| 2 | On the job tick **Show on Public Page**, paste the form's ID in **Sign-Up Form**; reload. | Both shifts are listed, soonest first. As a staff user the two fields are read only. |
| 3 | Open a shift. | The job's description, the shift's day, time and place, places left and the form. No names of people booked. |
| 4 | Fill the form with C's name and email and send. | The confirmation shows. As the admin, C has a Signed up sign-up on that shift and no duplicate contact. |
| 5 | Fill the shift up, then reload its page with **Waitlist when full** off. | Sign-up is closed. Turn the waitlist on: the form shows and a new sign-up is Waitlisted. |
| 6 | Set **Self-service profile form** to the profile form; run `VolunteerReminderBatch.startMorning();` with C's shift inside the reminder window. | C's reminder ends with a personal link. |
| 7 | Open the link. | C's first name, upcoming shift, hours this year and total with their value, and the profile form. |
| 8 | Change one character of the link's signature and open it. | The page says it is not available. |
| 9 | On the real link, pick availability days and an emergency contact name and send. | C's Availability Days and Emergency Contact Name now hold those values. |

**Cleanup:** untick **Show on Public Page**; clear the profile form setting; delete the test sign-ups.

## T-VOL-31: Moving From V4S With the Migration Kit

**Purpose:** confirm the V4S Jobs, Shifts and Hours kit copies jobs, shifts, sign-ups and completed hours, keeps which job and shift each belongs to, and never changes V4S.
**Prerequisites:** admin; an org with Volunteers for Salesforce installed (a scratch or test org, never production); in V4S, a job J with street and city, two shifts on J (one past with Duration 3, one future with no Duration), a Confirmed and a No-Show hours entry on the future shift, and a Completed hours entry of 2.5 hours on the past shift, each for an existing contact; **Hours require approval** on.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Integrations**. | Volunteers for Salesforce shows **Installed in this org** and a **Start Migration** button. |
| 2 | Select **Start Migration**, then preview and load **Volunteer Jobs**. | One job named as J, Location "street, city", Active. **Check this step** matches. |
| 3 | Load **Volunteer Shifts**. | Two shifts on the new job: the past one ends three hours after its start and is Completed; the future one ends one hour after its start and is Open. |
| 4 | Load **Sign-Ups**. | Two sign-ups on the new future shift: Confirmed and No show, for the same contacts. No Attended sign-up and no hours are made. |
| 5 | Load **Completed Hours**. | One hours entry of 2.5 for the contact on the new job and past shift, Submitted, listed in **Approve Hours**. |
| 6 | Open the V4S records. | Nothing in V4S changed. |
| 7 | Undo **Completed Hours**, turn **Hours require approval** off, load the step again. | The entry is Approved. Turn the setting back on. |
| 8 | Read the kit's checklist. | It names the V4S site pages, recurring schedules, tabs and permission sets, and uninstalling. |

**Cleanup:** undo the four steps in reverse order.

## T-VOL-32: Volunteering at a Glance and the Log Hours Tab

**Purpose:** confirm staff in the BarnCRM app see a person's volunteering and can log hours without switching apps (D-200 R1).
**Prerequisites:** Volunteers Staff user; a person with approved hours this year; an organization.

| Step | Action | Expected result |
|---|---|---|
| 1 | In the **BarnCRM** app, open the person. | The sidebar's glance area shows **Volunteering at a Glance**: **Volunteer Hours This Year** and **Last Volunteer Date** from the person, with **Log Hours**. |
| 2 | Click **Log Hours**, fill in a job, a date and 2 hours, and click **Save**. | The **Log Hours** tab opens with the person filled in. "Hours logged." and you are back on the person's page. |
| 3 | Open **Log Hours** from the App Launcher. | The form opens empty. Save an entry: the form clears for the next one. |
| 4 | Open the organization. | No **Volunteering at a Glance** card. |
| 5 | As a Volunteers Read Only user, open the person. | The card shows its figures with no **Log Hours** button. |

**Cleanup:** delete the hours entries from steps 2 and 3.
