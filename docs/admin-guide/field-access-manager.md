# Field Access Manager

**Package:** Core
**Feature:** C-65 (release 0.17, decision D-157, ADR-0156)

## What It Does

**Field Access Manager** gives or removes **Read** and **Edit** on fields and kinds of record,
for several permission sets at once, from one page. It is the **Change Field Access** view of
[Access Explorer](access-explorer.md), in **Org Optimizer**.

Use it when a new field, a new module or a new kind of volunteer means a group of people needs
to see or change something they cannot today. Without it you would open each permission set in
Setup, find the kind of record, and tick fields one at a time.

Every change is shown row by row before anything is saved, and can be undone for as long as an
import can (**Days an import can be undone**, in the **Import** section of BarnCRM Settings).

It changes only Read and Edit. Create, Delete, View All, Modify All, system permissions, tabs,
apps and who holds which permission set stay in Setup and on the [Access page](access.md).

## How to Turn It On

There is nothing to switch on. You need both:

- the **BarnCRM Admin** role (the BarnCRM Admin permission set, which carries the Manage
  BarnCRM Settings permission), and
- Salesforce's **Manage Profiles and Permission Sets** system permission (System
  Administrators have it).

Without both, **Change Field Access** says which one is missing and offers nothing to change.

## Which Permission Sets You Can Change

Only permission sets your organization made. Field Access Manager never lists or changes:

- **profiles**: a change reaches everyone on the profile at once, and Salesforce is moving
  permissions off profiles. Give access with a permission set instead;
- **permission set groups**: change a permission set inside the group, and Salesforce
  recalculates the group. Access Explorer's **In Groups** and **Includes** show which;
- **muting permission sets**, **standard permission sets** Salesforce ships, and **permission
  sets installed by a managed package** (BarnCRM's own included, once installed as a package):
  those cannot be changed, or an upgrade would put them back;
- **BarnCRM's own permission sets**, such as BarnCRM Staff or Volunteers Coordinator, however
  BarnCRM was installed: BarnCRM keeps their access up to date itself, so a change made here
  would be overwritten. To give BarnCRM users more access, assign them a permission set your
  organization made as well;
- the access rows Salesforce keeps for user licenses and permission set licenses.

You can choose up to 10 permission sets for one change.

## Which Fields You Can Change

Fields Salesforce lets you restrict. Required fields, system fields such as Created By, and
fields everyone who can read the record sees (such as Name) are not listed, because Salesforce
does not let anyone give or take them. Formula, roll-up summary and auto number fields can be
given **Read** only: nobody edits them.

## What Is Added for You

Salesforce refuses access that does not fit together, so Field Access Manager adds what is
needed and shows each added row with its reason under **Why**:

| You ask for | Also changed |
|---|---|
| **Read** or **Read and Edit** on a field | **Read** on its kind of record, if the permission set lacks it |
| **Read and Edit** (field or kind of record) | **Read** |
| **Read** only on a kind of record that has Edit | **Delete** and **Modify All** are removed with **Edit** |
| **No Access** on a kind of record | Every permission on it (Create, Delete, View All and Modify All too), and the permission set's access to every field on it |

A row already at the access you asked for is counted as **unchanged** and not written.

## A Five-Minute Walkthrough

Start from the sample data (see [Sample data](sample-data.md)). In Setup, make a permission set
called **Event Volunteers** (no license) if you do not have one to try this on.

1. Open **Org Optimizer**, choose **Access Explorer**, then **Change Field Access** under
   **Show**.
2. In **Permission Sets**, type `Event` and choose **Event Volunteers**. It is added under the
   search box. Add more the same way, or remove one with its **x**.
3. In **Kind of Record**, choose **Contact**. The **Fields** table lists every Contact field you
   can change, with **Now**: how many of the chosen permission sets give Read and Edit today.
   Type in **Filter Fields** to narrow it.
4. Tick **Email** and **Phone**, choose **Read and Edit** in **Access for the Ticked Fields**,
   and press **Add to Changes**. Both appear under **Changes**.
5. In **Kind of Record**, choose **Relationship**, set **Access to the Kind of Record** to
   **Read**, and press **Add to Changes**.
6. Press **Preview**. The **Preview** table has one row per permission set and field or kind of
   record, with **Now**, **After** and **Why**: **Contact** **Read** shows "Needed for field
   access" if the set could not read Contacts. The line above it says how many rows change and
   how many are already right.
7. Press **Apply Changes** and confirm. The page says how many rows changed and how many were
   refused, and that the change can be undone under **Recent Changes**. Access Explorer's **By Person or Permission Set** view now shows the
   new access.
8. Under **Recent Changes**, the change is listed first with **When**, **By**, **Rows Changed**,
   **Refused**, **Status** and **Undo Until**. Press **Undo** and confirm: every row goes back to what it was,
   and the status reads **Undone**.

## Preview, Apply and Undo

- **Preview first, always.** Nothing is saved until you press **Apply Changes** on a preview.
- **The preview is checked again.** If the number of rows to change is different when you apply
  (someone changed a permission set in Setup in the meantime), nothing is saved and the page asks
  you to preview again.
- **At most 2,000 rows in one change.** A larger change says so in the preview; split it by
  permission set or by kind of record.
- **Saved as you.** Rows are written with your own access, so Salesforce's own checks apply. A
  row Salesforce refuses (for example, a permission set whose license does not allow that kind
  of record) is listed with Salesforce's reason, goes to the [Error Log](error-log.md), and the
  other rows are still saved.
- **Undo** puts each row back to what it was before, for as long as the undo window lasts. A row
  someone changed since (in Setup, or with another change here) is kept as it is now, and the
  change's result says how many were kept. A change is undone once.
- **Where it is recorded.** Each change is a data job: **Recent Changes** lists the newest 20.
  Salesforce also writes every row change to its Setup Audit Trail, which the
  [Setup Changes](setup-changes.md) section copies every night (or press **Copy New Changes
  Now** there).

## Large Orgs

Field Access Manager reads one kind of record's fields at a time, and only the access rows of
the permission sets you chose, so an org with thousands of fields or permission sets is never
read whole. The **Kind of Record** list is the same one the Data Dictionary uses.

## Related

- [Access Explorer](access-explorer.md): see who has access, and why, before and after.
- [Access](access.md): BarnCRM roles and add-ons.
- [Create a new field during import](import-new-fields.md): gives BarnCRM's own permission sets
  access to the field it creates.
