# ADR-NEXT: BarnCRM uses the org fiscal year, and shows Setup values read only

**Status:** Accepted (owner decision, 2026-10-26)
**Date:** 2026-10-26
**Source:** owner QA feedback F1 (Brandon, 2026-10-26): "Fiscal Year Start Month in Settings
should reflect the org's fiscal calendar and should not need to be set manually." Scope added
the same day: the Organization section shows the Organization Name from Company Information,
read only, above Organization Legal Name. Supersedes the parts of ADR-0025 about two fiscal
years.

## Context

ADR-0025 left BarnCRM with two fiscal years: its own start month in BarnCRM Settings, which
every rollup window used (R-R3), and the org's fiscal year in Setup, which the packaged
retention reports read through fiscal year date literals. An administrator had to set both to
the same month, a Setup note asked for it, and a Health Check finding reported a mismatch.
Nothing was gained by the second value: no organization wants its totals and its reports to
measure different years, and the org already has a fiscal year that every Salesforce report,
forecast and dashboard follows.

The same question arose for the organization's name: Setup already holds it on Company
Information, and a BarnCRM copy could only drift from it.

## Decision

1. **One fiscal year, the org's.** Every fiscal rollup window and every check that names a
   fiscal year reads `Organization.FiscalYearStartMonth` through `FiscalYearSelector`. The
   BarnCRM setting `Fiscal_Year_Start_Month__c`, its console row, the Setup note asking for
   the two to match, and the `fiscal_year_mismatch` Health Check finding are removed.
2. **Read in system mode.** The month is org configuration, not record data, and rollups run
   as whoever saved a record, as the scheduling user and as the Automated Process user. The
   read must not depend on the runner, so it is `WITH SYSTEM_MODE`, cached per transaction.
   January is used only if the org returns no month.
3. **Custom fiscal years.** BarnCRM follows the standard fiscal year start month: windows are
   whole years from the first of that month. When the org has defined a custom fiscal year
   (a `FiscalYearSettings` row with `IsStandardYear` false), report date literals follow the
   custom periods instead, so Health Check reports `custom_fiscal_year` as information, with
   no fix button. The admin guide says so.
4. **Setup values shown read only.** `Setting_Definition__mdt.Data_Type__c` gains
   `SetupValue`: a console row that shows a value Setup holds, never stores or saves it, and
   says in its description where in Setup to change it. `SetupValueSelector` lists the values
   a row may name (`Organization.Name`, `Organization.FiscalYearStartMonth`); any other row is
   left out, and `check-custom-metadata.py` fails it. The General section shows **Fiscal year
   start month**; the Organization section opens with **Organization name**, directly above
   **Organization legal name**.

## Alternatives considered

**Keep the setting and copy Setup's month into it on install.** It would drift the first time
Setup changed, which is the defect this removes.

**Keep the setting as an override of Setup.** It is the old two-fiscal-year problem under
another name, and no owner asked for it.

**Read the month in user mode.** It works for an administrator and can fail for the
Automated Process user or a minimal staff profile, which would put totals on a January
boundary for one runner and the real one for another.

**Model custom fiscal years.** Reading `Period` rows and windowing on them is real work for an
option few nonprofits use. Reporting it honestly costs one query.

## Consequences

- Changing the fiscal year is done once, in Setup, followed by Recalculate in the Rollup
  Builder. The admin guide, testing guide and feature catalog say so.
- An org with a custom fiscal year gets totals on standard years and reports on its custom
  periods. Mitigation: the Health Check finding and the admin guide. Revisit if a subscriber
  needs custom periods.
- Orgs that installed an earlier build keep an unused `Fiscal_Year_Start_Month__c` field
  until the package version that drops it; nothing reads it.
- ADR-0025 decisions 1 and 4 are superseded; decisions 2 and 3 (reports say which fiscal year
  they mean, and use rollup fields where they can) stand.
