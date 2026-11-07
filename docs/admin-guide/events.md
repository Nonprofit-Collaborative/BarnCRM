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
with its registration window moved by the same amount, and its **Series** field names the first
event of the series. A monthly event keeps its day of the month, or the last day of a shorter
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

## Not Yet

Registration and attendees, a public event page, call for speakers, sponsorship, check-in,
reminders and volunteer shifts for an event come in later releases.
