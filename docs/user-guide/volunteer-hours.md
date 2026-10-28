# Volunteer Hours, Profiles and Letters

This page covers recording the time volunteers give, approving it, and what a person's record
shows about their volunteering: their profile, readiness, skills and availability. It also
covers hour letters and certificates. Jobs, shifts and sign-ups are on
[Volunteer jobs, shifts and sign-ups](volunteer-shifts.md).

**Before you start:** open the **BarnCRM Volunteers** app from the App Launcher. Team Members
enter hours and see the hours they entered themselves. Approving hours, the readiness card and
letters need the **Manage Volunteers** permission, which comes with the Coordinator and Admin
roles (the **Volunteers Coordinator** and **Volunteers Admin** permission sets). Read Only users
see no hours entries. If you need more access, ask your admin (see the
[Volunteers admin guide](../admin-guide/volunteers.md#roles-and-permission-sets)).

Only **Approved** hours count: in a person's totals, on reports and in letters. When your
organization requires approval (the usual setting), a new entry waits as **Submitted** until a
coordinator approves it.

## To Log Hours by Attendance

The quickest way: on the shift's **Sign-Ups** panel, click **Attended** in the person's row.
BarnCRM records hours for the length of the shift. See
[To mark attendance after a shift](volunteer-shifts.md#to-mark-attendance-after-a-shift).

## To Log Hours by Hand

Use this for work that was not on a shift, or a shift with no hours recorded.

1. Click the **Volunteer Hours** tab, then **New**.
2. Fill in **Contact** (or **Account**, if your people are person accounts: one or the other,
   never both).
3. Fill in **Job**, **Volunteer Shift**, or both.
4. Fill in **Date Worked** and **Hours**. Add **Notes** if useful.
5. Click **Save**.

You should see: a new entry (numbered like VH-000123) with **Status** **Submitted**. You cannot
change **Status** yourself; it moves only through approval.

To see entries, use the list view menu on the **Volunteer Hours** tab: **All Hours** or
**Awaiting Approval**.

## To Approve Hours

Needs **Manage Volunteers**.

1. Click the **Approve Hours** tab.
2. Leave **Show** on **Submitted** to see the entries waiting. To narrow the list, choose a
   **Job**, or set **From** and **To** (dates worked).
3. Tick the entries to approve, or tick the box in the heading row to select the whole page.
4. Click **Approve**.

You should see: "Entries approved: 3." (with your number), and the entries gone from the
Submitted list. They count in totals from now on, and record you in **Reviewed By** and the time
in **Reviewed Date**.

Use **Previous** and **Next** to move between pages.

## To Reject Hours

1. On **Approve Hours**, with **Show** on **Submitted**, tick the entries.
2. Click **Reject**.
3. Type the **Reason for rejecting** (required) and click **Reject selected**.

You should see: "Entries rejected: 1." The person who entered the hours sees your reason in
**Rejection Reason** on the entry.

## To Reopen Approved or Rejected Hours

An approved entry is locked. To correct or delete it, reopen it first.

1. On **Approve Hours**, set **Show** to **Approved** or **Rejected**.
2. Tick the entries and click **Reopen**.

You should see: "Entries reopened: 1." The entries are back at **Submitted**, out of every total,
and can be edited, deleted, or approved again.

## To See a Person's Volunteering

1. Open the person in the **BarnCRM Volunteers** app (for example from a sign-up, an hours
   entry, or global search).
2. Find the **Volunteer Profile** section.

You should see: **Volunteer Status** (Prospective, Active or Inactive), **Volunteer Since**,
**Availability Days**, **Availability Times**, **Emergency Contact Name** and **Emergency
Contact Phone**, which you can edit; and **Volunteer Hours Total**, **Volunteer Hours This
Year**, **Volunteer Hours Last Year**, **First Volunteer Date** and **Last Volunteer Date**, which
BarnCRM calculates from approved hours and you only read. "This year" and "last year" follow
your organization's fiscal year.

The section shows once a person has a **Volunteer Status** or approved hours. Coordinators and
admins always see it, so they can set the status of someone new.

## To Record Availability

1. On the person, in **Volunteer Profile**, click the pencil next to **Availability Days**.
2. Pick the days in **Availability Days** and the parts of the day in **Availability Times**
   (Morning, Afternoon, Evening).
3. Click **Save**.

## To Add a Skill or Interest to a Person

1. On the person, find the **Volunteer Skills** list and click **New**. (If it is not on the
   page, ask your admin to add it: see
   [Skills and interests](../admin-guide/volunteers.md#skills-and-interests).)
2. Choose the **Skill**, and a **Type**: **Skill** means they can do it, **Interest** means
   they would like to.
3. Click **Save**.

The list of skills itself is kept on the **Skills** tab by coordinators and admins.

## To Check a Volunteer's Readiness

Needs the Coordinator or Admin role.

1. Open the person in the **BarnCRM Volunteers** app.
2. Find the **Volunteer Readiness** card.

You should see: each onboarding step (for example Application, Background check, Orientation)
with its status, completed date and expiry, and **Current** or **Not current**. A step with no
record says **Not started**. Click a step to open it. After adding a step, click **Refresh**.

The card only informs: it never stops a sign-up or hours.

## To Make an Hours Letter or Certificate

Needs **Manage Volunteers**.

1. Open the person in the **BarnCRM Volunteers** app.
2. Click **Volunteer Letter** in the actions at the top of the record.
3. Choose the **Template** (an hours letter or a certificate).
4. Check **From** and **To**. They start at 1 January this year and today.
5. Click **Preview** to read the letter, then **Generate**.

You should see: "The letter is saved as a PDF in this person's Files." The letter counts only
**Approved** hours with a **Date Worked** in the period.

To make letters for a whole list of people at once, ask your admin: see
[Hour letters and certificates](../admin-guide/volunteers.md#hour-letters-and-certificates).

## Common Problems

- Problem: someone else's hours are missing from **Volunteer Hours**. Why and what to do: hours
  are private. A Team Member sees only the hours they entered; a coordinator sees them all.
- Problem: "Choose the volunteer job or the shift these hours were given to." Why and what to
  do: fill in **Job** or **Volunteer Shift**.
- Problem: "Enter a contact or an account, not both. An hours entry is one person." Why and what
  to do: clear one of the two fields.
- Problem: "Hours must be more than zero." Why and what to do: enter a positive number.
- Problem: "Approved hours are locked. Move the entry back to Submitted to change the person,
  the date or the hours, then approve it again." Why and what to do: ask a coordinator to
  **Reopen** it on **Approve Hours**.
- Problem: "Approved hours count in totals, so they cannot be deleted. ..." Why and what to do:
  reopen the entry first, then delete it.
- Problem: "Only a volunteer coordinator with the Manage Volunteers permission can approve,
  reject or reopen volunteer hours." Why and what to do: you edited **Status** on the record.
  Use the **Approve Hours** tab, which needs Manage Volunteers.
- Problem: **Approve Hours** shows "You need the Manage Volunteers permission to approve, reject
  or reopen volunteer hours. Ask your BarnCRM administrator." and no buttons. Why and what to do:
  you do not have the Coordinator or Admin role.
- Problem: "From must be on or before To." Why and what to do: fix the dates; the list stays as
  it was until you do.
- Problem: "Not moved: ... The reasons are listed on the screen." Why and what to do: some
  entries could not be changed (for example ones you can see but not edit). The others moved.
- Problem: a person's totals did not go up. Why and what to do: only **Approved** hours count.
  Check the entry's **Status**.
- Problem: no **Volunteer Profile** section or readiness card. Why and what to do: you opened
  the person in another app, or the person has no **Volunteer Status** yet. Switch to the
  **BarnCRM Volunteers** app, or ask a coordinator to set the status. The readiness card is
  empty for anyone without the Coordinator or Admin role.
- Problem: "No letter: this person has no approved volunteer hours in the period." Why and what
  to do: approve the Submitted entries first, or widen **From** and **To**.
- Problem: "Your organization's legal name is blank in BarnCRM Settings, so the letter will
  print without it. ..." Why and what to do: ask your admin to fill in the organization's legal
  name.
- Problem: "No letter: this account is a household or organization, not a person. Open the
  person instead." Why and what to do: letters are for people. Open a household member.
- Problem: "No volunteer letter template is active. ..." Why and what to do: ask your admin to
  make a template active.

## Related

- [Volunteer jobs, shifts and sign-ups](volunteer-shifts.md)
- [Reports and dashboards](reports-and-dashboards.md): hours reports and the Volunteers dashboard
- [People and households](people-and-households.md)
- Admin Guide: [Volunteers](../admin-guide/volunteers.md), including
  [Approving hours](../admin-guide/volunteers.md#approving-hours),
  [Volunteer totals](../admin-guide/volunteers.md#volunteer-totals) and
  [Onboarding requirements](../admin-guide/volunteers.md#onboarding-requirements)
