# Read-Only Access

The Read Only role is for board members, auditors and anyone who should look but not change
anything. This page lists what you can see with it, what you cannot do, and what BarnCRM says
when you try.

Before you start: your admin gives the **Read Only** role on the Access page. With the
Volunteers module, the role brings **Volunteers Read Only** automatically. With the Giving
module, your admin gives **Giving Read Only** separately, if you should see gifts. See
[Access](../admin-guide/access.md).

## What You Can and Cannot Do

### Core (BarnCRM App)

| Area | You can | You cannot |
|---|---|---|
| People, households, organizations | Open and read them, their list views and global search | Create, edit or delete |
| Addresses, relationships, affiliations | Read them on the cards and their tabs | Add, set as primary, make primary, remove (the cards do not show these buttons) |
| Household members | See the **Members** card and the **Household Members** tab | Add, move or make primary (the card does not show these buttons) |
| Household merge and split | Open **Merge or Split** and read it | Merge or split |
| Home tab | **What's New in BarnCRM**, the welcome and **Quick Links** | Use **New Household** (it is hidden) |
| BarnCRM Settings | Read every setting and its **Learn More** link | Change anything |
| Error Log | Read entries (open it from the navigation menu if it is not shown) | Change entries |
| Find, Data Manager, Org Optimizer | Nothing, unless your admin also gives the **BarnCRM Find and Export** add-on | Bulk update or bulk delete |

Tabs you see in the **BarnCRM** app: **Home**, **Households** and **Organizations**, plus
**Contacts** if your Salesforce profile shows it. **BarnCRM Console** adds **Addresses**,
**Relationships**, **Affiliations** and **Household Members**. **BarnCRM Settings** and
**Error Log** are in the admin apps, which you do not see; open them by typing their name in
the App Launcher.

If your admin gives you **BarnCRM Find and Export**, you can build, run, save and export Find
queries over everything you can read. You still cannot change records.

### Giving (with Giving Read Only)

| Area | You can | You cannot |
|---|---|---|
| Gifts, commitments, installments, allocations, soft credits, tributes | Read them | Enter, change or delete |
| Funds, appeals, gift batches | Read them | Create, change or post |
| Receipts, receipt runs, acknowledgments, acknowledgment runs and rules | Read them | Issue receipts or send acknowledgments |
| Stewardship plans and templates, donor levels | Read them | Change them |
| Quick Gift Entry | Nothing: the tab is not given | Enter gifts |
| Giving reports and dashboards | Run them and view dashboards | Create or change reports and dashboards |

The gift panels on a record still load, so you can read them; their actions are not for you.
A commitment's **Payment Schedule** card shows no **Pause**, **Resume**, **Mark Complete** or
**Cancel Commitment**, and **Refund or Write Off** and **Start Stewardship Plan** open a window
that says you cannot record a refund or start a plan.

### Volunteers (with Volunteers Read Only)

| Area | You can | You cannot |
|---|---|---|
| Volunteer Jobs, Volunteer Shifts, sign-ups, Skills | Read them; run reports and view dashboards | Create, change or delete |
| Volunteer Hours | Open the tab, but you see no hours entries (each person sees only the entries they made) | Enter or approve hours |
| A person's volunteer totals | Read them on the person | Change them |
| Volunteer Requirements, Volunteer Letter Templates, Approve Hours | Nothing: these are not given | Anything |

## To Check What You Can See

1. Open the App Launcher and choose **BarnCRM** (or **BarnCRM Fundraising**, or **BarnCRM
   Volunteers**).
2. Open a tab, then a record.

You should see: the record with its cards. Salesforce's **Edit** and **Delete** buttons are
not offered, or say you do not have access.

## What You See When You Try Something You Cannot Do

- On **BarnCRM Settings**: "You can read these settings but not change them. Ask your
  administrator for the Manage BarnCRM Settings permission."
- On **Merge or Split**: "You can see this household but not change it, so merging and
  splitting are switched off. Ask whoever manages access for edit access to both households."
- On the **Addresses**, **Relationships**, **Affiliations** and **Members** cards: nothing to
  try. **Add Address**, **Set as Primary**, **Add Relationship**, **Remove**, **Add
  affiliation**, **Make Primary**, **Add Member** and **Move to Another Household** are not
  shown to you.
- On the **Find** tab without the add-on: "Find needs the Find and Export Records permission.
  Ask your administrator to assign you the BarnCRM Find and Export permission set."
- On a gift batch (Giving): "You can see this batch but not change or post it. Ask your
  administrator for the Giving Staff permission set, or for edit access to this batch."
- Issuing a receipt (Giving): "You do not have permission to issue receipts. Ask your
  administrator for the Fundraising Staff role."
- Sending thank yous (Giving): "Sending thank yous needs the Send Acknowledgments permission.
  ..."
- Approving hours (Volunteers): "You need the Manage Volunteers permission to approve, reject
  or reopen volunteer hours. Ask your BarnCRM administrator."

None of these change anything. Nothing is saved when an action is refused.

## Common Problems

- Problem: the **Add** buttons on the cards are shown, but saving fails. The cards show the
  buttons to everyone; your role does not allow the save. This is expected.
- Problem: you see no gifts. You have no Giving permission set. Ask your admin for **Giving
  Read Only**.
- Problem: the **Volunteer Hours** list is empty. Hours entries are private to the person
  who entered them and to coordinators. Totals on each person still show.
- Problem: you need to change something. Ask your admin for a role that allows it, such as
  Team Member.

## Related

- [Getting around BarnCRM](getting-around.md)
- [Finding people and records](find.md)
- [People and households](people-and-households.md)
- Admin Guide: [Access](../admin-guide/access.md), [Volunteers](../admin-guide/volunteers.md),
  [BarnCRM Settings](../admin-guide/barncrm-settings.md)
