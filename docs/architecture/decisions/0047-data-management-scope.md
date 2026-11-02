# ADR-0047: Data management runs in the org, compiles queries from a document, and is phased

**Status:** Accepted; amended by ADR-0156 (Field Access Manager, C-65, D-157)
**Date:** 2026-09-23
**Source:** product owner decision (Brandon, 2026-09-23), plan Section 4.9, Section 6 and
Section 12 decision D-13; amends the import framework scope of C-14 and C-19

## Context

Maria has to load her old spreadsheet, fix many records at once and find and export exactly the
records she needs, without Setup, API names or an outside tool (plan Section 2.3). The owner asked
for NPSP Data Importer parity, Jetstream's query builder and bulk update, and the useful
dataimporter.io capabilities, phased, with the rest later. Gift import does not work today: no
package implements `ImportEntityProcessor`, and Core looks up a `GiftImportProcessor` class that
does not exist, while the first customers must migrate gifts. A Lightning session cannot call the
REST or Bulk API; the workaround is a Named Credential calling the org from Apex, a stored token
and a self-callout to explain at security review. Plan Section 4.10 forbids SOQL typed by admins.

## Decision

- **Everything runs inside the org, with no call to Salesforce's own APIs.** Batch Apex and
  user-mode DML only; no Named Credential, connected app or Bulk API in v1 or 1.x. Revisited only
  with scheduled imports (C-38), and only if the 1M-gift scale test shows Batch Apex too slow.
- **Queries are compiled from a document, never accepted as text.** Find, bulk update and saved
  queries share one query document (object, fields, R-R2 filter, order, limit). The compiler takes
  object and field names only from describe results, binds every value, and runs
  `Database.queryWithBinds` with `AccessLevel.USER_MODE`. The SOQL shown is rendered for display
  only. Typed SOQL is not in v1; C-36 may add it later only through its own ADR.
- **Bulk update is a data job.** It is an `Import_Batch__c` with `Operation__c` Update, stages no
  rows, treats the confirmed count as a ceiling, journals every change through the C-19 import
  journal, and is undone the same way an import is. The API names stay; the tab reads "Data jobs".
- **Phasing.** v1: gift import (G-23) and donation matching (G-24) in v0.5; matching and per-file
  values (C-32), load one object (C-33), Find with CSV export (C-34) and bulk update (C-35) in a
  new v0.7 Data management iteration. Later: typed SOQL and advanced find (C-36); transforms,
  dedupe on import and bulk delete (C-37); scheduled imports and external sources (C-38), which
  supersede R-IT6's "nothing loads on a schedule" only for that release.
- **Defaults.** When a matching key finds several records the row is rejected. Import stays with
  the settings permission; `Find_And_Export_Records` and `Bulk_Update_Records` are new custom
  permissions that grant no record access.
- **Never built.** Jetstream's metadata deploy, anonymous Apex, API explorer and
  org-wide automation tools (its permission tool too, until ADR-0156: the Field Access
  Manager, C-65, D-157, changes Read and Edit on permission sets the admin chooses), and dataimporter.io's org-to-org migration and backup: Setup, Data
  Loader and Jetstream serve the rare technical user, and each would add security review risk for
  nothing Maria needs. Jetstream is Apache-2.0 with the Commons Clause, not an open source
  license, so its ideas are used and its code is not.

## Alternatives considered

- **Leave data management to Data Loader, Jetstream and dataimporter.io.** Rejected: API names, no
  undo, and a third party holding an OAuth token to donor data.
- **A Bulk API path through a Named Credential.** Rejected for v1 and 1.x: Setup steps, a stored
  token and a self-callout, for speed Batch Apex already has at our scale.
- **Accept typed SOQL from v1.** Rejected: a second enforcement path and an exception to Section
  4.10, for a need reports and list views meet until use shows otherwise.
- **Fold C-34 and C-35 into Hardening.** Rejected: it breaks the three-major rule and puts the tools
  past the beta cohort that should test them.

## Consequences

- Plan Section 5.1 gains C-32 to C-38; the duplicate C-25 (interaction notes) becomes C-39.
  Section 5.2 gains G-23 and G-24 in v0.5, which now carries four major features.
- A new v0.7 Data management iteration is inserted; Volunteers to AppExchange renumber to v0.8 to
  v0.13. Earlier ADRs that name an iteration (ADR-0046 names v0.7 and v0.10) keep their text; the
  plan's roadmap governs.
- The query compiler needs security review notes, and v0.7 proves a 250,000-row import and a
  50,000-record bulk update with undo in the scale org.
- Undoing a gift import keeps any gift with an issued receipt (ADR-0010, ADR-0024).
