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
| 1 | `oi-test` | 20,000 contacts, 8,000 households, 60,000 gifts (keep total under about 90,000 records) | Every batch and queueable completes without a governor limit error at a realistic ratio of gifts to donors; per-chunk timings to extrapolate from |
| 2 | A Partial or Full Copy sandbox, or a Developer Pro sandbox with extra storage, owner approval needed | The full Section 7.3 target | The absolute numbers in the plan |

Tier 1 is the v0.11 exit evidence unless the owner provides a tier 2 org. Report the
extrapolation, not a pass, for anything only tier 1 measured.

### Data shape

Generate CSV files with a script under `scripts/data/` (not committed with real names: use
the sample data name lists). Keep the plan's ratios: 2.5 contacts per household, 3 gifts per
contact on average, with a long tail (1% of donors with 50 or more gifts, so per-parent
rollup work is uneven), 10% of gifts with a soft credit, 5% with two allocations, gift dates
spread over ten years so fiscal year rollups have work to do.

Load with Bulk API 2.0 (`sf data import bulk`), in this order, with Automation Control left
on so triggers run as they would for a customer: households and contacts, then gifts, then
soft credits and allocations. Record for each load: rows, elapsed time, failed rows and the
first error.

### Runs and what to record

| Run | How to start it | Pass when |
| --- | --------------- | --------- |
| Trigger path during load | The bulk loads above | No failed rows from limits (`Too many SOQL queries`, `CPU time`, `UNABLE_TO_LOCK_ROW`); lock errors under 0.1% and gone on retry |
| Full rollup recalculation | Rollups page, **Recalculate all** (`RollupFullRecalcBatch`) | Completes with no failed batches; Error Log has no limit errors; spot check 20 households and 20 contacts against a SOQL aggregate |
| Household naming | **Recompute all households** on the household naming settings (`HouseholdNamingBatch`) | Completes; names match the naming preview for a sample |
| Duplicate scan | **Scan for duplicates** (`DuplicateScanBatch`) | Completes; no batch reported as not checked; no CPU limit errors on the largest match groups |
| Donor levels and acknowledgments | `DonorLevelBatch` and `AcknowledgmentBatch`, started from anonymous Apex with `Database.executeBatch` if the scheduler is not due | Complete with no failed batches |
| Field utilization | `FieldUtilizationBatch`, the same way | Completes |
| Import | Import wizard with a 250k-row file on tier 2 (a 25k-row file on tier 1), contacts plus gifts | Completes; rows processed per minute recorded; undo of the whole batch (`ImportUndoBatch`) completes |
| Interactive pages | Open a household with 30 members, a contact with 500 gifts, the Giving dashboard, Find with a broad search | Each page usable in under 5 seconds; no `Too many query rows` error |

For each batch record: `AsyncApexJob` total and failed job items, elapsed time, and the
largest CPU time in a debug log of one chunk. A chunk using more than 70% of a limit is a
finding even when it passed: write it up as an issue with the numbers.

### Afterwards

Delete the loaded data (Bulk API hard delete, children first) so `oi-test` returns to the
sample data set, then rerun `scripts/org/seed-sample-data.sh oi-test` if the sample data was
removed. Write the results into the v0.11 release notes under "Scale test", with the tier,
volumes, timings and every finding.

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
