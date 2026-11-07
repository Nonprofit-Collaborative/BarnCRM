# Contact Point Sync

## What It Does

Some Salesforce features and apps (consent tools, Nonprofit Cloud, marketing and commerce apps)
read a person's email addresses, phone numbers and addresses from Salesforce **Contact Points**
(the Contact Point Email, Contact Point Phone and Contact Point Address objects). BarnCRM keeps
them on the person (Personal, Work and Alternate email, Home, Mobile, Work and Other phone) and on
the person's addresses. The optional **BarnCRM Contact Point Sync** module copies them across and
keeps the copies up to date, so those apps see the same details BarnCRM does.

BarnCRM itself never reads Contact Points. Only install this module if your org uses them.

## Before You Install

- Offered in both editions (see [Editions](editions.md)). It needs BarnCRM Core only.
- Your org needs the three Contact Point objects and the **Individual** object. Salesforce turns
  the Individual object on in Setup, under **Data Protection and Privacy** ("Make data protection
  details available in records"). Without it the module installs but copies nothing, and its page
  says why.
- If your org stores people as person accounts, they are copied too, exactly like contacts.
  Person accounts are optional: without them nothing changes.

## How the Copy Works

- **BarnCRM is the source.** A change to a person's email, phone or address is copied to their
  Contact Points right after the save. Nothing flows back: if someone edits a copied Contact Point
  directly, BarnCRM puts its value back the next time that person is copied.
- **What is copied.**
  - Email: Personal, Work and Alternate email and the standard Email, one Contact Point per
    address. The one that matches the person's preferred email is marked primary.
  - Phone: Home, Mobile, Work and Other phone and the standard Phone, one per number. The one
    that matches the preferred phone is marked primary.
  - Address: every **Current** address that is the person's own or their household's. The
    primary address is marked default. Former and undeliverable addresses are not copied: their
    Contact Points are removed, and the history stays on the address.
- **Moving household.** When a person joins, leaves or moves to another household (or a
  household's address changes), their address copies are updated right away, in the same save
  (or in a background job straight after when the save has little room left), not at the
  person's next save.
- **Each copy hangs from the person's Individual.** A person with something to copy and no
  Individual gets one, named after them.
- **Contact Points BarnCRM did not make are left alone.** BarnCRM remembers which Contact Points
  it made. When it would make a copy that already exists on the person's Individual (same email,
  number or street), it takes that one over instead of adding a second.
- **Deleting, merging and restoring.** Deleting a person removes their copies. Merging people
  keeps the surviving person's copies right. Restoring a person from the Recycle Bin makes their
  copies again. Erasing a person removes their copies.
- **A save never fails because of the copy.** A Contact Point Salesforce refuses (for example
  because of a validation rule your org added) is listed in the [Error Log](error-log.md) and the
  person's save goes ahead.

## Settings

In **BarnCRM Settings**, **Contact Points** section:

| Setting | What it does | Default |
|---|---|---|
| Sync Emails | Copies email addresses. | On |
| Sync Phones | Copies phone numbers. | On |
| Sync Addresses | Copies current addresses. | On |

Turning a kind off stops copying it and leaves the copies already made as they are. **Open
Contact Point Sync** opens the module's page.

The four automations, **Contact Point Sync: People**, **Contact Point Sync: Addresses**,
**Contact Point Sync: Person Accounts** and **Contact Point Sync: Household Moves**, are on the
**Automation** page, where you can switch each off or pause all automation. With Household Moves
off, a moved person's addresses catch up at their next save or with the backfill.

## The Contact Point Sync Page

The page (BarnCRM Settings, **Contact Points**, **Open Contact Point Sync**) shows:

- **Whether each kind can be copied in this org**, and if not, why: the object is not in this org,
  the Individual object is turned off, or your own access to the object is restricted (copies are
  still made; you just cannot see them).
- **The preview count**: how many people the backfill will check, and how many Contact Points
  BarnCRM manages now.
- **Run Backfill**: copies every person's details now, 200 people at a time. Use it once after
  installing, and after turning a kind back on. It needs the Manage BarnCRM Settings permission.
- **Last backfill**: when it finished and how many Contact Points it created, updated, removed and
  could not save.

## Who Can Do What

- **Contact Point Sync Admin** (given to everyone holding BarnCRM Admin): opens the page, previews
  and starts the backfill.
- Everyone else needs nothing: the copy is made for them when they save a person.

## Troubleshooting

- **The page says a kind cannot be copied.** Follow what the page says, for example turn on the
  Individual object in Setup, then run the backfill.
- **Failed copies in the last backfill.** Open the Error Log, filter on Contact Point Sync, and
  fix what Salesforce refused (often a required field or validation rule on the Contact Point
  object). Then run the backfill again.
- **An app shows an old value.** Check the Automation page: if Contact Point Sync is switched off
  or automation is paused, changes are not copied. Run the backfill once it is back on.
