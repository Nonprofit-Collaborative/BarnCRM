# Portals

A portal is a page on your organization's website where a person on file in BarnCRM (a
volunteer, a member, a client) signs in and sees or updates their own information. Your
BarnCRM admin sets portals up (see [Portal Builder](../admin-guide/portal-builder.md) in the Admin
Guide). This page is for staff who look after the people using them.

## Who Can Sign In

1. Open the **BarnCRM Admin** (or **BarnCRM Admin Console**) app and the **Portals** tab, then
   the portal.
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
