# Events

The **BarnCRM Events** app is where you plan your organization's events. You need the Events
Staff or Events Admin permission set to create and change events; with Events Read Only you can
look at them.

## Find an Event

Open the **Events Home** tab. **Upcoming** lists the events still to come, soonest first;
**Past** lists those that ended or were cancelled. Click an event's name to open it. The
**Events** tab has list views of every event.

## Create an Event

1. On **Events Home**, click **New Event**.
2. Give it a name, a **Start** and an **End**. For a conference over several days, set the End on
   its last day.
3. Choose its **Format** (In Person, Virtual or Hybrid) and fill in the venue or the online link.
4. Leave **Status** at **Draft** while you plan it, and change it to **Open** when you announce it.
5. Save.

## Repeat an Event

For a class or meeting that happens again and again:

1. On **Events Home**, open the event's row menu and choose **Repeat Event**.
2. Choose **Every Week**, **Every Two Weeks** or **Every Month**, and how many occurrences to add.
3. Check the dates under **Preview**, then click **Repeat Event**.

Each new date is a draft copy of the event, with its ticket types and tracks. Change each one on its own;
open the first event to see them all under **Occurrences**.

## Set Up Tickets

1. Open the event and click the **Tickets** tab.
2. Click **New Ticket Type**. Give it a name, such as `General`, and a **Price** (0 for free).
   Set a **Quantity** to limit how many are sold, or leave it empty. Save.
3. For a discount, click **New Promo Code**. Type the code, choose **Percent** or **Amount** and
   the **Discount Value**. To limit it to one ticket, choose the **Ticket Type**. Save.

To change or remove a ticket or code, use its row menu. BarnCRM records prices only; payments
are taken outside BarnCRM.

## Build the Agenda

1. Open the event and click the **Agenda** tab.
2. Click **New Track** for each strand, such as `Admins` and `Developers`. Sessions for everyone,
   such as a keynote, can stay in **No Track**.
3. Click **New Session**. Give it a title, a track, a **Start** and **End** inside the event's
   dates, and a **Room**. Save.
4. To move a session to another track, choose **Move to** in its menu, or drag it by its handle.
   With a keyboard, focus the handle, press Space, use the arrow keys and press Space again.
5. A red note on a session means another session uses the same room, or the same speaker, at
   the same time. Change one of them, or leave it if that is what you meant.

Use **When** to look at one day at a time, or at the sessions with no time yet.

## Read the Event Dashboard

The top of an event's **Details** tab shows how many days are left, how many ticket types, tracks,
sessions and speakers the event has, and which setup steps are still to do. An event with nothing
set up yet also offers **Event Templates**: choose **Community Conference** to preview its tracks,
tickets, sessions and planning dates, then click **Apply Template** to add them as drafts you can
change. Nothing is added until you click it.

## Offer Appointments with Hosts

1. Open the event and click the **Appointments** tab.
2. Under **Add Slots for a Host**, pick the **Host**, the **Day**, the time window (**From** and
   **To**) and the **Minutes per Slot**. The line below says how many slots it will add.
3. Click **Add Slots**. The slots appear under the host, each **Open**.
4. To book someone, open the slot's menu, choose **Book a Person** and pick them. A person cannot
   be booked into two slots that overlap.
5. Afterwards use the menu to mark the slot **Completed** or **No-Show**, **Release the Slot** to
   free it, or **Cancel Slot**.

A red note means two of one host's slots overlap. Change one, or leave it if that is intended.

## Plan Volunteers

If your organization uses Volunteers, the **Details** tab of an event has a **Volunteers**
section. Type a job name, such as `Registration Desk`, and click **Add Job**. Then click **Add
Shift** on the job, set when it starts and ends and how many volunteers you need, and click
**Save**. Each shift shows how many have signed up. Open the job's name to manage sign-ups and
hours in Volunteers. You need the Volunteers permission to add jobs and shifts.

## Add Speakers

1. Open the event and click the **Speakers** tab.
2. In **Add Speaker**, pick the person. They are added at once, as **Invited**, under their own
   name.
3. From their row menu choose **Edit** to add a headline, a bio, travel and A/V needs, or to set
   their status to **Confirmed**.
4. Choose **Add to Session**, pick the session and their role (Speaker, Moderator or Panelist),
   and click **Save**. The **x** beside a session takes them out of it.
5. **Remove** takes a speaker off the event and out of their sessions; the person stays in
   BarnCRM.

## Manage Sponsors

1. Open the event and click the **Sponsors** tab. **Add Level** makes a tier (Gold, Silver) with
   its amount, benefits and a deliverables list, one per line.
2. Choose a **Level** in the list above **Add Sponsor**, then pick the sponsoring organization. It
   is added as **Prospect**, with the level's amount and checklist.
3. In the checklist under a sponsor, change each item's status (Pending, Requested, Received,
   Done) as the logo, booth and passes come together. **Add Deliverable** in the sponsor's menu
   adds another item.
4. From the sponsor's menu, **Edit** sets the status to **Committed** or **Confirmed**, the amount
   and the contact. The total above the table adds up Committed and Confirmed amounts.

## Review Speaker Applications

1. Open the event and click the **Applications** tab. **Add Application** adds a proposal: its
   title, the applicant and the abstract.
2. From a proposal's menu choose **Score**, pick 1 to 5, add a note if you like and click **Save**.
   You have one score per proposal; scoring again replaces yours. The list shows the best average
   first.
3. Choose **Accept** to make the applicant a speaker (as **Invited**) or **Decline**, and confirm.
   If your admin chose email templates, the applicant gets the notice. If not, or if they have no
   email address, a message tells you, and the application shows why.

## Register People

1. Open the event and click the **Registrations** tab, then **New Registration**.
2. Pick the person in **Existing Person**, or type their name, email and postal code. BarnCRM
   finds them among your people before creating anyone; if several people match, pick the right
   one instead.
3. Choose their ticket and type a promo code if they have one.
4. **Add Guest** for each person they bring. A guest already in their household is found there;
   a new guest joins it.
5. Click **Register**. Anyone already registered is left out and named. When the event or the
   ticket is full, people go on the waitlist.

From an attendee's menu, **Mark Attended** or **Mark No-Show** after the event, **Move Off
Waitlist** when a seat frees up, **Cancel Attendee** for one person or **Cancel Registration** for
the whole booking.

When your admin has turned them on, BarnCRM emails each registered person a reminder a few days
before the event and each person you marked **Attended** a follow-up after it, and marks anyone
still **Registered** as **No-Show** once the event is over. An attendee's **Reminder Sent On** and
**Follow-Up Sent On** show when each went; clear one to send it again.

If your organization uses Summit Events, its registrations appear here each morning with source
**Summit Events**; change an imported attendee in BarnCRM.

## Check People In

1. Open the event and click the **Check-In** tab. The line at the top shows how many are in.
2. Find the person: type part of their name, email or ticket in **Search**, then click **Check
   In**. **Undo Check-In** takes it back.
3. With a ticket's QR code: click **Scan with Camera** and hold the code to the camera (if you
   do not see the button, your browser cannot scan; type the code into **Ticket code** and click
   **Check In by Code** instead).
4. To give someone their QR code, click the QR button beside their name and show or print it.
5. Someone arrives who is not on the list: **Add Walk-In**, type their name (and email if you
   have it), choose a ticket and click **Add and Check In**. Walk-ins can take the event past its
   capacity.

## Seat Guests at Tables

1. Open the event and click the **Seating** tab.
2. Click **Add Table**, name it, give its seats, and choose a host or a sponsor if it has one.
3. In the guest list, choose a **Table** for each guest. People who registered together move
   together; clear **Keep Party Together** to seat one person alone. **Suggest Seating** seats
   everyone who has no table.
4. If a table holds more people than its seats, it turns yellow and a message says so. You can
   keep it or move someone.
5. Type any dietary or access needs in the guest's row.
6. Click **Export Seating Chart** to download a file for the caterer or venue.
