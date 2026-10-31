# ADR-NEXT: The import reads every sheet of a workbook, and headings that name an object

**Status:** Accepted (owner decision)
**Date:** 2026-10-30
**Source:** owner requirements for C-49a (Super Importer: parsing), 2026-10-30. Amends
ADR-0049 ("first sheet, values only, .xlsx only").

## Context

ADR-0049 fixed the workbook reader's scope at one sheet: the first, or one the user picks.
Files from other systems often split one list across sheets (a sheet per year, per region, per
event), and the user had to save each sheet as its own file. Exports from Salesforce and from
other CRMs also name the object in the heading ("Contact.First Name", "Phone (Contact)",
"Contact_Phone"), which the exact field match (R-IT12) never read, and a file is often named
for what it holds ("contacts_2026.xlsx", a "Volunteer Shifts" tab).

## Decision

1. **Every sheet is read, and the user chooses which load.** The reader in
   `lwc/importWizard/xlsx.js` is unchanged; the wizard reads each sheet in tab order through
   `fileSource.js` (one source, file to sheets of rows, so a later source such as C-38 returns
   the same shape). The Check Columns step lists the sheets with their row counts, all sheets
   with rows chosen to start (or the one sheet there is).
2. **Chosen sheets load as one file into one object.** Columns are joined by the field they map
   to ("First Name" on one sheet and "Contact.First Name" on the next are one column); any
   other heading is its own column, blank in rows from sheets without it. Rows keep sheet order,
   and row numbers in results count across the chosen sheets. When the chosen sheets point at
   different objects (by their headings or their names), the step lists each sheet with its
   object and will not go on until the user clears sheets or goes back to choose another
   object. Loading several objects from one workbook is C-49c.
3. **A heading may name an object and a field.** `ImportHeaderParser` (Apex, pure) reads
   `Object.Field`, `Object: Field`, `Object / Field`, `Object | Field`, `Object - Field`,
   `Field: Object`, `Field (Object)` and, only when nothing clearer reads, `Object_Field`,
   never splitting at either underscore of `__`. The whole heading is tried as a field first.
   The object part matches a loadable object's label, plural label or API name (with or
   without `__c` and the namespace); two readings naming different fields name neither.
4. **The object is suggested from the file.** With no object chosen yet, the object is
   suggested from two-part headings, then a sheet's name, then the file's name (its extension,
   digits and the words export and import taken off). It is shown as a suggestion; the user
   can always change it.
5. **Exact matches only.** Every match is exact after the existing normalization (lower case,
   letters and digits only, `ImportColumnLibrary.normalize`). `ImportHeaderParser.match` is
   the single seam where fuzzy matching (approved by the owner 2026-10-30, a later slice) plugs
   in. Nothing that does not match exactly is mapped; it stays Do not load.
6. The people and organizations templates (`ImportColumnLibrary`) are unchanged.

## Alternatives considered

- **Keep one sheet per load.** Rejected: the owner asked for several sheets.
- **SheetJS for several sheets** (ADR-0049's named fallback). Rejected: the in-house reader
  already reads any sheet by name; reading several is a loop, not new parsing.
- **Parse headings in the browser.** Rejected: the object and field spellings come from the
  running user's describe on the server, where the existing field match already lives.

## Consequences

- A workbook's sheets are all inflated when the file is chosen, so a large workbook takes
  longer to open; the existing per-part size limits still apply.
- Row numbers in results and rejected rows count across the chosen sheets, not per sheet.
- C-49b to C-49d build on this: several objects per workbook and fuzzy matching.
