# Record Pages

**Feature:** C-08 Dynamic Forms record pages
**Package:** Core
**Iteration:** v0.1

## What It Does

BarnCRM ships the pages that open when you click a household, an organization or a person in
the **BarnCRM** app. They show the right fields for the kind of record, put the actions you
use most in the bar at the top, and carry BarnCRM's own panels (members, household,
affiliations, addresses), so you do not build any of it yourself. Because the pages choose
what to show by the record, a household and an organization share one page and a person has
another, and nobody has to maintain separate page layouts for them.

## How to Turn It On

There is nothing to turn on, and nothing to do in Salesforce Setup. The pages arrive with
Core, and the **BarnCRM** app opens households, organizations and people on them, on the
desktop and on the phone. Core ships one Account record type, **Household**, which no user has
until Household Upkeep is on ([Households](households.md)), and no Contact record type, so it
does not disturb any you already have. An account is an organization when it has the record
type chosen in **Record type for organizations** on **General** (or, when **No record type** is
chosen, no record type); the pages and the **Organizations** list read that through the
**Is Organization** field, so they follow your choice without being edited.

What ships:

| Page | Opens for | What is on it |
|---|---|---|
| **Account Record Page** | Households and organizations | A **Details** section (name, phone, owner, address, parent, and for an organization the website), the actions bar, the activity panel, related lists, and the panels below |
| **Contact Record Page** | People | **Person**, **Household** and **Reaching This Person** sections, the actions bar, the activity panel, a Potential Duplicates card, related lists, and the panels below |

What changes with the record:

- **A household** shows the **Members** panel and a **Name and Greetings** section
  (custom name, formal and informal greetings, member count, primary contact, anniversary).
  See [Household members](household-members.md) and
  [Household names and greetings](household-naming.md).
- **An organization** shows the **Affiliations** panel and the website. See
  [Affiliations](affiliations.md).
- **A person** shows the **Household** panel, **Relationships** and **Affiliations** panels,
  and the person's email addresses (see [Emails](emails.md)). See
  [Relationships](relationships.md).
- **Every record** shows the addresses panel. See [Addresses](addresses.md).

The action bar holds **Edit**, **Log an Interaction** ([Interaction notes](interaction-notes.md)),
**Delete**, and two more that depend on the record: **Merge or Split** on households only
([Household merge and split](household-merge-split.md)), and **Erase Person** on a person for
anyone with the permission to erase people ([Erase a person](erase-a-person.md)).

**Where the pages are used.** They are assigned to the **BarnCRM** app, so a record opened
in that app uses them. A record opened in another app, or on a page your organization
assigned itself, uses that page instead. With Giving installed, the **BarnCRM Fundraising** app opens
people, households and organizations on Giving's own pages, which add giving (see
[A donor's giving on their record](donor-records.md)).

**Your own pages win.** BarnCRM never replaces a record page you assigned yourself. If you
built your own Account or Contact page and assigned it, it keeps showing wherever you
assigned it. Each object also keeps one small fallback page layout, so a record that opens
on a page of yours still has usable fields and related lists. No profile layout assignments
ship: the new layouts are unassigned, so outside the **BarnCRM** app a record keeps the
layout your profiles already use. The pages above apply only in the **BarnCRM** app, so tell
staff to work there. The list views BarnCRM adds (for example **Households** and
**Organizations**) are scoped to **Everything**: each person still sees only the records
their own access allows, but there is no "my records" filter.

**Adding the Household panel to a person account page.** Where your org stores people as
person accounts, BarnCRM ships no page for them, because the person account page is your
org's. Add the panel yourself. The steps are in
[Household members](household-members.md), under "The Household panel on a person".

## A Five-Minute Walkthrough

Start with the sample data loaded ([Sample data](sample-data.md)).

1. Open the **BarnCRM** app and choose the **Households** tab. Open **The Garcia Family**.
   The page has the **Details** section, the **Members** panel, and **Name and
   Greetings**, with the formal and informal greetings.
2. Look at the action bar at the top. **Merge or Split** is there, because this is a
   household.
3. Click a member's name to open the person. The page now has **Person**, **Household** and
   **Reaching This Person** sections, and the **Household** panel names the household you
   came from. **Merge or Split** is gone, because a person is not a household.
4. Go back and open an organization from the **Organizations** tab. There is no **Name and
   Greetings** section and no **Members** panel; the **Affiliations** panel and
   the website show instead. The page is the same one the household used: it chose what to
   show from the record.
5. To make the page your own, open any record, click the gear icon, and choose **Edit
   Page**. Change it, then save and choose **Activation** to assign it. BarnCRM leaves it
   alone from then on.

## Common Mistakes

**"The Members panel, the Household panel or the Merge or split button is missing."** You are
most likely looking at the record outside the **BarnCRM** app, or somebody assigned a
different page in the Lightning App Builder. Open the record from the **BarnCRM** app, or add
the panel to the page that is assigned.

**"I added a field and it does not show."** The pages show fields from sections you place
them in, not from the page layout. Open the page in the Lightning App Builder and add the
field to a section; changing only the page layout does not add it to a BarnCRM page.

**"I edited the BarnCRM page and a later upgrade changed it back."** Edit a copy and assign
your copy instead. A page you assigned yourself is left alone; BarnCRM's own page is
packaged, and an upgrade can change it.

**"The panel is missing on a person account."** BarnCRM ships no person account page. Add the
panel as described above.

**"An organization shows no Affiliations panel and is missing from the Organizations list."**
Its record type is not the one chosen in **Record type for organizations** on **General**.
Change the account's record type, or choose that record type in the setting.
