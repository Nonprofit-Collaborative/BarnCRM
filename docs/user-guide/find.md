# Finding People and Records

Most days you only need to find one person or one household. Global search and list views
do that. When you need a precise list (everyone in one city with no email, every household
that gave this year), the **Find** tab builds it, saves it and exports it.

Before you start: global search and list views work for everyone. The **Find** tab needs the
**BarnCRM Find and Export** add-on, and your admin must have turned on the Data Manager
feature. Ask your admin. See [Find and export](../admin-guide/find.md).

Whatever you search or export, you only ever see records and fields your own access allows.
A colleague may see more or fewer rows than you for the same query.

## To Find One Record with Global Search

1. Click the search box at the top of any Salesforce page.
2. Type part of a name, an email address or a phone number.
3. Choose a result, or press Enter to see all results grouped by kind of record.

You should see: the record open in its own tab (in the **BarnCRM** app).

## To Use a List View

1. Open the **Households**, **Organizations** or **Contacts** tab.
2. On **Households** and **Organizations**, the tab shows the list of that name. On
   **Contacts**, pick a list from the list view menu.
3. Click a column heading to sort, or open the list and use Salesforce's list filters.

You should see: the **Households** list with the household name, **Member Count**,
**Informal Greeting** and **Custom Name**; the **Organizations** list with the name, phone and
**Primary Contact**.

## To Build and Run a Query in Find

1. Open the **Data Manager** tab and choose **Open** on the **Find and Export Records** card.
   The **Find** tab opens.
2. In **Object**, choose what to look for, for example **Contact** or **Account**.
3. In **Columns**, move the fields you want from **Available fields** to **Columns, in
   order**. To add a field from a related record, choose it in **Add fields from**.
4. Under **Conditions**, press **Add condition**. Choose a **Field**, an **Operator** (such as
   **equals**, **contains**, **is blank**, **is one of** or **is in the last N days**) and a
   **Value**. Add more conditions the same way.
5. Optional: with two or more conditions, tick **Use custom condition logic** and type, for
   example, `1 AND (2 OR 3)` in **Condition logic**.
6. Choose **Sort by**, **Direction** and **Rows to show** (up to 2,000).
7. Press **Run**.

You should see: a **Results** table and a line such as "200 rows found." If more records
match, the line says "Found the first 200 matching rows. Export to get every matching record."
The table shows 25 rows at a time: press **Show More** under it for the next 25.

Before you choose an object, the page shows only **Object** and **Saved queries** and a short
prompt. **Show Query**, closed at first, holds the query in SOQL. You never need to read it.

## To Keep Only Records That Have (or Lack) Related Records

1. Under **Related records**, press **Add related records**.
2. Choose **Has related records** or **Has no related records**.
3. Choose the **Kind of related record**, for example gifts on a household.
4. Optional: add conditions on those related records.
5. Press **Run**.

You should see: only the records that match. To show related records in a column instead,
use **Related Record Columns** and **Add a Related Record Column**.

## To Count or Total Instead of Listing

1. Build the query, then press **Summarize**.
2. In **Summary**, choose **Count of records**, **Total of**, **Lowest** or **Highest**, and
   for the last three a **Field to measure**.
3. Optional: choose **Group by**.
4. Press **Summarize**.

You should see: a table with one line per group. Blank values show as "(blank)".

## To Save and Share a Query

1. Run the query, type a **Query name**.
2. Optional: tick **Show to everyone who uses Find** to share it.
3. Press **Save**. To make a copy under a new name, open the menu next to **Save** and choose
   **Save As**.

You should see: "Saved" followed by the name. To open it later, choose it in **Saved
queries**. Queries shared with you show the sharer's name, for example "Springfield, no email
(shared by Maria Lopez)". Only the person who saved a query can change, share or delete it.

## To Delete a Saved Query

1. Open the query from **Saved queries**, open the menu next to **Save** and choose **Delete**.
2. In "Delete this saved query?", press **Delete**, or **Keep it** to leave it.

You should see: "Deleted" followed by the name. This cannot be undone. A shared query is
removed for everyone.

## To Export the Results

1. Run the query.
2. Open the **Export** menu and choose **Export to CSV** or **Export to Excel**. Every matching
   record is exported, not only the rows on screen, up to the export row limit your admin set.
3. For a very large export, choose **Export to Files** instead. You can leave the page.

You should see: a file download, and "Exported 1,234 rows." For **Export to Files**: "Export
to Files started. You can leave this page: BarnCRM tells you when the files are ready." When
it finishes, the page lists the files and the bell shows a notification. The files are in
Salesforce **Files**, **Owned by Me**. Delete them there once downloaded.

## To Type a Query Instead (Optional)

1. Press **Type a query**.
2. Type or paste a query in **Query (SOQL)** (SELECT, FROM, WHERE, ORDER BY and LIMIT).
3. Press **Use this query**.

You should see: the builder filled in from your text, ready to run.

## Common Problems

- Problem: "Find needs the Find and Export Records permission. Ask your administrator to
  assign you the BarnCRM Find and Export permission set." You do not have the add-on. Ask your
  admin.
- Problem: "This object is not available to you: ..." Your access does not include that kind
  of record. Choose another, or ask your admin.
- Problem: "This field is not available to you: ... Remove the condition, or ask your
  administrator for access." A shared query uses a field you cannot see. Remove that condition
  and use **Save as** to keep your own copy.
- Problem: "Left out columns you do not have access to: ..." The same, for columns. The query
  still runs without them.
- Problem: "Only the person who saved this query can change, share or delete it. Use Save as
  to keep your own copy." Use **Save as**.
- Problem: "Exported 50000 rows, the export row limit. Narrow the conditions, or ask an
  administrator to raise the limit." Add conditions, or use **Export to Files**.
- Problem: "Fix the conditions marked below, then try again." A condition is incomplete
  ("Choose a field.", "Enter a value.") or the logic is wrong ("The condition logic must use
  every condition."). Fix the marked lines.
- Problem: "Rows to show must be a whole number from 1 to 2000." Change **Rows to show**.
- Problem: fewer rows than a colleague sees. Find uses your own access. This is expected.

## Related

- [Getting around BarnCRM](getting-around.md)
- [People and households](people-and-households.md)
- [Duplicates](duplicates.md)
- Admin Guide: [Find and export](../admin-guide/find.md),
  [Bulk update](../admin-guide/bulk-update.md), [Bulk delete](../admin-guide/bulk-delete.md),
  [Access](../admin-guide/access.md)
