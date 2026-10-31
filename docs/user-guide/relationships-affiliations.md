# Relationships and Affiliations

A relationship connects two people: spouses, a parent and child, friends, colleagues. An
affiliation connects a person to an organization: an employer, a board, a congregation. You
enter a relationship once, on one person, and BarnCRM writes the other side for you. One
current affiliation per person can be primary, and it shows on the person as **Primary
Affiliation**.

Before you start: open the **BarnCRM** app. Adding, changing and removing these needs the Team
Member, Coordinator, Fundraising Staff or Admin role. The **Relationships** card is on every
person; the **Affiliations** card is on every person and organization.

## To Add a Relationship

1. Open the person. Find the **Relationships** card.
2. Click **Add Relationship**. The **New Relationship** form opens.
3. In **Related Person**, choose the other person.
4. Choose a **Type**: what the other person is to this person. Choose from Spouse, Partner,
   Parent, Child, Sibling, Grandparent, Grandchild, Friend, Colleague, Employer contact or
   Other.
5. Leave **Status** as Current. Optional: **Start Date** and **Description**.
6. Click **Add Relationship** at the foot of the form.

You should see: "Relationship saved, and the other person's record now shows it too." The
card shows the other person and the type. Open the other person: their card shows you, from
their side. If you entered Child on a parent, the child's card reads Parent.

Read the type from the record you are on. "Diego Garcia, Child" on Harper's record means Diego
is Harper's child.

## To Change or End a Relationship

The card has no Edit button. Change a relationship on its own record:

1. Open the **Relationships** tab from the navigation menu (near the end), and open the
   relationship.
2. Click **Edit**.
3. To end it, fill in **End Date**. To change it, change **Type** or **Description**.
4. Click **Save**.

You should see: the line on the card now carries a **Former** badge. The other person's
side changes with it, so both records always agree.

## To Remove a Relationship

1. On the **Relationships** card, click **Remove** on the line.

You should see: "Relationship removed from both people." There is no confirmation, so check
the line first. If the relationship was real but has ended, set an **End Date** instead, so
the history stays.

## To Add an Affiliation

1. Open the person (or the organization). Find the **Affiliations** card.
2. Click **Add Affiliation**. The **New Affiliation** form opens.
3. Choose the **Organization** (or, on an organization, the **Person**).
4. Fill in **Role** in your own words, for example Board chair.
5. Leave **Status** as Current. Tick **Primary** if this is the organization the person is
   chiefly associated with. Optional: **Start Date**, **End Date**, **Description**.
6. Click **Add Affiliation** at the foot of the form.

You should see: "Affiliation saved." The card shows the organization and role, with a
**Primary** badge if you ticked it. **Primary Affiliation** at the top of the person shows
that organization.

## To Change the Primary Affiliation

1. On the person's **Affiliations** card, click **Make Primary** on the line you want.

You should see: "Primary affiliation updated." The **Primary** badge moves, and the old one is
cleared for you. Only one current affiliation per person is primary.

## To End or Change an Affiliation

1. Open the **Affiliations** tab from the navigation menu, and open the affiliation.
2. Click **Edit**. To end it, fill in **End Date**. Click **Save**.

You should see: a **Former** badge on the line. A former affiliation is never primary, so if it
was primary, the person's **Primary Affiliation** becomes empty. Click **Make Primary** on
another line to fill it again.

An affiliation never moves a person between households.

## Common Problems

- Problem: "... already has this relationship with .... Open ... to change it." The
  relationship exists. Open the record named and change that one.
- Problem: "This relationship already exists. Ask an administrator to look at the existing
  one." It exists, but you cannot see it. Ask your admin.
- Problem: "A relationship needs two different people." You picked the same person.
- Problem: "BarnCRM could not update the other side of this relationship, so nothing was
  saved. The Error Log has the details." Tell your admin.
- Problem: "... already has an affiliation with ... as ... covering those dates. Open ... to
  change it." Same person, organization and role with overlapping dates. End the first one
  (fill in its **End Date**) before you add the second, or give them dates that do not
  overlap.
- Problem: "This person already has an affiliation with this organization and role covering
  those dates. Change the dates, or ask an administrator to look at the existing one." The same,
  for one you cannot see.
- Problem: "An affiliation needs an organization." Choose an **Organization**.
- Problem: "BarnCRM could not remove that relationship. Check that you can delete
  relationships ..." or "BarnCRM could not make that the primary affiliation ..." Ask your admin
  for access.
- Problem: the card has no **Add Relationship**, **Remove**, **Add Affiliation** or **Make
  primary** button. Your access lets you read these records but not change them (the Read Only
  role, for example). Ask your admin.
- Problem: **Primary Affiliation** went empty. The primary affiliation was ended. Make another
  one primary.

## To Load Many at Once

An admin can load a list of relationships or affiliations from a file with the **Relationships**
and **Affiliations** import templates (Admin Guide, Importing). Each person is found by email
address and each organization by name, so they must already be in BarnCRM. List each
relationship once: the other side is added for you. A row for something that already exists is
rejected and named in the results.

## Related

- [People and households](people-and-households.md)
- [Addresses, email and phone](addresses-email-phone.md)
- Admin Guide: [Relationships](../admin-guide/relationships.md),
  [Affiliations](../admin-guide/affiliations.md)
