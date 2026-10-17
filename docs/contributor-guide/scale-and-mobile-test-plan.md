# Scale and mobile test plan (v0.11)

The v0.11 row of the product plan asks for a scale test (plan Section 7.3: 100k contacts, 40k
households, 1M gifts, a full rollup recalculation within platform limits, and an import of a
250k-row file) and a mobile audit. Both need a real org, so neither runs in continuous
integration. This page is how the orchestrator runs them on `oi-test` and records the result.

## Before you start

- Run from a dedicated detached worktree at the pushed head being tested, never the main
  checkout (see "The org test gate" in [ci.md](ci.md)).
- `oi-test` is shared. Take the org lock other agents use before loading data, and release it
  when the data is deleted again. Do not run the org test gate at the same time: the volume
  slows every test and the gate's timings stop meaning anything.
- `sf org list limits --target-org oi-test` first and record `DataStorageMB`,
  `DailyAsyncApexExecutions`, `DailyBulkV2QueryJobs` and `DailyApiRequests`.

## Scale test

### Storage decides how much of the target fits

A scratch org has 200 MB of data storage, and Salesforce counts most records as 2 KB each, so
`oi-test` holds roughly 100,000 records in all. The full target (about 1.15 million records)
does not fit in any scratch org. Run it in two tiers:

| Tier | Where | Volume | Proves |
| ---- | ----- | ------ | ------ |
| 1 | `oi-test` | 10,000 contacts, 4,000 households, 30,000 gifts (about 78,500 records from the files and each gift's automatic default allocation, plus about 62,000 automatic household member soft credits, so about 140,000 in all; see "How to run tier 1" for the storage this takes) | Every batch and queueable completes without a governor limit error at a realistic ratio of gifts to donors; per-chunk timings to extrapolate from |
| 2 | A Partial or Full Copy sandbox, or a Developer Pro sandbox with extra storage, owner approval needed | The full Section 7.3 target | The absolute numbers in the plan |

Tier 1 is the v0.11 exit evidence unless the owner provides a tier 2 org. Report the
extrapolation, not a pass, for anything only tier 1 measured.

On tier 2, also read Salesforce Scale Center and run ApexGuru for the run window; see
[ApexGuru and Scale Center](apexguru-and-scale-center.md).

### Data shape

Generate CSV files with a script under `scripts/data/` (not committed with real names: use
the sample data name lists). Keep the plan's ratios: 2.5 contacts per household, 3 gifts per
contact on average, with a long tail (1% of donors with 50 or more gifts, so per-parent
rollup work is uneven), 10% of gifts with a soft credit, 5% split across two funds (70/30), gift dates
spread over ten years so fiscal year rollups have work to do.

Load with Bulk API 2.0 (`sf data import bulk`), in this order, with Automation Control left
on so triggers run as they would for a customer: households and contacts, then gifts, then
soft credits, then the fund splits (Apex, see below). Record for each load: rows, elapsed
time, failed rows and the top errors.

### Runs and what to record

| Run | How to start it | Pass when |
| --- | --------------- | --------- |
| Trigger path during load | The bulk loads above | No failed rows from limits (`Too many SOQL queries`, `CPU time`, `UNABLE_TO_LOCK_ROW`); lock errors under 0.1% and gone on retry |
| Full rollup recalculation | Rollups page, **Recalculate all** (`RollupFullRecalcBatch`) | Completes with no failed batches; Error Log has no limit errors; spot check 20 households and 20 contacts against a SOQL aggregate |
| Household naming | **Recompute all households** on the household naming settings (`HouseholdNamingBatch`) | Completes; names match the naming preview for a sample |
| Duplicate scan | **Scan for duplicates** (`DuplicateScanBatch`) | Completes; no batch reported as not checked; no CPU limit errors on the largest match groups |
| Donor levels | Turn the feature on and build a ladder first (see "Donor levels and acknowledgments" below), then **Recalculate now** on the Donor levels page (`DonorLevelController.recalculate()`, which starts `DonorLevelBatch`) | Completes with no failed batches; the rungs show donor counts that add up |
| Acknowledgments | `AcknowledgmentRunService.startEmailRun()` from anonymous Apex (starts `AcknowledgmentBatch`), after the acknowledgment setup below | Completes with no failed batches; processed items match the "To acknowledge" gifts |
| Field utilization | Org Optimizer, Field utilization section, choose the gift object and Contact (`FieldUtilizationController`) | Each call returns in under 30 seconds; no limit errors; no Error Log rows |
| Import | Import wizard with a 250k-row file on tier 2 (a 25k-row file on tier 1), contacts plus gifts | Completes; rows processed per minute recorded; undo of the whole batch (`ImportUndoBatch`) completes |
| Interactive pages | Open a household with 30 members, a contact with 500 gifts, the Giving dashboard, Find with a broad search | Each page usable in under 5 seconds; no `Too many query rows` error |

Donor levels and acknowledgments need setup the load does not do, so do it after the loads (levels
and a rule switched on earlier run in the gift triggers and change the load timings):

- **Donor levels.** The feature is off until the organization turns it on, and
  `DonorLevelController.recalculate()` refuses in two cases: the running user lacks the
  `Manage_BarnCRM_Settings` custom permission (in the BarnCRM Admin permission set; a plain
  System Administrator does not have it), or **Donor levels** is off in the Giving settings
  (`Donor_Levels_Enabled__c`). The 2026-10-17 run hit one of these and ran the batch directly,
  which skips the ladder. Supported start: as a user with BarnCRM Admin, open BarnCRM Settings,
  Giving, **Donor levels**, create three rungs (for example Friend 100 to 1,000, Sustainer 1,000
  to 5,000, Leadership Circle 5,000 and up, as in the donor levels admin guide), turn **Donor
  levels** on in Giving, then **Recalculate now**.
- **Acknowledgments.** The generator loads every 10th gift (3,000) as "To acknowledge"
  (`--acknowledge-every`, 0 turns it off); the rest are "Not required". Gifts are only queued by a
  rule (the trigger leaves a gift with no matching rule as loaded), so the loaded status is what
  `AcknowledgmentBatch` finds. The batch still sends nothing without an active **Email** rule, so
  for the full send path create one on the Acknowledgments page before starting the run, and
  remember that every match sends an email (about 3,000 against the org's daily email limit; use
  a larger `--acknowledge-every` to shrink it).
- **Field utilization** uses the 10-fields-per-call path only above 100,000 records of the
  object. Tier 1 has 30,000 gifts and about 10,000 contacts, so it uses the larger chunk and
  cannot measure the 10-field path; that needs tier 2.

For each batch record: `AsyncApexJob` total and failed job items, elapsed time, and the
largest CPU time in a debug log of one chunk. A chunk using more than 70% of a limit is a
finding even when it passed: write it up as an issue with the numbers.

### Afterwards

Delete the loaded data (Bulk API hard delete, children first) so `oi-test` returns to the
sample data set, then rerun `scripts/org/seed-sample-data.sh oi-test` if the sample data was
removed. Write the results into the v0.11 release notes under "Scale test", with the tier,
volumes, timings and every finding.

### How to run tier 1

From the dedicated worktree, holding the `oi-test` lock (needs `sf`, `jq` and `python3`):

```bash
bash scripts/org/scale-test-tier1.sh oi-test            # generate, load, record
# ... the runs table above ...
bash scripts/org/scale-test-tier1.sh cleanup oi-test    # hard delete, children first
```

- `scripts/data/generate-scale-data.py` writes the CSVs into `scale-test-data/` (git-ignored,
  seeded, names from `generate-sample-data.py`). The load script runs it for you. It also
  writes `import-wizard-25k.csv` (25,000 gift rows with the donor on each row, in the
  "Generic gift list" template's headings) for the Import row; those rows need the
  "Scale test General" fund, so run the import before cleanup, or clean up with
  `--keep-funds`. Undo the import batch in the wizard, not in cleanup.
- The load script records the four limits above, record counts, and per load the job id, rows
  processed and failed (read with `sf data bulk results`), elapsed seconds and the top error
  messages with counts in `scale-test-data/results-run-<alias>-<time>.md`. Each run also gets
  its own folder, `scale-test-data/run-<mode>-<alias>-<time>/`, that keeps the failed rows of
  every load as `failed-<load>.csv` (a later run or cleanup never overwrites them) and a
  `refused-by-code.tsv` tally. The run ends with the refused rows by error code (for example
  `DUPLICATES_DETECTED`) and the total, so a loss shows in the results file; read that summary
  before trusting the record counts. When a parent load had failed rows, the next file drops
  the rows whose parent did not load and the results file says how many (lost households take
  their contacts with them). It refuses any alias but `oi-test` unless `SCALE_TEST_ALLOW=1`.
- The tier 1 files hold 4,000 households, 10,000 contacts and 30,000 gifts, plus 3,000 soft
  credits, and 1,500 gifts to split across two funds. The gift trigger adds a default
  allocation to every gift, and each split adds one more allocation, so this loads about 78,500
  records (47,000 file rows, 30,000 automatic allocations, 1,500 second allocations); the
  plan's original 60,000 gifts would have loaded about 157,000 (before soft credits), over the
  roughly 100,000 a scratch org's 200 MB holds.
- The 3,000 soft credits in the file are not the only ones. With **Automatic household soft
  credits** on (the default, `Automatic_Household_Soft_Credits__c`), every gift also gets one
  automatic "Household Member" soft credit for each other current member of the donor's
  household (`SoftCreditService.createHouseholdMemberCredits`, run by the gift trigger). With
  about 2.5 contacts per household and a few large households, the 2026-10-17 run ended with
  65,299 `Soft_Credit__c` rows (857 before), about 62,000 more than the file, so expect about 2
  extra per gift and about 140,000 records in all. That run used about 230 MB of data storage
  (450 MB free before, 220 MB after, on a 500 MB org), so check the free storage covers that
  before loading. This is the product working as designed, not a load fault. Cleanup removes
  them with their gifts. Check `DataStorageMB` before loading. To change the size, set for
  example `SCALE_TEST_GENERATOR_ARGS="--households 3000 --contacts 7500 --gifts 20000"`.
- Splits are not Bulk loaded. Giving refuses any save that leaves a gift's allocations not
  totalling the gift (see "Splitting a gift one row at a time" in the gifts admin guide), and
  checks after every DML statement, so a second 30% allocation inserted on its own is refused.
  After the gifts load, the script runs one anonymous Apex script per 200 gifts
  (`scale-test-data/split-apex/`), each upserting the default allocation (cut to 70%) and the
  new 30% allocation to another fund in one statement. The results file records gifts split,
  skipped and failed.
- The org's standard Account and Contact duplicate rules (action on insert: Allow, with an
  Alert) refuse an API insert with `DUPLICATES_DETECTED` unless the caller sends the header
  `Sforce-Duplicate-Rule-Header: allowSave=true`, and Bulk API 2.0 cannot send it. Unique
  names are not enough: the rules match fuzzily, the generator's invented surnames
  (prefix plus suffix, such as Ashford and Ashwood) are near twins of each other, and a
  household's contacts share one mailing address. So households and contacts load through
  `scripts/data/rest-insert.py`, the REST sObject Collections API (200 rows per call, `sf api
  request rest`) with that header; gifts, soft credits and funds stay on Bulk API 2.0. Only
  the test load saves through the rules; the product and the org's rules are unchanged. The
  generator still gives each household its own street address and each contact its own name
  pair, email and phone, which keeps the rules from firing on most rows. Never deactivate the
  standard rules for this test.
- The generated "Scale test General" fund is loaded as the default fund when the org has none,
  so the load works without sample data; an org that already has a default keeps it. Cleanup
  removes the generated funds.
- Cleanup deletes soft credits, then gifts (their allocations go with them: Giving refuses to
  delete a gift's allocation while the gift remains), contacts and households, and exits
  nonzero when a delete job fails or records remain. Hard delete needs the Bulk API Hard Delete
  permission on the running user (off by default, even for System Administrators); without it
  the log says so. `SCALE_TEST_SOFT_DELETE=1` deletes to the Recycle Bin instead.

## Mobile audit

Run on `oi-test` with the Salesforce mobile app on one iPhone and one Android phone (or the
Salesforce mobile app in a device simulator if no device is available, and say so), as a
user holding the BarnCRM user permission sets, not an administrator.

| Screen | Check |
| ------ | ----- |
| Household record page and household members | Members list readable without horizontal scrolling; add and remove member work |
| Contact record page | Giving summary, relationships, interaction notes render; related lists open |
| Quick gift entry | A gift can be entered and saved one handed; amount and date pickers usable; errors visible without scrolling |
| Gift record page and soft credits | Read and edit work |
| Find | Search and result list usable; results open the record |
| Global actions | Every BarnCRM quick action that is on the mobile action bar opens and saves |
| Settings console, Setup Assistant, import wizard, gift batches | Desktop only: confirm each says so or is hidden on mobile rather than rendering broken |

For each screen record: device, OS, app version, pass or the problem with a screenshot. A
component that should not appear on a phone gets `formFactor` limits in its
`.js-meta.xml` or its FlexiPage, not a CSS workaround.

Also check every LWC at a 320 px wide viewport in a desktop browser (responsive mode), since
that catches most layout faults before a device is needed.

### Static audit of Core components (2026-10-13, no org)

Read from the source; the device run above still has to confirm it.

- **Form factors.** No Core `.js-meta.xml` declares `supportedFormFactors`, so each component
  supports what its page type supports: the six record panels (address, affiliation,
  household members, household of a person, relationships, merge and split) can be placed on
  a phone record page, and the admin pages are app or home pages. Nothing needed limiting.
- **Layout.** No Core component sets a pixel width or inline style. The one fixed grid that
  squeezed a control on a phone, the pause length picker on the Automation page, now stacks
  below the medium breakpoint. Wide tables sit in `slds-scrollable_x`.
- **Accessibility.** Every table has a name (`aria-label` from its heading label) and column
  headers with `scope="col"`; icon buttons and icons carry alternative text; no clickable
  `div` or `span`; status and errors use `role="status"`, `role="alert"` or `aria-live`.
  Import results now announce their counts as a run finishes.
- **Left for later: done.** The merge comparison table now takes an `aria-label` from the
  `Core_HouseholdMerge_ComparisonTable` label, and the Access page Remove buttons carry
  the person's name in an `aria-label` ("Remove {name}") as well as the `title`.
