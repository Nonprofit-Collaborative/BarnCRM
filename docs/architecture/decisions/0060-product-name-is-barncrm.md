# ADR-0060: The product name is BarnCRM

**Status:** Accepted
**Date:** 2026-10-12
**Source:** product owner decision (Brandon), plan Section 8.3 and Section 12 decision D-01;
supersedes the name part of ADR-0001 and settles the tentative name in ADR-0046; the namespace
stays deferred (ADR-0046)

## Context

The working title "Open Impact" was found to be in use (plan Section 8.3; decision D-01 was
re-opened on 2026-09-06). BarnCRM was chosen on 2026-09-23 after screening about 900 candidates.
On 2026-10-12 the product owner confirmed that the trademark search and the domain checks
cleared.

## Decision

The product is **BarnCRM**. It was renamed on 2026-10-12 in the plan, the GitHub repository
(Nonprofit-Collaborative/BarnCRM; GitHub redirects the old URL) and the docs.

The packaged labels and API names are renamed in a second pass, on top of the C-29 stack (PRs
#163 to #174), because C-29 introduced most of those labels. They are the app, the "Open Impact
..." labels and permission sets (now "BarnCRM ..."), the `Open_Impact_Giving` report and
dashboard folders (now `BarnCRM_Giving`), the `Open_Impact_Acknowledgments` email folder (now
`BarnCRM_Acknowledgments`), the `Open_Impact_Thank_You` template (now `BarnCRM_Thank_You`), the
package names in `sfdx-project.json` (now "BarnCRM Core" and so on) and every other label,
description, message and code comment that named the product. That pass lands before the first
package version, after which API names are permanent. The `Nonprofit_*` API names are a separate
decision and are not part of it.

The namespace remains deferred (ADR-0046).

## Consequences

- The docs and the packaged labels say BarnCRM together, so an admin guide page names a label
  exactly as it appears on screen.
- The vendored apex-rollup is never renamed.
- Historical statements keep the old name: ADR-0001, the release notes written under it and any
  sentence that describes the working title as history.
