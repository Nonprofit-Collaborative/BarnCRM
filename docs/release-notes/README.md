# Release Notes

## Purpose

One file per iteration, `v0.N.md`, written at the **end** of that iteration. It is the
iteration's report to Brandon: what shipped, what did not, what it costs him to verify
it, and what he should worry about.

Plan Section 9.5 defines the format and the rhythm. Brandon reviews once per iteration;
the builder does not wait for him mid-iteration unless blocked by a day-one decision
(plan Section 9.1 item 2) or by something on the escalation list (plan Section 11.4).

These files are the internal iteration reports. The public, admin-facing release notes
that ship with a promoted package version are written for Maria, not for developers (plan
Section 7.5 item 7), and are assembled from the release note line each feature writes as
part of its definition of done (plan Section 7.4).

**`v0.1.md` is written at the end of v0.1**, after the last feature meets the definition
of done and before any v0.2 work begins (plan Section 9.1 item 7).

## Before a release

The What's New card on BarnCRM Home shows the shipped `Release_Note` custom metadata records
of the newest version (canonical model R-WN2), not these files. So before a package version
is created (plan Section 7.5 item 2):

1. From this version's draft lines (`v0.N-draft-*.md`), write the few changes an administrator
   should hear about as `Release_Note.<Name>.md-meta.xml` records, with `Version__c` set to
   `0.N`, a headline, two or three lines of detail, a sort order, and the module that ships
   them (Core's in `packages/core`, a module's in its own package). See
   `packages/core/main/default/customMetadata/Release_Note.V0_6_Whats_New_Card.md-meta.xml`.
2. Run `python3 scripts/ci/check-whats-new.py --release`. It must pass. In ordinary builds the
   same check only warns, because drafts arrive before the entries are written.

## Template

Copy the skeleton below into `v0.N.md` and fill in every section. An empty section is
answered with "None", never deleted.

```markdown
# v0.N: <iteration theme>

**Date:** YYYY-MM-DD
**Packages changed:** <package and version, one per line>

## Features completed against the plan

| ID | Feature | Package | Notes |
|---|---|---|---|

One row per feature ID from the plan's feature catalog (Section 5), with anything that
differs from what the plan described.

## Features deferred and why

| ID | Feature | Moved to | Why |
|---|---|---|---|

A feature planned for this iteration that did not ship, the iteration it moved to, and
the honest reason. "Ran out of time" is an acceptable reason; silence is not.

## ADRs added

| ADR | Title | Status |
|---|---|---|

Every decision record written during the iteration, including any platform limitation
recorded under plan Section 9.3.

## Tests and coverage

| Package | Apex tests | Apex coverage | Jest tests |
|---|---|---|---|

Coverage target is 90% per package; 75% is the platform minimum and is not the target
(plan Section 7.2).

## Org shapes passing

| Org shape | Status | Notes |
|---|---|---|
| Platform-only | | See ADR-0013 for what this shape does and does not verify |
| Sales Cloud | | |
| Sales Cloud with NPSP | | |
| Person Accounts | | |
| Nonprofit Cloud | | Opt in, and needs an entitled Dev Hub |

## Open risks

What could still go wrong, carried forward from the plan's risk register (Section 11.1)
plus anything this iteration surfaced, with the mitigation and who owns it.

## Install and walk through this iteration

The exact steps for Brandon, in a fresh org, from nothing:

1. Create or open the org.
2. Install the package versions, in dependency order, with the install links.
3. Load the sample data.
4. Run the walkthrough: <link to each admin-guide page's five-minute walkthrough>.
5. What to check, and what "right" looks like at each step.
```

## Rules

- No em dashes.
- No namespace prefixes.
- Numbers are stated, not summarized: test counts, coverage percentages, and org shape
  results are exact.
- A deferred feature is always named. An iteration report that does not mention a planned
  feature is incomplete.
