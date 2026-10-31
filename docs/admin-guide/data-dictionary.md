# Data Dictionary

**Package:** Core
**Feature:** C-52 (plan Section 6.1.1 item 13, decision D-154)

## What It Does

The **Data Dictionary** section of **Org Optimizer** documents your data model in one table.
Choose one or more kinds of record, and it lists every field you can see, with:

| Column | What it shows |
|---|---|
| **Object** | The kind of record's label (the CSV adds an **Object API Name** column) |
| **Field** and **API Name** | The field's label and its API name |
| **Type** | The field type, such as text, picklist, currency or reference (a lookup) |
| **Length** | The most characters a text field holds |
| **Precision** | Digits for a number, currency or percent field, as total digits and decimal places (for example 18,2) |
| **Required** | Whether a record cannot be saved without a value |
| **Unique** | Whether the field's values must be unique |
| **External ID** | Whether the field is an external ID |
| **Custom** | Whether the field was created, rather than supplied by Salesforce |
| **Picklist Values** | The active values of a picklist, separated by semicolons |
| **Help Text** | The field's help text |
| **Formula** | The formula of a formula field |
| **Related To** | The kind of record a lookup points to |
| **Fill Rate** | Optional: the share of records with the field filled in (see below) |

It reads only what Salesforce reports about the fields. It never changes a record, field or
setting, and it does not list flows, triggers or other automation.

**Descriptions are not included.** A field's Description (the internal note in Setup) is not
available to this kind of read, so the dictionary shows Help Text instead. Fill in Help Text
where you want a field explained to people.

## How to Turn It On

You need the BarnCRM Admin role (the BarnCRM Admin permission set, which carries the Manage
BarnCRM Settings permission). It shows you the **Data Dictionary** section of the **Org
Optimizer** tab. Nobody else sees it. There is nothing to schedule and no setting to change.

## A Five-Minute Walkthrough

Start from the sample data (see [Sample data](sample-data.md)).

1. Open the **Org Optimizer** tab and choose **Data Dictionary**.
2. **Kinds of Record** starts with Core's data objects (such as Address and Relationship) plus
   Account and Contact chosen. Objects from the modules you installed are in **Available**:
   add the ones you want. For this walkthrough, move everything out of **Selected** except
   **Account**, using the arrows.
3. Press **Build Dictionary**. The table fills with Account's fields, sorted by label, and the
   page reads, for example, "Described 1 of 1 kinds of record."
4. Find **Website**: its **Type** is url, **Length** is 255, and **Custom** is No. Find a field
   with a Yes in **Custom**, such as **Is Organization**: its **Formula** column shows the
   formula.
5. Tick **Include Fill Rates** and press **Build Dictionary** again. A **Fill Rate** column
   appears, with the percentage of Account records that have each field filled in.
6. Press **Download CSV**. The file opens in a spreadsheet with the same columns.

## What Is Listed

- **Kinds of records.** The list offers the same kinds of record Field Utilization and Find do:
  everything you can open, with Salesforce's own system tables and settings left out.
- **Fields.** Every field you have field-level security access to read. A field hidden from you
  is not listed, so an administrator who can see everything gets the full dictionary.
- **Required** means a person must give a value when creating a record. Fields Salesforce sets
  itself, and fields with a default, are not marked required.
- **Picklist Values** lists the values you can choose today, by their API value, in the order
  Setup shows. A very long list is cut at 4,000 characters.
- **Order.** Kinds of record appear in the order of the picker (by label); fields within a kind
  of record are sorted by label.

## Fill Rates

**Include Fill Rates** reuses [Field utilization](field-utilization.md): the same counting, the
same limits, and the same wait. For each kind of record, the page counts the fields a chunk at a
time, then shows one **Fill Rate** per field (across record types). It adds time in proportion to
the number of records and fields, so leave it off when you only want the structure.

- A kind of record with more than 1,000,000 records is not counted. Its fill rates stay blank and
  the page names it.
- A kind of record with no records has blank fill rates.
- A field Field Utilization does not count (formulas, checkboxes, automatic numbers) has a blank
  fill rate.
- A long text field's fill rate is for the 200 most recently changed records, as in Field
  Utilization.
- Fill rates are not saved. To keep a count for trends, use **Save Utilization Snapshot** in
  Field Utilization.

## Download CSV

**Download CSV** saves what the table shows (every row, not only the page you can see) as a
UTF-8 file with a byte-order mark, so Excel reads accents correctly. Text that starts with
`=`, `+`, `-` or `@` is saved with a leading apostrophe, so a spreadsheet shows it as text and
never runs it as a formula. The file name is `Data_Dictionary-` and the date.

Saving the file to the **Files** tab is not offered: the export-to-Files service writes the
results of a Find query, not a table the page built.

## Common Mistakes

**Expecting every field.** The dictionary lists what you can read. If a field you expect is
missing, check your field-level security, or build the dictionary as an administrator who can see
it.

**Turning on Fill Rates for every object.** With dozens of kinds of record chosen, fill rates
count each one in turn. Choose the kinds of record you care about first.

**Looking for descriptions or automation.** Field descriptions, flows and triggers are outside
what this section reads. Use Setup, or the Unused Setup section, for those.

## Related

- [Org Optimizer](org-optimizer.md)
- [Field utilization](field-utilization.md)
- [Find and export](find.md)
