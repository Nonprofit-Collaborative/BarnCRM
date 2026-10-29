# ADR-0122: BarnCRM comes in two editions, the Nonprofit Edition and the Standard Edition

**Status:** Accepted (owner decision, Brandon, 2026-10-14; plan decision D-96)
**Date:** 2026-10-14
**Source:** owner decision of 2026-10-14 and his clarification the same day; plan Section 4.1
"Suites and packaging" and decision D-96; supersedes the suite names in ADR-0046 and ADR-0072

> **Amended by ADR-0143** (`0143-edition-internal-values.md`, plan D-145, 2026-10-29): the
> stored values are now `Standard` and `Nonprofit`, not `Community` and `Impact`. The rest of
> this record stands.

## Context

ADR-0046 named two suites, the Impact Suite (nonprofits) and the Community Suite (any other
organization). ADR-0072 made the Setup Assistant's first step ask which suite, and showed the
choices as "Community Suite" and "Nonprofit Edition (Impact Suite)", so one offering had two
names. "Community Suite" also suggests a lesser or free tier, and "Community" clashes with
Salesforce Community Cloud and the Trailblazer Community.

## Decision

- BarnCRM is one suite of tools that comes in two editions. Both editions have the full core
  suite of tools (people, households, relationships, addresses, imports with undo, Find and
  bulk update, duplicate review, Org Optimizer, Health Check, settings and the rest of Core).
- The **Standard Edition** (formerly the Community Suite) is the core suite, for any other
  Salesforce org. It is Core alone, with the modules that fit offered. It is never described as
  reduced, basic or a subset.
- The **Nonprofit Edition** (formerly the Impact Suite) is the Standard Edition plus the
  nonprofit tools: Giving and the other nonprofit modules.
- "Impact Suite" and "Community Suite" are retired in user-facing text and documentation.
- Nothing about packaging, module offers or behavior changes. The setting's stored values
  (`Community` and `Impact` in `Suite__c`), the setting name, labels' API names, class and
  component names are unchanged; only the text people read changes.

This supersedes the names in ADR-0046 and ADR-0072. Their other decisions stand.

## Alternatives considered

- **"Community Edition."** Rejected: it clashes with Salesforce Community Cloud and the
  Trailblazer Community, and in software it usually means a cut-down free tier, the opposite of
  the Standard Edition, which has the full core suite.
- **Keeping the suite names.** Rejected: two names for one offering, and "Community" misleads.

## Consequences

- Labels, help, the admin guide, the feature catalog and the plan use the edition names.
- Accepted ADRs keep their original wording; read this record for the current names.
- API names that carry the old idea (`Suite__c`, `Core_SuiteChoice_*`, `setupStepSuite`) stay,
  to avoid breaking metadata, saved settings and tests.
