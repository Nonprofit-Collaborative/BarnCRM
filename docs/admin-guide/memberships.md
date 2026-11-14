# Memberships

## What It Does

Memberships keeps your members: people, households and organizations who belong to your
organization for a term, at a level, with benefits. Each **membership** is one term (a year, say)
at one **level**, with a start and end date and a status. When a member renews, BarnCRM adds the
next term and marks the old one Renewed, so you keep each year's history and payment.

- **Levels** are what you sell: a type and tier (Individual, Family Gold, Corporate Partner), the
  dues, how many months a term lasts, and how many grace days a member keeps after it ends.
- **Benefits** are listed on each level (free admission, a newsletter, two guest passes).
- **Renewals** come from staff, from Giving gifts to the level's fund when Giving is installed,
  from a recurring gift that keeps a membership going, or from dues paid online through BarnCRM
  Payments.
- **Lapse handling** runs each morning: an ended membership goes to Grace, then Lapsed.
- **Reminders** can email members before their membership ends (off until you turn them on).
- **A member directory** on your website lists members who opt in, through Portal Builder.

Memberships does not use Opportunities and does not need Giving or Payments; it uses them when
they are installed.

## How to Turn It On

### Before You Install

- Memberships is offered in **both editions** (see [Editions](editions.md)).
- It needs BarnCRM Core only. Giving (renewals from gifts) and Payments (dues paid online) are
  optional.

### Installing

Install it from **Module Manager** (see [Module Manager](module-manager.md)). When the install
finishes, BarnCRM gives you, the person who installed it, the **Memberships Admin** permission
set. Like every module it is installed **off**: turn it on in Module Manager when you are ready.
Its tabs join the BarnCRM apps: **Memberships** for staff and **Membership Levels** for admins.

### Who Gets What

BarnCRM gives the Memberships permission sets from the roles on the **Access** page (see
[Access](access.md)), every hour and whenever a role is given. It never takes one away.

| Role | Permission set | What they can do |
|---|---|---|
| BarnCRM Admin | Memberships Admin | Set up levels and benefits, see and change every membership |
| Team Member, Fundraising Staff | Memberships Staff | Add, renew and update memberships; read levels and benefits |
| Read Only | Memberships Read Only | Read memberships, levels and benefits |

## Setting Up Levels

1. Open the **Membership Levels** tab and click **New**.
2. Fill in:
   - **Level Name**: what members see, such as Family Gold.
   - **Type** and **Tier**: optional, to group levels (Type Household, Tier 2, say). Tier 1 is
     the entry tier.
   - **Dues**: what one term costs.
   - **Term Months**: how long a term lasts (default 12). Enter **0** for a membership that does
     not expire, such as a lifetime membership.
   - **Grace Days**: how long a member stays in **Grace** after the end before **Lapsed**
     (default 30).
   - **Giving Fund ID**: only for renewals from gifts (see below). Leave blank otherwise.
   - **Active**: clear it to stop offering the level. Existing memberships keep it.
3. Save, then add the level's **Benefits** from its Benefits list: a name, details, a quantity
   when counted, and a sort order.

## Memberships and Their Status

| Status | Meaning |
|---|---|
| Pending | Made but not paid yet (waiting for an online payment) |
| Current | In its term |
| Grace | Ended, but still within the level's grace days |
| Lapsed | Ended and past the grace days |
| Renewed | Followed by a newer term |
| Cancelled | Ended early, or its online payment was refunded |

When a membership is saved, BarnCRM fills what is blank: the **Dues** from the level, a **Start
Date** of today for a Current membership, the **End Date** from the level's Term Months (less a
day), and **Member Since** from the term it renews. A membership names a contact, a household or
organization, or both (an organization member with its named contact).

**Origin** says whether a term is **New**, a **Renewal** (renewed while Current or in Grace, so
the new term starts the day after the old one ends) or a **Rejoin** (renewed after it lapsed, so
it starts on the renewal day). **Source** says how it was made: Staff, Gift, Recurring Gift,
Online Payment or Import.

## Renewing

### By Hand

On a membership, click **Renew** in the membership panel and choose the level (the same one by
default). BarnCRM adds the next term and marks this one Renewed.

### From Giving Gifts (When Giving Is Installed)

1. On each level that gifts should pay for, enter the **Giving Fund ID**: open the fund in Giving,
   copy the record ID from the address bar (the 18 characters after `/Fund__c/`) and paste it.
2. Leave **Renew memberships from gifts** on in **BarnCRM Settings**, **Memberships** (it ships
   on).

Each morning, BarnCRM looks at received gifts from the last 45 days allocated to a level's fund.
A gift from a donor (a contact, or a household or organization) that meets a level's dues pays a
term at the **highest** level on that fund whose dues it meets: a renewal of the donor's latest
membership, or a new membership starting on the gift date. A gift is used once. A gift that meets
no level's dues is left for you to handle by hand.

A gift that is part of a **recurring gift** counts the recurring gift's yearly amount, so a
monthly sustainer at 10 a month meets dues of 120. The membership remembers the recurring gift,
and while that recurring gift stays Active, the membership renews itself when its term ends
instead of lapsing.

### Online, Through BarnCRM Payments

With BarnCRM Payments installed and connected (see [Payments](payments.md)), a member can pay dues
online on Stripe's or PayPal's own page:

- **Staff:** on a membership, click **Email Payment Link**. BarnCRM asks the processor for a
  checkout page for the level's dues and emails its link to the membership's contact with the
  template **BarnCRM: membership payment link** (`BarnCRM_Membership_Payment_Link`, in the
  BarnCRM Memberships email folder; edit it to suit your voice, and keep the Payment Link merge
  field). The link also shows on the membership as **Payment Link**.
- **Members:** on the member portal (see below), **Pay Dues** on My Membership sends the same
  email.

The link works for a short time (Stripe about a day), so the email tells the member to ask for a
new one after that. After paying, the member returns to your Salesforce Site's home page (or
your org's own address when you have no Site).

When the processor reports the payment as paid (up to 15 minutes later), BarnCRM dates the
membership on the payment: a **Pending** membership becomes Current from the payment date, and
any other membership is renewed, the new term carrying the payment. A refunded payment cancels
the term it paid. A failed or abandoned checkout changes nothing.

To sign up a new member who pays online: add a membership with Status **Pending**, then click
**Email Payment Link**.

## Lapse Handling and Reminders

The **Memberships** step of the nightly run (6:55 AM in your org time zone, see
[Nightly Jobs](nightly-jobs.md)) does, in order: renewals from gifts, renewals from active
recurring gifts, then lapse handling (Current to Grace to Lapsed by the level's grace days), then
reminders. A membership with no end date never lapses. Each part handles up to 2,000 memberships
a morning; any more are handled the next morning. A reminder is only kept as sent once the email
goes out: if the org's daily email limit refuses the send, the reminders are tried again the next
morning.

Reminders are **off** when you install, because they email your members. To turn them on, go to
**BarnCRM Settings**, **Memberships**:

| Setting | Default | What it does |
|---|---|---|
| Send renewal reminders | Off | Emails each member once before their membership ends |
| Days before to remind | 30 | How many days before the end the reminder goes (1 to 365) |
| Renewal reminder template | BarnCRM_Membership_Renewal | The email template used; BarnCRM ships one for you to edit |
| Renew memberships from gifts | On | Gifts to a level's Giving fund pay memberships |

A reminder goes to the membership's contact when they have an email address and have not opted
out of email. A membership with no contact (a household with no named contact) gets no reminder;
name a contact on it to include it.

## The Member Directory (Portal Builder)

With Portal Builder installed (see [Portal Builder](portal-builder.md)), paste the **member**
template (`portal-client/templates/member.json`) into a portal's Template field. Members sign in
with their email address and see:

- **My Membership**: their memberships, level, status and dates, with **Pay Dues** when Payments is
  connected.
- **My Directory Listing**: whether they are listed, the location and the short bio they choose to
  show.
- **Member Directory**: every current member who chose to be listed, with only their name, level,
  location and bio, and a search box.

Nobody is listed unless they opt in. No email address, phone number or address of another member
is shown.

## Memberships Essentials

If your org runs the community's **Memberships Essentials** app, both can be installed together:
BarnCRM's objects have different names (Membership Term, Membership Level, Membership Benefit),
and BarnCRM adds no field to Contact or Account. To move to BarnCRM Memberships, use the
**Memberships Essentials** kit in the [Migration Assistant](migration-assistant.md): it copies your
Essentials membership products that have a tier as levels, then your Essentials memberships as
membership terms (their account, primary contact, dates and level), each with Source Import. A
membership that has not ended is Current, one that has ended is Lapsed. Dues are not copied
(Essentials keeps prices in price books): enter them on each level. Essentials itself is never
changed; retire it with the kit's checklist when you are ready.

## Certifications and Continuing Credits

Some organizations certify people (a trainer, a counselor, a docent) and ask them to keep learning
to stay certified. Memberships keeps both:

- a **Certification** is a credential you grant, with the **Credits Required** to renew it and
  how many **Valid Months** it lasts (default 24; **0** for one that never expires);
- a **Member Certification** is one person holding one certification: its status (Pending, Active,
  Expired or Revoked), when it was **Earned On** and when it **Expires On**;
- a **Continuing Credit** is credits the person earned toward renewing it: a course, a conference
  session, an event.

There is nothing to turn on. Admins set up certifications; staff record holders and credits.

### Setting Up a Certification

1. Open the **Certifications** tab and click **New**.
2. Give it a **Name**, the **Credits Required** to renew, and its **Valid Months**. Clear **Active**
   later to stop offering it; current holders keep it.

### Granting, Credits and Renewing

1. On the **Member Certifications** tab, click **New**: choose the **Certification** and the
   **Contact**. It starts **Pending**.
2. When they pass, open it and press **Grant** in the **Certification** panel. It becomes
   **Active**, Earned On is today and Expires On is set from Valid Months.
3. Add each **Continuing Credit** from its **Continuing Credits** list: the credits, the date,
   what earned them and the kind of activity. **Credits Toward Renewal** adds them up.
4. When Credits Toward Renewal reaches Credits Required, press **Renew**. The new period starts
   the day after the old Expires On (or today, if it had expired) and the credits are marked
   **Used**, so the next renewal starts from none. Renew is refused until there are enough
   credits.
5. **Revoke** ends a certification at once. **Grant** makes it Active again.

Each morning an Active certification past its Expires On becomes **Expired**, in the Memberships
step of the nightly run.

### Who Gets What With Certifications

| Permission set | Certifications | Member certifications and credits |
|---|---|---|
| Memberships Admin | Create, edit, delete | Create, edit, delete, see all |
| Memberships Staff | Read | Create, edit |
| Memberships Read Only | Read | Read |

## Sample Data

**BarnCRM Settings**, **Load Sample Data** (see [Sample Data](sample-data.md)) adds a small
example of Memberships after Core's people are loaded: five levels (Individual, Family,
Supporter, Business and Lifetime) with their benefits, and fourteen memberships for the sample
people, households and organizations. They show a renewal that points back to the term it
renewed, memberships due for renewal in 10 to 25 days, one in grace, two lapsed, one pending,
one cancelled, a lifetime membership with no end date, and three members listed in the
directory. The sample is not linked to Giving gifts. **Remove Sample Data** deletes only the
levels and memberships the loader created (they carry a Sample Data checkbox); your own levels
and memberships stay.

## Erasing a Person

When you erase a person (see [Erase a Person](erase-a-person.md)), their memberships stay (as gifts
do) but their directory listing and the membership notes are cleared and the listing is turned
off. Their certifications and credits stay too, with their notes and the credits' activity text
cleared.

## Troubleshooting

| Problem | What to check |
|---|---|
| A gift did not renew a membership | The level's Giving Fund ID, the gift is Received and allocated to that fund, the gift meets the level's dues, Renew memberships from gifts is on, the gift is from the last 45 days |
| Email Payment Link says Payments is not ready | Payments is installed, turned on and its keys are entered on Payments Setup |
| A paid membership is still Pending | Payments processing is scheduled (Health Check); payments are applied every 15 minutes |
| Renew on a certification is refused | Credits Toward Renewal is below Credits Required, the certification never expires (Valid Months 0), or it is Pending or Revoked (use Grant) |
| No reminder was sent | Reminders are on, the membership has a contact with an email address who has not opted out, and the reminder template exists and is active |
