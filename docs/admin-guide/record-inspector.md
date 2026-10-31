# Record Inspector

**Package:** Core
**Feature:** C-55 (plan Section 6.1.5, decision D-156)

## What It Does

The **Record Inspector** shows every field of one record that you are allowed to read, in one
searchable table, including the fields the page layout leaves out. For each field it shows:

| Column | What it shows |
|---|---|
| **Field** | The field's label |
| **API Name** | The name the field goes by in reports, flows, imports and code, with a **Copy** button |
| **Type** | The field type, such as text, picklist, currency or reference (a lookup) |
| **Value** | The value this record holds, or nothing when the field is empty |

Use it to answer "where does this value live?", "what is that field called in an import file?"
and "is that field really empty, or just not on the page?"

It is read only. It never changes a record, and it shows you only what your own access to the
record and its fields already lets you see: a field hidden from you by field security is not
listed, and a record you cannot open cannot be inspected.

A few things are left out because they cannot be shown as text: files stored in a field, and the
combined address and location fields (their separate parts, such as street and city, are listed
as fields of their own). A value longer than 2,000 characters is cut there and marked
**Shortened**.

## How to Turn It On

You need the BarnCRM Admin role (the BarnCRM Admin permission set, which carries the Manage
BarnCRM Settings permission). Nobody else sees the component. There is nothing to schedule and
no setting to change.

BarnCRM already puts it in the right column of the Contact and Account record pages that
install with Core. Only people with the BarnCRM Admin role see it. To add it to other pages:

1. Open any record page and choose **Edit Page** from the gear menu.
2. From the component list, drag **Record Inspector** onto the page, in a side column or a tab.
3. Click **Save**, and activate the page if it is not already active.

You can add it to the record page of any kind of record, yours or BarnCRM's.

## How to Use It

1. Open a record whose page has the Record Inspector. The card is collapsed and has read nothing
   yet.
2. Click **Inspect This Record**. The table lists every field you can read, sorted by label,
   with a count such as "120 fields".
3. Type in **Search Fields** to narrow the list. It matches the label, the API name, the type
   and the value, and ignores capital letters.
4. Click **Copy** beside an API name to copy it, ready to paste into an import file, a flow or a
   report filter.
5. Click **Open in Setup** beside a field to open that field's page in Object Manager in a new
   tab, where you can see its definition, help text and field-level security.
6. Click **Open in Find** above the table to open Find with this kind of record already chosen,
   ready to build a query on it.
7. Click **Refresh** to read the record again after an edit.

## What Can Go Wrong

- **The card says you need the Manage BarnCRM Settings permission.** Ask a BarnCRM Admin to
  assign you the BarnCRM Admin permission set.
- **A field you expect is not listed.** Field security hides it from you. Ask the person who
  looks after profiles and permission sets whether you should be able to read it.
- **The table says it shows only part of the fields.** A kind of record with a very large number
  of readable fields (over 2,000) is cut there. Search for the field you want in Setup instead.
