# Importing

## 1. What it does

Importing loads a spreadsheet of people, households, and organizations into Open Impact
without a consultant, and, with the Giving module installed, their gifts too
([Importing gifts](gift-import.md)). You upload the file, Open Impact suggests which column means what,
you say how a row should be matched against records you already have, and then you run a
**dry run** that tells you exactly what would be created, updated, matched, or rejected
before anything is written. When the preview looks right you commit it, and the results
screen tells you what happened, row by row, including every row that failed and why.

Every record an import creates is tagged with the import it came from, so six months
later you can still answer "where did these 400 households come from".
And for 30 days after you commit it, an import can be undone: the records it created are
removed and the values it changed are put back (section 5).

## 2. How to turn it on

Nothing to turn on. The **Import** tab is in the Open Impact app for anyone with the
**Manage Open Impact Settings** permission. If you do not see the tab, ask whoever set up
your org to give you the Open Impact Admin role on the **Access** page.

A few things are worth knowing before your first large file:

1. Open **Open Impact Settings** and choose **Import**.
2. **Rows per chunk** controls how many rows are processed at a time. Leave it at 200.
   Lower it to 50 if your org has a lot of custom automation and an import fails with a
   limit error; raise it only if a very large file is running slowly and nothing else
   fires on save.
3. **Days an import can be undone** is 30 unless you change it, and can be anything from 1
   to 365. Each import keeps the window it was committed with.
4. **Import** on the same page has an **Open the import wizard** link, which is the same
   place the **Import** tab takes you.
5. With the Giving module installed, the same page has the two donation matching settings
   ([Importing gifts](gift-import.md), section 2).

Open Impact ships two ready-made mappings, a **generic donor list** and a **generic gift
list**. You can edit either one, and your edits are never overwritten by an upgrade. With the
Giving module installed it also ships mappings that read the exports of the system you are
moving from, without renaming a column: see [Migrating from Nonprofit
Cloud](migrating-from-nonprofit-cloud.md) and [Migrating from NPSP](migrating-from-npsp.md).

## 3. A five-minute walkthrough (as Maria)

You need a CSV file or an Excel workbook (.xlsx). A small one is best for the first run: five
or six rows.

1. Open the **Import** tab. Select **Generic contact list**, then **Next**.
2. Select **Upload file** and choose your file. Open Impact reads the header row and shows
   you every column it found, with the first few values from the file underneath each one.
3. Check the columns. Each column shows what Open Impact thinks it is, for example
   "Email" for a column headed `Donor Email`. Change anything that is wrong from the
   picker beside it. A column you do not want loaded is set to **Do not load**, and its
   values are kept on the staged row but written nowhere. The mapping remembers your
   choices: the next file with the same headings opens with them, and a column you set to
   **Do not load** stays that way even when Open Impact recognizes its heading.
4. Choose how rows are matched. **Email exact** is the safe default. Read the sentence
   under each rule before you change it: **Name plus postal code** will treat two
   different people who share a name at one address as the same person.
5. Optionally, under **Control totals**, type how many rows the file should have (and, for a
   gift file, what its amounts should add up to). The dry run checks them and a commit is
   refused while they do not match.
6. Select **Dry run**. Nothing is written. When it finishes you see four counts, "would
   create", "would update", "would match and change nothing", and "would be rejected",
   and a table of the rejected rows with the reason for each one. Select **Download
   exceptions** to get those rows back as a CSV you can fix in your spreadsheet. A new
   person or organization that appears on several rows is counted once as "would create";
   their later rows count as matching them, which is what the commit will do. A donor with
   twelve monthly gifts in the file becomes one person with one household, not twelve.
7. If the preview is wrong, fix the file or the mapping and dry run again. Nothing you
   have done so far has changed a record.
8. When the preview is right, select **Commit**. Processing runs in the background and
   the screen updates as it goes.
9. The results screen shows the same four counts for what actually happened, the run log,
   and links to the records. Select **View rows** to see every row and what became of it.

To check the tag, open one of the new households and look at **Created By Import Batch**.
It links back to the import.

## 4. Two people on one row

Most donor lists give a couple one line: two names, one address, one gift. Map the second
person's columns to **Contact 2** and Open Impact puts both people in the same household.
You get one household with two members, not two households, and it works the same way
whether your org keeps people as contacts or as person accounts.

Where your org keeps people as person accounts, map the columns exactly as you would for
contacts (Email, Mailing Street, Email Opt Out and so on). Open Impact writes each to the
person account's own field for it, and finds the person again by that field when you load
the next file: by their email under **Email exact**, and by their last name and mailing
postal code under **Name plus postal code**. A person account's billing postal code counts
too, because people loaded by other tools often have their postal code only there.

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
  code, Open Impact tells them apart by first name. A row naming one of them alone is matched
  by first name too, so "Jane Smith" finds Jane, not John. When several people share the
  email, or the surname and postal code, and none has the row's first name, a new person is
  created rather than a guess made. First names are compared ignoring capitals but not
  accents: "Jáne" and "Jane" are different names. A row naming Jane alone in the same file
  as the couple's row finds the same Jane, in the couple's household, whichever row comes
  first.
- **Where only one person has that email, or surname and postal code, a row with another
  first name matches them.** Today, with only John Smith at an address, a "Jane Smith" row
  at that address is matched to John and his first name is changed to Jane. Check the dry
  run's Updated rows for this before you commit. (This rule is under review.) Loading the same file again finds each of
  them rather than adding the second person again. Two people on one row with the same
  matching details and the same first name cannot be told apart: that row is rejected.
  Under the email rule, a second person who shares the first person's email needs a last
  name unless they are already in your org with that email and first name.

## 5. Undoing an import

An import you regret can be undone for 30 days after you commit it. Undo removes the gifts,
people, households and organizations that import created, and puts back the values it changed
on records you already had. It does not touch anything else. A gift with a receipt is never
removed, and neither is its donor ([Importing gifts](gift-import.md), section 6).

1. Open the **Import** tab. **Recent imports** lists your last imports, newest first, with
   the date each one can be undone until.
2. Select **Undo** beside the import. Open Impact counts what it would remove (gifts,
   people, households and organizations) and how many changed values it would put back, and shows
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
- **It keeps a record that has gained something since.** If somebody recorded a gift, a
  relationship, an affiliation or an address for a person the import created, that person is
  kept, and so is their household. A household somebody else has joined is kept too. Each
  record kept is listed with the reason in the import's journal.
- **It does not overwrite a correction.** A value somebody has changed since the import is
  left as they set it, and listed as not put back.
- **It does not empty the recycle bin.** Deleted records go to the recycle bin, where you can
  restore them for as long as Salesforce keeps them.

An undo that stops part way, for example because of a limit error, shows **Undo failed**.
Select **Undo** again: it finishes the job without repeating what it already did.

**Days an import can be undone** in **Open Impact Settings**, **Import**, sets the window, from
1 to 365 days. The window is fixed when an import is committed, so changing the setting only
affects imports you commit afterwards.

## 6. Files that arrive every month

Some files come back on a schedule: a monthly export from your payment processor, a
quarterly list from a partner. Mark the mapping you use for one as recurring and the Hub
keeps track of it for you.

1. Open the **Import** tab and choose the mapping.
2. Select **This file arrives regularly**, and give the source a name you will recognize,
   for example "Monthly processor export". The name is required while the box is ticked.
3. Select **Next** and import the file as usual.

The Open Impact home page then lists every recurring source with the date it was last
imported, oldest first, and **Never** for one you have not loaded yet. When a date is older
than you expect, that file has not been loaded this month.

Marking a mapping recurring changes nothing about how its files are imported. Open Impact
never fetches or loads a file on its own: every file is still uploaded, dry run and
committed by a person, because an import nobody watched is an import nobody checked.

## 7. Common mistakes

**An Excel file shows the wrong columns, or none.** Only the **first sheet** of a workbook is
read, and its first row must be the column headings. Move the sheet you want to the front, or
copy it into a workbook of its own. A formula is read as the value Excel last saved for it,
and a date as the date, whatever format the cell shows. An older .xls file, or a
password-protected workbook, cannot be read: save it as .xlsx or CSV and upload that. A
browser too old to open a workbook says so; save the sheet as CSV instead. So does a workbook
too large to open in the browser (more than 500,000 rows or 1,000 columns, or a sheet over
100 MB once unpacked).

**"This import is already running a dry run or a commit."** Only one run of an import goes
at a time. Wait for the one running to finish (its results appear when it does), then start
again. While it runs, rows it has not reached yet still show the previous run's result.

**An import shows Failed although you did not see it fail.** Salesforce stopped its dry run or
commit before it finished (for example, the job was aborted in Setup). If it was a dry run,
run the dry run again. If it was a commit, part of the file may already be loaded, and a
committed import cannot be dry run or committed again: undo it, which removes what it loaded
(anything changed since it stopped is kept), then upload the file as a new import.

**"No column was matched to a name or an email."** The dry run refuses to run when the
mapping has no way to identify a person or an organization. Usually the file's header row
is not the first row: a title line or a blank line above it means Open Impact read the
wrong row as the header. Delete the rows above the header in your spreadsheet and upload
again.

**Every row comes back as "would create" when you expected updates.** The matching rule
is not finding your existing records. **Email exact** matches only when the email in the
file is exactly the email on the record, so a file of work addresses will not match
people whose personal address you hold. Run a dry run with a different rule, or add an
external identifier column to the file and use **External ID**.

**Rows rejected with "Required value missing: last name".** A person needs a last name.
Rows where the name column is empty, or where a single "Full Name" column was mapped to
first name only, fail this way. Map the full name column to **Full name** and Open Impact
splits it, or split the column in your spreadsheet.

**The import finished but some rows failed.** That is by design: one bad row does not
throw away the rest of the file. The failed rows are counted as rejected, each carries the
reason, and none of them wrote anything. Fix those rows in your spreadsheet, save them as
a smaller file, and import that file on its own.

**Salesforce warned about duplicates, and the import saved the people anyway.** An import
saves past a duplicate rule set to alert, as a bulk load does, so a couple at one address or
a person resembling someone already here is not rejected. Afterwards run the duplicate scan
(see [Duplicates](duplicates.md)) to review any pair it made. A duplicate rule set to
**Block** still blocks: those rows are rejected with the rule's message, although the dry run
counted them as would create, because a dry run saves nothing for the rule to check.

**The run log says "Not loaded: you do not have access to" a field.** Your user may not
edit that field, so its column was skipped on every row, in the dry run and in the commit, and
the rest of each row loaded. The run log names each such field once. The Open Impact Admin role
lets you edit the standard fields import mappings use (see "Fields the Open Impact Admin role
can import" below), so this usually means a column mapped to some other field, or a user
without that role. Ask your Salesforce administrator for edit access to the field and import
the file again: the second import matches the people it already created and adds the
missing values.

**The run log says "Not matched on" a field.** Your user may not read the field your
matching rule uses (for example Email under **Email exact**), so nobody in the file could be
found by it, and a person your org holds only by that field counts as new. Where people
are person accounts this can be one of the two postal codes (mailing or billing) while the
other still matches. Do not commit: ask your Salesforce administrator
for access to the field, then dry run again.

**Gift columns in the file were not loaded.** Gifts are loaded by the Giving module. Without
it, gift columns are recognized and kept with the staged row, and the run log says so. With
it installed, see [Importing gifts](gift-import.md).

**"The control totals do not match."** The dry run counted a different number of rows, or a
different total of gift amounts, from the control totals you typed. The run log gives both
numbers. Fix the file or the totals and dry run again; the commit is refused until they agree.

## Fields the Open Impact Admin role can import

Salesforce controls standard fields one by one, and a person with only a minimal profile
could otherwise not write them. So the Open Impact Admin permission set grants read and edit
access to the standard fields the import mappings write:

| Object | Fields |
|---|---|
| Contact | Email, Phone, Mobile Phone, Home Phone, Mailing Address, Title, Birthdate, Email Opt Out, Fax Opt Out, Do Not Call |
| Account (households and organizations) | Billing Address, Phone, Website |

Where people are person accounts, access to their person fields (Person Email, Person
Mailing Address and the rest) follows the contact fields of the same name, and a person's
phone is the account's Phone.

**Birthdate is sensitive.** It is granted so a migration file's birthdates are not lost, but
your organization may not want everyone with Open Impact Admin to see it. To withhold it, give
your administrators a permission set that does not include it, or ask your Salesforce
administrator to remove Birthdate from a cloned role: the importer then skips the column and
says so in the run log, and nothing else in Open Impact needs it.

## Field reference

For building a report on your imports.

| What you want | Object | Field |
|---|---|---|
| One upload and its counts | Import Batch | Row Count, Rows Created, Rows Updated, Rows Matched, Rows Rejected |
| Why an import failed as a whole | Import Batch | Run Log |
| One row of the file | Import Row | Row Number, Status, Error Message |
| The records a row resolved to | Import Row | Household, Contact 1, Contact 2, Organization, Gift, Soft Credit |
| The control totals of a file | Import Batch | Expected Count, Expected Amount, File Amount |
| The import a record came from | Account, Contact, Gift | Created By Import Batch |
| Which mappings are for a recurring file, and when each was last used | Import Template | Is Recurring, Source Name, Last Import Date |
| When an import can be undone until | Import Batch | Undo Deadline |
| What an import changed on existing records, and what an undo kept | Import Journal | Phase, Entry Count, Entries |
