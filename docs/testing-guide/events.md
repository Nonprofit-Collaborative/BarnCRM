# Event Management

Scripts for events and the Events page (EV-01 to EV-06, EV-08 to EV-21, EV-23 to EV-28) and
their sample data. The attendee app (EV-22, EV-29) and sponsor lead scanning are tested in
[Portal Builder](portal-builder.md), T-PB-12 and T-PB-13.
Setup detail:
[Event Management](../admin-guide/events.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Event
Management deployed. Event Management works on the platform-only shape. Give the testers their
roles on the **Access** page: admin (Admin role), staff (Program Staff role) and read-only (Read
Only role). Each gets its Events permission set from the role.

Messages on every Events page: a refusal shows BarnCRM's own sentence, or the org's validation
rule wording when a save breaks one (D-191). Only an unexpected failure shows the general text,
such as `Nothing was saved. Try again. If it happens again, ask your BarnCRM admin to check the
Error Log.`, and the Error Log then has the detail.

## T-EV-01: Create an Event and Find It

**Purpose:** confirm an event saves with its rules and shows on the Events page.
**Prerequisites:** staff.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **BarnCRM** app and look at its tabs, then the App Launcher. | **Events Home**, **Event Calendar**, **Events** and **Event Speakers** follow **Data Manager** (and the other modules' pages); the App Launcher lists no BarnCRM Events, BarnCRM Forms or BarnCRM Portal Builder app (D-188), and **BarnCRM Admin** has **Portals** and **Portal Accesses** before **Error Log**, which is last. Open **Events Home**: the page says nothing is coming up and offers **New Event**. |
| 2 | Click **New Event**. Name `Spring Gala`, Start next Saturday 6:00 PM, End the same day 5:00 PM, save. | Refused: `End must be after Start.` |
| 3 | Set End to 10:00 PM, Capacity `0`, save. | Refused: `Capacity must be at least 1. Leave it empty for no limit.` |
| 4 | Set Capacity `200`, Venue Name `Town Hall`, save. | Saved as **Draft**, **In Person**. The page shows the highlights, a **Details** tab and the related lists in the sidebar. |
| 5 | Back on **Events Home**. | `Spring Gala` is listed with next Saturday's date, `6:00 PM to 10:00 PM`, a grey **Draft** badge and `Town Hall`. |
| 6 | Create `Admin Week` from next Monday 9:00 AM to next Wednesday 5:00 PM, Format **Virtual**, Online Link `https://example.org/join`. | On **Events Home** its dates read Monday to Wednesday and **Where** says `Online`. |
| 7 | Change `Spring Gala` to **Cancelled**, then click **Past**. | `Spring Gala` is under **Past**, not **Upcoming**. |

**Cleanup:** None.

## T-EV-02: Repeat an Event

**Purpose:** confirm Repeat Event makes draft occurrences in one series.
**Prerequisites:** staff, `Admin Week` from T-EV-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Events Home**, open `Admin Week`'s row menu, choose **Repeat Event**. | A dialog explains the copies, with **Every Week** chosen, **Occurrences to Add** `4` and four dates under **Preview**. |
| 2 | Choose **Every Month**, set **Occurrences to Add** to `60`. | **Repeat Event** is disabled. |
| 3 | Set it to `2`, click **Repeat Event**. | A message says `2 occurrences added as drafts.` Two more `Admin Week` events are listed a month and two months on, each **Draft**, Monday to Wednesday. |
| 4 | Open the first `Admin Week`. | **Occurrences** in the sidebar lists the two copies. Each copy's **Series** is the first event. |

**Cleanup:** Delete the copies as admin.

## T-EV-03: Read-Only and Staff Access

**Purpose:** confirm each role sees what it should.
**Prerequisites:** read-only and staff testers.

| Step | Action | Expected result |
|---|---|---|
| 1 | As read-only, open **Events Home**. | Events are listed; there is no **New Event**, and the row menu offers only **Open**. |
| 2 | As staff, open an event and try to delete it. | Staff cannot delete an event. As admin, delete works. |
| 3 | As read-only, open an event's **Tickets** tab. | Tickets and codes are listed; there is no **New Ticket Type** or **New Promo Code**. |

## T-EV-04: Ticket Types and Promo Codes

**Purpose:** confirm ticket types and codes save with their rules and show on the Tickets tab.
**Prerequisites:** staff, an event with Capacity `100`.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the event, click **Tickets**. | Two empty sections, **Tickets** and **Promo Codes**, with **New Ticket Type** and **New Promo Code**. |
| 2 | **New Ticket Type**: `General`, Price `-5`, save. | Refused: `Price cannot be below 0. Use 0 for a free ticket.` |
| 3 | Price `50`, Quantity `80`, save. Add `Student`, Price `20`, Quantity `40`. | Both listed, `$50.00` and `$20.00`, each **Active**. A warning says the quantities add up to 120, more than the capacity of 100. |
| 4 | **New Promo Code**: `early`, Percent, Discount Value `120`, save. | Refused: `A percent discount can be at most 100.` |
| 5 | Discount Value `10`, Ticket Type `General`, save. | Listed as `early`, `10%`, `General`, **Active**. |
| 6 | Add another code `EARLY`, Amount `5`. | Refused: the code `EARLY` is already used for this event. |
| 7 | Edit `early`: Valid Until yesterday. | It shows **Expired**. |
| 8 | Delete `Student` from its row menu and confirm. | It is gone and the capacity warning with it. |
| 9 | On **Events Home**, **Repeat Event** for this event, one occurrence. Open the copy's **Tickets**. | `General` is there with its price; no promo codes. |

**Cleanup:** Delete the copy as admin.

## T-EV-05: Agenda Builder

**Purpose:** confirm tracks and sessions, moving by menu, drag and keyboard, and clash flags.
**Prerequisites:** staff, an event from 9:00 AM to 5:00 PM on one day.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the event, click **Agenda**. | An empty state with **New Track** and **New Session**. |
| 2 | **New Track** `Admins` (Sort Order 1), then `Developers` (Sort Order 2). | Columns **Admins**, **Developers** and **No Track**, in that order. |
| 3 | **New Session** `Keynote`, no track, 9:00 to 10:00 AM, Room `Hall A`. | It shows under **No Track** with its time and `Keynote, Hall A`. |
| 4 | **New Session** `After Hours`, 6:00 to 7:00 PM. | Refused: the session must start and end within the event's dates. |
| 5 | **New Session** `Flows 101`, track Admins, 9:30 to 10:30 AM, Room `hall a`. | Both `Keynote` and `Flows 101` show a red note: same room at the same time as the other. |
| 6 | From `Flows 101`'s menu choose **Move to Developers**. | It moves to **Developers**; its time and room are unchanged; the room note stays. |
| 7 | Drag `Flows 101` by its handle onto **No Track**. | It moves there. |
| 8 | Tab to `Flows 101`'s handle, press Space, Left Arrow, Space. | A screen reader announces each step; it moves one column left. |
| 9 | Edit `Keynote`: Status **Cancelled**. | The clash notes go away. |
| 10 | **New Session** `Lightning Talks` with no Start or End. In **When** choose **Unscheduled**. | Only `Lightning Talks` shows. |
| 11 | Delete the `Admins` track and confirm. | Its sessions stay, under **No Track**. |
| 12 | As read-only, open **Agenda**. | No drag handles, no **New Track** or **New Session**. |

**Cleanup:** None.

## T-EV-06: Speakers

**Purpose:** confirm adding speakers from Core people, assignments, the one-per-person rules and
removal.
**Prerequisites:** staff, an event with two sessions at the same time, `Opening` and `Flows 101`
(neither cancelled), and a person `Ana Garcia`.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the event, click **Speakers**. | An empty state and **Add Speaker**. |
| 2 | In **Add Speaker** pick `Ana Garcia`. | A row `Ana Garcia`, status **Invited**; her name opens the person. |
| 3 | Pick `Ana Garcia` again. | Refused: Ana Garcia is already a speaker at this event. |
| 4 | Row menu **Edit**: Headline `Architect`, Status **Confirmed**, AV Needs `Projector`. Save. | The row shows `Architect` and **Confirmed**. |
| 5 | Row menu **Add to Session**: `Opening`, role **Speaker**, **Save**. | `Opening (Speaker)` under Sessions. |
| 6 | **Add to Session** `Opening` again, role **Moderator**. | Refused: this speaker is already in this session. |
| 7 | **Add to Session** `Flows 101`, **Panelist**. Open **Agenda**. | Both sessions show a red note: a speaker is also in the other at the same time. |
| 8 | On **Speakers**, click the **x** beside `Flows 101`. | Only `Opening (Speaker)` remains. |
| 9 | Row menu **Remove**, confirm. | The row is gone; `Ana Garcia` is still in BarnCRM. |
| 10 | As read-only, open **Speakers**. | The list shows; no **Add Speaker**. |

**Cleanup:** None.

## T-EV-07: Call for Speakers

**Purpose:** confirm adding applications, scoring, accept and decline with notices, and the
Events settings.
**Prerequisites:** staff, an event, two people with emails (`Ana Garcia`, `Sam Lee`) and one with
none (`Kim Wu`), and one active email template with the developer name `Speaker_Declined`. The
shipped templates `BarnCRM_Speaker_Accepted` and `BarnCRM_Speaker_Declined` are the defaults.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the event, click **Applications**. | An empty state and **Add Application**. |
| 2 | **Add Application**: Proposal Title `Scaling Flows`, Applicant `Ana Garcia`. Save. Add `Old Topics` for `Sam Lee` and `Quiet Talk` for `Kim Wu`. | Three rows, status **Submitted**. |
| 3 | Menu **Score** on `Scaling Flows`, 5, Save. | Status **In Review**; average `5.0 (1)`. |
| 4 | Score `Scaling Flows` again with 3. | Still one review; average `3.0 (1)`. |
| 5 | Menu **Score** on `Old Topics`, 1. | `Scaling Flows` is listed first. |
| 6 | Open **BarnCRM Settings**, **Events**. | **Accepted Notice Template** shows `BarnCRM_Speaker_Accepted` and **Declined Notice Template** shows `BarnCRM_Speaker_Declined`, neither blank. |
| 7 | **Accept** `Scaling Flows`, confirm. | Status **Accepted**, and the notice was emailed from the shipped accepted template. |
| 8 | In Settings, enter `Speaker_Declined` as the declined template. **Decline** `Old Topics`, confirm. | Declined, and the notice was emailed from your template. No speaker is made for Sam Lee. |
| 9 | Open **Speakers**. | `Ana Garcia`, **Invited**, and no one else. |
| 10 | **Decline** `Quiet Talk`. | Declined; a warning that the applicant has no email address. |
| 11 | Open a declined row's menu. | Only **Edit**: no Score, Accept or Decline. |
| 12 | As read-only, open **Applications**. | The list shows; no **Add Application**, no Score, Accept or Decline. |

**Cleanup:** Delete the applications and Ana Garcia as a speaker.

## T-EV-08: Sponsorship

**Purpose:** confirm levels, adding sponsors with the level's amount and checklist, deliverable
statuses, the totals and the one-per-organization rule.
**Prerequisites:** staff, an event, and organizations `Acme Software` and `Beta Org`.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the event, click **Sponsors**. | Empty states for levels and sponsors; **Add Level**. |
| 2 | **Add Level**: Level Name `Gold`, Amount `5000`, Deliverables `Logo for the program`, `Booth`, `Passes` on three lines. Save. | A `Gold` row with amount 5,000. |
| 3 | Choose level `Gold`, pick `Acme Software` in **Add Sponsor**. | A sponsor row, **Prospect**, amount 5,000, `0/3` deliverables; the checklist lists a Logo, a Booth and a Passes item. |
| 4 | Pick `Acme Software` again. | Refused: Acme Software is already a sponsor of this event. |
| 5 | Set the Logo item to **Done**. | The row shows `1/3`. |
| 6 | Menu **Add Deliverable**: `Banner at the entrance`, Other, **Save**. | `1/4`; the new item is listed. |
| 7 | Menu **Edit**: Status **Committed**. Save. | The line above the table reads Committed and confirmed: 5,000. |
| 8 | Choose **No Level**, pick `Beta Org`. Edit it: Status **Confirmed**, Amount `1500`. | A second sponsor with no level; the total reads 6,500. |
| 9 | Menu **Edit** on `Acme Software`: paste into **Linked Record** the identifier of any Giving gift (only if Giving is installed). | With Giving: its name shows under the sponsor. Without Giving, or an identifier of anything else: no name and no error. |
| 10 | On the level `Gold` menu, **Remove**, confirm. | The level is gone; `Acme Software` stays with no level and its checklist. |
| 11 | Menu **Remove** on `Beta Org`, confirm. | The sponsor and its checklist are gone; the organization is still in BarnCRM. |
| 12 | As read-only, open **Sponsors**. | The lists show; no Add Level, no Add Sponsor, and the menus offer only Remove for staff (hidden or refused). |

**Cleanup:** Delete the sponsors and levels.

## T-EV-09: Registrations and the Waitlist

**Purpose:** confirm hand registration matches Core people without duplicates, puts guests in the
household, applies codes, waitlists when full and changes attendance.
**Prerequisites:** staff; an event with Capacity `2`, an active ticket type `General` priced `40`
and a promo code `HALF` (Percent, 50, Maximum Uses 1); a person `Jane Doe`, email
`jane@example.org`, in a household.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the event, click **Registrations**. | An empty state and **New Registration**. |
| 2 | **New Registration**: type First Name `Jane`, Last Name `Doe`, Email `JANE@example.org`; Promo Code `half`; **Register**. | Registered 1. A row `Jane Doe`, **General**, price 20, **Registered**. No new person: People still has one Jane Doe. |
| 3 | **New Registration**: pick `Jane Doe` in **Existing Person**, **Register**. | Refused: nobody new to register, Jane Doe already registered. |
| 4 | **New Registration**: type `Sam` `Lee`; **Add Guest** `Max` `Lee`; Promo Code `HALF`; **Register**. | Refused: the code has been used as many times as it allows. Nothing saved. |
| 5 | Clear the code, **Register**. | Registered 1, waitlisted 1: Sam holds the last seat, Max is **Waitlisted**. Max is a new person in Sam's household. |
| 6 | Max's menu **Move Off Waitlist**. | Refused: no seat is free. |
| 7 | Jane's menu **Cancel Registration**, confirm. Then Max's menu **Move Off Waitlist**. | Jane is **Cancelled**; Max is **Registered**. |
| 8 | Sam's menu **Mark Attended**; Max's menu **Mark No-Show**. | The badges show **Attended** and **No-Show**; the summary counts 1 attended. |
| 9 | As read-only, open **Registrations**. | The list shows; no **New Registration** and no menus. |
| 10 | As a user with no Events set, open the **Event Registrations** list in a report. | No registrations are visible. |

**Cleanup:** None.

## T-EV-10: Reminders, Follow-Ups and No-Shows

**Purpose:** confirm the morning run emails reminders and follow-ups once each and marks no-shows,
and does nothing while the settings are off.
**Prerequisites:** admin; Event Management on; the nightly run scheduled; an Open event starting
tomorrow with Jane (a real inbox you can read) **Registered**; a second event that ended yesterday
with Sam **Attended** (with an email) and Max **Registered**.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Events**. | Six settings: the three switches Off, lead days 2, the two shipped template names. |
| 2 | Leave them off; in **Nightly Jobs**, run the step **Event reminders, follow-ups and no-shows** now (or wait for 7:30 AM). | Nothing is emailed; no attendee changes. |
| 3 | Turn **Send event reminders**, **Send follow-ups** and **Mark no-shows** on; run the step again. | Jane gets the reminder naming the event; her **Reminder Sent On** is set. Sam gets the follow-up; **Follow-Up Sent On** is set. Max is **No-Show**. |
| 4 | Run the step again. | No second email to Jane or Sam. |
| 5 | Set **Reminder email template** to `No_Such_Template`; clear Jane's **Reminder Sent On**; run again. | No email; the **Error Log** has a Warning naming `No_Such_Template`; Jane's stamp stays blank. |
| 6 | Type `0` in **Days before an event to remind**. | Refused: the value must be from 1 to 30. |

**Cleanup:** Set the template back to `BarnCRM_Event_Reminder` and turn the three settings off.

## T-EV-11: Summit Events Import

**Purpose:** confirm Summit Events registrants land in BarnCRM people without duplicates, and that
nothing shows without Summit.
**Prerequisites:** admin. Part A: an org without Summit Events. Part B: an org with Summit Events,
a Summit event instance next week with two registrations: Jane Doe (`jane@example.org`, already a
BarnCRM person, Summit contact blank) Registered, and a new person Started.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Part A: open **Nightly Jobs**. | No **Summit Events import** step. |
| 2 | Part B: open **Nightly Jobs**; run **Summit Events import** now (or wait for 7:15 AM). | One event named after the instance, External Key `summit:` and its ID. One registration, source **Summit Events**, Jane **Registered**. |
| 3 | Search People for Jane Doe. | One Jane Doe: no duplicate. The new person from the Started registration is not created. |
| 4 | Open Jane's Summit registration. | Its contact is Jane. |
| 5 | Run the step again. | No second event or registration. |

**Cleanup:** None.

## T-EV-12: Event Dashboard and Conference Template

**Purpose:** confirm the dashboard counts and that the template is opt-in, previewed first and
applied once.
**Prerequisites:** staff and a new event `Test Dreamin` that starts in 60 days and ends two days
later, with no ticket types, tracks or sessions.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the event; look at the top of **Details**. | **Event Dashboard** with about 60 days to go, four counts of 0 and three setup steps **To Do**. **Event Templates** is offered. |
| 2 | Open **Agenda** and **Tickets**. | Both empty: no template was applied by itself. |
| 3 | On **Details** choose **Community Conference**. | A summary (3 tracks, 4 ticket types, 13 sessions) and the **Planning Timeline** with dates; nothing is added yet. |
| 4 | Click **Apply Template**. | A success message; the counts show 3 tracks, 4 ticket types and 13 sessions, and **Event Templates** is gone. |
| 5 | Open **Agenda**. | Three track columns plus No Track; sessions are drafts on days 1 and 2. |
| 6 | Make an event with the same dates but ending one day after it starts; choose the template. | The summary says some sessions fall outside the event's dates and are left out. |
| 7 | As read-only, open the event. | The dashboard shows; no **Event Templates**. |

**Cleanup:** delete the test events.

## T-EV-13: Appointments

**Purpose:** confirm adding slots for a host, booking, the no-double-booking rule and status
changes.
**Prerequisites:** staff, an event that starts tomorrow at 08:00 and ends at 18:00, and people
`Priya Rao` (host), `Sam Lee` (a second host) and `Omar Hill`.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the event, click **Appointments**. | An empty state and the **Add Slots for a Host** form. **Add Slots** is disabled. |
| 2 | Pick `Priya Rao` as **Host**, set **Day** to the event's day, **From** 09:00, **To** 10:00, **Minutes per Slot** 20, **Location** `Table 4`. | The line says it adds 3 slots of 20 minutes; **Add Slots** is enabled. |
| 3 | Click **Add Slots**. | A group `Priya Rao` with 3 **Open** slots at 9:00, 9:20 and 9:40; the heading says 3 open, 0 booked. |
| 4 | Add the same window for Priya again. | The line says 3 slots overlap and are left out; **Add Slots** stays disabled. |
| 5 | Set **To** to 18:30 (past the event's end). | A warning that some slots fall outside the event's dates. Set it back to 10:00. |
| 6 | Row menu of the 9:00 slot, **Book a Person**, pick `Omar Hill`. | The slot is **Booked** with Omar Hill; the heading says 2 open, 1 booked. |
| 7 | Add a 9:00 to 9:20 slot for `Sam Lee`. Book `Omar Hill` into it. | Refused: that person is already booked at the same time with another host. |
| 8 | Row menu of Omar's slot: **Mark No-Show**, then **Release the Slot**. | **No-Show**, then **Open** with no person. |
| 9 | Row menu of an open slot: **Cancel Slot**, then **Reopen Slot**. | **Cancelled**, then **Open**. |
| 10 | Row menu **Edit** on a slot: set End before Start. | Refused: End must be after Start. |
| 11 | As read-only, open **Appointments**. | The slots show; no **Add Slots** form and no **Book a Person**. |

**Cleanup:** delete the test event.

## T-EV-14: Event Volunteers

**Purpose:** confirm event volunteer jobs and shifts are kept in Volunteers through Core, and that
the section is absent without Volunteers.
**Prerequisites:** Core, Event Management and Volunteers deployed; a coordinator who holds both
the Events Staff and Volunteers Coordinator permission sets; an event that starts in 30 days from
08:00 to 18:00.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the event; look under the **Event Dashboard** on **Details**. | A **Volunteers** section with an empty state and **Add Job**, disabled. |
| 2 | Type `Registration Desk` in **New Job Name**; click **Add Job**. | A job `Registration Desk` with no shifts. |
| 3 | Click **Add Shift** on it. | A form with **Starts** at the event's start, **Ends** an hour later, **Volunteers Needed** 2. |
| 4 | Set **Volunteers Needed** to 0. | **Save** is disabled and the form says to ask for at least 1. |
| 5 | Set it to 3; set **Starts** to the evening before the event. | A note that the shift is outside the event's dates; **Save** is enabled. |
| 6 | Click **Save**. | A shift appears with `0 of 3 signed up`. |
| 7 | Click the job's name. | The Volunteer Job opens in Volunteers with **Event ID** set; its Shifts list shows the shift. |
| 8 | In Volunteers, sign a volunteer up for that shift; reload the event. | The shift shows `1 of 3 signed up`. |
| 9 | As someone with Events Staff only, open the event and add a job. | Refused with a message that the Volunteers permission may be needed; nothing is saved. |
| 10 | In an org with Event Management but not Volunteers, open an event. | No **Volunteers** section anywhere on the page. |

**Cleanup:** delete the test job in Volunteers.

## T-EV-15: Check-In and QR Codes

**Purpose:** confirm staff check people in by search, by typed or scanned code and as walk-ins,
and that QR codes are drawn in the browser.
**Prerequisites:** staff; an event with Capacity `2`, an active ticket type `General`, and two
registered attendees `Jane Doe` (email `jane@example.org`) and `Sam Lee`; a second event with one
attendee. A phone or laptop camera and Chrome or Edge for step 6.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the event, click **Check-In**. | Two rows and the line `0 of 2 checked in, 2 still to come.` |
| 2 | Type `jane` in **Search**. | Only Jane Doe shows. Clear it. |
| 3 | Click **Check In** on Jane. | A toast; Jane is **Attended**, her button reads **Undo Check-In**, the line reads `1 of 2`. On **Registrations** Jane is **Attended**. |
| 4 | Click **Undo Check-In** on Jane. | Jane is **Registered** again. |
| 5 | Click the QR button beside Sam. | A QR code appears under the title `QR code for Sam Lee`. Browser network tools show no request to any outside host. **Close** hides it. |
| 6 | Click **Scan with Camera** and show Sam's QR code from another screen. | Sam is checked in and the camera stops. In a browser with no scan support the button is absent and a note explains. |
| 7 | Copy a QR code's ID of an attendee of the second event into **Ticket code**, click **Check In by Code**. | Refused: no attendee on this event matches that code. Nobody changes. |
| 8 | Type Sam's code and press Enter (no click). | A message that Sam is already checked in, as with **Check In by Code**. |
| 9 | **Add Walk-In**: Last Name `Door`, **Add and Check In**. | A new row `Door`, **Attended**, though the event is at capacity. Registrations shows source **Staff**. |
| 10 | As read-only, open **Check-In**. | The list and QR buttons show; no **Check In** buttons, **Add Walk-In** or code box. |

**Cleanup:** None.

## T-EV-16: Sample Data

**Purpose:** confirm the Event Management sample data loads for the sample people and takes
away only itself.
**Prerequisites:** admin; Core's sample data not yet loaded; one event of your own with a
registration.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | **BarnCRM Settings**, **Load Sample Data**, wait for it to finish. | The Sample Data card shows an **Events** count of `2`. |
| 2 | Open **Events**. | **Harvest Community Conference** (in progress) and **Neighborhood Garden Night** (in 14 days) beside your own event. |
| 3 | Open the conference, **Check-In**. | Four attendees are **Attended**, three still **Registered**. |
| 4 | **Agenda**, **Speakers**, **Applications**, **Sponsors**. | Eight sessions in three tracks, three speakers, one In Review application `Small Teams, Big Data` with two scores (average `4.5`), three sponsors at three levels with deliverables. |
| 5 | **Tickets**. | General, Student and Volunteer, and the code `EARLYBIRD`. |
| 6 | **Remove Sample Data**. | Both sample events and every registration under them are gone; your own event and its registration stay. |

**Cleanup:** None.

## T-EV-17: Gala Tables and Seating

**Purpose:** confirm staff add tables, seat parties together, are warned about over-capacity,
record needs and export the chart.
**Prerequisites:** staff; an event with an active ticket type `General`; a registration for
`Pat Rivera` with one guest (two attendees), a registration for `Sam Lee` alone, an organization
sponsor `Acme` added on the Sponsors tab.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the event, click **Seating**. | No tables; three guests listed, the line `0 of 3 guests are seated; 3 have no table.` |
| 2 | **Add Table**: name `Table 1`, seats `2`, **Save Table**. Add `Table 2` with `4` seats, and `Acme Table` with `4` seats and sponsor `Acme`. | Three cards, each `0 of N seats`; Acme Table shows `Sponsor: Acme`. |
| 3 | Choose `Table 1` for Pat Rivera. | Pat and the guest both sit at Table 1; `2 of 2 seats`. |
| 4 | Choose `Table 1` for Sam Lee. | A warning toast; the Table 1 card turns yellow and shows `1 more than the seats at Table 1.` Nothing is refused. |
| 5 | Choose **No Table** for Sam Lee. | Sam is unseated; the warning clears. |
| 6 | Clear **Keep Party Together**, choose `Table 2` for Pat. | Only Pat moves; the guest stays at Table 1. |
| 7 | Type `Vegetarian` in Sam's **Dietary Needs**, click elsewhere. | Saved; reload and it is still there; it shows beside Sam on the chart once seated. |
| 8 | Click **Suggest Seating**. | Sam is seated at the first table with room; no one is placed at Acme Table. |
| 9 | Click **Export Seating Chart**. | A CSV downloads with a header row, one row per guest, `Vegetarian` in Sam's row, and the table, host and sponsor columns filled. Opening it in a spreadsheet shows no formula. |
| 10 | **Remove** Table 2. | The card goes; its guests remain in the list with **No Table**. |
| 11 | As read-only, open **Seating**. | The chart and export show; no **Add Table**, **Suggest Seating**, **Edit** or **Remove**, and the **Table** menus cannot save. |

**Cleanup:** None.

## T-EV-18: Badges and Sign-In Sheets

**Purpose:** confirm badges and sign-in sheets print from the browser with the chosen parts, and
that nothing leaves the browser.
**Prerequisites:** staff; an event with two ticket types (`VIP`, `General`), an attendee
`Ann Lee` of organization `Acme` on `VIP` and `Bo Kim` on `General`, a session `Keynote`;
pop-ups allowed for Salesforce.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the event, click **Badges**. | The line `2 of 2 people will print.` |
| 2 | Choose **Ticket Type** `VIP`. | The line reads `1 of 2`. Reset to **All Tickets**. |
| 3 | Leave **Badge Size** Standard, switch **Show QR Code** on, click **Print Badges**. | A new window opens with two 4 x 2 in badges (name, `Acme`, ticket, QR code) and the print dialog. Network tools show no request to an outside host. |
| 4 | Choose **Large** and switch **Show Organization** and **Show Ticket Type** off; print. | Badges are 4 x 3 in with the name (and QR code) only. |
| 5 | Scan a printed QR code on the Check-In tab (or copy the code into **Ticket code**). | That person is checked in. |
| 6 | Choose **Whole Event** under **Sheet For**, click **Print Sign-In Sheet**. | A table of both people with a Signature column and ten blank lines; heading shows the event name, date and venue. |
| 7 | Choose `Keynote`, print again. | The heading names the session, its time and room. |
| 8 | Rename an attendee to `<b>Zed</b>` and reprint. | The badge shows the text `<b>Zed</b>`, not bold type. |
| 9 | Block pop-ups and click **Print Badges**. | A warning toast says the browser blocked the window. |
| 10 | As read-only, open **Badges**. | Printing works. |

**Cleanup:** Rename the attendee back.

## T-EV-19: Post-Event Survey

**Purpose:** confirm an event's survey form goes to attendees in the follow-up and the answers
are summarized on the event; and that nothing shows without Forms.
**Prerequisites:** admin; Event Management and Forms on; a Salesforce Site active with
`Forms_Public_Guest` assigned to its guest user; a published public form `After the Event` with a
number question `rating` and a text question `comment`; an event that ended yesterday with Sam
(a real inbox you can read) **Attended**; follow-ups on.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the event, **Details**, find **Post-Event Survey**. | A **Survey Form** list with **No Survey** and `After the Event`; **Save** disabled. |
| 2 | Choose `After the Event`, click **Save**. | **Survey Results** appears with `0 responses` and no answers yet. |
| 3 | Run the step **Event reminders, follow-ups and no-shows** in **Nightly Jobs**. | Sam gets the survey email with a link; his **Survey Link** is filled in. |
| 4 | Open the link in a private window, answer `rating` 4 and `comment` and send. | The form's confirmation shows. After the form processing job runs (up to 15 minutes), a **Survey Response** exists for Sam. |
| 5 | Reload the event's **Details** tab. | `1 responses`, the rate against links sent, an average of 4 for `rating`, Sam's comment under his name. |
| 6 | Open the link again and answer `rating` 5. | After processing, still one response; the average is 5. |
| 7 | Choose **No Survey**, **Save**; clear Sam's **Follow-Up Sent On** and run the step. | Sam gets the plain follow-up, no link. |
| 8 | In an org without Forms, open an event. | No **Post-Event Survey** section. |

**Cleanup:** Delete the response, clear the survey form and turn follow-ups off.

## T-EV-20: Event Calendar

**Purpose:** confirm the calendar shows events and sessions in a month, week and list, filters
them, opens their records and downloads a calendar file made in the browser.
**Prerequisites:** staff; an Open in-person event `Spring Gala` this month with a session
`Opening Keynote`, a Cancelled virtual event `Donor Webinar` this month, and a Draft event next
month.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Event Calendar** tab. | The current month in **Month** view with `Spring Gala` and `Donor Webinar` on their days (the webinar struck through); today marked. |
| 2 | Click the next arrow, then **Today**. | The Draft event shows next month; **Today** returns to this month. |
| 3 | Choose **Cancelled** in **Status**. | Only `Donor Webinar` shows. Choose **All Statuses**. |
| 4 | Choose **Virtual** in **Format**, then **All Formats**. | Only the webinar shows, then both. |
| 5 | Turn on **Show Sessions**. | `Opening Keynote (Session)` appears on the gala day. Turn it off and it goes. |
| 6 | Choose **Week**. | The seven days around today with their entries; the arrows move a week. |
| 7 | Choose **List**. | The month as days with entries, each with when, status, format and place; the keynote shows `Part of Spring Gala` with Show Sessions on. |
| 8 | Click the download button on `Spring Gala`. | A file `spring-gala.ics` downloads. Browser network tools show no request to any outside host. Opening it in a calendar app shows the gala with its start, end and venue. |
| 9 | Click an entry name. | The record opens. |
| 10 | As read-only, open the tab. | The calendar and downloads work; nothing can be changed from it. |

**Cleanup:** None.

## T-EV-21: Public Event Page and Registration

**Purpose:** confirm an event's public page shows only what staff published, takes registrations
through the public form intake, and that Events still works without Forms.
**Prerequisites:** admin; BarnCRM Forms installed with an active Site set up for public forms
(see the Forms testing guide); a published public form with questions `first`, `last`, `email`
and a `ticketType` choice listing `General` and `Student`, and public processing scheduled. An
Open event with Capacity `2`, an Online Link, tickets `General` (price `25`) and `Student` (price
`0`), one inactive ticket `Old`, a Confirmed session `Keynote` and a Draft session `Secret Talk`,
a Confirmed speaker and an Invited one, and the form's record ID in **Registration Form Key**.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | In a private browser window, open `<site address>/FormsPublic?record=<event ID>`. | `This page isn't available right now.`: Public Page is off. |
| 2 | Tick **Public Page** on the event; reload. | The event's name, dates, venue and description; **Tickets** lists General with `$25.00` and `Pay at the door or by arrangement with us.`, and Student with **Free**; **Agenda** lists Keynote only. No Old ticket, Secret Talk, speakers, seat counts or online link. The registration form shows under **Register**. The browser tab shows the event's name, not the form's (if the Site doesn't allow it, the tab shows `Form`: note it). |
| 3 | Tick **Show Speakers** and **Show Seats Left**; reload. | **Speakers** lists the Confirmed speaker only (name, headline, bio); Keynote reads `With` and their name; each ticket shows `Seats left: 2`. |
| 4 | In **BarnCRM Settings**, Events, change **Public page payment note** to `Pay by check at the door.`; reload. | General shows the new note. |
| 5 | Fill in the form as `Robin Zzpage`, ticket `General`, and send. | The form's confirmation shows. Within 15 minutes (or after **Process Again** on the Received submission), **Registrations** shows Robin with source **Form**, ticket General, amount owed 25. |
| 6 | Reload the page. | General shows `Seats left: 1`. |
| 7 | Open `<site address>/FormsPublic?list=events`. | **Upcoming Events** lists the event, linked to its page; the browser tab reads `Upcoming Events`. |
| 7a | Set Student's **Sales End** to yesterday. Fill in the form as `Lee Zzpage`, ticket `Student`, send and process. | The submission is **Needs Review**, its message ending `The ticket type Student is not on sale now, so a form cannot register people for it.`; Lee is not registered. Clear Sales End. |
| 8 | Open the event page in a second private window and leave it open. Set **Registration Closes** to yesterday; reload the first window. | `Registration for this event is closed.`; no form. |
| 9 | In the second window, fill in the form as `Kim Zzpage` and send; process it. | The submission is **Needs Review**, its message ending `Registration for this event is closed.`; Kim is not registered. Set the event to **Draft**: the page is unavailable and the list no longer shows it. |
| 10 | As the integration user (see Forms, Integrations and Portals), GET `/services/apexrest/barncrm/forms/v1/pages/<event ID>` with the event Open again. | The same page as JSON, with `formId`; no online link, codes or attendee data. |
| 11 | In an org with Event Management and no Forms, tick **Public Page** on an Open event and run **Health Check**. | Warning **Public Event Pages Need BarnCRM Forms**. Events, tickets and registrations work as before. |

**Cleanup:** delete Robin Zzpage's registration and contact and the Kim and Lee Zzpage contacts; untick
**Public Page**.

## T-EV-22: Paid Registration

**Purpose:** confirm a paid public registration waits for payment with its seats held, is
confirmed when the processor reports the payment, and is cancelled when the checkout is abandoned
or refunded; and that nothing changes with the setting off.
**Prerequisites:** the T-EV-21 setup (event, General ticket at `25`, public form, Site); BarnCRM
Payments installed in **test mode** with Stripe test keys entered, its receiver address added in
the Stripe dashboard and processing scheduled (see the Payments testing guide); a test email
address you can read.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | With **Take payment online** off, register `Pat Zzpay` (General) through the public page and process it. | Registered at once, amount owed 25, **Payment Status** empty; no email. |
| 2 | In **BarnCRM Settings**, Events, turn on **Take payment online**. Reload the public page. | General's note says a secure payment link is emailed after registering. |
| 3 | Register `Sam Zzpay` (General, your test email) and process it. | Sam's registration is **Pending Payment**, Payment Status **Unpaid**, and Sam holds a seat (seats left goes down). Within two minutes Payment Status is **Link Sent**, **Payment Link** holds a `checkout.stripe.com` address and the email `Complete your registration for <event>` arrives with it. |
| 4 | Open the link and pay with Stripe's test card `4242 4242 4242 4242`. | Within 15 minutes the registration is **Registered**, Payment Status **Paid** and **Amount Paid** 25. |
| 5 | In the Stripe dashboard, refund 10 of Sam's payment. | Within 15 minutes Payment Status **Partly Refunded**, Amount Paid 15; the registration stays Registered. Refund the rest: Payment Status **Refunded**, Amount Paid 0 and the registration **Cancelled**. |
| 6 | Register `Ash Zzpay` (General) and process it; do not pay. Ask an admin to set the payment's created date back three days in a scratch org, or wait two days, then let processing run. | Ash's payment is Cancelled; the registration is **Cancelled**, Payment Status **Cancelled**, and the seat is free again. |
| 7 | On **Registrations**, open the menu of Pat's registration (made with the setting off) and choose **Send Payment Link**. | `The payment link was emailed to the registrant.`; Payment Status **Link Sent**; the registration stays **Registered**. |
| 8 | Open the menu of a free registration, then of Sam's paid one. | Neither menu offers **Send Payment Link**. |
| 9 | Uninstall or disable Payments in a scratch org with the setting on and run **Health Check**. | Warning **Event Payments Are Not Ready**; form registrations are confirmed at once as in step 1. |

**Cleanup:** delete the Zzpay registrations and contacts; turn **Take payment online** off.

## T-EV-23: Session Proposals and Matrix Scoring

**Purpose:** confirm presenters, reviewer assignments, weighted criteria, blind review, the
scoring matrix and compare on the Applications tab.
**Prerequisites:** admin and staff; an Open event with three proposals `Alpha`, `Beta` and
`Gamma` from three people; a second user with Events Staff.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, choose **Scoring Criteria**, add `Relevance` weight `3` and `Delivery` weight `1`, and save. | Saved; the criteria show in that order. A weight of `11` or a label used twice is refused. |
| 2 | Open Alpha's menu, **Add Presenter**, pick a person, role Moderator. | The presenter shows under Alpha. Adding the applicant, or a sixth presenter, is refused. |
| 3 | Tick Alpha and Beta, choose **Assign Reviewers**, pick the staff user and click **Assign to Selected**. | The message starts `2 assignments added.`; doing it again adds 0. |
| 4 | As the staff user, tick **My Assignments**. | Alpha and Beta only. |
| 5 | Score Alpha: Relevance `5`, Delivery `1`. | Weighted score `4.00`, score 4. Alpha leaves My Assignments; Reviews 1. |
| 6 | As admin, score Alpha Relevance `3`, Delivery `3`, and Beta Relevance `4`, Delivery `4`. | Alpha's weighted average `3.50` (two reviews); Beta `4.00`; Beta ranks first. |
| 7 | Choose **Scoring Matrix**. | One row per proposal: Relevance and Delivery averages (Alpha 4.0 and 2.0), weighted average, total, reviews. |
| 8 | Tick Alpha and Beta and choose **Compare**. | Side by side: applicant, weighted average, each criterion's average and abstract. With only one, or five, ticked, Compare asks for two to four. |
| 9 | Tick **Blind Review** on the event's Details tab; reopen Applications. | Applicant, presenter and reviewer names show as `Hidden for blind review` on Alpha, Beta and Gamma. |
| 10 | Accept Alpha. | Alpha's names show again; the applicant and the presenter are speakers at the event. |

**Cleanup:** delete the proposals, speakers and criteria; untick Blind Review.

## T-EV-24: Badge Overrides

**Purpose:** confirm badge name, title and company print and show at check-in.
**Prerequisites:** staff; an event with a Registered attendee `Jordan Zzbadge` whose account is
`River Org`.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Registrations**, Jordan's menu, **Edit Badge**: name `Jo`, title `Chair`, company `Lake Org`; save. | Saved. |
| 2 | On **Badges**, **Print Badges** with Show Organization on. | Jordan's badge reads `Jo`, `Chair` and `Lake Org`. |
| 3 | Print the sign-in sheet. | Jordan's row reads `Jo` and `Lake Org`. |
| 4 | On **Check-In**, search `Jo`. | Jordan shows as `Jo` with `Jordan Zzbadge` beside it. |
| 5 | Clear the three fields and print again. | `Jordan Zzbadge` and `River Org`; no title line. |

**Cleanup:** delete Jordan's registration.

## T-EV-25: Session Ratings

**Purpose:** confirm a session's QR code opens the rating form and ratings average on the session
and speaker.
**Prerequisites:** admin; BarnCRM Forms with an active Site; a published public form with a
`rating` number question and a `comment` text question; an event with Confirmed sessions `Talk A`
and `Talk B` and a speaker on Talk A.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Agenda** tab, **Session Ratings**, choose the form and save. | Saved. |
| 2 | **Print Rating Codes**. | A print window with Talk A and Talk B, each with title, time, room and a QR code. |
| 3 | Scan Talk A's code with a phone (or open its link in a private window), rate `5` with a comment, send; rate again `3`. Process the submissions. | Talk A's card shows `Rated 4.0 (2)`. Two Session Ratings on Talk A with no person. |
| 4 | Open the **Speakers** tab. | Talk A's speaker shows `Average rating 4.0 from 2`. |
| 5 | Send the form from Talk B's link with no rating; process it. | No rating is added to Talk B. |
| 6 | In an org without Forms, open the Agenda tab. | No Session Ratings button and no rating codes. |

**Cleanup:** delete the ratings and clear the event's rating form.

## T-EV-26: Venues and Rooms

**Purpose:** confirm a venue and room fill the event and session (EV-24).
**Prerequisites:** staff; an event with blank Venue Name and Venue Address and a session with no
room or capacity.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Venues** tab. | List views All Venues and My Venues. |
| 2 | New venue `Zz Hall`, address `1 Main St`, map link `https://example.org/map`; add room `Room A`, capacity 40, setup Theater, where `Second floor`. | Saved; Room A in the venue's Rooms list. |
| 3 | On the event, pick Venue `Zz Hall` and save. | Venue Name `Zz Hall`, Venue Address `1 Main St`. |
| 4 | Change the event's Venue Name to `Main Hall` and save again. | It stays `Main Hall`: only blanks fill. |
| 5 | On **Agenda**, the session's **Edit**: pick Room Record `Room A`, save. | Room `Room A`, Capacity 40. |
| 6 | Give a second session the same room and an overlapping time. | Both cards flag the room clash, as for a typed room. |

**Cleanup:** delete the venue (its room goes with it); clear the event's venue fields.

## T-EV-27: Session and Speaker Details

**Purpose:** confirm session level, links and sponsor, and the speaker checklist (EV-25).
**Prerequisites:** staff; an event with a session, a speaker and a sponsor; another event's sponsor.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Session **Edit**: Level Beginner, Session Type Lightning Talk, slides and recording links, Sponsored By the event's sponsor. | Saved. |
| 2 | Try Sponsored By the other event's sponsor. | Not offered or refused: a sponsor of the same event only. |
| 3 | Speaker **Edit**: headshot, LinkedIn and website links; Agreement Signed and Slides Received on. | Saved; the speaker's row shows `Checklist 2 of 3`. |

**Cleanup:** none.

## T-EV-28: Budget and Funding

**Purpose:** confirm the Budget panel's totals and Net Cost (EV-23).
**Prerequisites:** staff; an event with a registration whose Amount Paid is 100.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the event's **Details** tab. | A Budget panel under the dashboard, with Add Expense and Add Funding. |
| 2 | Add Expense `Hall` (Venue, Budgeted 1000, Actual 1200) and `Lunch` (Food and Beverage, Budgeted 500). | Venue 1,000 budgeted and 1,200 actual; Food and Beverage 500 and 0; totals 1,500 and 1,200. |
| 3 | Add Funding `Acme MDF` (Partner Funds (MDF), Expected 800, Received 300). | Funding 800 expected, 300 received. |
| 4 | Read the totals. | Net Cost 800 (1,200 less 300 less 100); Budgeted Net Cost 600 (1,500 less 800 less 100). The dashboard shows Net Cost 800. |
| 5 | As read-only, open the event. | The panel shows; no Add buttons and no row menus. |

**Cleanup:** remove the lines.

## T-EV-29: Sponsor Lead Export

**Purpose:** confirm staff download a sponsor's leads (EV-28).
**Prerequisites:** T-PB-13 done, so the sponsor has a Lead and a Not Shared scan.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | On **Sponsors**, the sponsor's menu, **Download Leads**. | A CSV with one row: name, email, title, company, interest, notes and scan time of the Lead; no Not Shared row. |
| 2 | Do the same for a sponsor with no leads. | A message that there are no leads to download; no file. |

**Cleanup:** none.
