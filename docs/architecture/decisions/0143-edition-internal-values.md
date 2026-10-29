# ADR-0143: The Edition's Stored Values Are Standard and Nonprofit

**Status:** Accepted (owner decision, Brandon, 2026-10-29; plan decision D-145)
**Date:** 2026-10-29
**Source:** owner decision of 2026-10-29; amends the "internal values unchanged" part of
ADR-0122 (`0122-edition-names.md`, plan D-96)

## Context

ADR-0122 renamed the editions in everything people read (the Standard Edition, formerly the
Community Suite, and the Nonprofit Edition, formerly the Impact Suite) but kept the stored
values `Community` and `Impact` in `BarnCRM_Settings__c.Suite__c` and in
`BarnCRM_Module__mdt.Editions__c`, to avoid breaking saved settings and tests. Every
administrator who opens Custom Settings, and every contributor reading the code, then has to
translate between two names for one edition. No customer has installed BarnCRM and no package
version exists, so renaming the values now costs only BarnCRM's own test orgs.

## Decision

- `Suite__c` stores `Standard` for the Standard Edition and `Nonprofit` for the Nonprofit
  Edition. Every `BarnCRM_Module` record's `Editions__c` names the same values (`Nonprofit`, or
  `Standard;Nonprofit` for a module both editions offer).
- The Apex constants are `ModuleDetectionService.SUITE_STANDARD` and `SUITE_NONPROFIT`; the
  components compare the same values.
- Core's post-install steps (`CorePostInstall`, which runs on install, upgrade, source deploy
  and Finish Setup) rewrite a stored `Community` to `Standard` and `Impact` to `Nonprofit`. The
  rewrite is bookkeeping, not an administrator's change, so it adds no Recent Changes row, and
  a second run changes nothing.
- Until that rewrite has run, the old values are read as the new ones in two places, both
  through `ModuleDetectionService.SUITE_BY_OLD_VALUE`: `chosenSuite`, because the org test gate
  deploys without the post-install steps (`run-org-tests.sh` sets `SOURCE_POST_INSTALL=0`), so
  a test org would otherwise lose its edition and show first-run setup again; and Recent
  Changes, because rows logged before the rename keep the old codes and are never rewritten.
- The API names that carry the old idea (`Suite__c`, `Core_SuiteChoice_*`, `setupStepSuite`,
  `recommendedSuite`, `currentSuite`) stay: renaming them changes no value anybody reads.

## Alternatives considered

- **Keep the old values (ADR-0122 as written).** Rejected by the owner: the translation stays
  forever, and after the first package version the rename would need a real migration for
  every customer org.
- **Migrate only, with no reading of old values.** Rejected: the org test gate deploys without
  the post-install steps, so the test orgs would read as having no edition until someone ran
  Finish Setup.
- **Rewrite the logged Recent Changes rows too.** Rejected: they are an audit trail; reading
  the old codes as edition names is two map entries.

## Consequences

- ADR-0122's consequence that the stored values stay unchanged no longer holds; its other
  decisions stand. Accepted ADRs that quote the old values (ADR-0072, ADR-0124, ADR-0125,
  ADR-0127) keep their wording; read this record for the current values.
- An administrator who sets the edition in Setup types `Standard` or `Nonprofit`.
- `SUITE_BY_OLD_VALUE` can be removed once every BarnCRM test org has been migrated and its
  Recent Changes rows from before the rename no longer matter. No customer org ever stores the
  old values.
