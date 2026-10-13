# Org Optimizer

**Package:** Core
**Decision:** ADR-NEXT `NEXT-org-optimizer-and-data-manager-pages.md`

## 1. What it does

**Org Optimizer** is one page that answers "what in my org needs attention?" It brings
together the checks that used to live in four places: the record checks of the Data Hygiene
tab, the duplicate review from BarnCRM Settings, field utilization, and Health Check. Each one
is a section of the page, and nothing in a section runs until you open it, so the page itself
opens quickly however large your database is.

| Section | What it answers | Who sees it |
|---|---|---|
| **Overview** | What each section is for, with a button to open it. | Everyone who can open the page |
| **Data quality** | Which records need tidying up: people with no household, empty households, orphaned memberships and addresses, incomplete or failed default addresses. Each check has **Open in Find**. See [Data hygiene](data-hygiene.md). | Anyone with **Find and Export Records** |
| **Duplicates** | Which people and households are in your database twice. Scan, review each pair, merge two households, or say a pair is not the same. See [Duplicates](duplicates.md). | Administrators |
| **Field utilization** | How often each field of a kind of record is filled in, by record type, with saved counts for trends. See [Field utilization](field-utilization.md). | Administrators |
| **Health Check** | Whether BarnCRM is set up the way it should be, with a fix for some findings. Runs only when you press **Run Health Check**. See [Health Check](health-check.md). | Administrators |

"Administrators" means anyone with the **Manage BarnCRM Settings** permission, which the
**BarnCRM Admin** role carries. A section you cannot use is not shown.

Org Optimizer never changes a record by itself. Every change is a button you press in a
section, and each section's own page in this guide says what that button does.

## 2. How to turn it on

There is nothing to turn on.

1. Open the **BarnCRM** app and choose the **Org Optimizer** tab. (It is the tab that used to
   be called **Data Hygiene**; bookmarks to it still work.)
2. The **BarnCRM Admin** role and the **BarnCRM Find and Export** permission set both give
   the tab. Staff with Find and Export see **Overview** and **Data quality**; administrators
   see every section.
3. Duplicate review also needs the **BarnCRM Duplicate Review** permission set, which only
   users with a Sales Cloud or Service Cloud license can have (see [Duplicates](duplicates.md),
   How to turn it on). Without it the Duplicates section says so.

Duplicate review no longer has a panel in **BarnCRM Settings**. Under **Households**, the
**Duplicates** row has an **Open** button that takes you to this page.

## 3. A five-minute walkthrough (as Maria)

Start from the sample data (see [Sample data](sample-data.md)).

1. Open the **Org Optimizer** tab. **Overview** lists the sections with one line each.
2. Choose **Data quality**. The six checks count as the section opens. **People with no
   household** says **0** on fresh sample data.
3. Choose **Field utilization**. In **Kind of record** choose **Account**, and watch the table
   fill. Sort by **Filled** to see the fields nobody uses.
4. Choose **Duplicates** and press **Scan for duplicates**. The scan runs in the background;
   come back in a minute to see any pairs.
5. Choose **Health Check** and press **Run Health Check**. The findings appear, most serious
   first, each with what to do.
6. Go back to **Data quality** and press **Recount**: the counts are fresh each time you ask.

## 4. Why sections load only when opened

Some checks read every person or every household, and Health Check reads your org's setup.
On a large database that takes seconds. Opening the page runs none of it: each section runs
the first time you open it, and Health Check runs only when you press its button. Switching
back to a section you already opened shows what it found, and each section has its own
**Recount**, **Count again** or **Run** button for fresh numbers.

## 5. Common mistakes

- **Looking for the Data Hygiene tab.** It is the same tab, renamed **Org Optimizer**. The
  record checks are under **Data quality**.
- **Looking for duplicates in BarnCRM Settings.** Duplicate review moved here. The
  **Duplicates** row under **Households** in BarnCRM Settings opens this page.
- **Seeing only two sections.** The others are for administrators. Ask whoever set up your
  org for the **BarnCRM Admin** role on the **Access** page.
- **Expecting Health Check to run as the page opens.** It runs when you press **Run Health
  Check**, here, or on **BarnCRM Settings > Health**.

## Field reference

Org Optimizer adds no object and no field. Each section reads and writes what its own page in
this guide lists.
