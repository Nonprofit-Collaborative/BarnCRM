# Event Management

## What It Does

The BarnCRM Event Management module runs your organization's events, from an evening talk or a
monthly class to a gala or a multi-day community conference. Each **event** has its dates, its
format (in person, virtual or hybrid), where it is held, its capacity and its registration
window. A repeating event, such as a class every month, is a **series**: **Repeat Event** adds
the next occurrences in one step, each its own event.

Event Management works on its own: it needs BarnCRM Core and nothing else, and it uses no
Campaign. BarnCRM never holds money: ticket prices are what you charge, paid outside BarnCRM, or,
with the optional **BarnCRM Payments** module and **Take payment online** turned on, paid on your
own Stripe or PayPal checkout page and recorded on the registration (see Paid Registration).

## How to Turn It On

### Before You Install

- Event Management is offered in both editions (see [Editions](editions.md)).
- It needs BarnCRM Core and nothing else. Nothing here needs Volunteers, Giving, Funders or
  Programs.

### Installing

Install the BarnCRM Event Management package after Core. The install:

- gives the installing administrator the **Events Admin** permission set, and
- gives each BarnCRM role its Event Management set: **Events Admin** to BarnCRM Admin holders,
  **Events Staff** to the Team Member and Fundraising Staff roles, and **Events Read
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

Event Management has its own app, **BarnCRM Events** (**Events Home**, **Event Calendar**,
**Events**, **Event Speakers**, **Venues**, **Reports** and **Error Log**), shown to everyone
with an Events permission set. The same tabs, without Reports and Error Log, are also in the
**BarnCRM** and **BarnCRM Console** apps, after **Data Manager** (see
[The BarnCRM Apps](barncrm-app.md#a-modules-pages-in-the-barncrm-apps)). A scratch or Developer
Edition org gets no BarnCRM Events app, only the tabs in the BarnCRM apps. An event opens on
its own record page from any app.

The **Events Home** tab lists the events still to come,
soonest first, with their dates, status, format and place; **Past** lists those that ended or
were cancelled, latest first. Each event's name opens it. **New Event** opens the new event form.

### Event Calendar

The **Event Calendar** tab, beside Events Home, shows events as a **Month**, a **Week** or a
**List**. The arrows move a step and **Today** comes back. **Status** and **Format** narrow what
is shown without reloading; **Show Sessions** adds each event's sessions (a session follows its
event's status and format filter) and is off until you turn it on, since a conference has many.
A multi-day event shows on every day it spans; a cancelled one is struck through. Click an entry
to open its record. In the **List** view each row has a download button that saves a calendar
file (`.ics`) for that event or session, to add to your own calendar. The file is made in your
browser: nothing is sent anywhere. Times are shown in your own time zone.

The calendar reads up to 500 events and 1,000 sessions for the days shown and says so when it
stopped; use the filters or the week view to narrow it. Everyone with an Events permission set
sees it, with the records their sets allow. It needs no setup.

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
| Sales Start, Sales End | When it is on sale; End after Start. Empty means the registration window. A registration form takes the ticket only between them (a form that names no ticket takes the first one on sale); staff on the Registrations tab can use it any time. |
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

**Session ratings.** People in the room can rate a session from 1 to 5 by scanning its QR code.
It needs BarnCRM Forms and its Salesforce Site (see [Forms](forms.md), Public Forms):

1. In Forms, build a short form with a question keyed `rating` (a number or choice from 1 to 5)
   and, if you like, one keyed `comment`. Publish it and turn on **Public**. It needs no question
   that finds a person: ratings are anonymous.
2. On the Agenda tab choose **Session Ratings**, pick the form and **Save**. It is stored in the
   event's **Session Rating Form Key**.
3. **Print Rating Codes** opens a page with each confirmed session's title, time, room and QR
   code, one per half page, to print and put by each door. Codes are drawn in the browser. An
   event gets codes for its first 200 confirmed sessions by start time; past that, the panel says
   so.

Each answered form adds a **Session Rating** (rating and comment, no person) to the session. A
session card shows its **Average Rating** and how many rated it; the Speakers tab shows each
speaker's average over the sessions they speak in. A form with no rating from 1 to 5 adds nothing.
Anyone with the code can rate, as often as they like, so treat the averages as a guide.

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

### Call for Speakers

The **Applications** tab is the call for speakers. Each **speaker application** is one proposal:
a title, the **Applicant** (a Core person), an abstract and, if the applicant named one, a track.
**Add Application** adds one; applications that come in another way (a form, later the speaker
portal) land in the same list. Proposals are listed with the best average score first.

| Application field | What it is |
|---|---|
| Proposal Title | The name of the proposed talk. |
| Applicant | The Core person who applied. Required when the application is added. |
| Status | Submitted (the default), In Review, Accepted, Declined or Withdrawn. |
| Reviews, Average Score | How many reviewers scored it and their average, worked out by BarnCRM. |
| Notice Sent, Notice Result | When the decision email went out, or why none did. |

A reviewer opens a proposal's menu and chooses **Score**: a score from 1 to 5 and an optional note.
Each reviewer has one score per proposal; scoring again replaces it. The first score moves a
Submitted proposal to In Review. Scores, with the reviewer's name and note, show under the
proposal.

**Accept** and **Decline** are in the menu of a proposal that is still Submitted or In Review.
Accept makes the applicant a speaker at the event (status **Invited**), or links the speaker they
already are; Decline makes none. A decided proposal cannot be scored or decided again from the tab;
change it with **Edit** if you need to.

**Notices.** Accepting or declining emails the applicant. BarnCRM ships two text email templates
in the folder **BarnCRM Events**, **BarnCRM: speaker proposal accepted** (`BarnCRM_Speaker_Accepted`)
and **BarnCRM: speaker proposal declined** (`BarnCRM_Speaker_Declined`), and they are the defaults.
Edit them in Setup, or write your own and open **BarnCRM Settings**, **Events**, and enter its
unique name. The applicant is the recipient and the application is the record the template
merges, so `{!Contact.FirstName}` and `{!Speaker_Application__c.Name}` work. A blank setting
reads as the shipped template. To send no email for an outcome, make its template inactive.
If a notice cannot go out, because the template is missing or inactive, the applicant has no email
address or the send failed, the decision is still saved and **Notice Result** on the application
says why.

**Presenters.** A session proposal can have up to 5 presenters besides the applicant: open a
proposal's menu and choose **Add Presenter**, pick the person and their role (Speaker, Moderator or
Panelist). The remove button beside a presenter takes them off. Accepting the proposal makes the applicant and every
presenter a speaker at the event.

**Assigning reviewers.** Select proposals with their checkboxes, choose **Assign Reviewers**, pick
a user and click **Assign to Selected**. They get the proposals to score; a reviewer already assigned or who has scored
is not added again. **My Assignments** narrows the list to what you still have to score. An
assignment that is not yet scored does not count in Reviews or the averages.

**Scoring criteria.** **Scoring Criteria** (Events Staff and Events Admin) sets up to 10 criteria
for the event, each with a label and a weight from 1 to 10, for example Relevance (weight 3),
Speaker Experience (weight 1). With criteria, **Score** asks for a score from 1 to 5 on each; the
review's **Weighted Score** is the scores averaged by their weights, and its Score is that rounded.
Without criteria a review is one score from 1 to 5, as before. Proposals are ranked by
**Weighted Average**. Changing the criteria later leaves earlier reviews as they were scored.

**Scoring Matrix and Compare.** **Scoring Matrix** shows every proposal with its average on each
criterion, its weighted average, total and number of reviews. Select two to four proposals and
choose **Compare** to see them side by side: applicant, weighted average, each criterion's average
and the abstract.

**Blind review.** Turn on **Blind Review** on the event (Details tab) to hide applicants',
presenters' and reviewers' names on the Applications tab until a proposal is accepted or declined.
It keeps reviews fair; it is not a security setting, since the records themselves stay readable to
people with Events access.

### Sponsorship

The **Sponsors** tab runs the event's sponsorship. **Add Level** makes a tier, such as Gold, with an
**Amount**, its **Benefits** and a **Deliverables** list: one deliverable per line, the checklist a
new sponsor at that level starts with. A line that starts with Logo, Booth or Passes gets that type;
any other line is type Other.

To add a sponsor, optionally choose a **Level**, then pick the organization in **Add Sponsor**. The
organization is a Core account. The sponsor starts as **Prospect**, with the level's amount and the
level's checklist; an organization can sponsor an event once. A sponsor's row menu has **Edit**
(level, status, amount, contact, notes and the linked record), **Add Deliverable** and **Remove**
(which removes its checklist). Each checklist item has its own status: Pending, Requested,
Received or Done; the **Deliverables** column shows how many are done. The line above the table
adds up the amounts of **Committed** and **Confirmed** sponsors.

| Sponsor status | Meaning |
|---|---|
| Prospect | Being asked; not counted in the total. |
| Committed | Agreed to give; counted. |
| Confirmed | The commitment is in hand; counted. |
| Declined | Said no; not counted. |

BarnCRM takes no payments: the amount is what the sponsor has agreed to give. To tie a sponsorship
to the money, paste the record identifier of the Giving gift or commitment, or the Funders award,
into **Linked Record** on the sponsor (**Edit**). When Giving or Funders is installed and you can
read that record, its name shows under the sponsor; otherwise nothing shows. Sponsorship needs
neither module. Removing a level leaves its sponsors with no level, keeping their amounts and
checklists.

### Registrations

The **Registrations** tab lists everyone registered for the event, newest booking first, with
their booking number, ticket, price and status, and a line counting who holds a seat, who waits
and who attended (with the seats left when the event has a capacity).

**New Registration** registers someone by hand. Pick them in **Existing Person**, or type their
first and last name, email and postal code: BarnCRM looks for them among your people (by email,
then last name and postal code, each with the first name, then your duplicate rules) and creates
them only when nobody matches, so registering never makes a duplicate. When two or more people
match, nothing is saved and you are asked to pick the person. **Add Guest** adds a row for each
person they bring; a guest is looked for in the registrant's household first and, when new, is
created in that household. Choose each person's ticket and type a promo code if they have one.

| Registration rule | What happens |
|---|---|
| Ticket | Must be one of the event's active ticket types. With none chosen, the first active one is used; an event with no ticket types registers people at no price. |
| Promo code | Must be this event's, active, inside its dates, for one of the chosen tickets and under its Maximum Uses (registrations that are not cancelled count). Its discount sets each attendee's price. |
| Seats | Registered, Attended and No-Show attendees hold a seat. With no seat left on the event's Capacity or the ticket's Quantity, a new attendee is **Waitlisted**. |
| Once per event | A person already registered (not cancelled) is left out and named in a message. |
| Amount Owed | The prices of the attendees holding a seat. Paid outside BarnCRM, or online with Paid Registration. |

Each attendee's menu changes their status: **Mark Attended**, **Mark No-Show**, **Mark
Registered**, **Move Off Waitlist** (only when a seat is free; nothing moves off the waitlist on
its own), **Cancel Attendee** and **Cancel Registration** (everyone on the booking). The
registration's status follows its attendees: Registered while anyone holds a seat, Waitlisted
while everyone waits, otherwise Cancelled.

Registrations hold personal data, so they are private: only people with an Events permission set
see them (Events Read Only reads them; Events Staff and Events Admin change them).

**With BarnCRM Forms.** Put a Forms form's record ID in the event's **Registration Form Key**.
Each submission of that form filled from the event registers the person Forms matched or created,
with source **Form**; a question with the key `ticketType` (a ticket type's name) and one with the
key `promoCode` choose the ticket and the code. A form registers people only while the event is
**Open**, after **Registration Opens**, before **Registration Closes** and before the event ends.
A submission that cannot be registered (outside those times, a ticket not on sale, a used-up
code, an unknown ticket)
is kept for review in Forms. Staff can still register anyone on the tab. Without Forms, register
people on the tab.

### Paid Registration

With the optional **BarnCRM Payments** module (see [Payments](payments.md)) set up with your own
Stripe or PayPal keys, an event can take payment for its tickets online. Turn on **Take payment
online** in the Events settings; it ships off.

- **From the public page.** A registration from the event's form that owes more than zero is
  saved as **Pending Payment** with **Payment Status** Unpaid. Its people are Registered, so their
  seats are held. Within a minute or two BarnCRM asks your processor for a secure checkout page,
  saves its address on the registration (**Payment Link**, Payment Status **Link Sent**) and emails
  it to the registrant with the **Payment link email template** (`BarnCRM_Event_Payment_Link`,
  in the BarnCRM Events folder; keep `{!Event_Registration__c.Payment_Link__c}` in a template of
  your own). Promo codes are already applied to the amount.
- **From the Registrations tab.** **Send Payment Link** in a registration's menu emails a new link
  for any registration that owes money and is not paid. A registration made by staff is not held
  for payment: it stays Registered and only records the payment.
- **From the portal.** A portal template can offer the action `Events.SendPaymentLink` on a
  person's own registrations; it emails their current link again (it makes no new one).

If a checkout cannot be started (for example the processor refused the keys), Payment Status
reads **Failed** and the **Error Log** says why; fix the cause and use **Send Payment Link**.

| Payment Status | What happened | The registration |
|---|---|---|
| Paid | The processor confirmed the payment (up to 15 minutes later). **Amount Paid** is set. | Pending Payment becomes Registered. |
| Failed | The card was declined. The payer can try again on the same page. | Still waits. |
| Cancelled | The checkout was abandoned (after two days) or expired. | A registration waiting for payment is cancelled and its seats freed. |
| Partly Refunded | Part of the payment was refunded in Stripe or PayPal. | Unchanged; Amount Paid is lowered. |
| Refunded | All of it was refunded. | Cancelled. |

BarnCRM issues no refunds and stores no card details: refund in your Stripe or PayPal dashboard
and the refund is recorded here. Cancelling a paid registration does not refund it. Payment Status,
Amount Paid, Payment Key and Payment Link are set only by BarnCRM. Health Check warns when **Take
payment online** is on and Payments is not installed or its keys are missing; until it is ready,
form registrations are confirmed at once as before.

### Public Event Page

An event can have a public page on your Salesforce Site, the same Site public forms use (see
[Forms](forms.md), Public Forms). Public pages need **BarnCRM Forms**: without it there is no
public page, the rest of Event Management works as before, and Health Check says so.

On the event's **Details** tab, in **Public Page**, choose what is published. Nothing is public
until you turn it on.

| Field | What it shows |
|---|---|
| Public Page | The page exists while the event is **Open** or **Closed** (never Draft, Completed or Cancelled): name, dates, format, venue, description, active tickets whose sales have not ended (price, description) and **Confirmed** sessions. |
| Show Speakers | Confirmed speakers' names, headlines and bios, and who speaks in each session. |
| Show Seats Left | Seats left for each ticket (the fewer of the event's Capacity and the ticket's Quantity), or that it is full and new registrations join the waitlist. |

Never shown: the online link (registrants get it from reminders), capacity itself, promo codes,
registrations, attendees, or speakers' email, travel and audiovisual needs.

**Addresses**, on your Site's address (for example `https://example.my.site.com`):

- one event: `<site address>/FormsPublic?record=<event record ID>`
- a list of Open public events that have not ended, soonest first (up to 50):
  `<site address>/FormsPublic?list=events`

**Registration.** While the event is **Open** and now is between **Registration Opens** and
**Registration Closes**, the page shows the form named in **Registration Form Key** (on the
Registration section of the Details tab). The form must be published and public in Forms;
otherwise the page says registration is not taken online. Answers get the public form checks
(hidden question, timing, hourly limit) and are processed by the scheduled public form processing
as for any public form, so people are matched, never duplicated, and seats, codes and the
waitlist apply exactly as on the Registrations tab.

**Paid tickets.** A ticket with a price shows the price and the **Public page payment note**
setting (default "Pay at the door or by arrangement with us."); a free ticket shows Free. The
registration records the amount owed. With **Take payment online** on and Payments ready, the
note says instead that a secure payment link is emailed after registering (see Paid Registration).

**Off-platform sites.** Portal Builder or any other site can show the same pages through the
Forms API as its integration user: `GET /services/apexrest/barncrm/forms/v1/pages/<event ID>`
and `GET /services/apexrest/barncrm/forms/v1/pages?kind=events`, then post the answers to the
form endpoint with the event's ID as `contextRecordId` (see Forms, Integrations and Portals). Give
that user **Events Staff** too, so its registrations are written at once; otherwise they wait for
the scheduled processing.

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

### Appointments

The **Appointments** tab holds bookable slots with a **host**, such as mentor or advisor time at a
conference. Each slot is an **Event Appointment** with a host (a Core person), a start and end, a
status, a location and an optional person booked into it.

| Field | What it is |
|---|---|
| Host | The Core person who hosts. Required for a new slot. |
| Person | Who is booked; empty while the slot is **Open**. |
| Start, End | When it runs: End after Start, inside the event's own dates. |
| Status | Open (the default), Booked, Completed, No-Show or Cancelled. |
| Location | A table, a room or a meeting link. |

**Add Slots** picks a host, a day, a time window and the minutes per slot, and adds the slots
back to back (up to 100 at a time); the line under the form says how many it will add. A slot that
overlaps one the host already has is left out. A row menu **Book a Person** puts a person in an
open slot; a person cannot be booked into two overlapping slots in one event. The menu also marks
a booked slot **Completed** or **No-Show**, **Release the Slot** (clears the person), **Cancel
Slot** and **Reopen Slot**, and has **Edit** and **Delete**. Two slots of one host that overlap
are flagged, never refused. Staff and admins book and change slots; Read Only sees them.

### Volunteers

When **BarnCRM Volunteers** is installed, the **Details** tab also shows a **Volunteers** section:
the event's volunteer jobs, each with its shifts and how many volunteers have signed up out of how
many are wanted. **New Job Name** with **Add Job** adds a job for this event; **Add Shift** on a
job opens a small form (**Starts**, **Ends**, **Volunteers Needed**, starting at the event's first
hour) and **Save** adds the shift. A shift outside the event's dates only warns, because setup the
day before and teardown the day after are ordinary.

The jobs and shifts are ordinary Volunteers records, so sign-up, reminders, nudges, hours and
totals work on them as on any other: open the job's name to manage it in Volunteers. Event
Management only needs Core; it reaches Volunteers through a Core extension point, remembers the
event on the job as its record ID in the **Event ID** field (text, not a link), and shows nothing
when Volunteers is not installed. Who may add jobs and shifts is decided by the Volunteers
permission sets (Coordinator, Staff, Admin), not the Events ones. Deleting an event leaves its
volunteer jobs in Volunteers, where their hours and history stay.

### Check-In

The **Check-In** tab is for the door. It lists everyone who holds a seat (Registered, Attended or
No-Show) with a count of who is in and who is still to come.

- **Search** by name, email or ticket; every word typed must match. A person with a **Badge
  Name** shows it, with their name beside it.
- **Check In** moves a person to Attended; **Undo Check-In** puts them back to Registered. This is
  the same status the Registrations menu sets, so the Registrations tab and the reports agree.
- **QR code.** The QR button beside a person draws their code in the browser, to show on a phone
  or print. The code holds only the attendee's record ID, so no extra field is stored. The
  drawing library (QR Code Generator for JavaScript, MIT license) ships inside the package as the
  static resource `BarnQrCode` and is listed in the repository's `NOTICE` file; no outside
  service is called.
- **Scan with Camera** appears where the browser can read QR codes (Chrome and Edge on Android
  and desktop; not Safari or Firefox at the time of writing). It reads a code, checks that person
  in and stops. Everywhere else, type or paste the code into **Ticket code** and click **Check In
  by Code**. A code from another event is refused.
- **Add Walk-In** registers a person who is not on the list (matched to Core people like any
  registration, source Staff) and checks them in at once. A walk-in is not held to the event's
  capacity or waitlist, since the person is already at the door. No promo code or guests.

Checking in needs the Events Staff or Events Admin permission set; Events Read Only can look and
show a QR code.

### Seating

The **Seating** tab lays out a gala or any seated event. It holds **tables** and a **guest list**
of everyone Registered or Attended.

- **Add Table** takes a name, the seats (at least 1), an optional **Host** (a Core person) and an
  optional **Sponsor** (a sponsor of this event from the Sponsors tab, for a table the sponsor
  bought). **Edit** and **Remove** change a table; removing one leaves its guests registered with
  no table.
- **Seating a guest.** Choose a table in the guest's **Table** column. A **party** is the people
  on one registration; they move together while **Keep Party Together** is on. A table may hold
  more people than its seats: the chart turns yellow and a warning shows, but nothing is refused.
- **Suggest Seating** places the guests with no table: whole parties, largest first, at the first
  table with room for the whole party. It never fills a sponsor table and tells you how many guests
  did not fit.
- **Dietary Needs** and **Access Needs** (255 characters each) are saved when you leave the
  field, and show beside the guest's name on the chart.
- **Export Seating Chart** downloads a CSV (table, host, sponsor, seats, guest, organization,
  ticket, dietary and access needs; guests with no table last) made in the browser.

Editing needs the Events Staff or Events Admin permission set; Events Read Only can look and
export. Needs are personal data: they are on the attendee, which only people with an Events
permission set can see.

### Badges and Sign-In Sheets

The **Badges** tab prints what the door needs. Pages open in a new browser window and print from
the browser, so nothing is sent to an outside service and no PDF is made; allow pop-ups for
Salesforce if the browser blocks the window.

- **Print Badges** prints a badge for each person Registered or Attended who matches the
  **Search** and **Ticket Type** filters. Choose **Badge Size**: Large (4 x 3 in), Standard
  (4 x 2 in) or Compact (3.4 x 2.3 in). Switch **Show Organization** (the person's account),
  **Show Ticket Type** and **Show QR Code** on or off. The QR code is the same code the Check-In
  tab reads, drawn in the browser by the `BarnQrCode` resource, so a scanned badge checks the
  person in.
- **Print Sign-In Sheet** prints a table of name, organization and ticket with a signature
  column and ten blank lines for people who were not registered. Choose **Whole Event** or one
  session; sessions have no attendance of their own, so a session sheet lists everyone
  registered for the event.

**Badge overrides.** An attendee's **Badge Name** (a preferred name), **Badge Title** (a job title
or pronouns) and **Badge Company** print instead of their name and account when set; the title
prints only when set. Set them from the attendee's menu on the Registrations tab (**Edit Badge**),
or on the attendee record. The sign-in sheet and Check-In use the same badge name and company.

In the browser's print dialog choose Letter paper and turn off headers and footers for the
cleanest badges. Events Read Only can print.

### Venues and Rooms

The **Venues** tab keeps each place you hold events once: its **Address**, **Capacity**, a **Map
Link** (a map or floor plan the attendee app shows) and **Notes**. A venue's **Rooms** list holds
its rooms, each with a **Capacity**, a **Setup** (Theater, Classroom, Banquet, Boardroom,
Reception, U-Shape, Other) and **Where** (floor or wing, shown to attendees). The tab has All
Venues and My Venues list views.

Pick a **Venue** on the event (its Details) and, when you save, a blank **Venue Name** and **Venue
Address** are filled from it. Pick a **Room Record** on a session (**Agenda** tab, the session's
**Edit**): saving copies the room's name into the session's **Room**, and its capacity into a
blank **Capacity**, so room clash flags, the public page and badges read the room as before. A
later change to a venue or room is not pushed to events already saved; edit those, or pick the
room again. Typing a room without a room record still works.

### Session and Speaker Details

Each session (**Agenda** tab, **Edit**) has a **Level** (All Levels, Beginner, Intermediate,
Advanced), a **Slides Link**, a **Recording Link** and **Sponsored By**, a sponsor of the same
event for a sponsored session. The session's format is its **Session Type**, which includes
Lightning Talk and Roundtable.

Each speaker (**Speakers** tab, **Edit**) has a **Headshot Link**, **LinkedIn** and **Website**,
and a checklist: **Agreement Signed**, **Slides Received** and **Dry Run Done**. The Speakers tab
shows how many of the three are done for each speaker. Speakers can keep their headshot and links
current themselves in the speaker portal (see [Portal Builder](portal-builder.md)).

### Budget and Funding

The **Budget** panel on the event's **Details** tab, under the dashboard, tracks the money:

- **Expenses** are the budget's lines. Each has an **Item**, a **Category** (Venue, Food and
  Beverage, Audio Visual, Speakers, Travel, Marketing, Printing, Staff, Technology, Other), a
  **Budgeted** amount, the **Actual** spent, a **Vendor**, a **Status** (Planned, Committed, Paid)
  and a **Due Date**. **Add Expense** adds one; a line's menu edits or removes it.
- **Funding** is money a sponsor or partner gives toward the event: its **Source**, a **Type**
  (Sponsorship, Partner Funds (MDF), Grant, In-Kind, Other), an optional **Partner Organization**
  and **Sponsor**, what is **Expected** and what is **Received**. **Add Funding** adds one.
- The panel shows budgeted against actual for each category, funding expected against received,
  and **Net Cost**: actual spend less funding received and the registrations' amount paid (shown
  as **Paid online**: it counts only payments taken through Paid Registration, not money you
  collected outside BarnCRM; record that as Funding). Below
  it, **Budgeted Net Cost** uses budgeted spend and expected funding. The event dashboard shows Net
  Cost too.

A sponsor's amount on the Sponsors tab is what they agreed to give; it is not counted until you
record the money as funding (Type Sponsorship, with the sponsor picked), so nothing is counted
twice. Events Read Only see the panel; Events Staff and Admin add and change lines.

### Announcements

Add news for attendees from the event's **Announcements** related list: a **Title**, the
**Message** and **Publish At** (now by default). The attendee app shows each announcement once its
time has come, newest first. Change Publish At to schedule one.

## Attendee App

The attendee app is a portal (see [Portal Builder](portal-builder.md)) that attendees save to their
phone's home screen from your WordPress site: no app store, nothing to pay. It needs Portal
Builder and its WordPress plugin. Paste `portal-client/templates/attendee.json` into a portal's
Template field and put the shortcode on a page with `app="yes"`:
`[barncrm_portal key="attendees" app="yes" name="Spring Summit"]`. People sign in with the email
they registered with; with an Any Matching Person portal every registrant can sign in at once.

What attendees see, always only for events they are registered for and not cancelled from. The
Agenda and Event Info pages leave out events that have ended, so past events do not crowd them;
the Attendees and Sponsors pages still read up to 200 of a person's events (newest first, and a
warning in the Error Log when that cap is reached). People scan QR codes (Scan buttons) only where
the browser can read one itself: Chrome and Edge on Android and desktop can; iPhone Safari and
Firefox cannot, and the person types the code instead.

| Page | What it does |
|---|---|
| My Events | Their attendee rows. Here they choose **Show Me in the Attendee List**, write a **Headline**, **About Me** and **How to Reach Me**, and choose **Share My Details With Sponsors**. All off or blank until they choose. |
| Agenda | The event's Confirmed sessions with time, room, track, type, level and description. **Add to My Agenda** picks one. |
| My Agenda | Their picks, **Add to Calendar** (an .ics file for their phone's calendar), **Remove from My Agenda**, and **My Rating** with a comment once a session has started. |
| Attendees | Attendees who chose to be listed: name, badge title and company, headline and about. Searchable. **Connect** asks to connect. |
| Connections | Requests and connections. **Accept** or **Decline** a request; once connected, each sees the other's How to Reach Me. A private **Note** and a **Message to Send** with **Send Message**. |
| Messages and Sent | Messages from connections, with **Reply**; and what they sent. |
| Announcements | Your announcements, once their time has come. |
| Sponsors | Confirmed sponsors with their level and booth. |
| Event Info | Dates, venue, the venue's map link and the online link. |
| My Details | Their name and phone. |

Rules that protect attendees:

- Nobody is listed until they turn on Show Me in the Attendee List, and the list never shows an
  email, phone or address. How to Reach Me is shown only to people they accepted.
- **Messages are off until you turn on Attendee messages** in Settings. Then a person can message
  only someone they are connected with, up to 50 messages a day. Messages are Salesforce records
  your event staff can read; say so in your event's code of conduct.
- **Personal agenda.** A person picks a session once. A session whose picks reach its **Capacity**
  is full. A session that overlaps one already picked is refused, unless you turn on **Allow
  overlapping picks**; then it is added and marked Overlaps. The session's **Agenda Picks** shows
  how many picked it.
- **Ratings stay anonymous.** A rating from My Agenda adds one Session Rating with no name, the
  same as the rating form's (see Session Ratings). It is sent once and cannot be changed.

### Sponsor Lead Scanning

Sponsors collect leads by scanning attendees' badge QR codes (the same code Check-In reads). Paste
`portal-client/templates/sponsor.json` into a portal (Invited works well: add a Portal Access for
each sponsor contact and booth staff member) and put its shortcode on a page, with `app="yes"` if
sponsors should install it.

- Who can scan: the sponsor's **Contact** on the Sponsors tab, and any attendee whose **Booth Staff
  For** names the sponsor (set it with **Edit Badge** on the Registrations tab).
- **Scan** reads the code with the phone's camera where the browser can (Chrome and Edge on
  Android, for example); elsewhere the person types the code printed under it, or uses the
  phone's camera app and pastes it.
- Each scan is saved as a Booth Scan on the sponsorship at the scanned attendee's event. Only an
  attendee who turned on **Share My Details With Sponsors** is **Shared**, with name, email,
  title and company. Otherwise the scan is **Not Shared** and keeps nothing about the person; an
  unknown code is **Not Found**; a second scan is **Already Scanned**.
- The rep adds notes and an interest (Hot, Warm, Cold) and can **Download CSV** of their leads.
  Staff use **Download Leads** in a sponsor's menu on the Sponsors tab: a CSV of that sponsor's
  Shared scans.

## Settings

As an admin, open the **Events** section of **BarnCRM Settings**. Each setting saves org-wide as
you change it.

| Setting | Default | What it does | Takes effect |
|---|---|---|---|
| Send event reminders | Off | Each person Registered for an Open or Closed event gets one reminder email before it. | At the next 7:30 AM run |
| Days before an event to remind | 2 | How many days before an event its reminders go out, from 1 to 30. | At the next 7:30 AM run |
| Reminder email template | BarnCRM_Event_Reminder | The unique name of the email template reminders use. | At the next 7:30 AM run |
| Send follow-ups | Off | Each person marked **Attended** gets one follow-up email after the event ends (within seven days). | At the next 7:30 AM run |
| Follow-up email template | BarnCRM_Event_Follow_Up | The unique name of the email template follow-ups use. | At the next 7:30 AM run |
| Survey email template | BarnCRM_Event_Survey | The unique name of the email template a follow-up uses for an event that has a survey (see Post-Event Survey). | At the next 7:30 AM run |
| Mark no-shows | Off | Once an event has ended (within seven days), attendees still **Registered** become **No-Show**. | At the next 7:30 AM run |
| Accepted speaker notice template | BarnCRM_Speaker_Accepted | The unique name of the email template sent when a speaker application is accepted (see Call for Speakers). A blank value reads as the shipped template. | At the next decision |
| Declined speaker notice template | BarnCRM_Speaker_Declined | The unique name of the email template sent when a speaker application is declined. A blank value reads as the shipped template; to send no email, make the template inactive. | At the next decision |
| Public page payment note | Pay at the door or by arrangement with us. | Shown beside each ticket with a price on a public event page while payment is not taken online. | At once |
| Take payment online | Off | A form registration that owes money waits for an online payment through BarnCRM Payments, with its seats held (see Paid Registration). Needs Payments with its keys entered. | At the next registration |
| Payment link email template | BarnCRM_Event_Payment_Link | The unique name of the email template that sends a registrant their payment link. | At the next link |
| Attendee messages | Off | Connected attendees can message each other in the attendee app (see Attendee App). | At once |
| Allow overlapping picks | Off | A person may add a session that overlaps one already on their agenda; it is marked Overlaps. | At the next pick |

## Reminders, Follow-Ups and No-Shows

A step of [BarnCRM Nightly Jobs](nightly-jobs.md) named **Event reminders, follow-ups and
no-shows** runs each morning at 7:30 AM while Event Management and at least one of the three
settings are on. It has no switch of its own; if Health Check shows the nightly run as not
scheduled, use its **Schedule all nightly jobs** fix once. All three settings ship off, because
turning them on emails real people. While **Take payment online** is on, the same morning run
also starts checkouts for any registration still Pending Payment and Unpaid, so one whose
checkout did not start at registration is picked up by the next morning.

**Templates.** Two text templates ship in the **BarnCRM Events** email folder:
`BarnCRM_Event_Reminder` and `BarnCRM_Event_Follow_Up`. Copy one in Setup, Classic Email
Templates, change the copy and type its unique name in the setting. The person is the template's
recipient (`{!Contact.FirstName}`) and the attendee its related record
(`{!Event_Attendee__c.Event_Name__c}`). A template name that matches no template sends nothing
and writes a Warning in the **Error Log**.

**One email each.** Each attendee is stamped (**Reminder Sent On** or **Follow-Up Sent On**)
before it is emailed and never emailed again for that step; a failed send clears the stamp so
the next morning tries again, and is listed in the **Error Log**. Clear the stamp to send it
again. People with no email or with Email Opt Out are skipped. The org's daily email limit
applies.

**No-Show.** A No-Show keeps its seat and its price on the registration; change it from the
attendee's menu when it is wrong.

## Post-Event Survey

An event can send the people who came a link to a short survey, with the answers kept against
each attendee and summarized on the event. It needs the BarnCRM **Forms** module: without Forms
the **Survey** section on the event's Details tab is not drawn, and follow-ups are the plain
thank-you.

1. In Forms, build the survey form and publish it, and turn on **Public** for it in its
   settings, so a person with no login can fill it in. Public forms need a Salesforce Site set up
   once (see the Forms guide). A survey form needs no question that finds or creates a person:
   the answers belong to the attendee whose link was used.
2. On the event's **Details** tab, in **Post-Event Survey**, choose the form in **Survey Form**
   and click **Save**. **No Survey** clears it. Only published public forms are listed.
3. Turn on **Send follow-ups** in the Events settings.

When the 7:30 AM run sends the follow-up to each person marked **Attended** (within seven days
after the event), the email is the **Survey email template** (`BarnCRM_Event_Survey`, in the
BarnCRM Events email folder) instead of the plain follow-up, and it carries that person's own
link as `{!Event_Attendee__c.Survey_Link__c}`; keep that merge field in a template of your own.
An event without a survey, or an org whose Site cannot be found, sends the plain follow-up.
The link opens the form on your Site tied to that attendee, so each answer is stored with the
attendee and event. Answering again replaces the earlier answers.

**Results.** The same section shows how many answered and the response rate (of those sent a
link), then one block per question in the form's order: numbers show the average, lowest and
highest; picklists and checkboxes show counts and percentages; other answers list the newest
twenty with the person's name. Every answer is also a **Survey Response** record you can report
on (attendee, submitted on, answers as JSON).

Answers are kept for as long as the attendee exists. Anyone holding the link can answer for
that attendee, so do not ask for anything sensitive.

## Summit Events

When the Summit Events package is installed, Event Management imports its registrations each
morning; without Summit nothing about it shows. A step of [BarnCRM Nightly Jobs](nightly-jobs.md)
named **Summit Events import** runs at 7:15 AM, before the reminders, and needs nothing set up.

| Summit | BarnCRM |
|---|---|
| Event instance | An event, named after the instance title (or the Summit event), Open or Completed by its dates, created the first time one of its registrations is imported. Its **External Key** is `summit:` and the instance's ID. |
| Registration | A registration with source **Summit Events** and one attendee, Registered, Attended or No-Show as in Summit. Its **External Key** is `summit:` and the registration's ID. |
| Registrant | A Core person, found by Summit's contact or by BarnCRM's matching (email, then name and postal code, then your duplicate rules), created only when nobody matches. The person found is written back to the Summit registration's contact when it was blank. |

The first import takes every Summit registration; later ones take those changed in the last two
days. Started and Cancelled registrations are left out. A registration is imported once: later
changes in Summit are not copied, so change the attendee in BarnCRM. Registrations that cannot be
imported (for example two people match) are counted in a Warning in the **Error Log** and tried
again while they stay recently changed. Summit's own handling of people outside its contact field
is left alone.

## Not Yet

Ticket emails with the QR code for an event come in a later release. Push notifications to the
attendee app are not offered: announcements show when the app is opened.
