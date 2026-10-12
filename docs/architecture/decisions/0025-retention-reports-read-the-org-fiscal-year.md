# ADR-0025: Retention reports read the org fiscal year, and the two fiscal years have to agree

**Status:** Accepted
**Date:** 2026-09-08
**Source:** builder decision under plan Section 9.3 (platform limitation), found while
building G-16 against canonical model Section 26 and `Fiscal_Year_Start_Month__c`

## Context

BarnCRM holds its own fiscal year. `Fiscal_Year_Start_Month__c` in Nonprofit Settings
names the month the organization's year begins, and rule R-R3 computes every fiscal rollup
window from it at run time: `Giving_This_Year__c`, `Giving_Last_Year__c`,
`Giving_Two_Years_Ago__c`, and now `Gifts_Last_Year__c`.

A Salesforce report cannot read that setting. Report filters express a relative year with a
date literal, `THIS_FISCAL_YEAR`, `LAST_FISCAL_YEAR`, `LAST_N_FISCAL_YEARS:n`, and a report
groups a date by fiscal year with a date granularity. All of those resolve against the org's
fiscal year in Setup, which is a separate value an administrator sets separately, and which
defaults to a calendar year starting in January.

The retention reports are fiscal-year shaped by definition: LYBUNT and SYBUNT are questions
about year boundaries, and a boundary that is off by a month puts a real donor on or off a
solicitation list. So the reports need a fiscal year, they cannot have the one the rest of
the package uses, and the difference is invisible: both settings produce a report that runs
and looks right.

There is no report-side workaround. A formula field could compute a fiscal year from the
setting, but a report filter still has to compare it to something, and every relative
comparison a report offers is a date literal. Making the reports calendar-year shaped would
be wrong for the roughly half of nonprofits whose year starts in July or October.

## Decision

The packaged retention reports use Salesforce fiscal-year date literals and fiscal-year
grouping, so they read the **org's** fiscal year from Setup.

1. The two fiscal years must be set to the same month, and it is an administrator's job to
   do it. `docs/admin-guide/retention-reports.md` makes it step one of "How to turn it on":
   set the fiscal year in Setup to match `Fiscal_Year_Start_Month__c` in Nonprofit Settings.
2. Every packaged report that names a fiscal year says in its own description which fiscal
   year it means, so the mismatch is legible from inside the report.
3. Where a retention question can be asked without a date literal, it is. LYBUNT, SYBUNT
   and the retained test read `Last_Gift_Date__c` and `Gifts_Last_Year__c`, which the rollup
   engine fills from the Nonprofit Settings fiscal year. The literals then bound the same
   window from the other side, which is exactly why the two have to agree.
4. Health Check does not yet compare the two. That is a candidate check, recorded here
   rather than built, because Health Check v2 (C-21) is the place for a check with a fix
   action and this one has a one field fix. **Superseded 2026-09-09:** the comparison shipped
   in C-11 rather than waiting for C-21, because the existing `withFix` pattern already carries
   a finding to a settings console section and the check needed nothing C-21 was going to add.
   The `fiscal_year_mismatch` finding names both months and opens General settings.

## Alternatives considered

**Build the retention reports entirely from rollup fields, with no date literal at all.**
This would carry the Nonprofit Settings fiscal year end to end. It fails on grouping: the
new versus retained report and the conversion report group donors by the fiscal year of
their first gift, and a report can only group a date by the fiscal year Setup knows. It also
fails on SYBUNT, which needs "before this fiscal year began" and has no field for it.

**Ship the reports calendar-year shaped and say so.** Simple, and wrong for any organization
whose year starts in July. A retention report on the wrong year boundary is the defect this
feature exists to remove.

**Compute fiscal year fields on Account with a formula that reads the setting.** A formula
field cannot read a custom setting's org-level value in a way that is safe to package here,
and it would add three fields to every donor record to work around a Setup value an
administrator can set in ten seconds.

**Make the package write the org fiscal year to match.** Fiscal year in Setup is not a
setting a package should take over: changing it rewrites how every standard report, forecast
and dashboard in the org reads, including reports that have nothing to do with BarnCRM.

## Consequences

- **An org with mismatched fiscal years gets retention reports that disagree with the donor
  record.** A donor's Giving Last Year is measured on one boundary and their appearance on
  LYBUNT on the other. The mitigation is step one of the admin guide, the per-report
  descriptions, and the "Common mistakes" entry that names the symptom: a donor on the LYBUNT
  list whose Giving This Year is not zero.
- **A future Health Check rule can close this properly** by comparing
  `Fiscal_Year_Start_Month__c` to the org's fiscal year and offering the fix. Revisit at
  C-21, or sooner if a subscriber reports the symptom above. **Shipped 2026-09-09** in C-11,
  reading Setup's month from `Organization.FiscalYearStartMonth` and BarnCRM's from the
  same call the rollup engine makes, so the number compared is the number the totals were
  computed from, January default included.
- **Nothing else in the package changes.** The rollup engine keeps its own fiscal year, and
  R-R3 is untouched.
