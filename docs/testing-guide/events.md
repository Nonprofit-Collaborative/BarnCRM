# Event Management

Scripts for events and the Events page (EV-01). Setup detail:
[Event Management](../admin-guide/events.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Event
Management deployed. Event Management works on the platform-only shape. Give the testers their
roles on the **Access** page: admin (Admin role), staff (Program Staff role) and read-only (Read
Only role). Each gets its Events permission set from the role.

## T-EV-01: Create an Event and Find It

**Purpose:** confirm an event saves with its rules and shows on the Events page.
**Prerequisites:** staff.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **BarnCRM Events** app. | It opens on **Events Home**, then **Events**, **Reports** and **Error Log** last. The page says nothing is coming up and offers **New Event**. |
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

## T-EV-07: Event Dashboard and Conference Template

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

## T-EV-08: Appointments

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

## T-EV-09: Event Volunteers

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
