# BarnCRM feature catalog

BarnCRM is a free, open source suite of Salesforce packages: a neutral Core for any organization, plus optional modules for giving, integrations, volunteers, programs and funders. This catalog lists what each package does, grouped by module and category, Major features first, with the status of each item as of 2026-10-13 (main at PR #219, which landed batches 2 to 7).

**How this is kept current:** the catalog is updated in the same pull request that adds, changes, or removes a feature. A branch that builds a feature sets its row to "Built, not merged" with the branch name; the merge makes it "Shipped".

**Legend**

- **Major**: a headline capability a buyer or admin would name.
- **Minor**: a supporting capability, setting, or refinement.
- **Shipped**: merged to main. No package version has been created yet (the namespace is deferred), so "Shipped" means built and on main, not yet installable as a released package.
- **Built, not merged**: built on the named branch or open pull request, waiting for review, an org test run, or the branches it is stacked on.
- **Replaced**: shipped earlier and superseded by the feature the row names; kept in the code only where the row says.
- **Planned**: in the product plan roadmap (iteration shown where the plan gives one). "Proposed" marks an idea recorded for consideration, not approved or scheduled.
- **Feature ID**: the product plan ID (C = Core, G = Giving, X = Connect, V = Volunteers, P = Programs, L = Logic Models, F = Funders), or an ADR where the capability came from a decision rather than a numbered feature. "new ADR" is a decision record still on its branch; it gets a number when it merges.

**Editions and suites**

| Suite | What it is | Packages |
|---|---|---|
| Community Suite | For businesses, clubs and any organization that is not a nonprofit | Core alone, plus modules that fit (Volunteers; Events later) |
| Impact Suite (Nonprofit Edition) | For nonprofits; a choice any organization can make | Core plus Giving, with Connect, Volunteers, Programs, Logic Models and Funders offered as further modules |

An admin installs Core, then turns on the Nonprofit Edition, which opens Salesforce's installer for Giving; other modules are offered the same way. A module that is never installed leaves nothing in the org.

---

## 1. Core

**Suite:** both. Core is neutral: households, relationships, addresses, import, rollups, settings, Health Check and the Setup Assistant carry no nonprofit wording (C-29, merged in PR #163). The BarnCRM names landed in PR #181. Core installed alone is the Community Suite.

### 1.1 People and Households

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Household model | Major | Groups the people you treat as one donor or customer into a household record, created automatically for every new person. | Shipped | C-01 |
| Two ways of belonging to a household | Major | Supports a simple model (a person belongs to one household) and a flexible model (membership is its own record, so a person can be in several households, with role, primary flag and dates). A membership names exactly one person, and a second current membership of one person in one household is refused. | Shipped | C-01, C-22 |
| Household names and greetings | Major | Writes and keeps current a household name, a formal greeting and an informal greeting from patterns you set, with a live preview. | Shipped | C-02 |
| Household merge and split | Major | Merges two households into one or moves people out into a new or existing household from buttons on the household page, recalculating totals. | Shipped | C-09 |
| Merge and split finish in place | Minor | Merge and split confirm in a platform dialog; afterwards the action window closes and the household page and members panel refresh without a reload. | Built, not merged (feature/q-05-modern-dialogs-1) | C-09, Q-05 |
| Person Account support | Major | Works fully in orgs that store people as person accounts (as Nonprofit Cloud orgs usually do), without depending on them. | Shipped | C-22 |
| Multiple email addresses | Major | Gives each person personal, work and alternate email boxes plus a Preferred Email choice that keeps the standard email field in step, with its own switches on the Automation page, separate from household upkeep. | Built, not merged (fix/people-20) | C-25, PEOPLE-28 |
| Automatic household creation switch | Minor | Setting to turn automatic household creation on or off (ships on). | Shipped | C-01 |
| Delete empty households setting | Minor | Optional tidy-up that removes a household when its last member leaves; ships off, and never removes a household something outside BarnCRM depends on. | Shipped | C-01, ADR-0036 |
| Households with gifts are kept | Minor | The empty household tidy-up never removes a household that gifts or pledges are credited to, so past gifts keep their household. | Shipped | ADR-0070 (D-20) |
| Membership model chosen at install | Minor | Install looks at the org and picks the simple or flexible membership model; the setting refuses a switch that would hide membership data you already have. | Shipped | C-01 |
| Greeting tokens and preferred names | Minor | Patterns use first name, last name and salutation tokens, and a person's preferred name replaces the first name in greetings. | Shipped | C-02 |
| Deceased members in greetings | Minor | Leaves a deceased person out of greetings, with "the late" option in the formal greeting. | Shipped | C-02 |
| Exclude from name or greetings | Minor | Per-person boxes to leave someone out of the household name, or out of the greetings, while still counting them as a member. | Shipped | C-02 |
| Custom name lock | Minor | A "custom name" box on a household stops BarnCRM recalculating its name and greetings. | Shipped | C-02 |
| Different surnames and hyphenated names | Minor | Naming handles couples with different surnames, hyphenated names and member ordering. | Shipped | C-02 |
| Household panel on a person | Minor | Panel on each person's page naming their household and other members, with a link back. Placed on the shipped contact page; an admin can add it to a person account page. | Shipped | C-01 |
| Primary contact follows the primary member | Minor | The household's primary contact mirrors whoever is marked primary on its members, including person accounts; nobody is promoted automatically when the primary leaves. In the simple model the primary contact must be a member, and a new household names its first person. | Shipped | C-22, ADR-0044, ADR-0107 |
| Household Members panel | Minor | Panel on the household page listing members, marking the primary, with Make primary and Add member (search for or create a person; a person account where the org stores people that way). | Shipped | C-01, ADR-0107 |
| A contact saved into a household joins it | Minor | In the flexible model, a new contact whose account is a household gets a membership there, so it is counted and named and not given a second household. | Shipped | ADR-0107 |
| New household button | Minor | One click on the Hub home opens a new household with a placeholder name that is replaced once a member is added. | Shipped | C-01 |
| Households follow person changes | Minor | Renaming, deleting or restoring a person recounts and renames their households in both membership models. | Shipped | C-01 |
| Member count | Minor | Keeps each household's member count correct as people join, move or leave. | Shipped | C-01 |
| Nonprofit Cloud household guards | Minor | Detects households Nonprofit Cloud already manages and never renames, readdresses, deletes or duplicates them. | Shipped | X-09 (in Core) |
| Interaction notes | Minor | A "Log an interaction" action on person and organization pages records a meeting or contact report as a completed activity, for major-gift work. | Shipped | C-39 |

### 1.2 Relationships and Affiliations

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Relationships | Major | Records how people are connected (spouse, parent, sibling, friend, colleague) and writes the matching record on the other person automatically. | Shipped | C-15 |
| Affiliations | Major | Records a person's connection to an organization (employer, board, congregation) with role, dates and one primary. | Shipped | C-16 |
| Eleven non-gendered relationship types | Minor | Ships types such as Parent and Child, Grandparent and Grandchild, Spouse, Partner, Sibling, Friend and Colleague, none gendered. | Shipped | C-15 |
| Keep both sides in step setting | Minor | Org-wide or per-record switch for reciprocal relationship upkeep; editing or ending one side changes the other. Restoring either side from the recycle bin brings the other back. | Shipped | C-15 |
| Primary affiliation on the person | Minor | The person's primary organization is shown on their record; ending that affiliation clears it. | Shipped | C-16 |
| Overlapping affiliation check | Minor | Refuses a second affiliation with the same organization and role whose dates overlap one on file. | Shipped | C-16 |

### 1.3 Addresses

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Address records | Major | Keeps many addresses per household, organization or person, with one default copied into the standard address fields so mail merges and other apps keep working. The first address added is the default, the address in use cannot be unticked on its own, and a deleted default is replaced by a non-seasonal address first. | Shipped | C-17 |
| Seasonal address swap | Major | A nightly job swaps in a seasonal address on its start date and puts the previous one back when the season ends, with its last run shown in the app. | Shipped | C-18 |
| Household or personal address setting | Minor | Decides whether editing one person's address moves the whole household (default) or gives that person an address of their own. | Shipped | C-17 |
| Person account address capture | Minor | A person held as a person account who is saved with a mailing address, or whose mailing address changes, gets an address record of their own. | Built, not merged (fix/people-21) | PEOPLE-17 |
| Seasons that cross New Year | Minor | A season such as November to March is handled as one range. | Shipped | C-17, C-18 |
| Overlapping season report | Minor | Two seasonal addresses covering the same day are reported rather than silently chosen. | Shipped | C-18 |
| Swap scheduling in the app | Minor | Schedule, unschedule and "Run the swap now" from settings, with a "not run in 36 hours" warning. | Shipped | C-18 |
| Verification-ready fields | Minor | Verification status and date fields that BarnCRM never writes, so an address verification app can own them. | Shipped | C-17 |

### 1.4 Data Quality

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Duplicate scan and review | Major | Scans existing people and households with Salesforce's own duplicate rules and lists every likely pair on one page for review. Never proposes a Nonprofit Cloud household or a person account paired with a contact; one scan runs at a time; organization pairs written on save do not hide the households behind them; a person account rule alone starts no households pass. | Shipped; fixes built, not merged (`fix/duplicates-1`, `fix/duplicates-2`, `fix/duplicates-3`) | C-20 |
| Household merge from a duplicate pair | Minor | Merges a duplicate household pair in one step using the standard household merge. | Shipped | C-20 |
| Person merge upkeep | Minor | After Salesforce's person merge, the kept person joins the other's households and totals recalculate. Shortly after any Salesforce merge, the kept record keeps one default address, a kept person loses relationships with themselves and second copies, their primary affiliation is chosen again, and a household merged this way is recounted and renamed, with a person who was in both households left with one membership. | Built, not merged (fix/people-13-merge) | C-20 |
| "Not a duplicate" dismissals | Minor | A dismissed pair, with a reason, is not suggested again, including when a duplicate rule reports it again on save; any BarnCRM Admin can delete one. | Shipped; fix built, not merged (`fix/duplicates-1`, `fix/duplicates-2`) | C-20 |
| Duplicate Review permission set | Minor | Separate permission set for reviewing suggestions (assigned in Setup, because Salesforce limits it to Sales and Service Cloud licenses). | Shipped | C-20, ADR-0050 |
| People without a household, empty households | Minor | Health Check counts and links people in no household and households with nobody in them, changing nothing. | Shipped | C-21 |
| Relationships and affiliations with no person | Minor | Health Check counts and links relationships with no person on one side and affiliations with no person (left by a person delete), changing nothing. | Built, not merged (fix/people-19) | PEOPLE-19 |
| Org Optimizer | Major | The Data Hygiene tab becomes Org Optimizer: one page with lazily loaded sections for data quality, duplicates, field utilization and Health Check (run on demand), each shown only to people who may use it. Duplicate review moves here from BarnCRM Settings, which keeps a link. | Built, not merged (`feature/org-optimizer-shell`) | ADR-0103 |
| Org Optimizer: errors, storage and limits | Minor | Errors section (unread count, recent entries, acknowledge, link to the Error Log) and a read-only Storage and limits section: data and file storage, daily API requests, background jobs and single emails used, and the records BarnCRM's own objects keep at about 2 KB each. | Built, not merged (`feature/optimizer-errors-storage`) | ADR-0103 |
| Org Optimizer: unused setup | Minor | Admin-only, read-only section listing setup nobody seems to use: users not logged in for 90 days, unassigned permission sets, reports not run for a year, never-used email templates, inactive flows, and scheduled jobs owned by inactive users, each with a count, five names and a Setup link. | Built, not merged (`feature/optimizer-setup-checks`) | ADR-0103, owner decision 2026-10-13 |
| Org Optimizer: more data-quality checks | Minor | Three more Data quality checks with Open in Find: people with no way to reach them, deceased people who can still be emailed, and people not changed in a number of years set in BarnCRM Settings (1 to 20, default 5). | Built, not merged (`feature/optimizer-quality-checks`) | C-28, ADR-0079, D-40 |
| Org Optimizer: unused setup thresholds | Minor | The days before a user (default 90, 30 to 365) or a report (default 365, 90 to 1,095) counts as unused are BarnCRM settings under General, bounded. | Built, not merged (`feature/optimizer-thresholds`) | D-40 |
| Org Optimizer: object limits and record types | Minor | Two more admin-only Unused setup checks over Account, Contact and BarnCRM's own objects: objects at 80% or more of their edition's custom field limit, and record types that are inactive or that no record uses. Bounded work: one describe per object, one record type query, at most 50 one-row lookups. | Built, not merged (`feature/optimizer-object-limits`) | ADR-0103 |
| Data hygiene console | Minor | One page for orphans, missing households and bad addresses, built on saved queries; people with no household counted as Health Check counts them. | Shipped; fix built, not merged (`fix/duplicates-2`) | C-28 |

### 1.5 Import and Data Management

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Complete import exceptions file | Minor | Download exceptions holds every rejected row (up to 100,000 per download), read through an Apex pagination cursor, written with the same Excel-safe CSV writer as Find (byte-order mark, formula guard); the rejected-rows table says when it shows only the first 200. | Built, not merged (feature/q-03-apex-cursors) | Q-03, C-14 |
| Data Job records | Minor | Import, bulk update and bulk delete records read **Data Job** (plural **Data Jobs**), since all three are data jobs; the tab stays **Import**; API names are unchanged. | Built, not merged (`fix/data-jobs-relabel`) | ADR-0047 |
| Import wizard | Major | Uploads a spreadsheet, suggests column mappings, runs a dry run showing what would be created, updated, matched or rejected, then commits with per-row results; the single quote a Find export puts before = + - or @ is taken off, so an exported phone number loads as it was. | Shipped; fix built, not merged (`fix/find-4`) | C-14 |
| Import results file | Minor | Download results gives every row of a finished import (people or Load one object) with its outcome, the record IDs it created, updated or matched, and the reason for a rejected row, beside the row's own columns, to reconcile against the source system or load the next file by record ID. | Built, not merged (feature/import-results-file) | Data tools parity rank 3, C-14 |
| Import undo | Major | Undoes a committed import within a set window: removes what it created and puts back values it changed, keeping anything that has since gained a life of its own. | Shipped | C-19 |
| Excel workbook import | Major | Reads .xlsx files directly in the browser, no CSV conversion needed. | Shipped | C-19, ADR-0049 |
| Separator and sheet choice | Minor | Detects whether a text file's columns are separated by commas, semicolons, tabs or pipes, with a choice to change it, and lets you pick which sheet of a workbook to load. | Built, not merged (feature/import-delimiter-sheet) | Data tools parity rank 10, ADR-0049 |
| Import matching rules | Major | Separate matching rules for people and for organizations (email, name plus postal code, or an ID field you choose), set per file in the import wizard. | Shipped | C-32 |
| Find | Major | A Find tab that builds a query over one object from lists (no typing a query), shows the matching records, and exports them to CSV; deleting a saved query asks first (saying so when it is shared), and the SOQL preview waits for a pause in typing. | Shipped; fix built, not merged (`fix/ui-1`) | C-34 |
| Load one object | Major | Inserts, updates or upserts any object, including custom ones, with the same dry run, journal and undo. | Shipped | C-33 |
| Lookups by any field | Minor | A Load one object lookup column finds its parent by any text, email or phone field, such as an organization's phone; a field Salesforce does not index is refused on an object over 100,000 records. | Built, not merged (`feature/load-match-any-field`) | C-33, R-IT13 |
| Update by a field you choose | Minor | Load one object updates the record a text, email or phone field you choose finds, such as a contact's email, people included; a row that finds nothing is rejected and nothing is created. | Built, not merged (`feature/load-update-by-field`, stacked on `feature/load-match-any-field`) | C-33, R-IT12 |
| Related records in one file | Major | Load one object also creates a related record from each row (sessions of a program, attendees of an event), grouped by the parent key; parents load first, rows of a failed parent are rejected, and one dry run and one undo cover both. | Built, not merged (`feature/load-related-records-1` to `-3`, stacked on `feature/load-update-by-field`) | C-33, R-IT17 |
| Import row rules | Minor | Skip rows where a column equals, contains or is empty (logged Skipped, not Rejected), One row per chosen key columns (later repeats skipped and listed), and Empty cells clear the field per column for one-object updates and upserts (off by default, dry run counts what it would clear, journaled so undo restores). | Built, not merged (`feature/import-filter-dedupe-blanks-1`, `-2`) | Data tools parity ranks 8 and 9, ADR-0113 (`0113-import-row-rules.md`) |
| More transform steps | Minor | Map values (a from and to table with anything else and match capitals), If then (equals, contains, is empty), Keep part, First and last characters, Shift a date (days or months) and Today's date, in import column changes and bulk update; still a closed step list with no evaluation, document version 2. | Built, not merged (`feature/transform-steps-2-1`, `-2`) | Data tools parity rank 6, ADR-0112 (`0112-more-transform-steps.md`) |
| Data Manager | Major | A Data Manager tab with a card for each data tool the person may use (import, find, bulk update, bulk delete, Org Optimizer), the import mappings, every data job in one list, and links to Salesforce's own export and Recycle Bin. Import and Bulk Update leave the app navigation and open from here. | Built, not merged (`feature/data-manager-hub`) | ADR-0103 |
| Data job history | Minor | One list of imports, bulk updates and bulk deletes, newest first, filtered by kind, with counts, undo deadline and each tool's own Undo confirmation; replaces the three separate history lists on the Import and Bulk Update tabs; the list refreshes by itself while a job or an undo is running. | Built, not merged (`feature/data-job-history`, `fix/ui-1`) | ADR-0103 |
| Erase a person | Major | Erases one person on request (right to be forgotten): empties every personal field, deletes their addresses, ends relationships, affiliations and household memberships, marks the Individual record Forget, keeps anonymous totals and gifts, and writes an Erasure record that holds no erased value. Own permission set in no role, preview of exactly what changes, typed name to confirm, not undoable. | Built, not merged (`feature/erase-person-1`, `-2`, `-3`) | new ADR (`0110-erase-a-person-anonymizes-in-place.md`) |
| Bulk update | Major | Sets, clears or copies up to five fields on the records a Find query returns, with a count preview, journal and undo (also for a job stopped part way); a household's name is left to household naming, a value too long to undo is refused, and access taken away part way stops the job with the reason; each person lists their own jobs (an administrator may list everyone's), the first refusals are listed wherever they fell, and the chunk size is a setting (10 to 200); progress polling slows after a minute and retries once on an error. | Shipped; fix built, not merged (`fix/bulk-1`, `fix/bulk-2`, `fix/bulk-4`, `fix/ui-1`) | C-35 |
| Bulk update with steps | Minor | Changes each record's own value in a bulk update with the import's transform steps (find and replace, tidy text, add other fields, read a date), previewed before and after; date, date and time, and whole-number fields read and save exactly; a checkbox result that is not a yes or no word is refused; Capitalize each word is fast on long text; a stopped job's run log says how many records were not reached. | Shipped (#219); fix built, not merged (`fix/bulk-1`, `fix/bulk-3`) | C-37, ADR-0081 |
| Bulk delete | Major | Deletes the records a Find query returns, behind its own permission set and a per-job run limit, with a count preview, cascade warning, typed confirmation, journal and undelete from the Recycle Bin, including households automation emptied and a job stopped part way; the import's undo refuses it; each person lists their own jobs (an administrator may list everyone's), and the chunk size is a setting (10 to 200); progress polling slows after a minute and retries once on an error. | Shipped (#219); fix built, not merged (`fix/bulk-1`, `fix/bulk-2`, `fix/bulk-4`, `fix/ui-1`) | C-37, ADR-0091 (`0091-bulk-delete-from-a-find-query-with-undelete.md`) |
| Delete by file | Major | Load one object's Delete by record ID: a file's record IDs are dry run as an import, then deleted as a bulk delete once the count is typed, with the cascade warning, journal and undelete; needs Bulk Delete Records, not Find. | Built, not merged (`feature/delete-by-file`, `feature/delete-by-file-2`) | C-37, ADR-0114 (`0114-delete-by-file.md`) |
| Download before delete | Minor | "Download these records first" on the bulk delete and delete by file panels: every record the delete would delete, with every field the person can see, saved as CSV before the count is typed. | Built, not merged (`feature/backup-before-delete`) | C-37 |
| Shipped mappings | Minor | Generic donor list and generic gift list mappings that upgrades never overwrite once edited. | Shipped | C-14 |
| Two people on one row | Minor | A row naming two people creates one household with both in it, in either membership model. | Shipped | C-14 |
| Import tagging | Minor | Every record an import creates is tagged with the import it came from. | Shipped | C-14 |
| Import journal | Minor | Records every value an import changed on existing records, and what each undo kept and why. | Shipped | C-19 |
| Days an import can be undone setting | Minor | Undo window from 1 to 365 days (default 30); each import keeps the window it was committed with. | Shipped | C-19 |
| Trial import, then the rest | Minor | After the preview, imports only the first rows for real (25 by default, a BarnCRM Settings Import setting, changeable per file), shows their results, then imports the remaining rows into the same import with one undo for both. | Built, not merged (feature/import-trial-run) | Data tools parity rank 4, R-IB16 |
| Rows per chunk setting | Minor | Controls how many rows are processed at a time (default 200) for orgs with heavy automation. | Shipped | C-14 |
| Recurring file tracking | Minor | Mark a mapping as "arrives regularly" and the Hub home shows when each recurring source was last loaded. | Shipped | C-19 |
| Skipped-field reporting | Minor | The run log names any mapped field the user cannot edit instead of dropping values silently. | Shipped | C-14 |
| "Do not load" remembered | Minor | A column set to Do not load stays that way on the next upload. | Shipped | C-14 |
| Duplicate-safe new donors | Minor | A new donor appearing on several rows is created once, and the dry run counts them once. | Shipped | C-19 |
| Person account import | Minor | Imports email, address, opt-outs, birthdate and title onto person accounts and re-finds them on a second load. | Shipped | C-14 |
| Checkbox values in imports | Minor | Reads yes, y, x, checked, on and their opposites in any case as ticked or cleared; any other value leaves the box as it was and is named by row, column and value in the run log. | Built, not merged (`fix/import-unrecognized-checkbox`) | C-14, R-IT11 |
| First-name matching guard | Minor | A row whose first name differs from the only match at the same key creates a new person instead of renaming the existing one. | Shipped | C-14 (plan 11.2 item 17) |
| Neutral import wizard | Minor | Without Giving installed, the wizard offers no gift columns, and the gift templates live in Giving. | Shipped | C-29 |
| Match by an ID field you choose | Minor | Pick which external ID field a file matches on, for people and for organizations. | Shipped | C-32 |
| When a row matches several records | Minor | A setting decides what happens when a row matches more than one record: reject the row (the default) or use the most recently changed record; either way the row is flagged for review. | Shipped | C-32 |
| Import runs as previewed | Minor | The import uses the template exactly as its preview ran with it; a template edited after the preview changes the next preview, not the import. | Built, not merged (fix/import-2) | C-14 (IMPORT-1) |
| One way to read and compare values | Minor | People imports read dates in the user's locale, numbers as spreadsheets export them (currency symbols, locale grouping, bracketed negatives; fix/import-9) and times as Load one object does; a value a field cannot take rejects the row with the field named; a re-import updates only real changes, capitals included. | Built, not merged (fix/import-3) | C-14 (IMPORT-4, IMPORT-8) |
| Rejected rows create nothing | Minor | A row rejected for its person (no last name, several matches) creates no organization, so the preview and the import agree; a row that fails part way points at what it saved. | Built, not merged (fix/import-4) | C-14 (IMPORT-3) |
| Affiliations from imports | Minor | A people import links each row's first person to the organization on the row with an affiliation, or finds the one they have; counted in the preview and removed by undo. An Affiliation: role column sets a new affiliation's role. | Built, not merged (fix/import-5, role column fix/import-6) | C-32 (IMPORT-10, IMPORT-22), R-AF5 |
| Original file kept up to 2.5 MB | Minor | The wizard keeps a copy of an imported file up to 2.5 MB and says when a larger one, or one that could not be saved, imports without it. | Built, not merged (fix/import-6) | C-14 (IMPORT-23) |
| Import templates added at install and upgrade | Minor | Each package adds the import templates it ships when installed, and an upgrade adds templates a later version ships, leaving edited ones as they are. | Built, not merged (fix/import-7) | C-14 (IMPORT-19), D-41 |
| Import row cleanup | Minor | A nightly job removes the staged rows of imports that finished more than 90 days ago (adjustable in BarnCRM Settings, Import; 0 keeps them); the import keeps its counts, run log and undo. | Built, not merged (fix/import-8) | C-14, D-40, R-IR5 |
| Retry fixed rejected rows | Minor | After a commit with rejected rows, upload the fixed rows (up to 10,000) on the results step: they are previewed, then committed into the same import, the replaced rows are marked Retried, and one undo removes both. Only the person who committed it, while it can be undone. | Built, not merged (feature/import-retry-rejects) | C-14, R-IB17 |
| Values for every row | Minor | Give a value the whole file shares (such as a city missing from every row) once; a row with its own value keeps it. | Shipped | C-32 |
| Match by Salesforce record ID | Minor | A file that carries Salesforce record IDs matches on them directly. | Shipped | C-32 |
| Match only | Minor | A file can be set to update records it finds and never create new ones. | Shipped | C-32 |
| Your own fields in the wizard | Minor | The wizard offers the org's own custom fields as mapping targets. | Shipped | C-32 |
| Import undo keeps households with gifts | Minor | Undoing an import keeps a household that gifts or pledges are credited to, and journals why. | Shipped | C-19, ADR-0070 (D-20) |
| Find conditions | Minor | Conditions on the object's fields and related records, relative dates such as "in the last 30 days", and custom condition logic; a multi-select field's equals reads "is exactly", since it matches the whole set of values. | Shipped; fix built, not merged (`fix/find-3`) | C-34 |
| Saved and shared queries | Minor | Save a Find query under a name to run again, and share it read only with everyone who uses Find; Save as keeps the new copy open even when another query has the same name; a person's own queries are listed before shared ones, so other people's never push hers off the list. | Shipped; fix built, not merged (`fix/find-1`, `fix/find-2`) | C-34 |
| Find export to Files | Minor | Runs a Find export on the server, past what a browser can hold: CSV files of up to 50,000 rows in the person's Files, the export row limit enforced on the server, progress on the page and a notification when ready. | Built, not merged (`feature/find-server-export`, `feature/find-server-export-2`) | C-36, ADR-0115 (`0115-find-export-to-files.md`) |
| Find export | Minor | Exports every matching record (not only the rows on screen) to CSV, up to an export row limit set in the app (a convenience stop, not a security control); results follow each person's own access; date-times are shown and exported with their time in the person's Salesforce time zone; a shared query's column the person cannot see is left out with a notice; the file name carries the person's local date. | Shipped; fix built, not merged (`fix/find-3`, `fix/find-4`, `fix/ui-1`) | C-34 |
| Advanced Find | Minor | Typed queries checked through the same builder, child records, aggregates (grouped only by fields Salesforce can group, dates shown as dates), XLSX export (cells cut at Excel's 32,767 characters, the sheet built a piece at a time so a large export never needs one huge string) and inline edit; the platform's share, history and feed tables are not offered; the SOQL shown reads back as typed, backslashes included, and a query of the wrong shape is refused with a message; each object is described once per request however many paths cross it. | Shipped; fix built, not merged (`fix/find-1`, `fix/find-2`, `fix/find-3`, `fix/find-4`) | C-36, ADR-0078 |
| Data transforms and duplicate-rule matching (part 1) | Minor | Import column changes (a declarative step list, no code evaluation) previewed before and after, a shared DataTransform engine for bulk update, and matching through the org's active duplicate rules with the template's several-matches policy (a person account rule counts for person accounts only, an account rule for organizations; a contact import never matches the contact half of a person account). | Shipped (part 1); bulk update steps and bulk delete shipped (#219); fix built, not merged (`fix/duplicates-2`, `fix/duplicates-3`) | C-37, ADR-0081 |
| Scheduled imports and external sources | Minor | Loads from SFTP, cloud storage or other systems on a schedule, committing only within admin-set limits. | Planned (1.x) | C-38 |

### 1.6 Automation and Rollups

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Rollup engine | Major | Calculates totals on households, people, organizations and module records from definitions admins manage in the app, with Real time, Scheduled (nightly) or Both modes. | Shipped | C-13 |
| Trigger framework | Major | One shared trigger dispatcher for every module: each object has a one-line trigger, and the handlers it runs, and their order, come from a registry, so modules add behavior without editing each other's triggers. Every handler can be switched off, paused or bypassed (except rules marked always-on), and failures are logged and shown as a plain message instead of a stack trace. | Shipped | C-04, ADR-0017, ADR-0024 |
| Automation control | Major | Lists every packaged automation with a description and an on/off switch, plus a global pause for bulk loads. | Shipped | C-04 |
| BarnCRM's own rollup engine | Major | BarnCRM's own calculation core replaces the vendored apex-rollup library: it plans each record's totals in a few queries, writes only totals that changed, and handles totals in the record's currency. It is the only rollup path since rollup slice S8, with instant recalculation, a queue with retry, and a full nightly run. | Shipped | ADR-0082 (supersedes ADR-0015), ADR-0083 |
| Rollup operations | Minor | Count distinct, Any and None into checkboxes, First and Last into text, text lists with a delimiter and an each-value-once option, and a save check on the target field type. | Shipped | ADR-0082 |
| Rollup Builder | Major | A Rollup Builder tab and app page where admins create, edit and copy any rollup, shipped or their own, in five steps with a filter builder and never a query. Saving refuses a second rollup that would write the same field for the same records, and field history records who changed how a total is calculated. | Shipped (#219) | ADR-0082 (rollup slice S11) |
| Rollup preview and estimate | Minor | Previews an unsaved rollup on one record next to what the record holds now, and says how many records it would maintain. Recalculate all first says how many records it goes through and roughly how long, and offers Run tonight instead. | Shipped (#219) | ADR-0082 (rollup slice S12) |
| Needs attention | Minor | Under the Rollup Builder list: the queue backlog and its oldest wait, each record whose recalculation failed, by name, with Retry for selected records or all, a warning when the nightly run is not scheduled, and how the last full run ended. | Shipped (#219) | ADR-0082 (rollup slice S13) |
| Recalculate rollups Flow action and template | Minor | A Recalculate rollups action a record-triggered Flow calls to keep every total that counts one of your own objects current in the same save, plus a Draft Flow template to copy. | Shipped (#219) | ADR-0082 (rollup slice S10) |
| Agent-ready Core actions | Minor | Four actions a Flow or a customer's own Agentforce agent or MCP server can call: Find People (with each person's household), Get Household Summary, Create Person (into an existing household or one of their own) and Get Data Job Status. Each describes itself and every input precisely, runs with the user's own access and answers a refusal in plain words. BarnCRM Staff and Admin include all four; Read Only includes the two read actions. Example agent topic metadata ships outside the packages, in `examples/agentforce/`. BarnCRM ships no AI. | Built, not merged (`feature/q-14-agent-actions`) | Q-14, ADR-0104 |
| Automatic pause expiry | Minor | A pause ends on its own at a set time, records who paused and when it ended, and Health Check flags a pause that will not end. | Shipped | C-23, ADR-0055 |
| Automations that always run | Minor | Rule-enforcing automations (such as the receipt lock) are listed but cannot be switched off. | Shipped | ADR-0024 |
| Switches created at install | Minor | Installing or upgrading a package creates the switch for every automation it ships. | Shipped | C-21 |
| Rollup freshness | Minor | Shows when each total was last calculated, per definition and per record, with a Hub warning when the nightly run has not completed in 36 hours. | Shipped | C-13 |
| Shipped rollups created at install | Minor | Each package creates its own default totals at install; upgrades add new ones without touching edited ones. | Shipped | C-13, ADR-0029 |
| Restore shipped rollups | Minor | Recreates any shipped total that is missing, skipping one whose field your own rollup already writes. | Shipped | C-13, C-21 |
| Recalculate on demand | Minor | Recalculate any single total, or all of them, from the Rollups page. | Shipped | C-13 |
| Default rollup mode setting | Minor | Decides how a newly created rollup starts out (Real time, Scheduled or Both). | Shipped | C-13 |
| Fiscal-year aware totals | Minor | This year, last year and two years ago follow the fiscal year start month set in the app. | Shipped | C-13 |
| Schedule nightly recalculation | Minor | One button on the Rollups page schedules the nightly run. | Shipped | C-13 |
| Vendored calculation engine | Minor | The open source apex-rollup library, replaced by BarnCRM's own engine (no rollup runs through it since rollup slice S8) and deleted from Core in rollup slice S9 after the engine comparison run. | Replaced; deletion built, not merged (`feature/rollup-s9-remove-vendored-2`) | ADR-0015, ADR-0082 |
| Instant totals from gifts and pledges | Minor | Saving a gift or commitment updates the donor's totals in the same save, not only overnight. Fund and soft credit totals still update overnight until the new engine. | Shipped | C-13 (rollup slice S1) |
| Instant totals on your own objects | Minor | For a total that counts one of your own objects, the Rollup Builder generates and deploys the trigger that keeps it instant, with no setup. A research spike proved the approach. | Planned (amendment A2; slices S15 to S17; spike on `feature/rollup-s15-spike`) | ADR-0082 |
| Plainer rollup modes | Minor | Modes named Instantly, Every night and Both (recommended); bulk changes queue instead of slowing the save. | Shipped | ADR-0082 |
| Waiting totals never stranded | Minor | Totals waiting in the rollup queue are started by the nightly run, the end of a pause, Retry and a new Start now button in Needs attention; Health Check reports failed totals and totals waiting over an hour. Rollup definitions are read once per transaction. The Recalculate rollups Flow action is global, so a subscriber's Flow Builder lists it. | Built, not merged (`feature/q-01-async-rollups-1`) | Q-01, rollup review ROLLUPS-5, 7, 11 |
| Totals recalculated just after the save | Minor | Instantly and Both totals are queued in the save and recalculated a few seconds after it, so a gift save spends about 8 rollup queries instead of about 55 and cannot fail on them. A setting in the Rollups section (When instant totals are calculated) switches back to During the save, where a save recalculates only when its planned queries fit. | Built, not merged (`feature/q-01-async-rollups-2`) | ADR-0098 (async rollups), Q-01, rollup review ROLLUPS-2 |
| Rollups run only what changed | Minor | A save recalculates only the totals its change can move: a soft credit save no longer reruns every gift and pledge total on the donor, and Every night totals wait for the nightly run. A soft credit save's recalculation drops from about 32 queries to about 8, a gift save's from about 36 to about 25. | Built, not merged (`feature/q-01-async-rollups-3`) | ADR-0099 (rollups recalculate only what a save changed), D-48, rollup review ROLLUPS-4 |
| Rollup Builder date and filter checks | Minor | The Builder measures a fiscal year window on a date field only, refuses an Instantly total that moves with the date (a fiscal year window, or an is this year, is last year or is in the last N days condition), here and on the Rollups list, and says these conditions use the calendar year. Contains and starts with match % and _ as typed, a date shaped value on a text field is compared as text, Preview needs the settings permission, and a field another rollup fills is shown as filled straight after a save. | Built, not merged (`feature/q-01-async-rollups-4`) | Rollup review ROLLUPS-3, 8, 14, 15, 16 |
| Recalculate all covers every rollup | Minor | Recalculate all, and the one run Run tonight sets up when the nightly run is off, rebuild every active rollup including Instantly ones; the estimate counts their records too. The nightly run still covers Every night and Both only. | Built, not merged (`feature/q-01-async-rollups-6`) | Rollup review ROLLUPS-8 (owner decision) |
| Instant totals after background jobs | Minor | A change saved by any background job, an integration's included, starts the totals queue as soon as the job's step is saved, instead of waiting for a later save or the nightly run. | Built, not merged (fix/sample-data-chain-depth) | R-RQ3 follow-up, ADR-0100 |
| Flow templates for switchable automation | Minor | Inactive Flow templates a customer can Save As and own ("switch ours off, run yours") for Core automations: keep an account's first address, check affiliations, primary affiliation, relationship checks and keeping both sides of a relationship in step. A CI check requires a template or a written reason for each switchable automation. | Shipped | ADR-0040, ADR-0090 |

### 1.7 Administration and Settings

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Hub app and home page | Major | One app with a home page that shows what to do next, a setup checklist, and tiles for errors, rollup freshness, seasonal swaps and recurring imports. | Shipped | C-03 |
| Settings console | Major | One in-app page for every setting, grouped by section, with search, plain-language descriptions and "Learn more" links, so normal use never needs Salesforce Setup. | Shipped | C-03 |
| A range on every number setting | Minor | Every number setting has a lowest and highest value: the console marks a value outside them and saves nothing, and the server refuses it naming the setting and the range. | Built, not merged (fix/admin-7) | ADMIN-27 |
| Setup Assistant | Major | A guided, resumable eight-step checklist from install to first real record, with Back, Next and Skip. | Shipped | C-12 |
| Access page | Major | Assigns packaged roles (permission set groups) to colleagues from the app and shows who holds each role. | Shipped | C-06 |
| Confirmations in a dialog | Minor | Yes or no confirmations (role changes, recompute all households, sample data load and remove, Health Check fixes, household merge and split) open in a platform modal that holds keyboard focus, closes on Escape and returns focus to the button, keeping each action's own button label. Typed-count confirmations for bulk changes stay inline. | Built, not merged (feature/q-05-modern-dialogs-2) | Q-05 |
| Automatic access | Minor | A guide page gives exact Salesforce user access policy definitions (new staff get a role; with Giving, each role also gets its Giving permission set) to create in Setup, with deployable samples; the Access page and the Setup Assistant's access step link to it. No policy ships in a package. | Built, not merged (`feature/q-09-user-access-policies`) | Q-09, ADR-0095 |
| Coexistence mode | Major | Detects whether the org also runs NPSP or Nonprofit Cloud, proposes the matching mode (Standalone, NPSP, Nonprofit Cloud) and records it. | Shipped | C-07 |
| Rearrangeable home page | Major | The home page is built from separate tiles (welcome, setup checklist, errors, Health Check, rollups, seasonal addresses, regular files, quick links) in standard regions, so an admin can rearrange or hide them in App Builder. | Shipped | C-03 |
| Module Manager | Major | A page in settings listing every module with its status and installer link, Turn off and Turn on for a module's automation, and a count of what an uninstall would delete. | Shipped | C-24 |
| Suite choice | Major | The Setup Assistant's first step asks Impact Suite or Community Suite and, when the Nonprofit Edition is chosen and Giving is missing, links to Salesforce's installer for Giving with Check again. | Shipped | C-30 |
| Neutral Core | Major | Moves nonprofit wording, the giving and receipt settings and the nonprofit setup steps out of Core into Giving, so Core alone is the Community Suite. | Shipped | C-29, ADR-0059 |
| Analytics module: field utilization | Major | An on-demand count, in Org Optimizer's Field utilization section (no tab or app page of its own), of how often each field of a chosen object is filled in, per record type, with saved counts for trends and reports. | Built, not merged (`feature/field-utilization-on-demand`) | plan 6.1 item 10, ADR-0086, ADR-0101 field-utilization-on-demand |
| Packaged roles | Minor | Five roles: Admin, Fundraising Staff, Program Staff, Volunteer Coordinator and Read Only; packaged sets are never cloned. | Shipped | C-06 |
| Manage settings permission | Minor | Only holders of the manage-settings permission can change settings; everyone else sees a read-only view with a notice. | Shipped | C-03 |
| Settings change history | Minor | "Recent changes" records each changed setting with old value, new value, who and when; unchanged saves write nothing. | Shipped | C-03 |
| Settings search | Minor | Search box finds any setting by name, description or section and jumps to it; a failed search says so instead of "no results", and a slow answer to an earlier word never replaces a newer one. | Shipped; fix built, not merged (`fix/ui-1`) | C-03 |
| Setup prerequisite notes | Minor | A settings section that depends on a change only Setup can make (fiscal year, Custom Metadata deploy switch, duplicate review, rollup target fields, email deliverability, module permission sets, bulk permission sets) says what, why and where at its top, and shows Done or Not done yet where BarnCRM can read it (fiscal year, email deliverability). Giving's Acknowledgments and Receipts pages and Connect's Campaign sync, Opportunity mirror and Accounting export pages show their own notes with the same Core component. | Built, not merged (`feature/settings-setup-prereqs`, `feature/settings-setup-prereqs-2`) | C-03, owner decision 2026-10-13 |
| Setup progress remembered | Minor | The assistant reopens on the step you reached and collapses to a "Setup complete" tile that can be reopened. | Shipped | C-12 |
| Organization identity step | Minor | Records the organization's name, tax ID, address and logo in the assistant (used by receipts). | Shipped | C-12 |
| Modules step | Minor | Shows each package as present or not installed, with links to what it does. | Shipped | C-12 |
| Modules tile | Minor | A home page tile showing which modules are installed. | Shipped | C-24, ADR-0018 |
| Pickers in settings | Minor | Settings that name a record or record type offer a picker instead of a typed ID, the fiscal year start is a month list, and each description is read out with its control. | Shipped | C-03, ADR-0074 |
| Coexistence options gated by detection | Minor | NPSP and Nonprofit Cloud modes are offered only where that product is detected (or already saved); Standalone is always offered. | Shipped | C-29 follow-up |
| Installer gets admin access | Minor | The person who installs receives the admin role automatically by a background job after install. | Shipped | C-06 |
| Sample data | Minor | Loads a realistic demo set (200 households, 440 people, 25 organizations, connections and affiliations) only when an admin asks, and removes it all in one action. | Shipped | C-10 |
| Neutral sample organizations | Minor | Sample organizations become mostly businesses, schools and clubs, and the guide states sample data is never loaded automatically. | Shipped | C-29 follow-up |
| Sample data loads in any org | Minor | The sample data load, Giving's included, runs as batch jobs one step at a time, so it finishes in Developer Edition, trial and scratch orgs, where a chain of more than five queued jobs stopped it before. | Built, not merged (fix/sample-data-chain-depth) | C-10 follow-up |
| Package labels renamed to BarnCRM | Minor | Renames the app, settings ("BarnCRM Settings"), roles, folders, templates and API names from the old working title to BarnCRM. | Shipped (PR #181) | plan 11.3 item 6 |
| Faster, safer settings saves | Minor | A settings save writes only the keys that changed, under a lock, so two admins saving at once do not undo each other. | Shipped | plan 11.3 |
| Job notifications | Minor | The person who starts a long job (import, bulk update or delete, an undo, sample data load, rollup recalculation, field utilization or seasonal swap Run now, duplicate scan, household name recompute; with Giving, the statement run, acknowledgment send and donor level recalculation) gets one bell notification when it finishes or stops, with counts and a link to the job or its settings page; scheduled runs send none; one setting turns them off. | Built, not merged (feature/q-04-job-notifications-1, -2, -3) | Q-04 |
| What's new after upgrade | Minor | A "What's new" card on the home page summarizes what changed after an upgrade, hidden once read and when nothing is new. | Shipped | C-27, ADR-0087 |
| In-app tips | Minor | Salesforce In-App Guidance tips shown once per person on first visit to BarnCRM Settings (docked; points to the Setup Assistant and What's new), Import, Find and Bulk Update (floating). Single prompts, so no licence; turned off in Setup, In-App Guidance. | Built, not merged (`feature/q-10-in-app-guidance`) | Q-10, new ADR |
| What's new kept current | Minor | A release checklist step writes each release's What's new entries from its release notes, and a CI check warns (and fails at release) when the newest release notes have none. | Built, not merged (fix/admin-6) | ADMIN-28 |
| Unlocked-to-managed migration kit | Minor | Moves a production pilot from unlocked to managed packages: check, export, reimport with every record link translated, and verify record by record. | Shipped | C-31, ADR-0088 |
| Telemetry (opt-in) | Minor | Anonymous, opt-in usage counts (installed modules, org shape, error counts), off by default. | Not planned (deferred indefinitely, D-24: no AppExchange listing for now; a listing would use AppExchange App Analytics instead) | C-26 |
| CMDT Manager | Minor | A Custom metadata page in BarnCRM Settings (General) where holders of the BarnCRM Metadata Admin permission set add, edit and archive the org's own relationship types; shipped types are read only. | Shipped | plan 6.1 item 9, ADR-0085 |

### 1.8 Monitoring and Health

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Error Log | Major | Records every caught failure in plain language with the record, user and what to do, and lets you mark entries reviewed or fixed. | Shipped | C-05 |
| Health Check | Major | Checks org shape, licenses, coexistence fit, access gaps, paused automation, unread errors and data problems, each with a plain explanation and a button. | Shipped | C-11, C-21 |
| Error digest email | Minor | Optional daily or weekly email counting new Error Log entries by source and severity; sends nothing when nothing is new. | Shipped | C-23 |
| Error Log retention | Minor | The daily Error Log run deletes entries older than 180 days, whatever their status; the number of days is a BarnCRM Setting, and 0 keeps everything. | Built, not merged (fix/admin-6) | ADMIN-26, R-E6 |
| Errors survive rollback | Minor | Entries are published as events so an error is kept even when the failed work is rolled back. | Shipped | C-05 |
| Errors tile | Minor | Hub home tile counts errors to review that the user may see. | Shipped | C-05 |
| Fix buttons that ask first | Minor | Health Check fixes show what they will do, wait for Confirm, only add (never delete or overwrite), and are recorded in settings history. | Shipped | C-21, ADR-0048 |
| Missing defaults findings | Minor | Finds missing shipped totals, automation switches and import templates, and nightly totals with no schedule. | Shipped | C-21 |
| Fiscal year mismatch finding | Minor | Warns when the fiscal year in Setup and the one in settings start in different months. | Shipped | C-11 |
| Membership fit findings | Minor | Flags membership records the current setting hides and person accounts while the setting expects contacts; the Hub shows a count of install problems. | Shipped | C-01, C-21 |
| Multi-currency warning | Minor | Warns that multiple currencies are not supported yet. | Shipped | C-11 |
| Stalled digest finding | Minor | Warns when the error digest is scheduled but has not run for two days. | Shipped | C-23 |
| Module findings extension | Minor | Lets installed modules add their own Health Check findings without Core knowing about them. | Shipped | ADR-0057 |
| Schedule all nightly jobs | Minor | One Health Check finding lists every nightly job that is not scheduled (rollups, seasonal addresses, error digest, and those Giving and Connect add), and one fix schedules them all. | Shipped | C-21, ADR-0075 |
| Jobs of a deactivated owner | Minor | Health Check names every scheduled BarnCRM job whose owner was deactivated (it has stopped but still looks scheduled), and one fix schedules them again as the admin. | Built, not merged (fix/admin-4) | ADMIN-12, ADR-0105 |
| Capped error count | Minor | The unread error count reads "999+" on the home page and "1,000 or more" in Health Check past a cap. | Shipped | plan 11.3 |
| One capped error count | Minor | The home page, the Error Log tile and Health Check share one capped count of new errors, and the install problem count arrives in the home page's one server call. | Built, not merged (fix/admin-4) | ADMIN-8 |
| Health Check last result on Home | Minor | BarnCRM Home shows when Health Check last ran in full and how many findings it had, with Run now, instead of running every check on each load. Any page can do the same through one panel setting. | Built, not merged (fix/admin-5) | ADMIN-7, ADR-0106 |

### 1.9 Record Pages and App Experience

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Dynamic Forms record pages | Major | Ships record pages for households, organizations and people whose sections show or hide by record type, assigned in the app on install. | Shipped | C-08, ADR-0043 |
| Household and Organization record types | Minor | Accounts carry Household or Organization record types with compact layouts and list views. | Shipped | C-08 |
| One minimal fallback layout per object | Minor | Each object keeps one fallback page layout; no profile layout assignments are packaged. | Shipped | C-08, ADR-0043 |
| No Contact record type | Minor | Core ships no Contact record type, so it does not disturb an org's existing ones. | Shipped | ADR-0041 |
| Activities instead of Chatter | Minor | Packaged records use the activity panel, not a Chatter feed. | Shipped | ADR-0042 |
| Your own pages win | Minor | A record page you assigned yourself is never replaced. | Shipped | C-08 |
| Clearer screens | Minor | Save buttons disable while saving, spinners say what they wait for, and errors use plain words. | Shipped | C-01 |
| Plainer wording | Minor | Import buttons read Preview, Import these rows and Download rejected rows; schedule times name the time zone; errors point to the Error Log; warning icons are announced to screen readers. | Shipped | UX review |
| Activity actions on the fallback layout | Minor | The packaged account layout includes Log a Call, New Task and New Event, so its activity panel can create activities. | Shipped | C-08 |
| Console tabs | Minor | In a console app, records opened from BarnCRM pages open as subtabs of the tab you are in; Settings, Import, Find and Rollup Builder name their tab for what is on screen; a household merge or split refreshes the household's tab. Outside a console nothing changes. | Built, not merged (feature/q-07-workspace-api) | Q-07 |
| Cards read through the platform | Minor | The Addresses, Affiliations and Relationships cards read and save through Lightning Data Service: they show a loading state instead of "none on file" while they load, pick up edits made elsewhere on the page, refresh the record's own fields after Set as default or Make primary, and show picklist values in the reader's language. Settings pages reopen on what was last saved, and the import wizard opens with one wait instead of three. | Built, not merged (`feature/q-06-lds-graphql-1` to `-4`) | Q-06, ADR-0093 (record reads through Lightning Data Service) |
| Console app with a barn logo | Major | The BarnCRM app opens records in tabs: households, organizations and people in their own tab, addresses, relationships, affiliations and household members as subtabs of their parent; it has a blue barn logo and a matching, darker blue header color. | Built, not merged (`feature/console-app-icon`) | ADR-0102 |

---

## 2. Giving

**Suite:** Impact Suite (Nonprofit Edition). Depends on Core. Adds gifts, funds, pledges, receipts and the nonprofit wording; any organization may choose it.

### 2.1 Gift Processing

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Gifts | Major | Records each transaction (money, stock or goods) from one donor on one date, credited to the right household automatically. | Shipped | G-01 |
| Funds and allocations | Major | Designates each gift to one or more funds, by amount or percent, totalling the gift exactly. | Shipped | G-01 |
| Quick Gift Entry | Major | A one-screen, phone-friendly form for entering a gift the moment it arrives, with defaults filled in. | Shipped | G-03 |
| Gift batches | Major | Types a stack of checks against the deposit slip total and posts them as ordinary gifts, all or none, only when they balance. | Shipped | G-17, ADR-0045 |
| Refunds and write-offs | Major | Records money that went back as a linked negative gift with a reason, never editing the original. | Shipped | G-04 |
| In-kind gifts | Major | Records gifts of goods or services with a description and fair market value, kept out of every money total. | Shipped | G-18, ADR-0030 |
| Matching gifts | Major | Links an employer's matching gift to the employee's gift, visible from both, with the employee soft credited. | Shipped | G-10 |
| Gift auto-numbering and donor rule | Minor | Gifts are numbered automatically, and each has exactly one donor: a person or an organization or household. | Shipped | G-01 |
| Default fund | Minor | A gift entered without a designation goes to the default fund. | Shipped | G-01 |
| Date defaults to today | Minor | A gift saved without a date is dated today. | Shipped | G-01 |
| Gift statuses | Minor | Received, Pending, Refunded, Written off and Cancelled. | Shipped | G-01, G-04 |
| Cancelled gifts | Minor | A Pending gift that will never be paid is set to Cancelled: no negative gift, out of every total and export, allowed even in a closed month, and logged. | Shipped | G-04, ADR-0054 |
| Cancelling frees the installment | Minor | Cancelling a gift expected to pay a pledge installment frees that installment for the next gift. | Shipped | G-04 |
| Payment methods | Minor | Cash, Check, Card, ACH, Stock, In-kind, Grant and Other, with a reference such as check number. | Shipped | G-01 |
| Refund reverses matched credit | Minor | Refunding the employer's gift writes a matching negative credit for the employee, so partial refunds leave partial recognition. | Shipped | G-10, ADR-0031 |
| Refunded gifts cannot be matched | Minor | A refunded or written-off gift cannot be half of a match. | Shipped | G-10 |
| Quick Gift Entry conveniences | Minor | Save and new for a stack of checks, a double-tap guard, person-account donor search, and in-kind fields that replace the amount box. | Shipped | G-03, G-18 |
| Open Batches list | Minor | A half-typed batch is saved and can be picked up later; posted batches are locked. | Shipped | G-17 |
| In-kind validation rules | Minor | Five rules refuse in-kind mistakes, such as a cash gift left carrying an in-kind value. | Shipped | G-18 |
| A gift keeps its household | Minor | When a donor moves to another household, past gifts stay with the household they were given to; household totals through current membership follow the person. | Shipped | G-01, ADR-0071 (D-20) |
| Quick Gift Entry in the utility bar | Minor | Quick Gift Entry opens from the Fundraising app's utility bar on any page. | Shipped | G-03 (UX pass) |
| "Payment Method" label | Minor | The gift type field is labelled Payment Method in the app and on Quick Gift Entry. | Shipped | G-03 (UX pass) |
| Gift page polish | Minor | Gift page shows one donor field and shows refund, original gift and matched gift fields only when relevant. | Shipped | G-01 (UX pass) |
| Quick Gift Entry messages and new donors | Minor | A problem is shown on the field it concerns, the donor picker offers the standard new person form, and batch lines name their line number for screen readers. | Shipped | G-03, G-17 (UX pass) |
| Pay a scheduled pledge payment | Minor | Quick Gift Entry and the Gift Batches "Pays" column list the donor's open pledge payments, suggest the one a gift pays, and let staff pick it. | Shipped | G-03, G-17, G-24, ADR-0084 |
| Stock and planned gift types | Minor | Extra fields for stock and planned gifts. | Planned (1.x) | G-21 |

### 2.2 Pledges and Recurring

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Commitments | Major | Tracks pledges and recurring gifts in one place, with real installment records, paid to date and balance. | Shipped | G-07 |
| Pledge balance rollups | Minor | Pledge balance on households, organizations and people, plus paid amounts on commitments and installments. | Shipped | G-11 |
| Commitment list views | Minor | Overdue, Upcoming 30 days, Active pledges and Active recurring. | Shipped | G-07 |
| Apply to oldest unpaid installment | Minor | A gift naming a commitment but no installment is applied to the oldest unpaid one (a setting). | Shipped | G-07 |
| Pause and cancel | Minor | Pausing leaves scheduled installments alone; cancelling marks unpaid ones Skipped; nothing received is changed. | Shipped | G-07 |
| Rolling schedule horizon | Minor | Keeps a year of installments ahead of an open-ended recurring gift (horizon is a setting). | Shipped | G-07 |
| Overdue after grace days | Minor | Marks payments overdue after a grace period set in the app. | Shipped | G-07 |
| Nightly jobs page | Minor | One button schedules the installment top-up, overdue pass and donor level pass; shows each job's last run and result; "Run now" available. | Shipped | G-07, ADR-0038 |
| Schedule preview | Minor | Previews a commitment's payment schedule on the record. | Shipped | G-07 |

### 2.3 Soft Credits and Tributes

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Soft credits | Major | Recognizes people who influenced a gift (solicitor, honoree, household member) without counting money twice. | Shipped | G-08 |
| Tributes | Major | Records gifts in honor or in memory of someone, who to notify, the donor's message and whether the notice went out. | Shipped | G-09 |
| Automatic household member credits | Minor | A gift from one household member soft credits every other current member (a setting), in both membership models. | Shipped | G-08 |
| Refunded gifts keep their soft credits | Minor | Soft credits stay visible on a refunded gift rather than vanishing. | Shipped | ADR-0023 |
| Tribute amount never stated | Minor | Tribute notices never state the gift amount. | Shipped | G-09 |
| Tribute panel on the gift | Minor | A panel on the gift page shows and updates the tribute notification. | Shipped | G-09 |

### 2.4 Appeals

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Appeals | Major | Names each fundraising effort with goal, cost, dates and a parent appeal, with total raised and gift count calculated from gifts. | Shipped | G-05 |
| Net raised and percent to goal | Minor | Calculated as formulas, so they are never stale. | Shipped | G-05 |
| Default appeal | Minor | A default appeal chosen in setup fills in on new gifts. | Shipped | G-03, C-12 |

### 2.5 Donor Stewardship

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Acknowledgments | Major | Ordered rules put each gift in the right thank-you queue (email, letter or none); emails send in a batch or overnight, letters export as a merge file, and every send is recorded. | Shipped | G-12, ADR-0032 |
| Donor levels | Major | Places every donor on your own giving ladder from an existing total, keeping their previous level and the date they moved. | Shipped | G-14, ADR-0028 |
| Stewardship plans | Major | Templates of follow-up steps that create real tasks with due dates when a gift or pledge arrives, or when started by hand. | Shipped | G-15 |
| Membership tracking | Major | Membership levels with expiry and renewal reminders, likely as its own package. | Planned (1.x) | G-22 |
| Rule criteria | Minor | Acknowledgment rules match on amount range, gift type, appeal and first gift only. | Shipped | G-12 |
| Standard email templates | Minor | Thank-you emails use ordinary Salesforce email templates, with a packaged sample template. | Shipped | G-12 |
| No double thanks | Minor | A gift cannot be thanked twice, even if a batch is retried. | Shipped | G-12 |
| Send Acknowledgments permission | Minor | Separate permission for sending thank-yous. | Shipped | G-12 |
| Thank-you greets "friend" | Minor | The thank-you email greets "friend" when the person has no first name. | Shipped | G-12 (UX pass) |
| Acknowledgment rules edited in the app | Minor | Rules are created and edited on the Acknowledgments page with the email template chosen by name; a new stewardship plan's key is made from its name. | Shipped | G-12, G-15 (UX pass) |
| Which total a ladder measures | Minor | Setting chooses total giving, this fiscal year, last fiscal year or largest gift. | Shipped | G-14 |
| Levels follow refunds down | Minor | A refund can move a donor down a level. | Shipped | G-14 |
| Level movement list views | Minor | Shows who joined or left a level, placed on save, nightly and by "Recalculate now". | Shipped | G-14 |
| Plan triggers | Minor | Start on first gift, any gift, a gift over an amount, a pledge or recurring gift becoming active, or by hand. | Shipped | G-15 |
| Task assignment choices | Minor | Tasks go to the donor's owner, the person who started the plan, or one named person. | Shipped | G-15 |
| One running plan per donor | Minor | The same plan will not start twice on a donor while it is running. | Shipped | G-15 |
| Tasks never deleted | Minor | Cancelling a plan leaves its tasks; a failed plan never stops a gift saving. | Shipped | G-15 |
| Donor scoring (RFM) | Minor | Recency, frequency and monetary scores calculated as rollups. | Planned (v0.9) | G-19 |
| Major-gift portfolios and interaction summaries | Minor | Portfolios of major-gift prospects per staff member, interaction summaries and more mature donor scoring. | Planned (post-1.0) | plan 6.1 item 5 |

### 2.6 Receipting

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Gift receipts | Major | Produces a numbered PDF receipt for a gift, stored on the receipt and the gift, never changed once issued. | Shipped | G-13, ADR-0010 |
| Year-end statements | Major | Consolidated statements listing a household's or organization's gifts for a year, generated in batch runs. | Shipped | G-13 |
| Void and reissue | Minor | A wrong receipt is voided with a reason and a new one issued; both stay on record. | Shipped | G-13 |
| Gap-free numbering | Minor | Numbers come only from a locked sequence per series; a number used by a failed document is recorded as void, so every gap is explained. | Shipped | G-13, ADR-0033 |
| Built-in tax wording | Minor | Required US tax language (IRS Publication 1771) is added by BarnCRM and cannot be deleted from a template. | Shipped | G-13 |
| In-kind receipt wording | Minor | A receipt for goods describes what arrived and never states a value. | Shipped | G-18 |
| Receipt templates | Minor | Two editable letters, single gift and consolidated statement, that upgrades never overwrite once edited. | Shipped | G-13 |
| Receipt branding | Minor | Legal name, address and tax ID always print; an optional logo with width and delivery-route settings. | Shipped (logo path unverified in an org) | G-13, ADR-0016 |
| Receipt lock | Minor | A gift with a receipt number cannot have its amount, date, donor or in-kind description changed, even with automation switched off. | Shipped | G-04, ADR-0024 |
| Override Receipt Lock permission | Minor | Granted in Setup for one correction; every use is logged and Health Check reports who holds it. | Shipped | ADR-0024 |
| Receipt file access | Minor | Receipt files follow access to the receipt and gift, not the donor, with role-based read access. | Shipped | ADR-0034 |
| Issue Receipts permission | Minor | Separate permission for issuing, voiding and starting receipt runs. | Shipped | G-13 |
| Failed receipt finding | Minor | Health Check counts receipts voided because generation failed. | Shipped | C-11 |
| View PDF link | Minor | Each receipt in the Receipts panel has a View PDF link to the standard file preview. | Shipped | G-13 (UX pass) |
| Letterhead on every receipt | Minor | The organization's name and address print above every receipt and statement, whatever the letter says, with a preview that writes nothing. | Shipped | G-13 (UX pass) |
| Receipt letter editor and preview | Minor | Receipt letters are edited in a rich text editor limited to what the PDF prints, with a preview of the unsaved draft for a sample gift. | Shipped | G-13 (UX pass) |

### 2.7 Accounting Controls

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Posting flag | Major | After export, "Mark these gifts posted" locks each gift's date, amount, donor, payment method, reference and funds, and blocks deletion. | Shipped | G-20, ADR-0053 |
| Closed periods | Major | A "books closed through" date stops any gift in a closed period from being added, changed or deleted. | Shipped | G-20, ADR-0053 |
| Refunds in an open period | Minor | Refunds and write-offs of posted gifts are new gifts dated today, landing in the month the money went back. | Shipped | G-20 |
| Override Posting Lock permission | Minor | Reopening a period or changing a locked gift needs a Setup-granted permission, and every use is logged. | Shipped | G-20 |
| Post Gifts permission | Minor | Separate permission for marking gifts posted. | Shipped | G-20 |
| Unposted gifts in a closed period finding | Minor | Health Check names gifts in a closed period never marked posted. | Shipped | G-20 |

### 2.8 Gift Import and Migration

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Gift import | Major | Loads gifts from a file with donor, amount, date, payment method, appeal, fund splits, a soft credit and a tribute, through the same checks as hand-entered gifts. | Shipped | G-23 |
| Donation matching | Major | Matches an imported gift to an existing gift by external ID or to the donor's open installment within a date window and amount tolerance. | Shipped | G-24 |
| Nonprofit Cloud migration templates | Major | Four mappings read Nonprofit Cloud exports as they are: person accounts, gifts from people, gifts from organizations, undesignated gifts. | Shipped | plan 6.3 |
| NPSP migration templates | Major | Three mappings read NPSP exports: contacts with their emails, and paid payments from people and from organizations. | Shipped | plan 6.3 |
| Load twice, get gifts once | Minor | Gifts with an external ID match on a second load instead of duplicating. | Shipped | G-23 |
| Four matching behaviours | Minor | Match or create (default), Always create, Match only, Never match; closest date wins and ties are rejected. | Shipped | G-24 |
| Matching defaults in settings | Minor | Default date window and amount tolerance live in the Import settings, and the dry run's choices hold through commit. | Shipped | G-24 |
| Control totals | Minor | Expected row count and total from the deposit slip are checked in the dry run before commit. | Shipped | G-23 |
| Undo keeps receipted gifts | Minor | Undoing a gift import keeps any gift a receipt or statement lists, and its donor, with the reason journaled. | Shipped | G-23 |
| Split-gift lines refused | Minor | A gift exported as one line per designation is rejected until combined, so no gift loads to one fund only. | Shipped | plan 6.3 |
| Restore import templates | Minor | Health Check finds missing shipped mappings and restores them without touching yours. | Shipped | C-21 |

### 2.9 Reporting and Dashboards

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Giving dashboard | Major | A packaged dashboard and reports: gifts this month, giving by month, by fund, by appeal, top donors and recent gifts, with relative dates. | Shipped | G-06 |
| Retention reports | Major | LYBUNT, SYBUNT, new versus retained, and first-to-second gift conversion, each with written definitions, counting donors not gifts. | Shipped | G-16, ADR-0026 |
| Giving totals on donors | Major | Total giving, gift count, first, last and largest gift, this year, last year, two years ago, soft credit totals and in-kind totals on households, organizations and people. | Shipped | G-02 |
| Fund and appeal totals | Minor | Total raised, this year, gift count and last gift date on funds; total raised and gift count on appeals. | Shipped | G-02 |
| In-kind gifts report | Minor | In-kind Gifts This Year, counting only gifts in the books. | Shipped | G-18 |
| Donors with Giving report type | Minor | A report type whose rows are donors, used by the retention reports. | Shipped | G-16 |
| Dashboard runs as the viewer | Minor | Each person sees only the gifts they may see. | Shipped | G-06 |
| Refund-correct totals | Minor | A refunded gift stays in the count and leaves the total; a fully refunded donor shows zero, not blank. | Shipped | ADR-0022 |
| Giving totals update on save | Minor | Totals on donors move when a gift or commitment is saved, not only overnight (see Core 1.6, Instant totals from gifts and pledges). | Shipped | G-02 (rollup slice S1) |

### 2.10 Giving App and Administration

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Fundraising app | Major | An app with tabs for gifts, funds, appeals, commitments, batches, receipts and Quick Gift Entry. | Shipped | G-06, ADR-0018 |
| Donor record pages with giving | Major | Giving ships person and household or organization pages with a Giving section, related lists for gifts, commitments and soft credits, and a New Gift action. | Shipped | ADR-0064 (UX pass) |
| Gift, Commitment and Gift Batch record pages | Minor | Packaged record pages for Giving records, opened automatically in the Fundraising app. | Shipped | ADR-0043 |
| Actions and lists placed on the Giving pages | Minor | Gift, commitment and batch pages carry their own actions (Refund or Write Off only on a received gift) and sorted lists of allocations, refunds and a commitment's gifts; donor pages gain Log an interaction; the gift's activity panel can log calls, tasks and events. | Built, not merged (feature/q-08-dynamic-pages) | Q-08, ADR-0097 |
| Giving permission sets | Minor | Giving Admin, Giving Staff and Giving Read Only (assigned in Setup until the Module Manager joins them to roles). | Shipped | C-06 |
| Fundraising Staff includes Giving Staff | Minor | Assigning the Fundraising Staff role on the Access page also gives Giving Staff, so gift entry needs no separate Setup step. | Built, not merged (fix/admin-6) | owner decision 2026-10-13 |
| Giving sample data | Minor | With Giving installed, sample data adds about 700 gifts over three years, funds, appeals, commitments, soft credits, tributes and in-kind gifts, dated relative to load. | Shipped | C-10 |
| Giving settings pages | Minor | Acknowledgments, receipts, donor levels, stewardship plans, nightly jobs and accounting periods are all set in the settings console. | Shipped | ADR-0020 |
| Fundraising app navigation and fallback layouts | Minor | Adds Contacts, Households, Organizations and Commitments tabs, plain list view names, and a fallback layout for each object. | Shipped | UX pass |
| Giving owns the nonprofit setup steps | Minor | Giving contributes its own Setup Assistant steps (default fund and appeal, organization identity) and Health Check questions. | Shipped | C-29 |
| Giving settings that ship on stay on | Minor | The first Giving settings save no longer switches off settings that ship on (apply gifts to installments, household soft credits, receipt logo). | Shipped | plan 11.3 |

---

## 3. Connect

**Suite:** Impact Suite. Depends on Core and Giving. Holds every link to standard Salesforce objects (Opportunity, Campaign) and outside systems, so the rest of BarnCRM runs on a Platform-only org. Each feature has its own permission set.

### 3.1 Integrations

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Opportunity mirror | Major | Keeps gifts and Opportunities in step in one chosen direction (Gifts to Opportunities, or Opportunities to Gifts), so NPSP rollups and Opportunity-based apps keep working. | Shipped | X-01, ADR-0058 |
| Campaign sync | Major | Gives every appeal a matching Campaign and keeps it updated, one way, so Campaign Members and email tools work. | Shipped | X-02, ADR-0056 |
| Inbound gift API | Major | A versioned web address and a "Record Inbound Gift" Flow action let a giving page or processor record gifts directly. | Shipped | X-03, ADR-0051 |
| Accounting export | Major | Downloads gifts in a date range as a CSV with one row per fund, accounting codes and refunds as negative rows, ready for QuickBooks or Xero. | Shipped | X-04, ADR-0051 |
| Gift Transaction mirror | Major | Mirrors gifts one way to Nonprofit Cloud's Gift Transaction so native donor summaries still see them. | Planned (v0.6 per plan 6.3; next roadmap item) | X-07 |
| NPSP coexistence adoption | Major | Adopts existing NPSP household accounts and maps record types. | Planned (v0.10) | X-05 |
| Mirror reconciliation page | Minor | Compares gifts and won Opportunities for any date range, lists differences, and fixes the gift side in one click. | Shipped | X-01 |
| Mirror nightly catch-up | Minor | A scheduled run catches up anything a save could not mirror; Health Check flags a stalled run. | Shipped | X-01 |
| Mirror record type filter and start date | Minor | Limits which won Opportunities become gifts. | Shipped | X-01 |
| Mirror never blocks or deletes | Minor | A gift always saves even when its Opportunity cannot be made; the reason goes to the Error Log. | Shipped | X-01 |
| Sync all appeals | Minor | Gives every existing appeal its Campaign in one click, with parent appeals mapped to parent Campaigns. | Shipped | X-02 |
| Off until switched on | Minor | Campaign sync and the Opportunity mirror ship off; orgs without Campaigns are told so on the page. | Shipped | X-01, X-02 |
| Idempotent by external ID | Minor | A gift sent twice is recorded once; the same ID with a different amount is refused. | Shipped | X-03 |
| No invented donors | Minor | A gift for an unknown donor is refused and logged rather than creating a duplicate person. | Shipped | X-03 |
| API documentation and samples | Minor | Reference and sample requests and responses for developers. | Shipped | X-06 |
| OpenAPI description of the inbound gift API | Minor | The inbound gift API is published as an OpenAPI 3.1 file, checked in CI against the code. | Shipped | X-06 |
| Using BarnCRM actions with AI | Minor | "Record Inbound Gift" describes itself and every input precisely, so a customer's own Agentforce agent or MCP server can choose and fill it; an admin guide page covers setup, access and cost. BarnCRM ships no AI. | Shipped | X-03 |
| Money-only, repeatable export | Minor | Exports only Received, Refunded and Written off gifts; downloading changes nothing. | Shipped | X-04 |
| Unposted-only export and Mark posted | Minor | Shows only gifts not yet posted and marks the exported gifts posted (with Giving's posting flag). | Shipped | X-04, G-20 |
| Processor webhooks | Minor | Community-contributed receivers for common payment processors. | Planned (1.x) | X-08 |
| Nonprofit Cloud household migration | Minor | A supervised, reversible one-time migration of native household groups. | Planned (proposed, parked) | X-09 |

---

## 4. Volunteers

**Suite:** both (offered in the Community Suite and the Impact Suite). Depends on Core. Package is an empty placeholder on main; an early draft from 2026-09-09 sits on a stale branch and is not active work.

### 4.1 Volunteer Management

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Volunteer profiles, jobs and shifts | Major | Volunteer details on a person, with jobs and the shifts that fill them. | Planned (v0.8) | V-01 |
| Sign-ups and hours with approval | Major | Staff record sign-ups and hours, with an approval step. | Planned (v0.8) | V-02 |
| Hours rollups and coordinator dashboard | Major | Volunteer hours rolled up to people and households, with a coordinator dashboard. | Planned (v0.8) | V-03 |
| Public sign-up page | Major | An unauthenticated public sign-up page. | Planned (1.x) | V-09 |
| Skills, availability, interests | Minor | Tracks what volunteers can do and when. | Planned (v0.8) | V-04 |
| Onboarding status | Minor | Application, background check and orientation status. | Planned (v0.8) | V-05 |
| Volunteer hours import template | Minor | Loads a volunteer hours sheet with the Core import. | Planned (v0.8) | V-06 |
| Recurring shifts | Minor | Shifts that repeat on a schedule. | Planned (v0.8) | V-07 |
| Hour letters and certificates | Minor | Hour letters and certificates through the receipts engine. | Planned (v0.8) | V-08 |

---

## 5. Programs

**Suite:** Impact Suite. Depends on Core. Package is an empty placeholder on main.

### 5.1 Program Delivery

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Programs, services and enrollments | Major | Records programs, the services they offer and who is enrolled. | Planned (v0.9) | P-01 |
| Attendance and service delivery | Major | Logs attendance and services delivered in a grid, including on a phone. | Planned (v0.9) | P-02 |
| Case notes | Minor | Dated, typed notes, private by default. | Planned (v0.9) | P-04 |
| Program dashboard | Minor | A packaged program dashboard. | Planned (v0.9) | P-05 |
| Roster import template | Minor | Loads a program roster with the Core import. | Planned (v0.9) | P-06 |
| Intake and eligibility fields | Minor | Intake and eligibility fields with configurable picklists. | Planned (v0.9) | P-07 |
| Participant privacy sharing preset | Minor | A sharing preset that protects participant privacy. | Planned (v0.9) | P-08 |
| Waitlists and capacity | Minor | Waitlists and capacity limits for programs. | Planned (1.x) | P-09 |

### 5.2 Logic Models (separate package)

**Suite:** Impact Suite. Depends on Core only; works alongside Programs without referencing it. No package directory exists yet.

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Logic model builder | Major | Builds inputs, activities, outputs, outcomes and impact in the app, for the organization and optionally per program. | Planned (v0.9) | L-01 |
| Indicators | Major | Indicators on outputs and outcomes with unit, baseline, target and result per period. | Planned (v0.9) | L-02 |
| Indicator sources | Major | Indicator values entered by hand, imported, or computed from any object. | Planned (v0.9) | L-03 |
| Logic model report | Minor | Compares periods, ready to send to a funder. | Planned (v0.9) | L-04 |
| Link outcomes to grant deliverables | Minor | Connects outcomes to grant deliverables when Funders is installed. | Planned (v0.10) | L-06 |
| Evidence log | Minor | Records what supports each assumption, with its source. | Planned (1.x) | L-05 |

---

## 6. Funders

**Suite:** Impact Suite. Depends on Core and Giving. Package is an empty placeholder on main.

### 6.1 Grants and Funders

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Funder pipeline | Major | Tracks grants applied for and awarded, with stages, amounts and decision dates; a funder is an organization record. | Planned (v0.10) | F-01 |
| Reporting requirements and deadlines | Major | Tracks funder reports due, with reminders. | Planned (v0.10) | F-02 |
| Restricted fund tracking | Major | A simple ledger of restricted money received, released or spent, with a balance. | Planned (v0.10) | F-03 |
| Government award fields | Minor | Assistance listing number, award number, period and drawdowns. | Planned (v0.10) | F-04 |
| Multi-year award schedules | Minor | Award schedules built on commitments and installments. | Planned (v0.10) | F-05 |
| Funder report merge template | Minor | A merge template for funder reports. | Planned (v0.10) | F-06 |
| Board dashboard | Minor | Revenue mix, funder concentration and restricted balances. | Planned (v0.10) | F-07 |
| Deadline calendar view | Minor | A calendar of funder deadlines. | Planned (v0.10) | F-08 |

### 6.2 Other future modules

| Feature | Type | What it does | Status | Feature ID |
|---|---|---|---|---|
| Events package | Major | Simple event registration and attendance for non-fundraising events (both suites). | Planned (post-1.0) | plan 6.1 item 2 |

---

## 7. Cross-module platform capabilities

| Capability | What it means | Status | Source |
|---|---|---|---|
| Core plus optional module packages | Each module is a separate package; an unused module leaves no objects, tabs or automation behind. | Shipped (as source) | ADR-0003 |
| Unlocked now, managed at listing | Built as unlocked packages following managed-package rules, then released as second-generation managed packages for AppExchange. No package version has been created yet. | Planned | ADR-0002, ADR-0046 |
| Namespace deferred | No namespace prefix is hard-coded anywhere; a CI check enforces it until the namespace is registered. | Shipped | ADR-0001, plan 4.3 |
| Runs on Platform-only licenses | Core, Giving and the other modules name no Opportunity, Campaign, Case, Lead or Industries object; only Connect does, through dynamic code. A CI check enforces the allowed object list. Not yet tested in a Platform-only org. | Shipped (static checks) | ADR-0009, ADR-0013 |
| No Person Account dependency | Full support where Person Accounts are on, no requirement that they are; every person reference carries both a contact and an account option. | Shipped | plan 4.2, 6.3 |
| No paid add-on dependency | No Data Cloud, OmniStudio, CRM Analytics, Experience Cloud or Marketing Cloud; standard reports only. | Shipped | ADR-0009 |
| Settings live in the app | Every admin setting is in the in-app settings console, never only in Setup; documented exceptions (duplicate review permission, lock overrides) say why. | Shipped | plan 4.8 |
| Permission model | Packaged permission sets and groups never cloned, separate custom permissions for sensitive actions, code that respects sharing and field security, and a small set of documented system-mode writes. | Shipped | C-06, ADR-0021 |
| Explicit access modes | Every packaged Apex class states its sharing, and every query and save states user or system mode, with a CI check, so nothing relies on a platform default. | Shipped | ADR-0021 |
| Portability checks | CI checks that every packaged object and field is in the canonical model and that shared JavaScript modules stay free of Salesforce imports. | Shipped | plan 6.1 item 7 |
| AI-readiness pack | Documented export schemas and a canonical-model JSON export so any AI tool can be grounded in clean data. | Planned (post-1.0) | plan 6.1 item 7 |
| Upgrade-safe defaults | Shipped defaults (rollups, import templates, receipt templates) are copied to editable records, and upgrades add new ones without touching edits. | Shipped | ADR-0006, ADR-0029 |
| Error logging everywhere | Every module writes failures to the shared Error Log instead of failing silently. | Shipped | C-05 |
| Accessibility | Target is WCAG 2.1 AA with base Lightning components; icon-only buttons carry screen-reader names. The v0.11 static pass names every Core table for screen readers, announces import result counts, moves Core templates to `lwc:if`, and records a static mobile audit (contributor guide, scale and mobile test plan). | Shipped (partial), Built, not merged (v0.11 static pass, `fix/a11y-1` and `fix/a11y-2`), Planned (device audit) | plan 4.14 |
| Mobile | Quick Gift Entry and household pages work on a phone; a mobile audit is planned for v0.11. | Shipped (partial), Planned (audit) | G-03, plan 6 |
| Translation-ready | All text in custom labels, English only for now; Spanish is a post-1.0 theme. The v0.11 sweep moves the import wizard's column targets and matching rules into labels and turns sentences built by joining words into one label with placeholders, so a translation can reorder them. | Shipped (labels), Built, not merged (v0.11 sweep, `fix/i18n-1`), Planned (localization) | plan 4.14 |
| Multi-currency | Not supported in v1; Health Check warns when present. BarnCRM's own rollup engine already totals in the record's currency. | Planned (post-1.0) | plan 4.2, 6.1 |
| Professional Edition | Not a target. | Not planned | plan 11.2 item 11 |
| Open source license | Apache 2.0. | Shipped | ADR-0008 |
