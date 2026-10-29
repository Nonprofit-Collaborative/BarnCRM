# ADR-0046: Two suites from the same packages, a tentative name, unlocked now and managed at listing

> Naming note: the suite names in this ADR are superseded by ADR-0122. The Impact Suite is now the Nonprofit Edition and the Community Suite is now the Standard Edition. The text below keeps the names as decided on 2026-09-23.

**Status:** Accepted
**Date:** 2026-09-23
**Source:** product owner decision (Brandon), plan Section 3 "Suites and packaging", Section 8.3,
Section 11.2 open question 5, and Section 12 decisions D-01 and D-02; amends ADR-0001 (name) and
ADR-0002 (packaging)

## Context

"Open Impact" is not available as a product name (ADR-0001 re-opened the name on 2026-09-06).
Organizations that are not nonprofits want the household and relationship model without gifts,
receipts or nonprofit wording, and the 2026-09-22 parking-lot direction answered that with a
separate CI-built community Households edition. ADR-0002 chose managed 2GP packages, but the
namespace is not registered and pilots need fast iteration. Salesforce documents no conversion
of an installed unlocked package to managed: its Package Migrations feature covers 1GP managed
to 2GP managed only. A package also cannot install another silently; the Tooling API
PackageInstallRequest exists but is not a supported product path.

## Decision

- **Tentative name BarnCRM**, subject to the plan Section 8.3 checks. The repository, labels
  and docs keep the working title until the name is verified, then are renamed in one pass. The
  namespace stays deferred. This re-opens the name part of ADR-0001; its namespace deferral stands.
- **Two suites from the same packages.** Impact Suite (nonprofits) is Core plus Giving, with
  Programs, Logic Models, Volunteers, Funders and Connect offered. Community Suite (for-profit
  and other organizations) is Core alone, with the modules that fit (Volunteers, Events later)
  offered; nonprofit-only modules are never offered.
- **One install to start.** An administrator installs Core. The Setup Assistant's first step asks
  which suite; the Nonprofit Edition toggle opens Salesforce's installer for Giving, then offers
  the other modules (C-24, C-30). Each module is one administrator click in Salesforce's installer.
- **Core is neutral (C-29).** Nonprofit wording, the nonprofit app, the giving and receipt settings
  and the nonprofit Setup Assistant steps move to Giving. Core is never split into a base package
  it depends on; ADR-0003 stands. Open question 5 (bundle Core and Giving) is resolved: separate.
- **Unlocked now, managed at listing (amends ADR-0002, does not supersede it).** Packages are
  built and piloted as unlocked packages under the namespace once registered, following
  managed-package rules from the start: anything `global` is permanent, nothing relies on a
  subscriber editing a packaged component, no namespace is hard-coded. The same source becomes
  2GP managed packages for the AppExchange listing with identical API names.
- **Production pilots on unlocked packages are allowed** (owner decision). Each moves to managed
  through a supported migration: export, uninstall unlocked, install managed, reimport, built and
  rehearsed before listing (C-31).
- Supersedes the 2026-09-22 parking-lot direction of a separate CI-built community Households
  edition.

## Alternatives considered

- **One package with hidden modules.** Rejected: Principle 3 says an unused module leaves nothing
  in the org, and Community orgs would carry gift and tax objects.
- **A separate CI-built community edition package.** Superseded: it duplicates Core.
- **Unlocked only.** Rejected: no AppExchange listing and no push upgrades.
- **Managed from day one.** Rejected: blocks fast pilot iteration, and the namespace is not yet
  registered.

## Consequences

- C-29, C-30 and C-31 are added to the plan (Section 5.1, roadmap v0.6, v0.7 and v0.10).
- Pilot orgs must be told in writing, before install, that they will migrate from unlocked to
  managed packages.
- Every review checks managed-package rules now, since unlocked packaging will not enforce them.
- The name is still unverified; a later ADR records the final name once Section 8.3 is done.
