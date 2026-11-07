# Event Management

## What It Does

The BarnCRM Event Management module runs your organization's events, from an evening talk or a
monthly class to a gala or a multi-day community conference. Each **event** has its dates, its
format (in person, virtual or hybrid), where it is held, its capacity and its registration
window. A repeating event, such as a class every month, is a **series**: **Repeat Event** adds
the next occurrences in one step, each its own event.

Event Management works on its own: it needs BarnCRM Core and nothing else, and it uses no
Campaign. BarnCRM takes no payments: ticket prices are what you charge, and payments go through
your own processor.

## How to Turn It On

### Before You Install

- Event Management is offered in both editions (see [Editions](editions.md)).
- It needs BarnCRM Core and nothing else. Nothing here needs Volunteers, Giving, Funders or
  Programs.

### Installing

Install the BarnCRM Event Management package after Core. The install:

- gives the installing administrator the **Events Admin** permission set, and
- gives each BarnCRM role its Event Management set: **Events Admin** to BarnCRM Admin holders,
  **Events Staff** to the Team Member, Coordinator and Fundraising Staff roles, and **Events Read
  Only** to the Read Only role. Someone given a role later gets the set within the hour, or at
  once when the role is given on the **Access** page.

A copy of the module deployed by hand (not installed) is finished from **Health Check** or the
**Module Manager** with **Finish Setup**, which runs the same steps.

### Roles

| Permission set | Can |
|---|---|
| Events Admin | Everything, including deleting an event (which deletes everything on it). |
| Events Staff | Create and change events and everything on them; never delete a whole event. |
| Events Read Only | Look at events and everything on them. |

Nothing is set up in Salesforce Setup.

## The Events Page

The **BarnCRM Events** app opens on the **Events Home** tab. It lists the events still to come,
soonest first, with their dates, status, format and place; **Past** lists those that ended or
were cancelled, latest first. Each event's name opens it. **New Event** opens the new event form.

### Repeat Event

From an event's row menu, **Repeat Event** asks how it repeats (**Every Week**, **Every Two
Weeks** or **Every Month**) and how many occurrences to add (1 to 52), and lists the new dates
before anything is saved. Each occurrence is a **Draft** copy of the event, as long as the event,
with its registration window moved by the same amount and its ticket types and tracks copied,
and its **Series** field names the first event of the series. A monthly event keeps its day of the month, or the last day of a shorter
month. After that each occurrence is changed on its own; nothing keeps them in step.

## The Event Page

An event's page has the event's highlights in the header, its tabs in the main column and its
related lists in the sidebar. The **Details** tab holds the event's fields:

| Field | What it is |
|---|---|
| Status | Draft while you plan it, Open once announced, Closed when registration ends, then Completed or Cancelled. |
| Format | In Person, Virtual or Hybrid. |
| Start, End | When it starts and ends. A multi-day event ends on a later day. End must be after Start. |
| Venue Name, Venue Address | Where it is held. |
| Online Link | Where to join a virtual or hybrid event. |
| Capacity | The most people it can take; empty for no limit. |
| Registration Opens, Registration Closes | When registration is taken; Closes must be after Opens. |
| Series | On a repeated occurrence, the first event of its series. |

### Tickets

The **Tickets** tab lists the event's **ticket types** and **promo codes**. **New Ticket Type**
and **New Promo Code** open a short form; each row's menu has **Edit** and **Delete**.

| Ticket type field | What it is |
|---|---|
| Ticket Type Name | What registrants see, such as General, Student or VIP. |
| Price | What you charge; 0 for a free ticket. Never below 0. BarnCRM takes no payment. |
| Quantity | How many may be sold; empty for no limit. At least 1 when set. |
| Sales Start, Sales End | When it is on sale; End after Start. Empty means the registration window. |
| Active | Offered to registrants. Clear it to stop offering a ticket without deleting it. |
| Sort Order | Its place in the list, lowest first. |

When the quantities of the active ticket types add up to more than the event's capacity, the tab
warns you. It refuses nothing, since not every ticket sells.

| Promo code field | What it is |
|---|---|
| Code | What a registrant types. One per event, whatever its case: `EARLY` and `early` are the same code. Spaces around it are trimmed. Another event may use the same code. |
| Discount Type, Discount Value | A percent off (above 0, at most 100) or an amount off (above 0). A discount never takes a price below 0. |
| Ticket Type | The one ticket type it applies to; empty for all of the event's tickets. |
| Maximum Uses | How many registrations may use it; empty for no limit. |
| Valid From, Valid Until | When it works; Until after From. |
| Active | The code can be used. |

Each code shows **Active**, **Inactive**, **Scheduled** (its dates have not started) or
**Expired**. The one-per-event rule is an automation that always runs (**Promo Code: one per
event** on the **Automation** tab); it cannot be switched off.

**Repeat Event** copies the event's ticket types to each occurrence, their sales dates moved
with it; promo codes are not copied.

### Agenda

The **Agenda** tab is the **Agenda Builder**: a column for each **track** (in Sort Order), then
**No Track**, each with its sessions by time. **When** shows one day, **Unscheduled** (sessions
with no time yet) or all of them. **New Track** and **New Session** open a short form; a track's
menu has **Edit** and **Delete**, and deleting a track keeps its sessions, with no track.

| Session field | What it is |
|---|---|
| Session Title | What the session is called. |
| Track | Its track, one of this event's; empty for none. |
| Start, End | When it runs: both or neither, End after Start, inside the event's own dates. |
| Room | Where it runs, as text. |
| Session Type | Talk, Workshop, Panel, Keynote, Break or Other. |
| Status | Draft, Confirmed or Cancelled. |
| Capacity | The most people it takes; empty for the room's own limit. |

A session moves to another track three ways, and only its track changes:

- its menu: **Move to** and the track;
- dragging the handle beside its title onto another column (on a touch screen, press and hold
  first);
- the keyboard: focus the handle, press Space, use the arrow keys, press Space to drop or Escape
  to cancel. A screen reader announces each step.

Two sessions in the same room at overlapping times, or with a speaker in common, are flagged in
red on both cards. Nothing is refused, and cancelled sessions are left out. **Repeat Event**
copies tracks but not sessions.

### Speakers

The **Speakers** tab lists the event's **speakers**, each a Core person, with their headline,
status and the sessions they are in. Picking a person in **Add Speaker** adds them at once, named
after the person; their row menu has **Edit**, **Add to Session** and **Remove**. Removing a
speaker takes them out of their sessions first; the person stays in BarnCRM. The **Event
Speakers** tab in the app lists every speaker at every event.

| Speaker field | What it is |
|---|---|
| Speaker Name | The name shown on the agenda; the person's name unless you change it. |
| Person | The Core person who speaks. One speaker per person per event. |
| Headline | A line under their name, such as their job and organization. |
| Status | Invited (the default), Confirmed, Declined or Cancelled. |
| Bio | A longer introduction. |
| Travel Needs, AV Needs | What they need to get there and to present. |

**Add to Session** puts a speaker in one of this event's sessions as a **Speaker**, **Moderator**
or **Panelist**; the same speaker is in a session once. A speaker in two sessions at the same
time is flagged on the **Agenda**, never refused. One speaker per person and one place per
session are automations that always run (**Event Speaker: one per person** and **Session
Speaker: once per session** on the **Automation** tab).

### Dashboard and Event Templates

The top of the **Details** tab is the **Event Dashboard**: days to go, counts of ticket types,
tracks, sessions and speakers (with how many speakers are confirmed), and the setup steps still to
do (ticket types, sessions, speakers). It reads this event only.

An event with no ticket types, tracks or sessions also shows **Event Templates**, to anyone who
may add those records. A template is a ready-made plan, shipped as JSON (the static resource
`BarnEventTemplates`). The **Community Conference** template is the "Dreamin" style event: an Admins,
a Developers and a Nonprofit track, a keynote, talks and workshops on two days, a lunch break each
day, four ticket types (Attendee, Student, Speaker, Sponsor) and a **Planning Timeline** (open the
call for speakers, sponsor outreach, recruiting volunteers, reminders, check-in), each step dated
back from the event's start.

Choosing a template only previews it. Nothing is added until you press **Apply Template**, and no
template is ever applied by itself. Sessions are placed from the event's start (day 1 is its first
day) as drafts; any that would fall outside the event's dates are left out and the preview says
how many. The apply is all or nothing, and an event that already has any ticket type, track or
session refuses it.

## Not Yet

Registration and attendees, session sign-up, a public event page, call for speakers, speaker portal, sponsorship, check-in,
reminders and volunteer shifts for an event come in later releases.
