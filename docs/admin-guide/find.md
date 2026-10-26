# Find and export

## 1. What it does

**Find** answers "show me exactly these records" without a report type, Setup or a query
language. You pick one object (Households, Contacts, Gifts with the Giving module, or any
other object you can see), choose the columns, add conditions such as "Status is one of
Received, Pledged" or "Gift Date is in the last 90 days", choose a sort order and how many
rows to show, and press **Run**. The results appear in a table. You can then:

- **Export to CSV**: every matching record, not only the rows on screen, up to the export
  limit set in BarnCRM Settings. The file is UTF-8 with a byte-order mark, so Excel opens
  names with accents correctly. The file is named for the object and today's date in your
  own time zone, for example `Gift__c-2026-10-13.csv`.
- **Export to Excel**: the same rows as an Excel workbook (.xlsx).
- **Save** the query under a name, to run it again next month.
- **Share** a saved query, so everyone else who uses Find can open it.
- **Summarize**: count, total, lowest or highest value, grouped by a field.
- **Edit in the table**, if you may also bulk update: change values in the results and save
  them, with an undo (section 7.6).

Find changes a record only when you edit it in the table and press **Save**. Everything it
shows, and everything it exports, is read with your own access: a record you cannot open, or
a field you cannot see, is not in the results and is not offered as a column or a condition. A
shared query works the same way for the person who opens it: they see the records their own
access allows, which may be fewer than you see.

Below the conditions, Find shows the query it will run, in Salesforce's query language
(SOQL), read only. You never need to read it. It is there so someone who knows SOQL can check
exactly what Find does, or copy it into another tool. Someone who prefers typing can type a
query in the same language instead of building it (section 7.4); Find reads it into the
builder and checks it exactly as if it had been built by hand.

## 2. How to turn it on

1. Find needs the **Find and Export Records** permission. The **BarnCRM Admin** role has it.
   To let a staff member find and export without making them an admin, assign them the
   **BarnCRM Find and Export** permission set (BarnCRM Settings, Access, Extra Permissions), alone or
   alongside their usual role. The permission opens the tool and nothing else: it never
   grants access to a record or field the person could not already see.
2. Open the **Find** tab in the BarnCRM app.
3. Optional: open **BarnCRM Settings**, choose **Import**, and set **Export row limit**
   (default 50,000). An export stops at this many rows and says so. The limit is a
   convenience stop that keeps a file a size a spreadsheet opens, not a security control: a
   person can still read every record their access allows, in several exports or other tools.
   To keep data from someone, take away their access to it.

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
   A date and time is written as `2026-01-05 09:30:00` in your own Salesforce time zone, the
   time the table shows, and the workbook from **Export to Excel** uses the same clock. A text
   value that starts with = + - or @ (such as `+44 20 7946 0000`) is written with a single
   quote in front, so a spreadsheet never runs it as a formula; BarnCRM's import takes that
   one quote off again.
7. Press **Save**, name it "Springfield, no email", and tick **Show to everyone who uses
   Find** so the volunteer coordinator can run it too.

## 4. Conditions

Conditions use the same filter builder as rollups. Each condition is a field, an operator and
a value; the operators offered depend on the field:

| Field type | Operators |
|---|---|
| Text, email, phone, URL | equals, does not equal, contains, does not contain, starts with, is one of, is not one of, is blank, is not blank |
| Picklist | equals, does not equal, is one of, is not one of, is blank, is not blank |
| Multi-select picklist | is exactly, is not exactly (the whole set of chosen values), is blank, is not blank |
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
- **Delete** asks first, naming the query: press **Delete** in the box to remove it, or **Keep
  it** to leave it as it is. When the query is shared, the box says that deleting it removes
  it for everyone who uses Find. A deleted query cannot be brought back.
- The SOQL box below the conditions updates when you pause typing, not on every key, so typing
  a value costs one check.
- The **Saved queries** list shows your own queries first, then the ones shared with you,
  with the name of the person who shared each. The list holds up to 500 queries; your own
  are always counted first, so shared queries never push one of yours off it.
- A shared query that names a field someone cannot see opens for them with that column left
  out, and a notice names it; a condition on such a field opens marked, and the query does not
  run for them until it is removed from their copy.
- Another page, such as the Data Hygiene console, can open Find on a saved query. Find opens
  that query and runs it straight away, as if you had chosen it from the list and pressed
  **Run**. A query you cannot open (deleted, or not shared with you) is simply not opened.

## 6. Common mistakes

- **"This object is not available to you."** Your access does not include reading that
  object. Ask whoever manages access in your org.
- **Fewer rows than a colleague sees.** Find uses each person's own access and sharing. This
  is deliberate; it is not a fault.
- **The export stopped early.** It reached the export row limit. Narrow the conditions, or ask
  an admin to raise **Export row limit** (at most 500,000). For a large export, use **Export to
  Files** (section 7.5a), which does not depend on your browser. Exports above 500,000 rows
  belong in Data Loader.
- **Contains on a number.** Numbers offer comparisons, not contains. Use "is at least" and
  "is at most" together for a range.
- **A date field shows the right day in the table but a condition seems a day off.** Date and
  time fields are compared in your own time zone, as Salesforce shows them.

## 7. Advanced Find

### 7.1 Related records in conditions

Under **Related records**, press **Add related records** to keep only the records that have,
or do not have, related records matching conditions of their own. For example, on Account:

- **Has related records**, **Gifts (Household)**, with the condition **Gift Date** is this
  year: every household with a gift this year.
- **Has no related records**, **Gifts (Household)**, with no conditions: every household that
  has never given.

The list offers each kind of record that points at the object, with the lookup it points
through in brackets, because one object can point at another in more than one way. You can add
two related-records conditions to a query; they are combined with the other conditions by AND.

### 7.2 Related record columns

Under **Related record columns**, choose a kind of related record and up to five of its
fields, to show the most recent related records in one column. For example, on Account, the
column **Contacts** with **Full Name** and **Email** shows each household's members as
"Ana Ruiz, ana@example.org; Ben Ruiz, ben@example.org". A column shows at most 10 related
records per row, newest first, and you can add two such columns. Exports write the same text.

### 7.3 Summarize

Press **Summarize** to count or total the matching records instead of listing them:

1. Choose **Count of records**, **Total of**, **Lowest** or **Highest**, and for the last three
   the number or date field to measure.
2. Optional: choose **Group by**, a field of the query's object such as **Status** or
   **Gift Date**. Only fields Salesforce can group by are offered, so currency, number and
   long text fields are not. Leave it empty for one line.
3. Press **Summarize**. A table shows one line per group, with the blank group shown as
   "(blank)".

Summaries use the same conditions and your own access. They cover at most 20,000 matching
records and show at most 2,000 groups; for more, narrow the conditions or use a report.

### 7.4 Typing a query

Press **Type a query** to type or paste a query instead of building it, for example:

```
SELECT Name, BillingCity FROM Account
WHERE BillingCity = 'Springfield' AND (Type = 'Household' OR Type = null)
ORDER BY Name LIMIT 500
```

Press **Use this query**. Find reads the text into the builder (object, columns, conditions,
sort and rows to show), and from there it is an ordinary Find query: it is checked against
your access, it runs with every value kept apart from the query, and it can be saved and
shared. Find never sends the text itself to Salesforce. **Type a query** starts with the query
shown below the conditions, so you can change a built query as text, and the other way round.

What a typed query may hold:

| Part | What it accepts |
|---|---|
| `SELECT` | Fields and related fields (`Household__r.Name`), up to 20. Related record columns as `(SELECT Name, Amount__c FROM Gifts__r LIMIT 5)`. |
| `FROM` | One object. |
| `WHERE` | `=`, `!=`, `<`, `<=`, `>`, `>=`, `IN (...)`, `NOT IN (...)`, `= null`, `!= null`, `LIKE 'text%'` (starts with), `LIKE '%text%'` (contains), `THIS_YEAR`, `LAST_YEAR`, `LAST_N_DAYS:n`, with AND, OR, NOT and brackets. Brackets are needed where AND and OR are mixed. Related records as `Id IN (SELECT Household__c FROM Gift__c WHERE ...)` or `Id NOT IN (...)`, joined to the rest with AND. |
| `ORDER BY` | One field, `ASC` or `DESC`. |
| `LIMIT` | 1 to 2,000. |

Anything else (GROUP BY, functions, other LIKE patterns, a second sort field) is refused with
a message pointing at the words it could not read. Use **Summarize** for totals.

### 7.5 Export to Excel

**Export to Excel** reads the same rows as **Export to CSV**, up to the same export row limit,
and downloads an Excel workbook with one sheet, a header row of column labels, numbers as
numbers and dates as dates (a date and time as the clock reads in your Salesforce time zone).
A very large export can take a while to build in the browser; for more than a few tens of
thousands of rows, CSV is faster. One Excel cell holds at most 32,767
characters, so a longer text value is cut to that length in the workbook; export to CSV to
keep it whole.

### 7.5a Export to Files

**Export to Files** runs the export on the Salesforce server instead of in your browser, for
exports too large for a browser tab to hold (a mailing list of a few hundred thousand donors,
for example). You can close the page while it runs.

1. Run the query and press **Export to Files**. The export starts in the background and the
   page shows its progress.
2. It reads every row the query matches, up to the **Export row limit**, in record ID order,
   with your own access, and writes them as CSV in the same format as **Export to CSV**. Columns
   of related records listed under a row (section 7.1's related lists) are not included.
3. A large export is split into several files of up to 50,000 rows each, every one with the
   header row, named for the object, the date and the part, for example
   `Contact-2026-10-13-a1b2c3-part-2.csv`. They are saved to your Salesforce Files (**Files**,
   **Owned by Me**); nobody else can see them unless you share them.
4. When it finishes, the page lists the files with a link to each, and BarnCRM sends you a
   notification (the bell) that opens the first file, if job notifications are on.

The files count against your org's file storage. Delete them from Files once you have
downloaded them.

**The export row limit is enforced on the server** for an export to Files: it never writes
more rows than the limit, whoever asks. For **Export to CSV** and **Export to Excel** the limit
is where your browser stops reading; treat it as a convenience, not a control on what people
with Find can read, which is always only what their own access allows.

### 7.6 Editing in the table

If you hold the **Bulk Update Records** permission as well as Find's, the columns you may edit
show a pencil after a query runs. Double-click a cell (or press Enter on it), change the value,
and press **Save** at the foot of the table. Find saves up to 200 changed records at a time.

- Only the query object's own fields that a bulk update may change can be edited: not fields
  of a related record, not formula or system fields, and not the fields BarnCRM keeps itself
  ([Bulk update](bulk-update.md), section 4).
- Each save runs with your access, and your organization's validation rules and automation
  run, as on any save. A record that is refused is marked in the table with the reason; the
  rest still save.
- Each save is recorded like a bulk update. It appears on the **Data Manager** tab under
  **Data jobs**, and can be undone there within the same window as an import. The
  undo puts back each value nobody has changed since.

## 8. What Find does not do (yet)

An export to Files runs once, when you press it: scheduled or recurring exports and sending a
file elsewhere are planned for a later release (C-38). Totals are a summary table, not a chart. To change many records to the same
value at once, run a query and press **Bulk update**, shown to people who also hold the Bulk
Update Records permission. See [Bulk update](bulk-update.md). To delete every record a query
returns, press **Bulk delete**, shown only to people who hold the Bulk Delete Records
permission. See [Bulk delete](bulk-delete.md).

## Field reference

| Where | Field | What it holds |
|---|---|---|
| Saved Query | Name | The name you gave the query. |
| Saved Query | Object | The API name of the object the query reads. |
| Saved Query | Query | The query document: object, columns, conditions, sort and row count. Written only by Find. |
| Saved Query | Shared | Whether everyone who uses Find can open it. |
| BarnCRM Settings, Import | Export row limit | The most rows one export writes. Default 50,000. |
