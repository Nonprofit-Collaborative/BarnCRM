# The Mapper and Saved Maps

**Package:** Core
**Decision:** ADR-NEXT `NEXT-reusable-mapper.md` (design: `docs/architecture/integration-hub-design.md`, Section 2)

## 1. What It Does

The **Mapper** is one screen for saying where each value goes: from the columns of a file, the
fields of a record, or a piece of JSON data another app sends, into the fields of a kind of
record or the keys of a JSON body. A finished map is saved as a **Map** with a name, and any
BarnCRM tool that understands maps can use it: today **Super Importer** (copy a map in with
**Use a Saved Map**, or save a template's columns with **Save as Map**), and the tools of the
BarnCRM Connector module when it is installed.

The screen has three panes side by side on a wide screen and one under the other on a phone:

1. **From**: every source value, each with two or three real examples from your sample (a
   file's first rows, a record you choose, or JSON you paste). JSON is shown in plain words:
   `profile.email` reads **profile, email**.
2. **To**: the fields of the kind of record the map fills, in three groups: **Required** (a new
   record needs them), **Suggested** (fields that look like one of your sources) and **All
   Fields**. A filled field reads as one sentence, for example "Email gets profile, email, then
   remove extra spaces, then all lower case."
3. **Preview**: the record (or JSON body) your sample would produce, value by value. A value
   with a problem has a badge: **required but empty**, **too long**, **not a number**, **not a
   date**, **not true or false**, **not in the picklist**, **no parent found** or **several
   parents found**.

What makes it quick:

- **Matched for you.** When the sources and fields are in, the Mapper fills every field whose
  name is the same as a source (ignoring capitals, spaces and punctuation). It then makes a best
  guess for the sources left, from words the names share, and marks each guess **Best Guess,
  Check It** until you press **Accept** or choose another source. **Match Fields** runs it again.
- **Drag or pick.** Drag a source from **From** onto a field in **To**, or press **Pick** on the
  field and choose the source from a list you can type in. By keyboard: tab to a source, press
  Space, move with the arrow keys and press Space again on the field. Dragging is never the only
  way.
- **Changes in plain words.** **Changes** on a field opens the same steps Super Importer and
  Super Transformer use: remove extra spaces, all capitals, all lower case, capitalize each
  word, find and replace, value when empty, add other columns, read as a date, map values, if
  then, keep part, first characters, last characters, shift a date, today's date and format
  digits. There is no formula language.
- **Fixed values and defaults.** **Always Use** puts the same text in a field for every record;
  **When Blank, Use** fills a field only when the source is blank.
- **Lookups in one sentence.** On a lookup field, choose **Find the Parent By** and **When No
  Parent Is Found**: "Finds the Account whose Name equals order, company; when none is found:
  leave it empty" (or **Reject the row**).
- **Matching in one sentence** (when the map fills a record), under **Matching**: "When Email
  matches, the record is updated; when several match, reject the row; when none match, create
  a record", followed by what that choice risks.
- **Check Before Running** runs the map over up to 200 samples on the server (every file row up
  to 200, the chosen record, or each item of a pasted JSON list) and lists the problems by
  field, with how many samples have each and which ones. Nothing is saved.

## 2. How to Turn It On

There is nothing to turn on. The Mapper needs **Manage BarnCRM Settings**, which the
**BarnCRM Admin** role has: it is how maps are made, changed, renamed and deleted. Maps are
org-wide: every administrator sees and may change every map.

The Mapper is reached from **Data Manager**: the **Maps** tile in **Bring Data In**. It opens
on that page, with **Back to Data Manager** above it.

A map that fills a record offers the kinds of record Super Transformer may change, and only the
fields you may edit. Fields are checked against your access each time a map is opened,
previewed or used, so a map is never a way past a field you cannot reach.

## 3. A Five-Minute Walkthrough (as Maria)

Maria gets a JSON export of event sign-ups and wants it to fill Contacts.

1. Open **Data Manager** and select **Maps**. Press **New Map**.
2. Type the name `Event sign-ups to Contacts`.
3. Under **From**, choose **JSON Data**, paste one sign-up (or a list of them) into **Sample
   JSON** and press **Use This Sample**. The **From** pane lists **profile, email**, **profile,
   first_name** and so on, each with its value.
4. Under **To**, keep **A Record** and choose **Contact**. The Mapper matches what it can:
   **Email** gets **profile, email**; **Last Name** gets **profile, last_name** with the badge
   **Best Guess, Check It**. Press **Accept** beside it.
5. On **Email**, press **Changes**, add **Remove extra spaces** and **All lower case**. The
   sentence now reads "Email gets profile, email, then remove extra spaces, then all lower
   case." The **Preview** shows the email as it will be saved.
6. On **Lead Source**, type `Event sign-up` in **Always Use**.
7. Under **Matching**, set **Match Existing Records By** to **A field** and **Field to Match
   By** to **Email**; keep **Reject the row** when several match and **Create a record** when
   none match.
8. Press **Check Before Running**. It reports, for example, "Mailing Postal Code: too long in
   2 samples (samples 3, 7)." Add a **First characters** step to fix it, and check again.
9. Press **Save Map**.

## 4. Managing Maps

The **Maps** panel lists every map with what it fills (a kind of record, a JSON body, or people
and organizations for a map saved from a people template).

- **Open** shows the map in the Mapper. **Save Map** changes it in place. Before a change is
  saved, the Mapper lists every tool that uses the map (for example "Used by 3 recipes"), from
  **Where Used**, so you know what the change reaches.
- **Rename** gives a map a new name; names are unique among maps, ignoring capitals.
- **Delete** removes a map after a confirmation. A tool that copied the map keeps its copy.
- **Where Used** (Data Dictionary, Field Utilization or the Record Inspector) lists a map that
  names a field or a kind of record, under **Map**, so a field is never retired while a map
  still fills it.

Maps are kept as rows of **Saved Transform** with the kind **Map**; Super Transformer's
**Saved Step Lists** never shows them, and the Maps panel never shows a step list.

## 5. Super Importer: Use a Saved Map and Save as Map

On Super Importer's **Check Columns** step (see [Importing](importing.md), section 3):

- **Use a Saved Map**: choose a map and press **Use Map**. Each file column whose name matches a
  map column (capitals and spaces ignored) takes the map's field, changes and lookup. Columns the
  map does not name keep their choice. A message says how many columns were set, and how many of
  the map's columns were not used (the file has no such column, or this template cannot load
  that field). The template keeps its own copy: changing the map later does not change it.
- **Save as Map**: type a name and press **Save as Map**. The columns you see (except **Do not
  load**) are saved as a new map, with their changes and lookups. Row rules, matching and values
  for every row stay with the template.

## 6. Common Mistakes

- **"A map named ... already exists."** Names are unique among maps. Choose another, or open the
  existing map and change it.
- **A field shows "You cannot edit this field or it is gone."** The map names a field that was
  deleted or that you cannot edit. Choose another field or remove the line; the rest of the map
  still works.
- **Everything is flagged "No record found".** The lookup's field holds something other than
  what the source sends (an ID where a name is sent, for example). Change the lookup's field.
- **The preview is empty.** There is no sample yet: choose a file, a record or paste JSON.
- **Save Map is greyed out.** A best guess is waiting: press **Accept** on it, pick another
  source, or press **Remove**. A guess is never saved unchecked.

## Field Reference

| Where | Field | What it holds |
|---|---|---|
| Saved Transform | Kind | **Map** for a saved map; **Step List** for a Super Transformer step list. |
| Saved Transform | Definition | The map document (canonical model R-MAP1). |
| Saved Transform | Object | The kind of record the map fills; blank for a JSON body or a people map. |
