# Volunteer jobs, shifts and sign-ups

This page covers the everyday side of scheduling volunteers: the jobs your organization needs
help with, the dated shifts of each job, and who signed up for each shift. Logging and approving
the hours people give, and hour letters, are on [Volunteer hours](volunteer-hours.md).

A volunteer is a person you already have in BarnCRM. There is no separate volunteer record:
sign-ups and hours link to the person.

**Before you start:** open the **BarnCRM Volunteers** app from the App Launcher. You need a
Volunteers permission set, which comes with your BarnCRM role (Team Member, Coordinator, Admin or
Read Only). If the app is missing, ask your admin (see the
[Volunteers admin guide](../admin-guide/volunteers.md#roles-and-permission-sets)). Read Only
users can look at jobs, shifts and sign-ups but change nothing.

## To find a job or a shift

1. Click the **Volunteer Jobs** tab, or the **Volunteer Shifts** tab.
2. Open the list view menu at the top left and pick a list:
   - Jobs: **All Jobs** or **Active Jobs**.
   - Shifts: **All Shifts**, **Shifts Needing Volunteers** (open shifts from today that still
     have places left) or **Past Shifts Still Open** (shifts that ended more than 7 days ago
     and were never closed).
3. Click a name to open the record.

You should see: a job page with its details and the **Shifts**, **Shift Schedules** and
**Job Skills** lists, or a shift page with the **Sign-ups** panel at the top.

## To create a job

1. On the **Volunteer Jobs** tab, click **New**.
2. Fill in **Job Name**, and if you like **Description**, **Location** and **Coordinator**.
   Leave **Active** ticked.
3. Click **Save**.

You should see: the new job page. Its **Total Hours** and **Last Volunteer Date** stay empty
until someone's hours on it are approved.

To stop offering a job, clear **Active** rather than deleting it.

## To create a single shift

1. Open the job and find the **Shifts** list.
2. Click **New**.
3. Fill in **Shift Name**, **Start Time**, **End Time** and **Volunteers Needed**. **Status**
   starts as **Open**. Leave **Location** empty to use the job's.
4. Click **Save**.

You should see: the shift in the job's **Shifts** list, and **Slots Remaining** equal to
**Volunteers Needed**.

A shift needs both a start and an end time: marking someone **Attended** uses them to work out
the hours.

## To set up a shift that repeats

Work that happens every week is set up once, as a shift schedule on the job, and BarnCRM creates
the dated shifts for you. Coordinators and Team Members can do this; only an admin deletes a
schedule.

1. Open the job and find the **Shift Schedules** list. Click **New**.
2. Fill in **Schedule Name**, **Weekdays** (pick one or more), **Repeat Every (Weeks)** (1 for
   every week, 2 for every other week), **Start Time**, **End Time**, **Start Date** and
   **Volunteers Needed**. Leave **End Date** empty to keep it running, and **Location** empty to
   use the job's.
3. Leave **Active** ticked and click **Save**.

You should see: within about a minute, the new shifts in the job's **Shifts** list, each showing
the **Shift Schedule** it came from. **Created Through** on the schedule shows the last day it
has created shifts for. BarnCRM keeps adding shifts every night, a set number of weeks ahead
(your admin sets how many).

**Changing a schedule** changes only its future shifts that nobody is using. Shifts with a
sign-up or hours are kept as they are, and **Shifts Kept** on the schedule says how many. Check
those by hand: they still have the old times.

**To end a schedule**, clear **Active** or set an earlier **End Date**.

## To take one day off a schedule

1. Open that day's shift.
2. Click **Edit**, set **Status** to **Cancelled**, and click **Save**.

Do not delete the shift: a deleted shift comes back the next time the schedule is changed, a
cancelled one does not.

## To sign someone up for a shift

1. Open the shift. The **Sign-ups** panel at the top shows **Volunteers needed**, **Slots
   filled** and **Slots remaining**, and lists who is signed up.
2. Click **Add sign-up**.
3. Choose the **Person**. Leave **Status** as **Signed up**, or pick another status.
4. Click **Save**.

You should see: "Sign-up added." under the figures, the person in the list, and **Slots
filled** up by one.

More people than **Volunteers needed** can be signed up: **Slots remaining** then goes below
zero.

## To change a sign-up's status

1. On the shift's **Sign-ups** panel, find the person's row.
2. Pick the new status in the **Status** column: **Signed up**, **Confirmed**, **Attended**,
   **No show** or **Cancelled**.

You should see: the change saved at once, and a message naming the person and the new status.
A **Cancelled** sign-up frees its slot.

## To mark attendance after a shift

1. Open the shift.
2. In each person's row, under **Attendance**, click **Attended** or **No show**.
3. When everyone is marked, click **Edit** on the shift, set **Status** to **Completed**, and
   click **Save**.

You should see: for each person marked **Attended**, the message "An hours entry was recorded
for this attendance." BarnCRM creates their hours for the length of the shift, waiting for
approval like any other entry (if your admin has this turned on). Marking someone **Attended**
a second time records nothing more, and changing the status back deletes nothing.

## To edit a sign-up's notes or remove a sign-up

1. On the shift page, scroll to the **Sign-ups** related list below the details.
2. Open the row menu and choose **Edit** to change **Notes**, or **Delete** to remove the
   sign-up (Salesforce asks you to confirm).

To free the place but keep a record that the person had signed up, set the status to
**Cancelled** instead of deleting.

## Common problems

- Problem: "This person is already signed up for ..." when you add a sign-up. Why and what to
  do: a person can be signed up only once per shift. Change the status of the sign-up that is
  already there.
- Problem: "... is marked Attended, but no hours entry was created. A shift needs a start and an
  end time for its hours to be created automatically; otherwise enter the hours by hand." Why
  and what to do: the shift's times could not be used, or your admin has turned off hours from
  attendance. Enter the hours yourself (see [Volunteer hours](volunteer-hours.md#to-log-hours-by-hand)).
- Problem: "This shift ends before it starts. Check the start and end times." Why and what to
  do: fix **End Time** so it is after **Start Time**.
- Problem: "Check the schedule: pick at least one weekday, repeat every 1 to 52 weeks, ..." when
  saving a shift schedule. Why and what to do: one of the schedule fields is missing or out of
  range. The message lists each rule; fix the field and save.
- Problem: a schedule's shifts stop a few weeks out, or none appeared. Why and what to do: open
  the schedule and click **Save** to fill the missing days now. If it keeps happening, tell your
  admin: the nightly job that creates shifts may not be running.
- Problem: "This job has shifts or volunteer hours, so it cannot be deleted ..." Why and what to
  do: clear **Active** on the job instead.
- Problem: the **Sign-ups** panel has no **Add sign-up** button or attendance buttons. Why and
  what to do: you have read only access. Ask your admin if you need to sign people up.
- Problem: "Showing the first ... sign-ups." Why and what to do: the panel shows a limited
  number of rows. Use the **Sign-ups** related list below the details to see them all.

## Related

- [Volunteer hours](volunteer-hours.md): logging, approving, profiles and letters
- [Reports and dashboards](reports-and-dashboards.md): the Volunteers dashboard
- [Getting around](getting-around.md)
- [People and households](people-and-households.md)
- Admin Guide: [Volunteers](../admin-guide/volunteers.md), including
  [Recurring shifts](../admin-guide/volunteers.md#recurring-shifts) and
  [Signing people up for a shift](../admin-guide/volunteers.md#signing-people-up-for-a-shift)
