# People and Households

A household is the group of people you treat as one: one mailing, one letter, one shared
history. BarnCRM creates a household for every new person, names it, writes its greetings and
keeps its member count right. Organizations (employers, foundations, congregations, partners)
are kept separately.

Before you start: open the **BarnCRM** app. Adding and changing people and households needs
the Team Member, Fundraising Staff or Admin role. With Read Only you can look
but not change; see [Read-only access](read-only-access.md).

## To Add a Person

1. Open the **Contacts** tab and click **New**.
2. Fill in the name. Leave the household (the **Account Name** field) blank.
3. Click **Save**.

You should see: the person's record, with a household already created for them, for example
**The Garcia Family**. The **Household** card on the person's **Connections** tab links to it, with
the member count and the formal greeting. If your org turned off automatic households, or
records membership the flexible way, the household field may stay blank: open the household
from the **Household** card or the **Households** tab.

## To Start From a Household

1. On the **Home** tab, click **New Household**.
2. The household is created and opens. Add people with **Add Member** (below).

You should see: a household with a placeholder name, renamed automatically once it has a
member.

**New Household** is the only way to start a household by hand. The **New** button on the
**Households** tab or on Accounts never offers **Household**, and an account can't be changed
into a household.

## To Add a Member to a Household

1. Open the household and click the **Connections** tab. Find the **Members** card.
2. Click **Add Member**. The **Add Member** dialog opens.
3. Either search under **Add Someone Already in Salesforce** (type in **Search by name** and
   choose the person), or fill in **Salutation**, **First Name** and **Last Name** (and,
   if you like, **Email** and **Phone**) under **Or Add Someone New**. If the person you choose is in another
   household, a line names it, for example "Ana Garcia is in The Lopez Family and will move to
   this household." Click **Save** to confirm, or **Cancel** to leave them where they are.
4. If a note appears under the name, such as "Already in BarnCRM: Ana Garcia, Tampa (Garcia
   Household). Use this person instead?", the person may already exist. Click **Use this
   person instead?** to add them rather than a duplicate; otherwise carry on.
5. Click **Save**.

You should see: "Added. The household name and greetings have been brought up to date." The
dialog closes. Each member shows as a tile with their initials, a **Primary** badge on the primary contact and a **Deceased** badge on
anyone marked deceased. (In orgs that use the simple way of belonging, a person belongs to
one household, so adding someone from the search moves them here.)

## To Change the Primary Contact

1. On the household's **Members** card, open the menu on the person's tile and choose **Make
   Primary**.

You should see: "... is now the primary contact." The **Primary** badge moves, and the
household's **Primary Contact** field follows.

## To Move a Person to Another Household

1. On the **Members** card, open the menu on the person's tile and choose **Move to Another
   Household**.
2. Choose the household to move them to, and click **Save**.

You should see: "Moved. Both households have been brought up to date."

## To Control Names and Greetings

A household's name and greetings are worked out from its members. On the household, the
**Name and Greetings** section shows **Member Count**, **Anniversary**, **Custom Name**,
**Formal Greeting** and **Informal Greeting**. On a person, the **Person** and **Household**
sections hold the fields that feed them.

| You want | Do this |
|---|---|
| Keep a household name you typed yourself | Edit the household, type the name and greetings, tick **Custom Name**, save. Nothing recalculates it until you untick it. A greeting you leave blank is filled from the members; one you typed is kept. |
| Use a nickname in greetings | Edit the person and fill in **Preferred Name**. It replaces the first name in greetings. |
| Leave someone out of the household name | Tick **Exclude From Household Name** on the person. They still count as a member. |
| Leave someone out of the greetings | Tick **Exclude From Greetings** on the person. |
| Record that someone has died | Tick **Deceased** on the person. They are left out of the greetings. |
| Record each person's place | Set **Household Role** (Head, Spouse or Partner, Child, Other). |

You should see: the household's name and greetings updated on the next save, unless
**Custom Name** is ticked (then only a blank greeting is filled).

## To Merge Two Households

Use this when the same family is in BarnCRM twice. You need edit access to both households.
You do not need permission to delete households.

1. Open the household you want to keep and click **Merge or Split** in the action bar.
2. Stay on the **Merge** tab. In **Find the Other Household**, type part of its name and pick
   it. Each household shows its city.
3. Read the **Household comparison**. Where the two disagree, choose **Keep This One** or **Keep
   the Other One**. Check **Members After the Merge**. Opened the one you meant to remove?
   Click **Keep the Other Household Instead** rather than starting again.
4. Click **Merge**. Read "This Cannot Be Undone", then click **Merge Households**.

You should see: "Merged. The household you kept now holds everyone from both." The other
household is deleted, and its history, files and notes move to the one you kept. A merge
cannot be undone, so check both households first.

## To Split Someone Out of a Household

1. On the household, click **Merge or Split**, then the **Split** tab.
2. Choose **A new household**, or **An existing household** and pick it.
3. Under **Choose Who Moves Out**, move each person who is leaving from **Stays in ...** to
   **Moves to ...**: tick their checkbox, use **Move to ...** in their tile's menu, or drag
   their tile across (on a phone or tablet, press and hold first).
4. Click **Split**, then confirm **Split** in "Split This Household?".

You should see: "Moved. Both household names and member counts are up to date."

## To Log an Interaction

1. On a person, household or organization, click **Log an Interaction** in the action bar.
2. Fill in **Subject**. Change **Date** if it happened on another day. **Type** starts as
   Meeting; change it if it was, for example, a call.
3. Add the people who took part, write your notes in **Comments**, and click **Save**.

You should see: the note under **Past Activity** in the activity timeline. Anyone who can see
the record can read it, so write accordingly.

## To Read a Person's Engagement Score

When your admin has turned Engagement Score on, a person's page shows an **Engagement Score**
meter from 0 to 100 and the day it was scored. A person who has not been scored yet shows
**Not scored yet** in place of the meter.

1. Open the person. The meter is on the right of the page.
2. Click the help icon beside the title to see what goes into the score.

A higher score means more recent giving, volunteering, event attendance and logged activity,
weighted the way your organization chose. It is worked out each night, so a gift entered today
counts from tomorrow. To list people by score, use **Engagement Score** in Find or a list view.

## To Add an Organization

1. Open the **Organizations** tab and open the list, then click **New**.
2. If Salesforce asks for a record type, choose the one your organization uses for
   organizations (your admin can tell you; it is never **Household**).
3. Fill in the name and details and click **Save**.

You should see: the organization's page with **Details**, an **Addresses** card and an
**Affiliations** card listing the people connected to it. See
[Relationships and affiliations](relationships-affiliations.md).

## To Erase a Person

Erasing a person on request is admin work. See [Erase a person](../admin-guide/erase-a-person.md).

## Common Problems

- Problem: "This person is not in a household yet". Automatic households may be off in your
  org. Add them from a household's **Members** card, or ask your admin.
- Problem: the **Members** card has no **Add Member** button and no menu on the tiles. Your access lets you read households but not change them (the Read Only
  role, for example). Ask your admin.
- Problem: "You can see this household but not change it, so merging and splitting are
  switched off. Ask whoever manages access for edit access to both households." Ask your admin.
- Problem: "You need edit access to both households to merge them." The other household is
  one you cannot edit. Ask your admin.
- Problem: "Both records must be households. Choose a household, not an organization."
  Organizations are merged with Salesforce's own tools by an admin.
- Problem: "The two households could not be combined, so nothing was changed." Salesforce
  refused the merge. The reason is in the Error Log; ask your admin.
- Problem: "The primary contact could not be changed. Check that you can edit this household
  and try again." Ask your admin for edit access.
- Problem: the household name will not update. **Custom Name** is ticked. Untick it.
- Problem: in an org that also has NPSP, a household's name and greetings are the ones NPSP
  had, and **Custom Name** is ticked. Your admin adopted NPSP's households and kept their
  wording. Untick **Custom Name** if you want BarnCRM to name it from its members.
- Problem: there is no **Households** tab. Your organization has not turned households on
  yet. Ask your admin.
- Problem: **Household** is not offered when you click **New**. That is expected: use **New
  household** on the **Home** tab.
- Problem: there is no **Merge or Split** button. You are on an organization, or outside the
  **BarnCRM** app.
- Problem: "This person is in a household, so Account Name must stay a household, not an
  organization. To connect them to an organization, add an affiliation. To move them, use
  Move to another household." You put an organization in the person's **Account Name**. Put
  their household back, then add an affiliation for where they work, or use **Move to another
  household** on the **Members** card.

## Related

- [Addresses, email and phone](addresses-email-phone.md)
- [Relationships and affiliations](relationships-affiliations.md)
- [Duplicates](duplicates.md)
- Admin Guide: [Households](../admin-guide/households.md),
  [Household members](../admin-guide/household-members.md),
  [Household naming](../admin-guide/household-naming.md),
  [Merging and splitting households](../admin-guide/household-merge-split.md),
  [Interaction notes](../admin-guide/interaction-notes.md)
