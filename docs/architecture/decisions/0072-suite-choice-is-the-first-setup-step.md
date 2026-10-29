# ADR-0072: The suite choice is a Core setting the Setup Assistant asks first

> Naming note: the suite names in this ADR are superseded by ADR-0122. The Community Suite is now the Standard Edition and the Impact Suite is now the Nonprofit Edition. The text below keeps the names as decided on 2026-10-12.

**Status:** Accepted (builder decision, under owner decisions of 2026-09-23 and 2026-10-12)
**Date:** 2026-10-12
**Source:** C-30; plan Section 4.1 "Suites and packaging"; ADR-0046; owner decisions (Brandon,
2026-10-12); amends decisions 4 and 7 of ADR-0062
(`0062-core-names-other-products-only-when-detected.md`)

## Context

ADR-0046 says the Setup Assistant's first step asks which suite: the Community Suite is Core
alone, the Impact Suite (Nonprofit Edition) is Core with Giving, and turning the Nonprofit
Edition on opens Salesforce's installer for Giving. A package cannot install another one
silently. Until now Core could tell a nonprofit org only by Giving being installed.

The owner decided on 2026-10-12: any org may choose the Nonprofit Edition; nothing nonprofit is
visible in Core except that choice; coexistence settings for NPSP and Nonprofit Cloud appear only
when that product is detected; sample data is never loaded by default.

## Decision

1. **The choice is a Core setting, `Suite__c`**, stored as text (ADR-0019): `Community` or
   `Impact`, blank until someone chooses. It is a preference, not a licence or a detection: any
   org may choose either, and changing it installs, removes or hides nothing.
2. **It is the Setup Assistant's first step** (`suite`, sort order 5, before coexistence). The
   step finishes when the setting has a value. The same choice is a picklist row in the General
   section of BarnCRM Settings, shown as "Community Suite" and "Nonprofit Edition (Impact Suite)".
3. **Choosing the Nonprofit Edition never installs anything.** When Giving is not installed the
   step shows how to install it: a link that opens Salesforce's installer for Giving in a new
   tab, when a published version exists, and Giving's description otherwise, plus a **Check
   again** button that re-reads what is installed. Giving's own steps join the assistant once
   it is installed. Choosing the Community Suite moves straight on.
4. **The suite is a third kind of gate**, beside "a module is installed" and a detected org
   shape. Step six (and the Module Manager, C-24) offers Giving, Programs, Funders and Connect
   when the suite is `Impact` or Giving is installed; otherwise Core, Volunteers and any module
   already installed. Core's own wording stays gated on Giving being installed, not on the
   suite: the choice itself is the one nonprofit thing every org sees.
5. **What is preselected.** The saved choice; otherwise the Nonprofit Edition when Giving is
   installed, or NPSP or Nonprofit Cloud is detected; otherwise nothing, so the administrator
   picks.
6. **Install links are release data in Apex.** `ModuleDetectionService` holds each module's
   published package version Id (`04t`), blank until that module is first published, and builds
   `/packaging/installPackage.apexp?p0=<Id>` from it. Only a new Core version can change either
   an Apex constant or a protected custom metadata row, so a metadata type would add an object,
   fields and rows for nothing an administrator can use.
7. **Sample data is untouched.** Choosing a suite loads nothing; sample data stays an explicit
   action (decision 8 of `0062-core-names-other-products-only-when-detected.md`).

## Alternatives considered

- **Ask the suite inside the coexistence step.** Rejected: one step would ask two unrelated
  questions, and the plan names the suite as the first step.
- **Gate Core's nonprofit wording on the suite.** Rejected: an org that chose the Nonprofit
  Edition but has not installed Giving has no gift screens for that wording to describe.
- **A custom metadata module catalog for install links.** Rejected for decision 6's reason.
- **Use the Tooling API `PackageInstallRequest` to install Giving.** Rejected: not a supported
  product path (ADR-0046), and the owner ruled out installing anything automatically.

## Consequences

- Core alone has eight Setup Assistant steps and nine with Giving; every later step moves down
  one.
- Until a module has a published version, the step and step six link to its README instead of an
  installer; the release that publishes a module fills in its Id (plan Section 6, v0.8).
- `0062-core-names-other-products-only-when-detected.md` decision 4 ("until C-30, an org without
  Giving sees Core and Volunteers") now also offers the full list when the suite is `Impact`.
