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

## T-EV-07: Registrations and the Waitlist

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
