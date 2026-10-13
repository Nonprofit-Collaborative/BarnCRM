# Importing

## 1. What it does

Importing loads a spreadsheet of people, households, and organizations into BarnCRM
without a consultant, and, with the Giving module installed, their gifts too
([Importing gifts](gift-import.md)). You upload the file, BarnCRM suggests which column means what,
you say how a row should be matched against records you already have, and then you run a
**preview** that tells you exactly what would be created, updated, matched, or rejected
before anything is written. When the preview looks right you import it, and the results
screen tells you what happened, row by row, including every row that failed and why.
A file that describes one kind of record, such as program sessions or one of your own custom
objects, loads through **Load one object** (section 9).

Every record an import creates is tagged with the import it came from, so six months
later you can still answer "where did these 400 households come from".
And for 30 days after you import it, an import can be undone: the records it created are
removed and the values it changed are put back (section 5).

## 2. How to turn it on

Nothing to turn on. The **Import** tab is in the BarnCRM app for anyone with the
**Manage BarnCRM Settings** permission. If you do not see the tab, ask whoever set up
your org to give you the BarnCRM Admin role on the **Access** page.

A few things are worth knowing before your first large file:

1. Open **BarnCRM Settings** and choose **Import**.
2. **Rows per chunk** controls how many rows are processed at a time. Leave it at 200.
   Lower it to 50 if your org has a lot of custom automation and an import fails with a
   limit error; raise it only if a very large file is running slowly and nothing else
   fires on save.
3. **Days an import can be undone** is 30 unless you change it, and can be anything from 1
   to 365. Each import keeps the window it was imported with.
4. **Import** on the same page has an **Open the import wizard** link, which is the same
   place the **Import** tab takes you.
5. With the Giving module installed, the same page has the two payment matching settings
   ([Importing gifts](gift-import.md), section 2).

BarnCRM Core ships one ready-made mapping, the **Generic contact list**. You can edit it,
and your edits are never overwritten by an upgrade. With the Giving module installed (and
only then), Giving adds a **generic gift list** and mappings that read the exports of the
system you are moving from, without renaming a column: see [Migrating from Nonprofit
Cloud](migrating-from-nonprofit-cloud.md) and [Migrating from NPSP](migrating-from-npsp.md).

## 3. A five-minute walkthrough (as Maria)

You need a CSV file or an Excel workbook (.xlsx). A small one is best for the first run: five
or six rows.

1. Open the **Import** tab. Select **Generic contact list**, then **Next**.
2. Select **Upload file** and choose your file. BarnCRM reads the header row and shows
   you every column it found, with the first few values from the file underneath each one.
3. Check the columns. Each column shows what BarnCRM thinks it is, for example
   "Email" for a column headed `Email Address`. Change anything that is wrong from the
   picker beside it. A column you do not want loaded is set to **Do not load**, and its
   values are kept on the staged row but written nowhere. A column only a module could
   load (an amount or a date, for example) is offered only when that module is installed;
   without it, BarnCRM suggests **Do not load** for it. The mapping remembers your
   choices: the next file with the same headings opens with them, and a column you set to
   **Do not load** stays that way even when BarnCRM recognizes its heading. Besides the
   usual columns, the picker lists your org's own fields on people and organizations that
   you may edit (for example "Person: Member Since"), and each one's Salesforce record ID
   (section 8). **Change values** beside a column tidies its values as they load, for
   example names in capitals or dates written day first (section 10).
4. Choose how rows are matched. **Email exact** is the safe default for people. Read the
   sentence under each rule before you change it: **Name plus postal code** will treat two
   different people who share a name at one address as the same person. If the file has
   organizations, choose how they are matched too (**Name exact** unless the file has an ID
   for them), and what happens when more than one record matches a row (**Reject the row**
   unless you have a reason to change it). On the same step, **Values for every row** lets
   you give a value the whole file shares, for example a city missing from every row; a row
   with its own value keeps it. Tick **Match only** when the file should update records you
   already have and never add new ones, and **Also match with my duplicate rules** to let your
   org's duplicate rules find people the rule missed. Section 8 explains every choice.
5. Optionally, under **Control totals**, type how many rows the file should have (and, with
   Giving, for a gift file, what its amounts should add up to). The preview checks them and the import is
   refused while they do not match.
6. Select **Preview**. Nothing is written. When it finishes you see four counts, "would
   create", "would update", "would match and change nothing", and "would be rejected",
   and a table of the rejected rows with the reason for each one. Select **Download
   exceptions** to get those rows back as a CSV you can fix in your spreadsheet. A new
   person or organization that appears on several rows is counted once as "would create";
   their later rows count as matching them, which is what the import will do. A person on
   twelve rows of the file becomes one person with one household, not twelve.
7. If the preview is wrong, fix the file or the mapping and preview again. Nothing you
   have done so far has changed a record.
8. When the preview is right, select **Import these rows**. Processing runs in the background and
   the screen updates as it goes. The import does what the preview showed: it uses the columns,
   values and matching choices the preview ran with, even if you or someone else has changed
   the template since. A change to the template counts from the next preview.
9. The results screen shows the same four counts for what actually happened, the run log,
   and links to the records. Select **View rows** to see every row and what became of it.

To check the tag, open one of the new households and look at **Created By Import Batch**.
It links back to the import.

## 4. Two people on one row

Most contact lists give a couple one line: two names, one address. Map the second
person's columns to **Contact 2** and BarnCRM puts both people in the same household.
You get one household with two members, not two households, and it works the same way
whether your org keeps people as contacts or as person accounts.

Where your org keeps people as person accounts, map the columns exactly as you would for
contacts (Email, Mailing Street, Email Opt Out and so on). BarnCRM writes each to the
person account's own field for it, and finds the person again by that field when you load
the next file: by their email under **Email exact**, and by their last name and mailing
postal code under **Name plus postal code**. A person account's billing postal code counts
too, because people loaded by other tools often have their postal code only there.

Each new person account gets a person account record type the person running the import can
use: their profile's default when it is a person type, otherwise the first person type
assigned to them by name. If none is assigned to them, the import creates no people and the
run log says so; assign a person account record type to their profile or a permission set
and run the import again. A Nonprofit Cloud org can have a Person Account record type that
the System Administrator profile is not given.

Three things are worth knowing about it.

- **The household is named from the file if you map a name for it.** Map a column to
  **Household: Name** and that name is used and treated as one you chose, so the naming
  patterns will not rewrite it later. Map nothing, and the household is named from the
  people in it in the usual way.
- **A second person who is already in your org is not moved.** If the second name on the
  row matches somebody you already have, they keep the household they are in today. An
  import never takes an existing person out of their household. Move them from the
  household page if that is what you want.
- **A row with only a second person on it still works.** They get a household of their
  own, the same as anybody else.
- **A couple who share an email, or a surname and postal code, are still two people.** When
  the matching rule would find both people on a row by the same email or surname and postal
  code, BarnCRM tells them apart by first name. A row naming one of them alone is matched
  by first name too, so "Jane Smith" finds Jane, not John. A row naming Jane alone in the
  same file as the couple's row finds the same Jane, in the couple's household, whichever
  row comes first.
- **A row with a different first name is a different person.** With only John Smith at an
  address, a "Jane Smith" row at that address creates Jane; John is not matched and is
  never renamed. The same holds under the email rule for a shared email, for a person you
  already have with no first name, and for people created earlier in the same file. First
  names are compared ignoring capitals and extra spaces ("JANE", " Jane " and "jane" are one
  name), but nothing else: an accent ("Jáne"), an initial ("J." for John) or a short form
  ("Bob" for Robert) is a different name, and a new person is created. Check the preview's
  "would create" count before you import; a file that spells names differently from your
  org creates people you may need to merge (see [Duplicates](duplicates.md)).
- **A row with no first name matches on the rest.** It finds the person with that email, or
  surname and postal code, and leaves their first
  name as it is: an empty cell never clears or renames anything. Loading the same file again finds each of
  them rather than adding the second person again. Two people on one row with the same
  matching details and the same first name cannot be told apart: that row is rejected.
  Under the email rule, a second person who shares the first person's email needs a last
  name unless they are already in your org with that email and first name. When a couple
  share the email, or surname and postal code, a row with no first name matches both of
  them, and is rejected unless you chose otherwise (section 8).

## 5. Undoing an import

An import you regret can be undone for 30 days after you import it. Undo removes the
people, households and organizations that import created (and, with Giving, its gifts), and
puts back the values it changed on records you already had. An import that loaded one object
(section 9) has the records it created removed the same way, counted under that object's name.
It does not touch anything else.
With Giving, a gift with a receipt is never removed, and neither is its donor ([Importing
gifts](gift-import.md), section 6).

1. Open the **Import** tab. **Recent imports** lists your last imports, newest first, with
   the date each one can be undone until.
2. Select **Undo** beside the import. BarnCRM counts what it would remove (people,
   households and organizations, and gifts with Giving) and how many changed values it would put back, and shows
   you the numbers with the import's name and file name. Nothing has changed yet.
3. Read the numbers. If they are what you expect, select **Undo this import**. If somebody
   has added or removed a record since you looked, the undo refuses and counts again, so you
   only ever confirm a number that is still true.
4. The undo runs in the background. When it finishes, the import shows **Undone** and its
   run log has a line saying who undid it, when, and how many records it deleted, kept and
   put back.

What undo will not do, on purpose:

- **It never deletes a record the import only matched or updated.** Those records were
  yours before the import. Values the import wrote to them are put back instead.
- **It keeps a record that has gained something since.** If somebody recorded a
  relationship, an affiliation or an address (or, with Giving, a gift) for a person the import created, that person is
  kept, and so is their household. A household somebody else has joined is kept too, and so
  is a household that gifts or pledges (with Giving) are still credited to, even when the
  gift was not entered after the import, for example an older gift whose donor was changed
  to a person in that household. Each record kept is listed with the reason in the import's
  journal.
- **It does not overwrite a correction.** A value somebody has changed since the import is
  left as they set it, and listed as not put back.
- **It does not empty the recycle bin.** Deleted records go to the recycle bin, where you can
  restore them for as long as Salesforce keeps them.

An undo that stops part way, for example because of a limit error, shows **Undo failed**.
Select **Undo** again: it finishes the job without repeating what it already did.

**Days an import can be undone** in **BarnCRM Settings**, **Import**, sets the window, from
1 to 365 days. The window is fixed when an import runs, so changing the setting only
affects imports you run afterwards.

## 6. Files that arrive every month

Some files come back on a schedule: a monthly export from your payment processor, a
quarterly list from a partner. Mark the mapping you use for one as recurring and the Hub
keeps track of it for you.

1. Open the **Import** tab and choose the mapping.
2. Select **This file arrives regularly**, and give the source a name you will recognize,
   for example "Monthly processor export". The name is required while the box is ticked.
3. Select **Next** and import the file as usual.

The BarnCRM home page then lists every recurring source with the date it was last
imported, oldest first, and **Never** for one you have not loaded yet. When a date is older
than you expect, that file has not been loaded this month.

Marking a mapping recurring changes nothing about how its files are imported. BarnCRM
never fetches or loads a file on its own: every file is still uploaded, previewed and
imported by a person, because an import nobody watched is an import nobody checked.

## 7. Common mistakes

**An Excel file shows the wrong columns, or none.** Only the **first sheet** of a workbook is
read, and its first row must be the column headings. Move the sheet you want to the front, or
copy it into a workbook of its own. A formula is read as the value Excel last saved for it,
and a date as the date, whatever format the cell shows. An older .xls file, or a
password-protected workbook, cannot be read: save it as .xlsx or CSV and upload that. A
browser too old to open a workbook says so; save the sheet as CSV instead. So does a workbook
too large to open in the browser (more than 500,000 rows or 1,000 columns, or a sheet over
100 MB once unpacked).

**"This import is already running a preview or an import."** Only one run of an import goes
at a time. Wait for the one running to finish (its results appear when it does), then start
again. While it runs, rows it has not reached yet still show the previous run's result.

**An import shows Failed although you did not see it fail.** Salesforce stopped its preview or
import before it finished (for example, the job was aborted in Setup). If it was a preview,
preview again. If it was an import, part of the file may already be loaded, and a
finished import cannot be previewed or imported again: undo it, which removes what it loaded
(anything changed since it stopped is kept), then upload the file as a new import.

**"No column was matched to a name or an email."** The preview refuses to run when the
mapping has no way to identify a person or an organization. Usually the file's header row
is not the first row: a title line or a blank line above it means BarnCRM read the
wrong row as the header. Delete the rows above the header in your spreadsheet and upload
again.

**Every row comes back as "would create" when you expected updates.** The matching rule
is not finding your existing records. **Email exact** matches only when the email in the
file is exactly the email on the record, so a file of work addresses will not match
people whose personal address you hold. A row whose first name is spelled differently from
the record ("Bob" for Robert, "J." for John) is also created, under either rule, rather than
renaming the record. Run a preview with a different rule, fix the spellings in the file, or
add an external identifier column to the file and use **External ID**. Under **External ID**,
check that a column is set to the field you chose (section 8): without one, nobody is matched.

**Rows rejected with "More than one person matches this row".** Two or more records in your
org share the email, or surname and postal code, or ID that the row was looked for by. A couple
sharing an email, and a row that gives no first name, is the usual cause. Merge the duplicates
(see [Duplicates](duplicates.md)), add a first name to the row, or match by an ID, then import
the rejected rows again. "More than one organization matches this row" is the same for two
organizations with one name. To load such rows into the most recently changed record instead,
see section 8.

**Rows rejected with "Required value missing: last name".** A person needs a last name.
Rows where the name column is empty, or where a single "Full Name" column was mapped to
first name only, fail this way. Map the full name column to **Full name** and BarnCRM
splits it, or split the column in your spreadsheet.

**The import finished but some rows failed.** That is by design: one bad row does not
throw away the rest of the file. The failed rows are counted as rejected, each carries the
reason, and none of them wrote anything. Fix those rows in your spreadsheet, save them as
a smaller file, and import that file on its own.

**Rows rejected with "The people on this row were saved, but its ... columns were not
loaded".** A module (Giving, for a gift file) failed while loading its columns for part of
the file. Everything it had saved for those rows was undone, so no half-loaded gifts remain,
but the people on them were already saved. The run log and the Error Log give the reason.
Fix it, then import the rejected rows again: the people are matched, not created twice.

**The run log says some rows "could not record their result".** The import ran, but those
staged rows could not be updated with what happened to them, so they still show an earlier
result. The Error Log has the same line. Check the Error Log for the cause and preview the
file again.

**"Row ... of the file is too long to import".** One row is longer than an import row can
hold, usually because a quotation mark opens a value and is never closed, so the rest of
the file reads as one value. Fix the row in your spreadsheet and upload the file again.

**Salesforce warned about duplicates, and the import saved the people anyway.** An import
saves past a duplicate rule set to alert, as a bulk load does, so a couple at one address or
a person resembling someone already here is not rejected. Afterwards run the duplicate scan
(see [Duplicates](duplicates.md)) to review any pair it made. A duplicate rule set to
**Block** still blocks: those rows are rejected with the rule's message, although the preview
counted them as would create, because a preview saves nothing for the rule to check.

**The run log says "Not loaded: you do not have access to" a field.** Your user may not
edit that field, so its column was skipped on every row, in the preview and in the import, and
the rest of each row loaded. The run log names each such field once. The BarnCRM Admin role
lets you edit the standard fields import mappings use (see "Fields the BarnCRM Admin role
can import" below), so this usually means a column mapped to some other field, or a user
without that role. Ask your Salesforce administrator for edit access to the field and import
the file again: the second import matches the people it already created and adds the
missing values.

**The run log says a value "is not a yes or no value".** A checkbox column held something
BarnCRM does not read as ticked or cleared (for example "maybe", or "Yes." with a full stop), so
that one checkbox was left as it was on that row, and the rest of the row loaded. The run log
names the row, the column and the value. The values BarnCRM reads are listed under "Checkbox
columns" in section 8. Correct the cells and import the file again.

**The run log says "Not matched on" a field.** Your user may not read the field your
matching rule uses (for example Email under **Email exact**), so nobody in the file could be
found by it, and a person your org holds only by that field counts as new. Where people
are person accounts this can be one of the two postal codes (mailing or billing) while the
other still matches. Do not import: ask your Salesforce administrator
for access to the field, then preview again.

**Columns for amounts, dates and the like were set to Do not load.** Only a module can load
them (the Giving module loads gifts), so without one BarnCRM offers nowhere to put them and
suggests **Do not load**. Nothing is lost: the staged row still keeps the whole original
line. With Giving installed, see [Importing gifts](gift-import.md).

**"The control totals do not match."** The preview counted a different number of rows (or,
with Giving, a different total of gift amounts) from the control totals you typed. The run log gives both
numbers. Fix the file or the totals and preview again; the import is refused until they agree.

**"A value for every row cannot give a person's name, email or matching ID".** A value for
every row that named a person would make every row the same person, so the import refuses it.
Put names and emails in the file instead. A value for the organization is fine.

**"No record with the ID ... was found that you can see".** The row gave a Salesforce record
ID, and BarnCRM found no such record, or your user cannot see it. A row with an ID is loaded
into that record or rejected; it never creates a new one. Check the ID against the record (a
report export is the safest source) and that you have access to it, then load the row again.

**"The ID ... is not a person" (or "not an organization").** The ID belongs to another kind
of record, for example a household's ID in a person's ID column, or a contact's ID in the
organization's. Map the column to the right one, or fix the ID.

**"Nothing matches this row, and this file only matches".** The file was marked **Match only**,
so a row whose person or organization is not already in Salesforce is rejected instead of
creating them. If those rows are new people, untick **Match only** and load them again.

**Load one object: "No record ... was found for" a lookup.** The value in a lookup column did
not find a record by the field that column names its parent by (section 9, step 4). Check the
value, or choose a different field in the column's second picker, or choose **Leave it empty**
to load the row without the lookup.

**Load one object: the object you want is not listed.** It is a setup or security object, one
of BarnCRM's own, or one you may not create or edit records of (section 9, "Which objects are
listed"). Ask your Salesforce administrator for access, or use Setup for setup objects.

**Load one object: "This row names the same record as an earlier row".** Two rows of the file
have the same record ID, or the same value in the upsert ID field. Only the first is loaded;
merge the two rows in the spreadsheet and load the second again if it held something new.

## 8. How rows are matched, and values for every row

The matching step of the wizard holds the choices below. How people and organizations are
matched, and what happens when several records match, are saved with the mapping, so the next
file loaded with it starts with the same ones; values for every row and **Match only** are for
this file only.

**People are matched by** one of three rules:

| Rule | What it does | What it risks |
|---|---|---|
| **Email exact** | Finds the person whose email is exactly the email in the file. | A file of work addresses will not match people whose personal address you hold, so they are created again. |
| **Name plus postal code** | Finds the person with that last name and postal code. | Two different people who share a name at one address are taken as one. |
| **External ID** | Finds the person whose ID field holds the value in the file, for example a member number from your other system. | Only as good as the IDs: a value typed into the wrong record matches the wrong person. |

Under every rule a row with a first name finds only a person with that first name (section 4).

**Organizations are matched by** **Name exact** (the same name, ignoring capitals and extra
spaces) or **External ID**. Name exact treats two organizations with one name, such as two
branches called "First Baptist Church", as one. Only organizations are searched: a household
or a person with the same name or ID is never taken for one.

**Choosing an ID field.** With **External ID**, choose the field from the list beside the
rule. It lists the fields your org marks **External ID** or **Unique** that hold text or an
email. If the list is empty, ask your Salesforce administrator to mark the field that holds
your other system's ID as External ID. Then, on the columns step, set the column holding the
ID to that field: it appears in the column list as, for example, "Person: Member Number"
or "Organization: Charity Number". A row with no ID is not matched, so its person or
organization is created (an organization needs a name for that).

**When more than one record matches** a row:

- **Reject the row** (the default). The row is rejected with the reason, nothing is written
  for it, and you fix the duplicates or the file and load it again. This is the safe choice,
  because a row loaded into the wrong duplicate is hard to notice.
- **Use the most recently changed record.** The row is loaded into whichever of them was
  changed last. Use it only when your duplicates are known and the newest is the one you keep.
  In a large file, a record the import itself updated earlier becomes the most recently changed,
  so the import can choose differently from the preview.

Either way every such row has **Several Matches** ticked: select **View rows** on the results
screen, or report on Import Rows, to see them. The run log says when rows were loaded into the
most recently changed record.

**Values for every row.** Select **Add a value**, choose what the value is for (the same list
as the columns), and type it. It is used on each row of this file whose own cell is empty, and
only for this file: the next file starts with none. A row's own value always wins, then the
file's value, then any default the mapping holds. A value cannot be a person's name, email or
ID field, because every row would then be the same person. It can be an organization: for a
staff list from one employer, give every row that organization's name.

**Salesforce record IDs.** If your file came out of Salesforce (a report export, for example),
map its ID column to **Person: Salesforce record ID**, **Second person: Salesforce record ID**
or **Organization: Salesforce record ID**. A row with an ID is loaded into exactly that record,
whatever the matching rule says, and is never matched to anyone else. If the ID is not a
record of the right kind, or no such record exists that you can see, the row is rejected and
nothing is created for it. A row whose ID cell is empty is matched by the rule as usual.

**Match only.** Tick **Match only** on the matching step for a file that should change records
you already have and add none, for example a list of updated phone numbers. A row whose person
or organization matches no record is rejected with the reason, and the preview shows you those
rows first. The choice is for this file only: the next file starts with it unticked.

**Your duplicate rules.** Tick **Also match with my duplicate rules** to let the duplicate rules
your org already uses (the ones that warn people as they type, see [Duplicates](duplicates.md))
find people and organizations the rule above does not. They are asked only about a person or
organization the rule found nobody for: a file of work emails, for example, can still find Ana
Ramirez by her name and phone if your rule for people compares those. What it risks: your
duplicate rules are usually looser than **Email exact**, so a row can be loaded into somebody who
is only similar. Every row matched this way has **Matched By Duplicate Rule** ticked and the run
log says there are such rows, so read them in the dry run before you commit (report on Import
Rows, or open the import's rows). A row whose two people the rules match to one record is
rejected. When a rule finds more than one
record, **When more than one record matches** decides, as for any match. Only organizations are
taken for organizations, and only people for people, whatever the rule compares. The choice is
saved with the mapping.

If no duplicate rule is switched on for people (or for organizations), the box changes nothing for
them, the matching step says so, and the run log says the rule above was used alone. Turn a rule
on as [Duplicates](duplicates.md) describes. A dry run matches only records that are already
there: a person an earlier row of the same file creates is found by the rule above, never by a
duplicate rule, so the commit can match a few more rows than the dry run did.

**Your own fields.** The column list includes the fields your org added to people (contacts)
and organizations (accounts), and the standard ones not already listed, wherever you may edit
them. Fields Salesforce calculates (formulas, roll-ups, auto numbers), lookups to other records
and the fields BarnCRM keeps for itself are not listed. A value is read as the field's type,
the same way a one-object load reads it (section 9): a date as 2026-10-12 or as your Salesforce
locale writes dates (4/2/1980 in the United States), a number with or without thousands
separators and a currency or percent sign, a time as 14:30. A value the field cannot take (a
date or number that cannot be read, text longer than the field) rejects the row, and the row
names the field and the value; checkboxes are below. Fix the cell and import the rejected rows
again.

**What counts as a change.** A matched person or organization is updated only where a value in
the file differs from what is stored, compared as the field holds it: 100 is the 100.00 already
there, and 1980-1-5 is the date already stored as 5 January 1980. Capitals count: "treasurer"
in the record and "Treasurer" in the file is a correction, and the import writes it.

**Checkbox columns.** Capitals and spaces around the value do not matter.

| The file says | The checkbox is |
|---|---|
| true, yes, y, 1, x, checked, on, t | Ticked |
| false, no, n, 0, off, f | Cleared |
| Nothing (an empty cell) | Left as it is |
| Anything else (for example "maybe") | Left as it is, and named in the run log |

A value BarnCRM cannot read never clears a box. In a people import that one field is skipped on
that row, the run log names the row, the column and the value, and the rest of the row still
loads. In a one-object load (section 9) the row is rejected with the value named, as for any
value the field cannot take. Fix the cell and import again; the second import matches the
records the first one created or updated.

## 9. Loading one object

Not every file is people. A spreadsheet of program sessions, a corrected export of one of your
own objects, or volunteer hours from a sign-in sheet each describe one kind of record. **Load
one object** loads a file into a single object, including your org's own custom objects, with
the same dry run, results, journal and undo as any import.

1. Open the **Import** tab and select **Load one object**.
2. Choose the object from the list, give the mapping a name (for example "Program sessions"),
   and select **Create**. The new mapping is chosen for you. Select **Next**.
3. Upload the file. Each column is matched to the field whose label or API name is its heading;
   anything else is **Do not load**. Change any column from the picker, which lists the fields
   of that object you may create or edit.
4. For a column that fills a lookup (a field that points at another record), a second picker
   says how the file names that record: **Salesforce record ID** (the default), the record's
   name, or any of its text, email or phone fields you may read (for example a program code or
   an organization's phone number). Matching is exact, ignoring case and the spaces around the
   value, so a phone number matches only when the file writes it the way the record holds it:
   "(555) 123-4567" does not find "555-123-4567".

   **Large objects.** Salesforce finds a record quickly by its ID, its name, an email, and a
   field marked External ID or Unique. Matching by any other field reads the whole object, so
   on an object holding more than 100,000 records you can see, the dry run is refused and names
   the field. Choose one of those fields instead, or ask your Salesforce administrator to mark
   the field External ID.
5. On the next step choose what each row does:

| Choice | What it does | What it risks |
|---|---|---|
| **Insert** | Creates a new record for every row. | Loading the same file twice creates every record twice. |
| **Update by record ID** | Changes the record whose Salesforce record ID is in the row's ID column. Map that column to **Salesforce record ID**. | A row whose ID is wrong, of another object, or not one you can see is rejected; nothing is created for it. |
| **Update by a field you choose** | Finds the record whose text, email or phone field you choose holds the row's value (for example Email), and changes it. Map a column to that field. | A row that finds no record is rejected; nothing is created for it. The field follows the matching and large object rules in step 4. |
| **Upsert by external ID** | Finds the record by the ID field you choose (one marked External ID) and changes it, or creates a record when none has that value. | A value typed into the wrong row changes the wrong record. |

   Also choose what happens when a lookup finds no record: **Reject the row** (the default) or
   **Leave it empty** and load the rest of the row. When a lookup, an update by a field you
   choose, or an upsert finds more than one record, the **When more than one record matches**
   choice applies, as in section 8.
6. Select **Dry run**, read the results, and commit.

**Which objects are listed.** Your org's own custom objects, and the standard objects
Salesforce treats as business records (ones you can find in global search), where you
may create or edit records. Never listed, whatever your access:

- Salesforce setup and security: users, groups, queues, profiles, roles, permission sets and
  their assignments, record types, licenses and the organization itself. Manage those in Setup.
- Custom settings, custom metadata, platform events, and history, sharing and feed records.
- BarnCRM's own bookkeeping (import mappings, imports, import rows and journals, the error log,
  setting changes, automation settings, rollup definitions) and household membership rows,
  which households manage themselves. With Giving, receipts, receipt runs, receipt number
  series and acknowledgments are never listed either.

**People and organizations load by Update only.** Contacts and accounts can be updated by record
ID, for example to load back an export you corrected in Excel, or by a field you choose, such
as a contact's email, but not inserted or upserted
here: new people, households and organizations come in through a people mapping, which builds
their households.

**Fields that are never written**, even when listed in your file: fields Salesforce fills in
(created and modified dates, IDs), formulas, roll-ups and auto numbers, every field a BarnCRM
rollup writes, the fields BarnCRM keeps on households and people, and a household's name. A
column mapped to one of them is named in the run log and skipped. A field you may not edit is
skipped and named the same way.

**A row is one record.** A value its field cannot take (a date Salesforce cannot read, letters
in a number, text longer than the field) rejects the whole row with the field and the value,
rather than loading the rest of it. A row naming the same record as an earlier row of the file
(the same ID, or the same value in the field rows are matched by) is rejected too: fix the
duplicate and load it again. Under **Match only**, a row that would create a record is
rejected. A value for every row cannot be the record ID or the field rows are matched by.

**Undo** works as in section 5. It deletes the records the import created (keeping any that
someone has edited or added a record to since) and puts back the values it changed.

## 10. Changing values as they load

A file from another system rarely says things the way your database does: names in capitals,
"St." where you write "Street", dates written day first, a first and a last name in two columns
you want as one. You can fix these in the mapping instead of in the spreadsheet, so the next
file of the same kind is fixed too.

1. On the columns step, select **Change values** beside a column.
2. Select **Add a change** and pick one. Changes run in the order listed, and you can add up
   to ten to one column:

| Change | What it does | Example |
|---|---|---|
| **Remove extra spaces** | Removes spaces at the start and end, and turns several spaces in a row into one. | `  Ana   Ramirez ` becomes `Ana Ramirez` |
| **All capitals** | Writes every letter as a capital. | `ca` becomes `CA` |
| **All lower case** | Writes every letter small. | `ANA@EXAMPLE.ORG` becomes `ana@example.org` |
| **Capitalize each word** | A capital at the start of each word, the rest small. | `RAMIREZ-LOPEZ` becomes `Ramirez-Lopez` |
| **Find and replace** | Replaces text you type with other text. Tick **Whole value only** to replace only a value that is exactly that text, and **Match capitals** to tell `ca` from `CA`. | `St.` becomes `Street`; with Whole value only, `CA` becomes `California` |
| **Value when empty** | Gives the cell a value when it is empty. | an empty cell becomes `Unknown` |
| **Add other columns** | Adds the values of other columns of the same row after this one, with a separator you choose (a space unless you type another). An empty one is left out. | `Ana` with Middle and Last becomes `Ana M Ramirez` |
| **Read as a date** | Reads a date written month first, day first or year first, with any separator, and writes it the way Salesforce reads it. A two-digit year below 50 is in the 2000s. | day first: `31/12/2025` becomes `2025-12-31` |

3. The panel shows the first values of the column before and after your changes. Select
   **Done**. The column shows how many changes it has.
4. Select **Dry run**. The results show, for the first rows of the file, each changed value
   before and after, under **Changed values**. Matching uses the changed values, so a person's
   email made lower case is matched as lower case.

The changes are saved with the mapping, like the columns, so the next file starts with them.
They run before **Values for every row**: a column a change leaves empty is then filled by the
file's value for every row, if you gave one. A change never runs code and never reads a record:
it only rearranges the text of the row. A date that cannot be read the way you chose is left as
it was, and the field then refuses it as it would any value it cannot take (a one-object load
and a people load both reject the row).

## Fields the BarnCRM Admin role can import

Salesforce controls standard fields one by one, and a person with only a minimal profile
could otherwise not write them. So the BarnCRM Admin permission set grants read and edit
access to the standard fields the import mappings write:

| Object | Fields |
|---|---|
| Contact | Email, Phone, Mobile Phone, Home Phone, Mailing Address, Title, Birthdate, Email Opt Out, Fax Opt Out, Do Not Call |
| Account (households and organizations) | Billing Address, Phone, Website |

Where people are person accounts, access to their person fields (Person Email, Person
Mailing Address and the rest) follows the contact fields of the same name, and a person's
phone is the account's Phone.

**Birthdate is sensitive.** It is granted so a migration file's birthdates are not lost, but
your organization may not want everyone with BarnCRM Admin to see it. To withhold it, give
your administrators a permission set that does not include it, or ask your Salesforce
administrator to remove Birthdate from a cloned role: the importer then skips the column and
says so in the run log, and nothing else in BarnCRM needs it.

## Field reference

For building a report on your imports.

| What you want | Object | Field |
|---|---|---|
| One upload and its counts | Import Batch | Row Count, Rows Created, Rows Updated, Rows Matched, Rows Rejected |
| Why an import failed as a whole | Import Batch | Run Log |
| One row of the file | Import Row | Row Number, Status, Error Message |
| Rows that matched more than one record | Import Row | Several Matches |
| How a mapping matches rows | Import Template | Person Matching Rule, Person Match Field, Organization Matching Rule, Organization Match Field, Several Matches, Use Duplicate Rules |
| Rows your duplicate rules matched | Import Row | Matched By Duplicate Rule |
| How a mapping changes values as they load | Import Template | Column Mapping (each column's changes) |
| The values given to every row of a file | Import Batch | File Values |
| Whether a file only matched existing records | Import Batch | Match Only |
| The records a row resolved to | Import Row | Household, Contact 1, Contact 2, Organization, Resulting Record, Second Resulting Record |
| The control totals of a file | Import Batch | Expected Count (and, with Giving, Expected Amount, File Amount) |
| The import a record came from | Account, Contact (and Gift, with Giving) | Created By Import Batch |
| Which mappings are for a recurring file, and when each was last used | Import Template | Is Recurring, Source Name, Last Import Date |
| When an import can be undone until | Import Batch | Undo Deadline |
| What an import changed on existing records, and what an undo kept | Import Journal | Phase, Entry Count, Entries |
| The records an import that loaded one object created | Import Journal (Phase Created), Import Row | Entries; Resulting Record |
| What a mapping that loads one object loads, and how | Import Template | Target Object, Load Operation, Load Match Field, Lookup Not Found |
