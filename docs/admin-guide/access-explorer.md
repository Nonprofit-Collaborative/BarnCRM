# Access Explorer

**Package:** Core
**Feature:** C-53 (plan Section 6.1.1 item 7, decision D-154)

## What It Does

The **Access Explorer** section of **Org Optimizer** answers "who can see or change what, and
why". It reads your org's profiles, permission sets and permission set groups and shows the
answer five ways:

| View | What it shows |
|---|---|
| **By Person or Permission Set** | Everything one person can read, create, edit or delete, kind of record by kind of record, and the profile, permission sets and permission set groups that give it. Choose **Permission Set** instead to see what one profile, permission set or group gives. Choose a kind of record to see field access too. |
| **By Kind of Record** | For one kind of record (or one of its fields), every profile, permission set and permission set group that gives access, how many active people hold each, and a list of the people who have access, 50 at a time. |
| **BarnCRM Permission Sets** | Every permission set and role BarnCRM ships, how many active people hold each, and whether the hourly Tab Access Check is scheduled. |
| **Compare Two** | Two people, or two profiles, permission sets or groups, side by side: what each can do on every kind of record (and on the fields of one), showing only the differences unless you ask for everything, with a similarity score. |
| **Modify All Report** | Every profile, permission set and group that holds **Modify All Data**, **View All Data** or **Author Apex**, and every one that holds **Modify All** or **View All** on a kind of record, with how many active people hold each and the groups it sits inside. |

Each table has **Download CSV**, which saves what it shows.

Access Explorer is **read only**. It never gives or takes access. To change who holds a BarnCRM
role or add-on, use the [Access page](access.md); for anything else, use Setup.

## How to Turn It On

You need the BarnCRM Admin role (the BarnCRM Admin permission set, which carries the Manage
BarnCRM Settings permission and View Setup and Configuration). It shows you the **Access
Explorer** tile and section in **Org Optimizer**, and an **Open Access Explorer** button on the
**Access** page of BarnCRM Settings. Nobody else sees them. There is nothing to
schedule and no setting to change.

To list people outside your part of the role hierarchy, you also need **View All Users**. On a
Salesforce license it comes with the optional **BarnCRM Access Manager** permission set (see
[Access](access.md)). Without it, Access Explorer lists only the people Salesforce lets you see,
and **People With Access** says so in one line above the list. Access Explorer never reads past
user sharing to show you people you could not otherwise see.

## A Five-Minute Walkthrough

Start from the sample data (see [Sample data](sample-data.md)).

1. Open the **Org Optimizer** tab (in the admin apps, or from its card on **Data Manager**) and
   choose the **Access Explorer** tile.
2. **By Person or Permission Set** is open, looking up a **Person**. Type part of a colleague's name in **Person** and choose them. The
   page shows their profile and an **Access Comes From** list: their profile, each permission set
   they hold directly, and each permission set group (role) with the permission sets inside it.
3. Read the table. Each kind of record they can at least read has a row with **Read**,
   **Create**, **Edit**, **Delete**, **View All** and **Modify All**, and **Granted By** names
   what gives that access. A role reads, for example, "Team Member (through BarnCRM Staff)".
4. Choose **Contact** in **Field Access For** (it offers the kinds of record the person can
   read). A second table lists every Contact field with
   **Read**, **Edit** and **Granted By**. Fields Salesforce always shows to anyone who can read
   the record (such as Name) say **Always**.
5. Choose **By Kind of Record**, then **Household Member** in **Kind of Record**. **Who Gives
   Access** lists every profile, permission set and group that gives access, with **Active
   People**. **People With Access** lists the people who have access and why. Press **Show
   More** for the next 50. Choose a field in **Field** to see the same for one field.
6. Back on **By Person or Permission Set**, choose **Permission Set** in **Look Up** and type
   `Staff`. Choose **BarnCRM Staff**: the table shows only what that permission set gives.
7. Choose **BarnCRM Permission Sets**. Each BarnCRM role and permission set shows how many
   active people hold it directly, and the **Tab Access Check** line says when it runs next.
8. Choose **Compare Two**. Leave **Compare** on **People**, type part of one colleague's name
   under **First** and choose them, then do the same under **Second**. The page shows a
   **Similarity** percentage and a **Kinds of Record** table with only the rows where the two
   differ. **Difference** reads, for example, "Only Pat: Edit, Delete. Only Sam: View All".
   Clear **Differences Only** to see every row. Choose a kind of record in **Compare Fields
   For** to compare its fields the same way.
9. Choose **Modify All Report**. **Data-Wide Access** lists everything that holds Modify All Data
   or View All Data. **Kinds of Record** lists every Modify All and View All on a single kind of
   record. **In Groups** names the permission set groups a holder sits inside, so you know where
   to remove it.
10. Press **Download CSV** under any table.

## Comparing Two

- **People or permission sets, not a mix.** **Compare** is **People** or **Permission Sets**
  (profiles, permission sets and groups). The two sides use the same choice.
- **What is compared.** The same totals **By Person or Permission Set** shows: profile,
  permission sets and groups added together. Read, Create, Edit, Delete, View All and Modify All
  are compared per kind of record; Read and Edit per field. A kind of record one side cannot
  read at all counts as no access.
- **Similarity.** The share of permissions given by both sides out of the permissions given by
  either side, as a whole percentage (100% when both give nothing). It counts kinds of record, not
  fields.
- **Differences Only** is on by default. The counts above each table say how many rows differ.

## The Modify All Report

Modify All Data and View All Data are the broadest permissions in Salesforce: they override
object, field and sharing settings. Author Apex lets its holders write and change Apex code. The
report answers "who holds these, and through what".

- **Data-Wide Access** has one row per profile, permission set or group holding any of Modify All
  Data, View All Data or Author Apex, with a column for each (**Modify All Data**, **View All
  Data**, **Author Apex**), **Active People** (people it is assigned to directly) and **In
  Groups**. Modify All Data always includes View All Data. Author Apex does not, so a holder of
  only Author Apex shows **Yes** in that column alone.
- **Kinds of Record** has one row per kind of record and holder with Modify All or View All on
  it, for standard objects and custom objects alike (**Scope** says which). Modify All always
  includes View All. Holders of Modify All Data or View All Data are left out of this table,
  because they hold it on every kind of record; they are in **Data-Wide Access**.
- **Through what.** A holder that is a permission set inside a group says so under **In Groups**:
  a person may hold it only through that group.
- If more than 2,000 rows qualify, the first 2,000 are listed and the page says the list is cut.

## How Access Is Worked Out

- **A person's access** is the sum of their profile, the permission sets assigned to them, and
  the permission set groups assigned to them. Salesforce adds them together; nothing takes
  access away except a muting permission set inside a group, which Salesforce has already
  applied to the group's total. Access Explorer shows the group's total, and names the
  permission sets inside it that give the access.
- **View All Data and Modify All Data.** A profile or permission set with either lets its holders
  see (or change) every record of every kind, whatever the rows say. Access Explorer shows a
  note naming where it comes from, on **By Person or Permission Set**, and lists it on **By
  Kind of Record**.
- **Records, not just kinds of record.** Access Explorer reports object and field permissions:
  whether a person may open a kind of record at all. Which individual records they see also
  depends on sharing (org-wide defaults, the role hierarchy and sharing rules), which it does
  not report. Use **Sharing Settings** in Setup for those.
- **Fields.** Field access applies only once a person can read the kind of record. Fields
  Salesforce does not let you restrict (such as Name and system fields) say **Always**.
- **Active people only.** People lists and counts include active users only. **By Person or
  Permission Set** can also show an inactive person, marked **Inactive**.

## Large Orgs

Access Explorer reads only what one view needs, when you ask for it:

- **By Person or Permission Set** reads one person's assignments (or one set) and the
  permissions of those sets only.
- **By Kind of Record** counts holders with one summary query, and lists people 50 at a time.
  If more than 2,000 profiles and permission sets give access to one kind of record, the first
  2,000 are listed and the page says the list is cut.

**Compare Two** reads the two sides' access exactly as **By Person or Permission Set** does, and
fields only for the kind of record you choose. The **Modify All Report** reads two things only:
the profiles and permission sets with Modify All Data, View All Data or Author Apex, and the object
permissions with Modify All or View All, up to 2,000 rows.

## Download CSV

**Download CSV** saves its table (every row loaded so far, not only the rows on screen) as a UTF-8 file with a byte-order mark. Text that starts with `=`, `+`, `-` or `@` is
saved with a leading apostrophe, so a spreadsheet never runs it as a formula. The file name is
`Access_Explorer-` and the date. On **By Kind of Record**, press **Show More** until every person
is loaded if you want them all in the file.

## Common Mistakes

**Expecting Access Explorer to change access.** It only reads. Use the [Access page](access.md)
for BarnCRM roles and add-ons, and Setup for everything else.

**Reading "no access" as "cannot see the record".** A person with read access to a kind of
record can still be kept from a particular record by sharing. Access Explorer tells you whether
they can open that kind of record at all.

**Missing people.** Without View All Users you see only the people Salesforce shows you. Give
yourself the BarnCRM Access Manager permission set (Salesforce licenses only) to see everyone.

**Forgetting the Tab Access Check.** Someone given a BarnCRM role in Setup gets the matching tabs
at the next hourly Tab Access Check. If **BarnCRM Permission Sets** says the check is not
scheduled, run **Health Check** and use its **Schedule All Nightly Jobs** fix.

## Related

- [Access](access.md)
- [Org Optimizer](org-optimizer.md)
- [Health Check](health-check.md)
- [Data Dictionary](data-dictionary.md)
