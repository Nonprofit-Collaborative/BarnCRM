# Custom metadata

## What it does

Some of the lists BarnCRM works from are kept as custom metadata, the part of Salesforce
that travels with the app. The **Custom metadata** page in BarnCRM Settings lets you add
your own entries to the lists that are meant to be extended, change them, and archive them,
without opening Salesforce Setup.

The first list is **Relationship types**: what the other side of a relationship becomes.
BarnCRM ships eleven types (Spouse, Parent and Child, and so on). If your organization
records godparents, mentors, or guardians, you add the pairs here and BarnCRM keeps both
sides in step for them the same way it does for its own.

Below it is **Match sources**: the related records the duplicate scan and imports look at
to tell that two people, or two households, are the same. Salesforce's duplicate rules only
compare fields on the person or account itself, so an email kept only on a contact point
email record, or an address kept only on a BarnCRM address, is never compared. Each source
names an object, the field holding the value, the field linking it to its person or
household, and how values are compared (Email, Phone or Address). See
[Duplicates](duplicates.md) for what the scan does with them.

The entries BarnCRM ships are shown on the same page, marked **Shipped with BarnCRM**,
and cannot be changed, except that a shipped match source can be archived and restored.
Upgrades keep them up to date, and they never overwrite what you added.

## How to turn it on

The page is for administrators who can already change the org in Setup, because saving an
entry changes the org's metadata.

1. Give yourself the **BarnCRM Metadata Admin** permission set (BarnCRM Settings, Access,
   Extra permissions). It is in no role on purpose: give it only to people who
   administer the org. Without it you do not see the page at all.
2. If BarnCRM was installed as a package, Salesforce asks once whether the app may change
   metadata. In Setup, open **Apex Settings** and turn on **Deploy Metadata from
   Non-Certified Package Versions via Apex**. This setting is in Setup only, and BarnCRM
   cannot turn it on for you: it is Salesforce's own safeguard. If it is off, saving an
   entry says so.
3. Open the **BarnCRM** app, click **BarnCRM Settings**, choose **General**, and scroll to
   **Custom metadata**.

A relationship type also has to be a choice in the **Type** list on a relationship, and
adding a choice to that list is done in Setup (Object Manager, Relationship, Fields, Type).
Add the choice there first, then add the type here. The page checks this and tells you if
the choice is missing. The **Reciprocal Type** field on a relationship needs nothing: BarnCRM
fills it in from your type, so it accepts any type you have added to **Type**.

## A five-minute walkthrough

Maria's organization runs a mentoring program and wants to record who mentors whom. Each
mentor's record should say who they mentor, and each mentee's record should say who mentors
them.

1. In Setup, open **Object Manager**, **Relationship**, **Fields & Relationships**,
   **Type**, and add two values: `Mentor` and `Mentee`. Save.
2. Open **BarnCRM Settings**, **General**, **Custom metadata**. Under **Relationship
   types** you see two tables. **Added by your organization** is empty. **Shipped with
   BarnCRM** lists the eleven types, with no actions on them.
3. Click **Add**. Fill in:
   - **Name**: Mentor
   - **Type**: Mentor
   - **Reciprocal Type**: Mentee
   - **Description**: Someone who mentors this person through the program.
   Click **Save**. The page says "Saving. Salesforce applies the change in the
   background, usually within a minute." When it is done it says "Saved. Mentor is in the
   list." and the row appears under **Added by your organization**, with the status
   **In use**.
4. Click **Add** again and add the other side: **Name** Mentee, **Type** Mentee,
   **Reciprocal Type** Mentor. Save and wait for "Saved".
5. Open a person, add a relationship of type **Mentor** to someone else, and save. Open
   the other person: their card reads **Mentee**. Before step 3 it would have read
   **Other**.
6. Back on the Custom metadata page, open the menu at the end of the Mentee row and choose
   **Archive**. Once it says "Saved", the row's status is **Archived** and BarnCRM stops
   using it: a new Mentee relationship gets **Other** on the other side. Choose
   **Restore** from the same menu to bring it back.
7. Scroll to **Recent changes** at the bottom of the page. Each save is listed with your name and the
   values before and after.

## Common mistakes

- **Adding the type here before adding the choice in Setup.** The save is refused with
  "Mentor is not a choice in the Type list on Relationship. Add it in Setup (Object
  Manager, Relationship, Fields, Type), then save again." Add the choice and save again.
- **Adding only one side.** BarnCRM writes the reciprocal type on the other person, and
  reads that type's own row whenever the other person's side is saved. Add both rows (Mentor
  to Mentee, and Mentee to Mentor). A type you add that is its own reciprocal, such as
  Neighbor to Neighbor, needs one row.
- **Trying to change a shipped type.** Shipped types have no actions. To use a different
  reciprocal for one of them, add your own type with a different name, for example
  `Employer` instead of `Employer contact`. A type can have only one active row, so the
  page refuses a second row for a type that already has one.
- **Expecting Delete.** There is no delete. Salesforce does not let an app delete custom
  metadata, so you archive an entry instead, and it stops being used. An archived entry can
  be restored. To remove it for good, delete it in Setup (Custom Metadata Types,
  Relationship Type, Manage Records).
- **Leaving the page before "Saved".** The change carries on in the background. Come back
  and click **Check again**. If it failed, the reason is in the Error Log.
- **Adding the same entry twice before the first save finishes** (in a second tab, or
  after the page says it is still saving). Each new entry gets a short code at the end of
  its API name in Setup, for example `Org_Mentor_k3x9`, so the second add never overwrites
  the first. You may end up with two entries: archive the one you do not want.

## Match sources

BarnCRM ships six:

| Source | Object | Value | Linked by | Compared as |
|---|---|---|---|---|
| Contact Point Email | Contact Point Email | Email Address | Parent | Email |
| Contact Point Phone | Contact Point Phone | Telephone Number | Parent | Phone |
| Contact Point Address | Contact Point Address | Street and Postal Code | Parent | Address |
| Address (person) | Address | Street and Postal Code | Contact | Address |
| Address (household) | Address | Street and Postal Code | Account | Address |
| Address (person account) | Address | Street and Postal Code | Person Account | Address |

The contact point objects exist only in some orgs (Nonprofit Cloud has them). Where an
object is missing, its source does nothing; nothing breaks.

How values are compared:

- **Email**: spaces at either end are ignored, and capitals do not matter.
- **Phone**: only the digits count, so (555) 123-4567 and 555.123.4567 match. A North
  American number written with a leading 1 matches the same number without it. A number with
  fewer than seven digits is ignored.
- **Address**: the street, with capitals, punctuation and extra spaces ignored and common
  words shortened (Street and St, Avenue and Ave match), together with the postal code
  (spaces ignored; a ZIP+4 counts as its first five digits).

A contact point record can belong to a person, an account, or a Salesforce **Individual**
(the privacy record behind a person). A person or an account is used as it is; an Individual
counts as every person who carries it, contacts and, where your org has person accounts,
person accounts too. A record that belongs to anything else is skipped.

When you add your own source, the value field (and, for an address, the postal code field)
must be a text, email or phone field Salesforce can search on, and the parent field must be a
lookup to a contact, an account or an Individual. The page refuses anything else.

A value shared by more than ten people or households, such as an office's main number, is
ignored: it says nothing about whether two of them are the same.

To add your own source, choose **Add** under **Match sources** and fill in the object's API
name (for example `Volunteer_Profile__c`), the field holding the value, the lookup to the
person or household, and **Normalization**. For **Address**, also fill in **Postal Code
Field**. The page checks that the object and fields exist and that the link is a lookup.

To stop using a shipped source, open the menu on its row under **Shipped with BarnCRM** and
choose **Archive**. **Restore** brings it back.

## Which lists can be extended

| List | Here | Why |
|---|---|---|
| Relationship types | Add, edit, archive | BarnCRM reads the list directly, so an entry you add is used at once. |
| Match sources | Add, edit, archive; archive and restore a shipped one | BarnCRM reads the list directly when it scans for duplicates and matches an import. |
| Rollups, import templates | No | BarnCRM copies the shipped entries into the Rollups and Import pages, which is where you add and change your own. |
| Automations, settings | No | These describe BarnCRM's own code and pages. An entry you added would point at nothing. |
| Receipt templates (Giving) | No | Copied into the Receipts page, where you edit your own. |
