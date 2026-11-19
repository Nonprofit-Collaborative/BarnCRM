# Portals

A portal is a page on your organization's website where a person on file in BarnCRM (a
volunteer, a member, a client) signs in and sees or updates their own information. Your
BarnCRM admin sets portals up (see [Portal Builder](../admin-guide/portal-builder.md) in the Admin
Guide). This page is for staff who look after the people using them.

## Who Can Sign In

1. Open the **BarnCRM Portal Builder** app (or **BarnCRM Admin**, or **BarnCRM Admin Console**)
   and the **Portals** tab, then the portal.
2. A portal set to **Invited** lets in only the people with a **Portal Access** record for it.
   To invite someone, open the **Portal Accesses** tab, select **New**, and pick the portal and
   the person. Their email address in BarnCRM is the one they sign in with.
3. A portal set to **Any Matching Person** lets in anyone whose email matches exactly one person
   in BarnCRM; their Portal Access is added the first time they sign in.

## What the Person Sees

- They enter their email on the portal page. If they may sign in, BarnCRM emails them a six-digit
  code that works for a few minutes. The page says the same thing whether or not the email is on
  file, so nobody can use it to find out who is.
- If the portal asks for a second factor, they also enter a code from an authenticator app (set up
  the first time they sign in).
- They then see the portal's pages: their own details, and the records of theirs the portal shows
  (for example their current roles), with only the fields the portal allows them to change.

## The Ready-Made Portals

Your admin may use one of the ready-made portals (see [Portal Builder](../admin-guide/portal-builder.md)).
Whatever the portal, a person sees and changes only their own records.

- **Volunteer portal.** Volunteers see open shifts and sign up or cancel, see their own shifts,
  view and log hours, and update their contact, availability and emergency contact. Hours they log
  arrive Submitted, or Approved if your organization does not require approval, and appear on
  **Approve Hours** like any entry. A person cannot edit hours after saving: change them from
  Salesforce. A cancelled sign-up shows on the shift's Sign-ups panel as Cancelled.
- **Speaker portal.** Speakers choose an open event and start a proposal, which appears on the
  event's **Applications** tab as Submitted with a title like "New proposal for" the event until
  they write their own title and abstract. They can edit it and withdraw it until it is decided,
  see every proposal's decision, see their sessions, and update their speaker details. Their
  sessions appear as soon as you assign them, with the session's time and room.
- **Donor portal.** Donors see their giving totals, pledge balance, gifts, pledges and issued
  receipts, and can change their phone and mailing address. They cannot give, edit gifts or
  download receipts through it; BarnCRM takes no payments.
- **Applicant portal.** Applicants choose an open cycle and apply, which starts a Draft
  application on the cycle; they complete it through its form link, and it becomes Submitted when
  the form arrives. They can withdraw it until it is decided, accept an offered award, and open
  report forms for the reports and conditions they owe.
- **Attendee app.** Attendees of your events see the agenda and build their own, add it to their
  phone's calendar, rate sessions, see announcements, sponsors and the venue map, and, if they
  choose to be listed, find and connect with each other. Picks show on each session's **Agenda
  Picks**; ratings arrive anonymous like any session rating. Messages work only if your admin
  turned them on, and only between people who accepted each other.
- **Sponsor portal.** Sponsor contacts and booth staff scan attendees' badges. Only attendees who
  chose to share their details become leads; download a sponsor's leads from the event's
  **Sponsors** tab. The Scan button reads a code with the camera in Chrome and Edge; iPhone
  Safari and Firefox cannot, so type the code there.
- **Service portal.** People in your programs see their enrollments, services, upcoming sessions,
  goals and referrals, and update their phone and address. They never see case notes.
- **Partner portal.** Staff of partner organizations see the referrals you shared with their
  organization, and, where your organization uses Grants, the grants they are the contact for and
  the reports you submitted.

## When Someone Cannot Sign In

On their **Portal Access** record:

- **Locked Until** has a time: too many wrong codes. Clear it to let them try again now.
- **Status** is Suspended: set it back to Active if they should have access.
- They lost their authenticator: clear **Second Factor Enrolled**; they set it up again next
  time.
- No email arrives: check their email in BarnCRM, and that two people do not share it (a shared
  email gets no code).

## Ending Someone's Sessions

To sign a person out everywhere, set their **Portal Access** **Status** to Suspended (and back to
Active later if they should return). To end one session, open it from their Portal Access and set
**Stage** to Ended.
