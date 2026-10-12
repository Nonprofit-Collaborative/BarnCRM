# Find and export

## 1. What it does

**Find** answers "show me exactly these records" without a report type, Setup or a query
language. You pick one object (Households, Contacts, Gifts with the Giving module, or any
other object you can see), choose the columns, add conditions such as "Status is one of
Received, Pledged" or "Gift Date is in the last 90 days", choose a sort order and how many
rows to show, and press **Run**. The results appear in a table. You can then:

- **Export to CSV**: every matching record, not only the rows on screen, up to the export
  limit set in BarnCRM Settings. The file is UTF-8 with a byte-order mark, so Excel opens
  names with accents correctly.
- **Save** the query under a name, to run it again next month.
- **Share** a saved query, so everyone else who uses Find can open it.

Find never changes a record. Everything it shows, and everything it exports, is read with
your own access: a record you cannot open, or a field you cannot see, is not in the results
and is not offered as a column or a condition. A shared query works the same way for the
person who opens it: they see the records their own access allows, which may be fewer than
you see.

Below the conditions, Find shows the query it will run, in Salesforce's query language
(SOQL), read only. You never need to read it. It is there so someone who knows SOQL can check
exactly what Find does, or copy it into another tool. Find does not accept typed SOQL.

## 2. How to turn it on

1. Find needs the **Find and Export Records** permission. The **BarnCRM Admin** role has it.
   To let a staff member find and export without making them an admin, assign them the
   **BarnCRM Find and Export** permission set (Setup, Users, Permission Sets), alone or
   alongside their usual role. The permission opens the tool and nothing else: it never
   grants access to a record or field the person could not already see.
2. Open the **Find** tab in the BarnCRM app.
3. Optional: open **BarnCRM Settings**, choose **Import**, and set **Export row limit**
   (default 50,000). An export stops at this many rows and says so.

## 3. A five-minute walkthrough (as Maria)

Maria wants every household in Springfield that has no email address on its primary contact,
to send them a letter.

1. Open **Find**. In **Object**, choose **Account**.
2. In **Columns**, move **Account Name**, **Billing City** and **Billing Postal Code** to the
   right. To add a field from a related record, choose the lookup in **Add fields from** (for
   example **Primary Contact**) and its fields appear in the list as "Primary Contact > Email".
   Add **Primary Contact > Email**.
3. Under **Conditions**, press **Add condition**. Choose **Billing City**, **equals**, and type
   **Springfield**. Add a second condition: **Primary Contact: more fields**, then **Email**,
   **is blank**.
4. In **Sort by**, choose **Account Name**, **Ascending**. Leave **Rows to show** at 200.
5. Press **Run**. The table shows the first 200 households. The line above it says how many
   rows are shown.
6. Press **Export to CSV**. Find reads every matching household, in pages, and downloads one
   file. If there are more than the export row limit, the file stops there and Find says so.
7. Press **Save**, name it "Springfield, no email", and tick **Show to everyone who uses
   Find** so the volunteer coordinator can run it too.

## 4. Conditions

Conditions use the same filter builder as rollups. Each condition is a field, an operator and
a value; the operators offered depend on the field:

| Field type | Operators |
|---|---|
| Text, email, phone, URL | equals, does not equal, contains, does not contain, starts with, is one of, is not one of, is blank, is not blank |
| Picklist | equals, does not equal, is one of, is not one of, is blank, is not blank |
| Number, currency, percent | equals, does not equal, is less than, is at most, is greater than, is at least, is blank, is not blank |
| Date, date and time | the number operators, plus is this year, is last year, is in the last N days |
| Checkbox | equals True or False |
| Lookup | equals, does not equal, is one of, is not one of, is blank, is not blank (by record Id) |

- **Fields on a related record.** Choose "*Lookup*: more fields" in the field list to pick a
  field on the related record, up to two lookups away (a gift's donor's household, for
  example).
- **Is one of** on a text field takes one value per line.
- **Is this year** and **is last year** are calendar years. **Is in the last N days** counts
  today and the N days before it.
- **Condition logic.** With two or more conditions, tick **Use custom condition logic** to
  combine them with AND, OR, NOT and brackets, for example `1 AND (2 OR 3)`. Every condition
  must appear in the logic.
- A condition that is incomplete, or a value that does not fit the field, is marked in place
  and the query does not run until it is fixed.

## 5. Saved and shared queries

- **Save** stores the object, columns, conditions, sort and row count under a name. Saving
  again with the same query open updates it; **Save as** makes a copy under a new name.
- **Show to everyone who uses Find** shares the query (read only) with every user in the org
  who can use Find. Untick it to stop sharing. Only the person who saved a query can change,
  share or delete it; anyone it is shared with can open it, run it, and save their own copy.
- The **Saved queries** list shows your own queries first, then the ones shared with you,
  with the name of the person who shared each.
- A shared query that names a field someone cannot see opens with that condition or column
  marked, and does not run for them until it is removed from their copy.

## 6. Common mistakes

- **"This object is not available to you."** Your access does not include reading that
  object. Ask whoever manages access in your org.
- **Fewer rows than a colleague sees.** Find uses each person's own access and sharing. This
  is deliberate; it is not a fault.
- **The export stopped early.** It reached the export row limit. Narrow the conditions, or ask
  an admin to raise **Export row limit**. Exports above a few hundred thousand rows belong in
  Data Loader.
- **Contains on a number.** Numbers offer comparisons, not contains. Use "is at least" and
  "is at most" together for a range.
- **A date field shows the right day in the table but a condition seems a day off.** Date and
  time fields are compared in your own time zone, as Salesforce shows them.

## 7. What Find does not do (yet)

Typed SOQL, subqueries of child records ("households with no gifts"), totals and groupings,
XLSX export, editing results in the table and exports run on the server are planned for a
later release (C-36). Changing many records at once is **Bulk update** (C-35), which starts
from a Find query.

## Field reference

| Where | Field | What it holds |
|---|---|---|
| Saved Query | Name | The name you gave the query. |
| Saved Query | Object | The API name of the object the query reads. |
| Saved Query | Query | The query document: object, columns, conditions, sort and row count. Written only by Find. |
| Saved Query | Shared | Whether everyone who uses Find can open it. |
| BarnCRM Settings, Import | Export row limit | The most rows one export writes. Default 50,000. |
