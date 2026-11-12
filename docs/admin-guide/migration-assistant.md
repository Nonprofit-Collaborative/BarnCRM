# Migration Assistant

## What It Does

The Migration Assistant moves your records and setup from another app in the same Salesforce
org into BarnCRM, one step at a time, in the right order. It reads the other app's records
directly, so there is no file to export and load back. Each step is checked before anything is
written, and you can see that what arrived matches what was there. At the end a checklist names
the other app's automations to switch off, so the two apps do not both keep running.

The Assistant never changes, switches off or uninstalls the other app. It reads it. You switch
off the old app's automations yourself, when you are ready, from the checklist.

A migration from one app is called a **kit**. A kit ships with the BarnCRM module that receives
the records, and the Assistant offers it only when the app it moves from is installed in your
org. These kits ship:

- **DLRS Rollups** (Rollup Builder): copies your DLRS rollups into Rollup Builder.
- **NPSP Customizable Rollups** (Rollup Builder): copies your NPSP customizable rollups into
  Rollup Builder.
- **NPSP People and Addresses** (Core): adopts NPSP households in place, then copies NPSP
  relationships, affiliations and household addresses. See
  [Migrating From NPSP](migrating-from-npsp.md#in-org-migration-kits).
- **PMM Programs and Services** (Programs): copies Program Management Module programs, cohorts,
  services, program engagements and service deliveries, keeping their links. See
  [Programs](programs.md#moving-from-pmm).
- **V4S Jobs, Shifts and Hours** (Volunteers): copies Volunteers for Salesforce jobs, shifts,
  sign-ups and completed hours. See [Volunteers](volunteers.md#moving-from-v4s).
- **NPSP Funds, Levels, Recurring Donations** (Giving): copies General Accounting Units,
  levels and recurring donations. See
  [Migrating From NPSP](migrating-from-npsp.md#in-org-migration-kits).
- **NPSP Gifts and Soft Credits** (Mirror): copies Campaigns as appeals, won Opportunities as
  gifts with their funds and tribute, and contact, partial and account soft credits. See
  [Migrating From NPSP](migrating-from-npsp.md#in-org-migration-kits).
- **Nonprofit Cloud Gifts and Soft Credits** (Mirror): copies Campaigns as appeals, gift
  designations as funds, gift commitments, paid gift transactions as gifts (linked for the
  Gift Transaction mirror) and gift soft credits. See
  [Migrating From Nonprofit Cloud](migrating-from-nonprofit-cloud.md#the-nonprofit-cloud-gifts-and-soft-credits-kit).

An app can have several kits, one for each BarnCRM module that receives its records. Its
listing then shows one **Start Migration** button per kit, each with the kit's name. Run them
in the order they are listed.

A kit for Outbound Funds follows in a later release. Until a kit
covers what you need, the import templates in [Migrating From NPSP](migrating-from-npsp.md) and
[Migrating From Nonprofit Cloud](migrating-from-nonprofit-cloud.md) move those records from a
file.

## How to Turn It On

There is nothing to turn on. You need **Manage BarnCRM Settings**, and for a step that loads
records also the permission to import (the **BarnCRM Admin** role has both).

1. Open the app launcher, type `BarnCRM`, and choose **BarnCRM Admin**.
2. Click **BarnCRM Settings**, then **Integrations** in the left navigation.
3. Find the app you are moving from. When BarnCRM has a kit for it, the listing shows
   **Start Migration**. Click it.

If you do not see **Start Migration**, either the app is not detected in your org (the listing
says **Not installed**, or is not shown at all), there is no kit for it yet, or you do not have
Manage BarnCRM Settings.

## Running a Kit

The Assistant opens in place of the list, with **Back to Integrations** at the top. It shows the
kit's name, what it moves, and its steps in order. Each step shows its status:

- **Not Started**, **Waiting** (an earlier step is not done yet), **Running** (records are being
  read, previewed, loaded or undone), **Ready to Review** (the preview is done), **Done**,
  **Undone** or **Failed** (the reason is in the results' run log).

Work through the steps from the top:

1. **A step that loads records** (for example, volunteer jobs). Click **Start**. BarnCRM counts
   the other app's records, reads them in the background and runs a preview (a dry run) of what
   loading them would do. Nothing is written yet. Click **Refresh** to see progress.
2. When the step says **Ready to Review**, click **Show Results**. You see the same results
   panel as a file import: what the load would create, update, match or reject, the run log,
   the rejected rows with their reasons, and **See Every Row** (see [Importing](importing.md)).
3. Click **Load** to write the records (confirm the count). When it finishes the step is
   **Done**. A rejected row can be corrected and retried from the data job's rows, as for a
   file import ([Correcting Rows](import-rows.md)).
4. **A step done in another BarnCRM tool** (for example, copying DLRS rollups). Click the
   tool's button (for example **Open Rollup Builder**), do the work there, come back and click
   **Mark Done**.

A step cannot start until every step above it is done, because later steps often point at
records the earlier ones made.

### Checking the Result

Under each loading step, **Verification** shows four numbers:

- **In the other app now**: how many records the step reads, counted again now.
- **Read into BarnCRM**: how many rows were read.
- **Loaded**: how many rows created, updated or matched a record.
- **Rejected**: how many rows failed.

The step says **Verified** when the first three agree and nothing was rejected. Otherwise it says
**Check this step** and the numbers show where they part. A kit can add its own check, shown the
same way; for a step done in another tool that is the only check.

Records you cannot see are not read. Run a migration as a user who sees every record of the
other app, such as a system administrator with the BarnCRM Admin role.

### Undo

Only the latest loading step that is **Done** offers **Undo**, and only while no later step is
done. Undo is the Super Importer undo: it removes what the step created and puts back what it
changed, within the undo window (see [Importing](importing.md)). An undone step can be started
again. A step done in another tool is unmarked with **Mark Not Done**; undo its work in that
tool.

### Retire the Old App

When every step is done, **Retire the Old App** lists the other app's automations to switch off,
each with where to find it. Tick each one once you have switched it off in that app. When every
step is done and every item ticked, the migration says **Complete**. Unticking an item or
undoing a step reopens it.

Keep the old app installed until you have checked your data in BarnCRM. Uninstall it from Setup,
**Installed Packages**, when you no longer need it.

## The Rollup Kits

Both rollup kits have one step, done on the **Rollup Builder** tab:

- **DLRS Rollups**: **Import From DLRS** (see [Rollups](rollups.md#import-from-dlrs)). The
  check counts your active DLRS rollups and how many have a BarnCRM copy that is on.
- **NPSP Customizable Rollups**: **Import From NPSP** (see
  [Rollups](rollups.md#import-from-npsp-customizable-rollups)). The check counts your active NPSP
  customizable rollups and how many have a BarnCRM copy that is on.

The retire checklist then reminds you to switch each copied rollup off in DLRS or in NPSP
Customizable Rollups.

## For Contributors: Adding a Kit

A kit is data plus, only when needed, one small class. It needs no change to Core.

1. Add a **Migration Kit** custom metadata record (`Migration_Kit__mdt`) to the module that owns
   the destination records (Mirror when the source is a standard object such as Opportunity):
   - **Source App**: the DeveloperName of the product's **Integration App** record. Add that
     record in Core first if it is missing, with Detection Objects.
   - **Steps**: a JSON array, in run order. A loading step:

     ```json
     {
       "key": "jobs",
       "label": "Volunteer Jobs",
       "kind": "import",
       "source": "ns.Job__c",
       "fields": ["Name", "ns.Description__c", "ns.Campaign__r.Name"],
       "filters": [{ "field": "ns.Inactive__c", "value": false }],
       "templateKey": "migration_example_jobs"
     }
     ```

     Write a packaged name with a dot where the platform has two underscores, as Integration App
     records do. A filter may add `"op": "notEquals"` (with `"value": null`, the field is not
     blank). When a column holds the Id of a record an earlier loading step moved (a job's
     campaign, say), add `"links": [{"column": "ns.Campaign__c", "step": "campaigns"}]`: staging
     puts the BarnCRM record that step made in its place, so the template maps that column by
     record Id. The earlier step's template must keep one row per `Id` (`"uniqueBy": ["Id"]`).
     A step done in another tool:
     `{"key": "copy", "label": "Copy Rollups", "kind": "tool", "tab": "Rollup_Builder", "toolLabel": "Open Rollup Builder"}`.
   - **Retire Checklist**: a JSON array of `{"key": "...", "text": "..."}`, one per automation of
     the old app to switch off, saying where.
2. For each loading step, ship an **Import Template Default** record with that Template Key whose
   column names are the step's field paths exactly as written in `fields` (and `Id`). Map them to
   BarnCRM fields as for any file. The template's matching, file values and row rules all apply.
3. Only if rows need reshaping (one source record to several rows) or a step needs its own
   check, set **Extension Class** to a class implementing `MigrationKitExtension` (Core):
   `rows(stepKey, records)` returns the rows for a page of source records, or null to keep the
   default; `verify(stepKey)` returns a source count and a done count, or null. For a loading
   step, a check the extension returns replaces the comparison of the row counts (reshaped rows
   need not match the source count); a rejected row still stops **Verified**.
4. Document the kit in its module's admin guide and add test rows to the Testing Guide.

See ADR-NEXT `NEXT-migration-assistant.md` for the design and the canonical model Section 29ZS
and R-MK1 for the rules.
