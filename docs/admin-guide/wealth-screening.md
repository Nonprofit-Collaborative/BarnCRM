# Wealth Screening Data

## What It Does

BarnCRM keeps what an outside wealth screening said about a person, so fundraisers see it
beside the person's giving (G-32). BarnCRM buys nothing and calls no screening service: you
choose a vendor, send them your list, and load the file they send back.

Five fields on the person, in the **Giving Details** section of the **Details** tab:

| Field | What it holds |
|---|---|
| **Capacity Rating** | The vendor's capacity rating or range, as they wrote it (text, because vendors differ) |
| **Affinity Rating** | The vendor's affinity or propensity rating, as they wrote it |
| **Screening Score** | The vendor's overall score, a number so it sorts and filters in Find |
| **Screening Date** | When the screening was run |
| **Screening Source** | The vendor or researcher it came from |

Nothing in BarnCRM reads, recalculates or totals these fields. Find, reports and donor
segments can filter on them like any other field.

## Who Sees It

**Giving Admin** and **Giving Staff** read and edit the five fields. **Giving Read Only** does
not see them: screening data is a judgment about a person's means, so it stays with the people
who fundraise. To show it to someone else, give them field access in a permission set of your
own.

## How to Turn It On

Nothing to turn on: the fields and the import template come with the Giving module.

## Loading a Vendor's File

1. Ask the vendor for a CSV with one row per person and the person's email address.
2. Open BarnCRM's import and upload the file. Choose the **Wealth Screening** template.
3. The template expects the headings **Email**, **Capacity Rating**, **Affinity Rating**,
   **Screening Score**, **Screening Date** and **Screening Source**. Rename the vendor's
   headings to these before uploading, or map each one on the mapping step.
4. Run it. Each row updates the person whose email matches. A row whose email matches nobody
   is reported and not loaded, so a screening file never adds a person.

Where people are person accounts, the same template works through the person's email on the
account.

## Things to Know

- **A new screening replaces the old one.** Loading a new file overwrites the five fields. Keep
  the vendor's file if you need the history.
- **Not a data source for scores or levels.** Donor scoring and donor levels use giving only.
- **Removing it.** Clear the five fields with Bulk Update when a screening is out of date or a
  person asks.
