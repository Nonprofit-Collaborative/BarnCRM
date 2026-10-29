# Importing

## 1. What It Does

Importing loads a spreadsheet of people, households, and organizations into BarnCRM
without a consultant, and, with the Giving module installed, their gifts too
([Importing gifts](gift-import.md)). You upload the file, BarnCRM suggests which column means what,
you say how a row should be matched against records you already have, and then you run a
**preview** that tells you exactly what would be created, updated, matched, or rejected
before anything is written. When the preview looks right you import it, and the results
screen tells you what happened, row by row, including every row that failed and why.
A file that describes one kind of record, such as program sessions or one of your own custom
objects, loads through **One Kind of Record** (section 9).

### What Are You Importing?

A path across the top of the **Import** tab shows its six steps: **Choose File Type**, **Upload
File**, **Check Columns**, **Match Rows**, **Preview** and **Results**. **Back** is always at the
bottom left and the step's main button at the bottom right.

The first step asks what the file holds. Each choice is a card that says what it creates.
Choose one and its templates show below the cards; choose another card to change your mind.
The cards work like radio buttons: Tab reaches them and the arrow keys move between them.

| Card | What it loads | Where to read more |
|---|---|---|
| **People and Organizations** | People, a second person on the same row, households, organizations and the links between people and organizations, with their mailing addresses. A file of organizations only works too. You choose the template; the first one is chosen for you. | Sections 3, 4 and 8 |
| **Gifts** | Gifts with the people and organizations who gave them. Shown only when one of your active templates loads gifts, which means the Giving module is installed. | [Importing gifts](gift-import.md) |
| **One Kind of Record** | Creates, updates or upserts the records of any one object you may load, such as program sessions or one of your own objects. You choose the object and name a new template. | Section 9 |
| **Records With Their Related Records** | One kind of record and its related records from the same rows, such as sessions and their attendees. As **One Kind of Record**, with **Update or create, matched by external ID** chosen for you (or **Update by record ID** where that is not offered), so the related records choice is open on the matching step. | Section 9, "Related Records in the Same File" |
| **Delete the Records a File Lists** | Sends the records whose IDs the file lists to the Recycle Bin, after a preview and a confirmed count. Shown only to people with **Bulk Delete Records**. As **One Kind of Record**, with **Delete by record ID** chosen for you. | Section 9, "Deleting the records a file lists" |
| **Your Templates** | Every active template in your org: the ones BarnCRM and your modules ship and the ones you made, each with its description, what it creates and when it last loaded a file. | Sections 2 and 6 |

Once a template is chosen, the step shows what it creates, built from its columns: for
example "This file can create: people, households, organizations, links between people and
organizations", or for a template that loads one object, "Loads: Program Session (and Session
Attendee)". A template still loads only what your file has columns for.

Every record an import creates is tagged with the import it came from, so six months
later you can still answer "where did these 400 households come from".
And for 30 days after you import it, an import can be undone: the records it created are
removed and the values it changed are put back (section 5).

## 2. How to Turn It On

Import is part of the **Data Manager** feature, which on a new install is off until you turn
it on: choose **Turn On** in the **Data Manager** row in **BarnCRM Settings**, **General**
(or leave it ticked in first-run setup); see [BarnCRM Settings](barncrm-settings.md). Once it
is on, the **Import** tab is for anyone with the **Manage BarnCRM Settings** permission. Open it from the **Data Manager** tab in the BarnCRM app: choose **Import a File**
(see [Data Manager](data-manager.md)). If you do not see the tile, ask whoever set up your org
to give you the BarnCRM Admin role on the **Access** page.

Every import, bulk update ([Bulk update](bulk-update.md)) and bulk delete
([Bulk delete](bulk-delete.md)) is saved as one **Data Job** record, with its counts, run log
and undo deadline. In reports and list views look for **Data Jobs**; the object's API name,
`Import_Batch__c`, has not changed.

A few things are worth knowing before your first large file:

1. Open **BarnCRM Settings** and choose **Import**.
2. **Rows per chunk** controls how many rows are processed at a time. Leave it at 200.
   Lower it to 50 if your org has a lot of custom automation and an import fails with a
   limit error; raise it only if a very large file is running slowly and nothing else
   fires on save.
3. **Days an import can be undone** is 30 unless you change it, and can be anything from 1
   to 365. Each import keeps the window it was imported with.
   **Rows in a trial import** is how many of a file's first rows **Try the First Rows**
   imports before the rest (section 3, step 8). It is 25 unless you change it, from 1 to
   2,000, and the wizard lets you change it for one file.
4. **Days the rows of an import are kept** is 90 unless you change it, from 1 to 3650, or 0
   to keep them for ever. See [How long the rows are kept](#how-long-the-rows-are-kept).
5. **Import** on the same page has an **Open Import** button, which is the same
   place the **Import** tab takes you.
6. With the Giving module installed, the same page has the two payment matching settings
   ([Importing gifts](gift-import.md), section 2).

BarnCRM Core ships three ready-made people templates, added at install and on upgrade:

| Template | For a file of | Columns it reads |
|---|---|---|
| **People and Organizations List** | People with their contact details, and optionally their household or organization. Chosen for you under **People and Organizations**. | First Name, Last Name, Email, Phone, Street, City, State, Postal Code, Country, Household Name, Organization |
| **Organization List** | Organizations only: businesses, foundations, partner groups. Organizations are matched by name. | Organization Name, Street, City, State, Postal Code, Country (the billing address), Phone, Website |
| **Couples and Households** | Two people on each row who share a household (section 4). | Contact 1 First Name, Last Name, Email and Phone; Contact 2 First Name, Last Name, Email and Phone; Household Name; Street, City, State, Postal Code, Country |

In an org installed before 2026-10-28 the first is called **Generic contact list**: an upgrade
adds the two new templates but never renames or changes one you already have. You can edit
any of them, and your edits are never overwritten by an upgrade. With the Giving module installed (and
only then), Giving adds a **generic gift list** and templates that read the exports of the
system you are moving from, without renaming a column: see [Migrating from Nonprofit
Cloud](migrating-from-nonprofit-cloud.md) and [Migrating from NPSP](migrating-from-npsp.md).

## 3. A Five-Minute Walkthrough (as Maria)

You need a CSV file (or another text file whose columns are separated by semicolons, tabs or
pipes) or an Excel workbook (.xlsx). A small one is best for the first run: five or six rows.

1. Open the **Import** tab. Under **What Are You Importing?**, choose **People and
   Organizations**. **People and Organizations List** (or **Generic contact list** in an older
   org) is chosen for you; select **Next**.
2. Select **Upload file** and choose your file. BarnCRM reads the header row and shows
   you every column it found, with the first few values from the file underneath each one.
   For a text file, **Columns are separated by** shows the separator BarnCRM found (commas,
   semicolons, tabs or pipes); change it if the columns look wrong, for example every heading
   in one column. For a workbook with more than one sheet, **Sheet** chooses which one to load
   (the first, until you choose another). Changing either reads the file again and suggests
   the columns afresh.
3. Check the columns. Each column shows what BarnCRM thinks it is, for example
   "Email" for a column headed `Email Address`. Change anything that is wrong from the
   picker beside it. A column you do not want loaded is set to **Do not load**, and its
   values are kept on the staged row but written nowhere. A column only a module could
   load (an amount or a date, for example) is offered only when that module is installed;
   without it, BarnCRM suggests **Do not load** for it. The template remembers your
   choices: the next file with the same headings opens with them, and a column you set to
   **Do not load** stays that way even when BarnCRM recognizes its heading. Besides the
   usual columns, the picker lists your org's own fields on people and organizations that
   you may edit (for example "Person: Member Since"), and each one's Salesforce record ID
   (section 8). **Change Values** beside a column tidies its values as they load, for
   example names in capitals or dates written day first (section 10).
4. Choose how rows are matched. **Email exact** is the safe default for people. Read the
   sentence under each rule before you change it: **Name plus postal code** will treat two
   different people who share a name at one address as the same person. If the file has
   organizations, choose how they are matched too (**Name exact** unless the file has an ID
   for them), and what happens when more than one record matches a row (**Reject the row**
   unless you have a reason to change it). On the same step, under **More Options** (open by
   itself once anything in it is set), **Values for Every Row** lets
   you give a value the whole file shares, for example a city missing from every row; a row
   with its own value keeps it. Tick **Match only** when the file should update records you
   already have and never add new ones, and **Also match with my duplicate rules** to let your
   org's duplicate rules find people the rule missed. Section 8 explains every choice.
5. Optionally, under **More Options**, **Control Totals (Optional)**, type how many rows the file should have (and, with
   Giving, for a gift file, what its amounts should add up to). The preview checks them and the import is
   refused while they do not match.
6. Select **Preview**. Nothing is written. When it finishes you see four counts, "would
   create", "would update", "would match and change nothing", and "would be rejected",
   and a table of the rejected rows with the reason for each one (the first 200; when there
   are more, the screen says how many it shows). Select **Download Rejected Rows** to get every
   rejected row back as a CSV you can fix in your spreadsheet, up to 100,000 rows in one
   download. The file opens cleanly in Excel: accented names keep their accents, and a value
   that starts with =, +, - or @ gets a leading apostrophe so the spreadsheet never runs it
   as a formula (a plain negative number such as -25.00 is left as it is). A new
   person or organization that appears on several rows is counted once as "would create";
   their later rows count as matching them, which is what the import will do. A person on
   twelve rows of the file becomes one person with one household, not twelve.
7. If the preview is wrong, fix the file or the template and preview again. Nothing you
   have done so far has changed a record.
8. When the preview is right, select **Import These Rows**. Processing runs in the background and
   the screen updates as it goes. The import does what the preview showed: it uses the columns,
   values and matching choices the preview ran with, even if you or someone else has changed
   the template since. A change to the template counts from the next preview.

   For a large file, try the first rows for real first. The preview writes nothing, so a
   validation rule, a required field or one of your org's own flows is first met when rows are
   saved. Under **Try the First Rows**, check the number (25 unless your org changed it in
   BarnCRM Settings, Import section, **Rows in a trial import**; you can change it for this
   file) and select **Import the First Rows**. Only those rows are saved; the results screen
   shows what became of them. If they are right, select **Import the Remaining Rows**: the rest
   of the file goes into the same import, under the same columns and matching choices, and one
   undo removes both parts. If they are wrong, undo the import (section 5), fix the file or the
   template, and upload it again. An import whose trial has run cannot be previewed again.
9. The results screen shows the same four counts for what actually happened, the run log,
   and links to the records. Select **Download**, then **Download Results**, to get every row of the file back as
   a CSV with what became of it: its outcome (Created, Updated, Matched, Rejected or Skipped),
   the Salesforce record IDs it resulted in (person, second person, household, organization,
   and a gift or other record a module loaded), the reason for a rejected row, and the row's
   own columns. Keep it to reconcile against the system the file came from, or to load the
   next file by record ID. Like the rejected rows file it opens cleanly in Excel and holds up to
   100,000 rows in one download; for a larger import the screen says how many it holds.

**Fixing the rejected rows.** You do not need a new import for the rows that were rejected.
Select **Download Rejected Rows** (on the results screen it is under **Download**), fix those rows in your spreadsheet (keep the same column
headings; the Row and Reason columns are ignored), and save the file. Then, still on the
results screen, choose the fixed file under **Retry Fixed Rows**. BarnCRM previews only
those rows, against the same template, and shows the counts for them; select **Import these
rows** to load them into the same import. Every earlier rejected row is marked **Retried**,
so keep in the file each rejected row you still want loaded, even one you did not change.
The earlier rejected rows no longer count,
so the import's rejected count and its rejected rows are now the fixed rows' results, and its
one **Undo** removes everything both runs created. Only the person who ran the import can
retry it, only while it can still be undone, and a retry file may hold up to 10,000 rows.
You can retry again if some fixed rows are still rejected. Row numbers in a retry carry on
after the original file's, so the first fixed row of an import of 200 rows is row 202.

To check the tag, open one of the new households and look at **Created By Import Batch**.
It links back to the import.

## 4. Two People on One Row

Most contact lists give a couple one line: two names, one address. Map the second
person's columns to **Contact 2** and BarnCRM puts both people in the same household. The
shipped **Couples and Households** template already maps columns headed "Contact 1 ..." and
"Contact 2 ..." (section 2). You get one household with two members, not two households, and it works the same way
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

## 5. Undoing an Import

An import you regret can be undone for 30 days after you import it. Undo removes the
people, households and organizations that import created (and, with Giving, its gifts), and
puts back the values it changed on records you already had. An import that loaded one object
(section 9) has the records it created removed the same way, counted under that object's name.
An import whose rejected rows you retried (section 3) is undone as one, both runs together.
It does not touch anything else.
With Giving, a gift with a receipt is never removed, and neither is its donor ([Importing
gifts](gift-import.md), section 6).

1. Open the **Import** tab. **Recent Imports** lists your last imports, newest first, with
   the date each one can be undone until.
2. Select **Undo** beside the import. BarnCRM counts what it would remove (people,
   households and organizations, and gifts with Giving) and how many changed values it would put back, and shows
   you the numbers with the import's name and file name. Nothing has changed yet. The
   numbers count the records the import created from your file. Undo also removes the
   households and gift allocations BarnCRM created automatically for those rows, so the
   total removed can be higher.
3. Read the numbers. If they are what you expect, select **Undo This Import**. If somebody
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
- **It keeps a record somebody edited since.** A person or household somebody (or another
  automation) changed after the import is kept. Totals the import or the undo recalculates
  are not an edit: when undo deletes the imported gifts, the donors' totals are recalculated,
  and the donors are still removed. A donor somebody edited before you selected Undo is kept
  even so. The import's own totals count as the import's when they are recalculated within an
  hour of it finishing, which is usually minutes. Totals recalculated later, such as by the
  nightly run, keep the record, since they could hide an edit; the journal says so. An edit
  made in that first hour and then followed by a recalculation of the same person's totals is
  not seen.
- **It does not overwrite a correction.** A value somebody has changed since the import is
  left as they set it, and listed as not put back.
- **It does not empty the recycle bin.** Deleted records go to the recycle bin, where you can
  restore them for as long as Salesforce keeps them.

An import that tried its first rows (section 3, step 8) is undone like any other: before the
remaining rows are imported, undo removes the trial rows' records; after, one undo removes
both parts.

An undo that stops part way, for example because of a limit error, shows **Undo failed**.
Select **Undo** again: it finishes the job without repeating what it already did.

**Days an import can be undone** in **BarnCRM Settings**, **Import**, sets the window, from
1 to 365 days. The window is fixed when an import runs, so changing the setting only
affects imports you run afterwards.

### How Long the Rows Are Kept

Every row of every file is kept as an Import Row so you can see what happened to it, download
the rejected rows and check what a re-import changed. Rows take storage, so a nightly job
removes the rows of an import once it finished more than **Days the rows of an import are
kept** ago (90 days unless you change it in **BarnCRM Settings**, **Import**; 0 keeps them for
ever). The import itself stays: its counts, run log and file name, and its undo, which never
reads the rows. A preview whose rows were removed cannot be committed: upload the file again.

The job is called **Import row cleanup**. Health Check reports it when it is not scheduled, and
its **Schedule All Nightly Jobs** fix schedules it. It runs at a quarter past one in the
morning.

## 6. Files That Arrive Every Month

Some files come back on a schedule: a monthly export from your payment processor, a
quarterly list from a partner. Mark the template you use for one as recurring and the Hub
keeps track of it for you.

1. Open the **Import** tab and choose the template.
2. Select **This file arrives regularly**, and give the source a name you will recognize,
   for example "Monthly processor export". The name is required while the box is ticked.
3. Select **Next** and import the file as usual.

The BarnCRM home page then lists every recurring source with the date it was last
imported, oldest first, and **Never** for one you have not loaded yet. When a date is older
than you expect, that file has not been loaded this month.

Marking a template recurring changes nothing about how its files are imported. BarnCRM
never fetches or loads a file on its own: every file is still uploaded, previewed and
imported by a person, because an import nobody watched is an import nobody checked.

### Start a New Template From This One

A template remembers the columns, changes, row rules and matching of the last file imported
with it. Two people files with different layouts, such as a monthly membership export and an
event sign-up list, should each have their own template, so one does not overwrite the
other's choices.

1. Open the **Import** tab and choose **People and Organizations** or **Gifts**, then the
   template closest to your file.
2. Select **Start a New Template From This One**. **New template name** starts as "Copy of"
   and the template's name; change it, for example to "Event sign-ups".
3. Select **Create**. The new template has the same columns, values for every row, row rules,
   matching and payment matching, and is chosen for you. It is yours: not recurring, never
   loaded, and the template it came from is unchanged. Select **Next**.

A template that loads one object has no such button: **One Kind of Record** makes a new one.

## 7. Common Mistakes

**Every heading shows as one column.** The file separates its columns with something other
than what BarnCRM chose (European exports often use semicolons). Choose the right separator in
**Columns are separated by** above the column list. A file of only one column reads as comma
separated.

**An Excel file shows the wrong columns, or none.** The **first sheet** of a workbook is read
until you choose another in **Sheet** above the column list, and the sheet's first row must be
the column headings. A sheet with no rows under its headings shows no columns and you cannot go
on until you choose another. A formula is read as the value Excel last saved for it,
and a date as the date, whatever format the cell shows. An older .xls file, or a
password-protected workbook, cannot be read: save it as .xlsx or CSV and upload that. A
browser too old to open a workbook says so; save the sheet as CSV instead. So does a workbook
too large to open in the browser (more than 500,000 rows or 1,000 columns, or a sheet over
100 MB once unpacked).

**A phone number from a Find export starts with a single quote.** Find puts one quote before a
value that starts with = + - or @, so a spreadsheet does not run it as a formula. The import
takes that one quote off, so `'+44 20 7946 0000` loads as `+44 20 7946 0000`. A value that
starts with a quote followed by anything else loads as it is.

**"This import is already running a preview or an import."** Only one run of an import goes
at a time. Wait for the one running to finish (its results appear when it does), then start
again. While it runs, rows it has not reached yet still show the previous run's result.

**An import shows Failed although you did not see it fail.** Salesforce stopped its preview or
import before it finished (for example, the job was aborted in Setup). If it was a preview,
preview again. If it was an import, part of the file may already be loaded, and a
finished import cannot be previewed or imported again: undo it, which removes what it loaded
(anything changed since it stopped is kept), then upload the file as a new import.

**"No column was matched to a name or an email."** The preview refuses to run when the
template has no way to identify a person or an organization. Usually the file's header row
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
throw away the rest of the file. The failed rows are counted as rejected and each carries the
reason. A row rejected before anything was saved (a missing last name, more than one match, a
value a field cannot take) wrote nothing, not even the organization it names; the preview
shows the same. A row whose save failed part way (a duplicate rule that blocks the second
person, say) keeps what was already saved, and the row's Contact and Organization fields point
at it, so a second import matches it instead of creating it again. Fix those rows in your
spreadsheet, save them as a smaller file, and import that file on its own.

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
lets you edit the standard fields import templates use (see "Fields the BarnCRM Admin role
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

**"This file is larger than 2.5 MB, so it imports without a copy of the original".** BarnCRM
keeps a copy of each file you import as a Salesforce File, so the original can be downloaded
again, but only up to 2.5 MB: a larger one is too big to send safely. The import itself goes
ahead and loads every row. Keep your own copy of the file. "The original file was not kept"
with a reason means the copy could not be saved; again, the import goes ahead.

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
organization's. Map the column to the right one, or fix the ID. An account whose record type
is not the one chosen in **Record type for organizations** is "not an organization" too.

**"No organization was matched or created, because you cannot use the ... record type".** The
run log says this when the record type chosen in **Record type for organizations** (General,
BarnCRM Settings) is not available to the user who loaded the file, so no organization in the
file is matched or created. Give that user the record type in Setup (on their profile or a
permission set), or choose a record type they have in the setting, then load the file again.
With **No record type** chosen this never happens.

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

## 8. How Rows Are Matched, and Values for Every Row

The matching step of the wizard holds the choices below. How people and organizations are
matched, and what happens when several records match, are saved with the template, so the next
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
or a person with the same name or ID is never taken for one. An organization is an account of
the record type chosen in **Record type for organizations** on **General** in BarnCRM Settings
(or with no record type, when **No record type** is chosen), and a new organization is created
with that record type. An account of another record type with the same name is not matched.

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

**Values for every row.** Select **Add a Value**, choose what the value is for (the same list
as the columns), and type it. It is used on each row of this file whose own cell is empty, and
only for this file: the next file starts with none. A row's own value always wins, then the
file's value, then any default the template holds. A value cannot be a person's name, email or
ID field, because every row would then be the same person. It can be an organization: for a
staff list from one employer, give every row that organization's name.

**A person and the organization on their row.** When a row names a person and an organization,
the import links them with an affiliation (see [Affiliations](affiliations.md)): the row's first
person, as a current affiliation of that organization. If the person already has a current
affiliation with it, nothing new is made, and two rows of one file linking the same person and
organization make one affiliation. A new affiliation follows the usual rules, so it becomes the person's primary one only when they
have no other. The preview counts a row that would add an affiliation as one that creates
something, and undoing the import deletes the affiliations it made. The row's second person is
not linked: put them on a row of their own to link them too. Map a column to **Affiliation: role**
to give a new affiliation its role, for example Board chair; an affiliation that already exists
keeps its own.

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
saved with the template.

The same box also asks your **match sources** (see
[Matching Logic](duplicates.md#matching-logic)) about a person the duplicate rules found
nobody for: the row's email, its phones, and its mailing and other street with postal code are
compared with the values on contact point records and BarnCRM addresses, in the same way the
duplicate scan compares them. A person whose email is kept only on a contact point email record
is found this way. A record found only through a match source is used only when both its first
name and its last name are the same as the row's (spaces at either end and capitals ignored; a
blank first name matches only a blank one), because a shared address, phone or family email
often means a relative, not the same person: a row for "Jane Smith" at the address or home
phone of an existing "John Smith" is not loaded into John, nor is a row for "Okonkwo-Bell" at
the address of an existing "Okonkwo"; each is handled like any row with no match. A person who
goes by another first name (Bob for Robert) is created new, and the next duplicate scan offers
the pair for review.
These rows are ticked **Matched By Duplicate Rule** too, and follow **When more than one record
matches** as well. Match sources are not asked about organizations, not about a person the
duplicate rules already matched, and not when the box is unticked. The sources are asked even
when no duplicate rule is switched on.

If no duplicate rule is switched on for people (or for organizations), the box changes nothing for
them, the matching step says so, and the run log says the rule above was used alone. Where your
org keeps people as person accounts, a contact import never takes a person account as the
person a contact rule matched, and a person account duplicate rule counts for those people
only, and an account rule for organizations; turn on the one you need. Turn a rule on as
[Duplicates](duplicates.md) describes. A dry run matches only records that are already
there: a person an earlier row of the same file creates is found by the rule above, never by a
duplicate rule, so the commit can match a few more rows than the dry run did. For a file that
loads one object, see "Your duplicate rules" in section 9.

**Your own fields.** The column list includes the fields your org added to people (contacts)
and organizations (accounts), and the standard ones not already listed, wherever you may edit
them. Fields Salesforce calculates (formulas, roll-ups, auto numbers), lookups to other records
and the fields BarnCRM keeps for itself are not listed. A value is read as the field's type,
the same way a one-object load reads it (section 9): a date as 2026-10-12 or as your Salesforce
locale writes dates (4/2/1980 in the United States), a number as a spreadsheet exports it, a
time as 14:30. For numbers that means a currency symbol or code ($1,250.00, €100, USD 1,250),
grouping as your locale writes it (1,250.50 in the United States, 1.250,50 in Germany, 1 250,50
in France), a percent sign, and a minus sign or brackets for a negative ((45.00) is -45). A
value whose decimal mark cannot be told, such as 1.250 when your locale writes decimals with a
comma and groups with spaces, is refused rather than guessed. A value the field cannot take (a
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

## 9. Loading One Object

Not every file is people. A spreadsheet of program sessions, a corrected export of one of your
own objects, or volunteer hours from a sign-in sheet each describe one kind of record. **Load
one object** (the **One Kind of Record** card) loads a file into a single object, including your org's own custom objects, with
the same dry run, results, journal and undo as any import.

A module can also ship a ready-made template that loads one object, such as a sheet of
volunteer hours. It appears under **Your Templates** like any shipped template, but only in an org
that has the object and every field it uses, and where the template's people (Contacts or
person Accounts) match yours; otherwise it is left out, and the reason is on the Error Log
(Health Check). You can edit it or switch it off like any other template.

1. Open the **Import** tab and choose **One Kind of Record** (or **Records With Their Related
   Records**, or **Delete the Records a File Lists**). A template you made before is under
   **Your Templates**.
2. Choose the object from the list, give the template a name (for example "Program sessions"),
   and select **Create**. The new template is chosen for you, with what it loads shown under
   it. Select **Next**.
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
| **Create new records** | Creates a new record for every row. | Loading the same file twice creates every record twice. |
| **Update by record ID** | Changes the record whose Salesforce record ID is in the row's ID column. Map that column to **Salesforce record ID**. | A row whose ID is wrong, of another object, or not one you can see is rejected; nothing is created for it. |
| **Update by a field you choose** | Finds the record whose text, email or phone field you choose holds the row's value (for example Email), and changes it. Map a column to that field. | A row that finds no record is rejected; nothing is created for it. The field follows the matching and large object rules in step 4. |
| **Update or create, matched by external ID** | Finds the record by the ID field you choose (one marked External ID) and changes it, or creates a record when none has that value. | A value typed into the wrong row changes the wrong record. |
| **Delete by record ID** | Deletes the record whose Salesforce record ID is in the row's ID column, as a bulk delete does. Listed only for people with **Bulk Delete Records**, and only for objects a bulk delete may delete. | Every record the file names goes, with the related records Salesforce deletes with it. See "Deleting the records a file lists" below. |

   Also choose what happens when a lookup finds no record: **Reject the row** (the default) or
   **Leave it empty** and load the rest of the row. When a lookup, an update by a field you
   choose, or an upsert finds more than one record, the **When more than one record matches**
   choice applies, as in section 8.
6. Select **Preview**, read the results, and commit. After the import, **Download Results**
   gives every row with its outcome, the record ID it created, updated or matched, and the
   reason for a rejected row (section 3, step 9).

**Your duplicate rules.** Under **Create new records** and **Update or create, matched by external ID**, tick **Also match
with my duplicate rules** (on the matching step) to stop a file from creating a second copy of
a record you already have. Each row that would create a record is first looked for with the
duplicate rules your org has switched on for that object (see [Duplicates](duplicates.md)),
custom objects included; a record they match is updated with the row's values instead, and a
row they match to nothing creates its record as usual. The box is not offered under **Update
by record ID**, **Update by a field you choose** or **Delete by record ID**, which never create
a record (so it never appears for contacts and accounts, which load by Update only).

- **Which wins.** The record ID and the field rows are found by always come first: under
  **Update or create, matched by external ID**, a row whose external ID finds a record updates that record and the
  duplicate rules are never asked about it. Only a row that would otherwise create a record is
  asked.
- **External IDs are never overwritten.** Under an upsert, a row the rules match to a record
  whose external ID field is empty fills it in with the row's value. A row they match to a
  record that already holds a different external ID is rejected, naming the field: check which
  record is right, then fix the file or the record.
- **More than one match.** When the rules match several records, **When more than one record
  matches** decides, as in section 8: the row is rejected, or the most recently changed record
  is updated.
- **One record, one row.** A record that an earlier row of the file already creates or updates
  is set aside before the choice. A row whose only matches are records earlier rows update is
  rejected, so no record is changed twice by one file.
- **Dry run and commit agree, with one limit.** The rules are asked only about records that
  were there before the import, and records earlier rows load are set aside, so the commit
  chooses as the dry run did. The limit: duplicate rules compare field values, so a value an
  earlier row of the commit changes on some record can make the rules match that record (or
  stop matching it) for a later row, where the dry run, which changed nothing, saw the old
  values. Compare the commit's results with the dry run's when one file both updates and adds
  similar records.
- **Read before you commit.** Duplicate rules are looser than a record ID or key, so a row can
  update a record that is only similar. Every row matched this way has **Matched By Duplicate
  Rule** ticked and the run log says so: check those rows in the dry run.
- **No rule, or a rule that fails.** If no duplicate rule is switched on for the object, the
  run log says so and every row is matched by its ID or key alone. If a rule is switched on but
  Salesforce could not run it, each row that would create a record is rejected with that reason
  rather than risk a duplicate: import those rows again later, or untick the box. The choice is
  saved with the template.

**Which objects are listed.** Your org's own custom objects, and the standard objects
Salesforce treats as business records (ones you can find in global search), where you
may create or edit records. Never listed, whatever your access:

- Salesforce setup and security: users, groups, queues, profiles, roles, permission sets and
  their assignments, record types, licenses and the organization itself. Manage those in Setup.
- Custom settings, custom metadata, platform events, and history, sharing and feed records.
- BarnCRM's own bookkeeping (import templates, imports, import rows and journals, the error log,
  setting changes, automation settings, rollup definitions) and household membership rows,
  which households manage themselves. With Giving, receipts, receipt runs, receipt number
  series and acknowledgments are never listed either.

**People and organizations load by Update only.** Contacts and accounts can be updated by record
ID, for example to load back an export you corrected in Excel, or by a field you choose, such
as a contact's email, but not inserted or upserted
here: new people, households and organizations come in through a people template, which builds
their households. They can also be deleted by record ID, below, as a bulk delete deletes them.

**Fields that are never written**, even when listed in your file: fields Salesforce fills in
(created and modified dates, IDs), formulas, roll-ups and auto numbers, every field a BarnCRM
rollup writes, the fields BarnCRM keeps on households and people, and a household's name. A
column mapped to one of them is named in the run log and skipped. A field you may not edit is
skipped and named the same way.

**A row is one record.** A value its field cannot take (a date Salesforce cannot read, letters
in a number, text longer than the field) rejects the whole row with the field and the value,
rather than loading the rest of it. A row naming the same record as an earlier row of the file
(the same ID, or the same value in the field rows are matched by) is rejected too: fix the
duplicate and load it again, or set **One row per** on that column (section 11). An empty
cell leaves its field as it is unless the column says **Empty cells clear the field**
(section 11). Under **Match only**, a row that would create a record is rejected. A value
for every row cannot be the record ID or the field rows are matched by.

**Undo** works as in section 5. It deletes the records the import created (keeping any that
someone has edited or added a record to since) and puts back the values it changed.

**Deleting the records a file lists.** **Delete by record ID** deletes the records a file names,
for example an export of test records somebody loaded by mistake. It needs the **Bulk Delete
Records** permission (see [Bulk delete](bulk-delete.md), section 2) as well as import access,
and the object must be one a bulk delete may delete. Map the ID column to **Salesforce record
ID**; every other column is ignored, and it loads no related records.

1. Select **Preview**. Nothing is deleted. A row is **Matched** (would be deleted) when its ID
   names a record of the object that you can see; a row whose ID is wrong, of another object,
   repeats an earlier row, or names a record you cannot see is rejected.
2. Instead of **Commit**, the results show the **Bulk Delete** panel. Press **Preview**: it says
   how many records would be deleted, names the first five, and lists the kinds of related
   record Salesforce deletes with them. Press **Download a Backup First** to save them,
   with every field you can see, as a CSV file. Type that number into **Type the number of
   records to confirm**, then press **Delete**. The panel shows the delete's progress.
3. The delete runs as a bulk delete: in chunks of up to 200, as you, with each record listed in
   the journal. A record deleted or hidden from you since the dry run is left alone and counted;
   a record Salesforce refuses is listed with the reason.
4. Once it starts, the job moves from the import history to **Data Jobs** on the **Data
   Manager** tab, where **Undo** brings the records back from the Recycle Bin within the bulk
   delete's undo window (at most 15 days). The import's own **Undo** refuses it.

A file naming more records than the **Bulk delete run limit** (default 10,000) is refused at
the confirm step: split the file.

### Related Records in the Same File

One file often holds two kinds of record: programs and their sessions, events and their
attendees, or a legacy system's accounts and their notes. Each row names its parent by a key,
and the rows that share a key belong to one parent. **Related records** loads both in one
import, with one dry run and one undo.

1. On the step where you choose what each row does, choose **Update or create, matched by
   external ID**, **Update by a field you choose** or **Update by record ID**. The field rows are matched by is the
   **parent key**: rows with the same value in it share one parent. **Create new records** cannot load
   related records, because a key that no field holds cannot find its parent again in a later
   part of the file or on a second run. To create new parents, give the object an External ID
   field (a program code, a legacy ID) and upsert by it.
2. Under **Related records**, choose the related object and the field on it that points at
   your object (for example **Session (Program)**). Only objects you may create records of
   are listed.
3. Back on the columns step, the picker lists the related object's fields after your object's,
   each starting with the related object's name. Map the related columns to them. The field
   that points at the parent is filled in by the load, so a column mapped to it is skipped.

How it loads:

- **Parents first.** The first row with a key is that parent's row: its parent columns create
  or update the parent. Later rows with the same key add related records to it, and their
  parent columns are not loaded, so put the parent's values on its first row.
- **A row with only a key and related columns** adds a related record to the parent that key
  finds, in the file or already in Salesforce. Under **Update or create, matched by external ID**, a key no record holds creates a
  parent with only that value.
- **A parent that fails takes its related records with it.** When a parent row is rejected,
  each later row with the same key is rejected with "The parent record of this row was not
  saved", and nothing is created for it. Fix the parent row and load the rejected rows again:
  the key finds the parents that were saved, so none is made twice.
- **A related record that fails** rejects its own row with the reason. Its parent is still
  saved, and loading the row again finds it by its key.
- **Related records are always created.** A second run of the same file adds them again, so
  load only the rows you fixed, not the whole file.

The dry run decides both, and writes neither. The counts are of your object's rows (a row that
adds a related record to a parent an earlier row named counts as matched), and the run log says
how many related records would be created and how many rows were rejected for theirs. Each row
keeps its related record as its second resulting record. **Undo** deletes the related records
first, then the parents the import created, and puts back the values it changed on parents
that already existed.

## 10. Changing Values as They Load

A file from another system rarely says things the way your database does: names in capitals,
"St." where you write "Street", dates written day first, a first and a last name in two columns
you want as one. You can fix these in the template instead of in the spreadsheet, so the next
file of the same kind is fixed too.

1. On the columns step, select **Change Values** beside a column.
2. Select **Add a Change** and pick one. Changes run in the order listed, and you can add up
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
| **Map values** | Changes each value listed in a table (up to 100 rows) to the value beside it. A value not in the table is kept, or becomes the value in **Anything else** if you give one; an empty cell stays empty. Spaces around the value are ignored, and capitals too unless you tick **Match capitals**. | `CA` becomes `California`, `NY` becomes `New York` |
| **If, then** | When the value equals some text, contains it, or is empty, writes the value you give (leave it empty to clear the cell). **Otherwise** is written when the test fails; leave it empty to keep the value. | equals `N/A`: `N/A` becomes empty |
| **Keep part** | Splits the value at a separator you type and keeps one part, counted from the start, or from the end if you tick **Count from the end**. No such part leaves the cell empty. | separator `@`, part 2: `ana@example.org` becomes `example.org` |
| **First characters**, **Last characters** | Keeps the first or last number of characters you give. | first 5: `97201-1234` becomes `97201` |
| **Shift a date** | Adds or takes away days or months (type a minus sign to go back). It reads a date written year first, so put **Read as a date** before it for other orders. Adding a month to the 31st gives the month's last day. | plus 1 month: `2025-01-31` becomes `2025-02-28` |
| **Today's date** | Writes today's date, or, if you tick **Only when empty**, fills only empty cells with it. | an empty cell becomes `2026-10-13` |

3. The panel shows the first values of the column before and after your changes. Select
   **Done**. The column shows how many changes it has.
4. Select **Preview**. The results show, for the first rows of the file, each changed value
   before and after, under **Changed values**. Matching uses the changed values, so a person's
   email made lower case is matched as lower case.

The changes are saved with the template, like the columns, so the next file starts with them.
They run before **Values for Every Row**: a column a change leaves empty is then filled by the
file's value for every row, if you gave one. A change never runs code and never reads a record:
it only rearranges the text of the row. A date that cannot be read the way you chose is left as
it was, and the field then refuses it as it would any value it cannot take (a one-object load
and a people load both reject the row).

## 11. Skipping Rows, One Row Per Key, and Empty Cells That Clear

Partner and event exports carry test rows, cancelled lines and repeats. Set these on the
columns step, under **Rows to Load**; they are saved with the template like the columns.

- **Skip rows where.** Up to five rules, each a column and a test: **equals** some text,
  **contains** it, or **is empty**. A row any rule matches is skipped. Cells are compared as they
  are in the file (before **Change Values**), ignoring spaces at the ends and capitals. Example:
  skip rows where Status equals `Cancelled`, or where Email contains `@test.`.
- **One row per.** Up to five columns, for example Email, or Event and Email. Only the first row
  of the file with each combination of their values loads; a later row with the same values is
  skipped and says which earlier row it repeats. Spaces at the ends and capitals are ignored,
  and a row whose key columns are all empty is never skipped for this.

A skipped row is not rejected: it is decided when the file is uploaded, before the dry run, and
the dry run, the commit and the run log all count it as skipped ("12 rows were skipped by Skip
rows or One row per"). **View rows** lists each one with its reason; it is not in the rejected
rows file. To load a skipped row after all, change the rule and upload the file again.

**Empty cells clear the field** (one-object loads that update or upsert, section 9). By default
an empty cell leaves the field as it is. Tick **Empty cells clear the field** beside a column
to clear the field instead when the cell is empty, for example to load back an export where you
deleted values in Excel. It is off for every column until you tick it.

- A **value for every row** still fills an empty cell first, so only a cell that stays empty
  clears.
- Records the load creates are not affected: there is nothing to clear.
- A required field or a checkbox cannot be cleared; the run log says so and leaves it.
- The dry run says how many values the commit would clear ("Empty cells would clear 37
  values"), and the commit's run log how many it cleared. Each cleared value is
  journaled, so **Undo** (section 5) puts it back, unless someone has given the field a value
  since.

People imports never clear a field from an empty cell.

## Fields the BarnCRM Admin Role Can Import

Salesforce controls standard fields one by one, and a person with only a minimal profile
could otherwise not write them. So the BarnCRM Admin permission set grants read and edit
access to the standard fields the import templates write:

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

## Field Reference

For building a report on your imports.

| What you want | Object | Field |
|---|---|---|
| One upload and its counts | Data Job | Row Count, Rows Created, Rows Updated, Rows Matched, Rows Rejected |
| Why an import failed as a whole | Data Job | Run Log |
| One row of the file | Import Row | Row Number, Status, Error Message |
| Rows that matched more than one record | Import Row | Several Matches |
| How a template matches rows | Import Template | Person Matching Rule, Person Match Field, Organization Matching Rule, Organization Match Field, Several Matches, Use Duplicate Rules |
| Rows your duplicate rules matched | Import Row | Matched By Duplicate Rule |
| How a template changes values as they load | Import Template | Column Mapping (each column's changes) |
| The values given to every row of a file | Data Job | File Values |
| Whether a file only matched existing records | Data Job | Match Only |
| The records a row resolved to | Import Row | Household, Contact 1, Contact 2, Organization, Resulting Record, Second Resulting Record |
| The control totals of a file | Data Job | Expected Count (and, with Giving, Expected Amount, File Amount) |
| The import a record came from | Account, Contact (and Gift, with Giving) | Created By Import Batch |
| Which templates are for a recurring file, and when each was last used | Import Template | Is Recurring, Source Name, Last Import Date |
| When an import can be undone until | Data Job | Undo Deadline |
| What an import changed on existing records, and what an undo kept | Import Journal | Phase, Entry Count, Entries |
| The records an import that loaded one object created | Import Journal (Phase Created), Import Row | Entries; Resulting Record |
| What a template that loads one object loads, and how | Import Template | Target Object, Load Operation, Load Match Field, Lookup Not Found |
