# ADR-0088: Pilots move from unlocked to managed packages with a command-line kit that reimports through the REST API

**Status:** Proposed
**Date:** 2026-10-12
**Source:** plan Section 3 "Suites and packaging", feature C-31 (Section 5.1, roadmap v0.11),
ADR-0046 (unlocked now, managed at listing)

## Context

ADR-0046 allows production pilots on unlocked packages and requires each to move to the managed
packages through export, uninstall, install managed, reimport (C-31). Salesforce offers no
conversion of an installed unlocked package. Uninstalling a package deletes its custom objects,
their records, its fields on Account and Contact, and the activities and file links on those
records. Reinstalling gives every packaged record a new Id, so every lookup between packaged
records, and every Text field that holds a record Id (ADR-0014), must be rewritten on reimport.
The namespace is deferred: the unlocked packages may carry no namespace or the registered one,
and the managed ones carry the registered one.

The task asked for the Core import engine to be reused for reimport where possible. The engine
(C-14, C-19, C-32) loads people, households and organizations from a spreadsheet through
matching rules, and Giving extends it for gifts. It does not load an arbitrary object, it does
not carry a source Id across, and its generic loader (C-33) is not built.

## Decision

- **The kit is command-line scripts in `scripts/migration/`, run by an implementer**, not a
  packaged feature. It runs once per pilot org, before the AppExchange listing, and nothing in it
  ships in a package.
- **The mapping is generated from the package source**, not written by hand:
  `build_mapping.py` reads every packaged object and field under `packages/`, drops formula and
  auto-number fields, orders objects so a parent loads before its children, and applies a small
  hand-kept overrides file (objects skipped, upsert keys, settings re-entered by hand). A new
  object or field is covered by regenerating, never by editing the mapping.
- **Both namespaces are parameters** (`--source-namespace`, `--target-namespace`, either may be
  empty). The mapping holds unprefixed names; the kit prefixes every packaged name at run time.
  No prefix is written into the repository.
- **Reimport goes through the REST sObject Collections API** (200 records a call, through
  `sf api request rest`), whose results come back in request order, so each source Id maps to
  its new Id with no extra field in the schema. Lookups to records not yet loaded, and Text
  values equal to a source Id, are filled in a second pass. Account and Contact keep their Ids,
  so their packaged fields are updated in place, and their record types are matched by developer
  name.
- **Records the managed install creates itself are upserted on their unique key**
  (automation switches, shipped rollups), so reimport never duplicates them.
- **Protected custom settings are not reimported.** A managed package's protected settings are
  not writable from outside it. The kit exports them as a readable list, and the administrator
  re-enters them in the BarnCRM Settings console after reimport.
- **Uninstall and install stay manual, numbered steps** in the admin guide. They are a single
  command each, irreversible, and must be watched.
- **Every run is rehearsed on a full copy sandbox of the pilot org first**, and the kit's verify
  step compares a re-export with the original, record by record, through the Id map.

## Alternatives considered

- **Reuse the Core import engine.** Rejected for now: it would need a generic object loader
  that carries source Ids, which is C-33 and later. Revisit if C-33 ships before the listing.
- **Bulk API upsert with a temporary external Id field on every packaged object.** Handles
  volume better, but deploys and later deletes metadata in a production org for a one-time job.
- **`sf data import tree` plans.** Resolve references natively but cap each file at 200 records.
- **A hand-written mapping.** Drifts from the source as objects are added.

## Consequences

- Auto-numbered record names (for example a gift's number) are reissued on insert. Export orders
  rows by creation date so numbers stay close, but gaps left by deleted records close up. The
  admin guide says so.
- Field history, the import undo window, and created and modified stamps are lost, unless the
  org enables "Set Audit Fields upon Record Creation" for the run, which the kit then uses.
- Volume: one API call per 200 records, each counted against the org's daily API limit. A
  pilot of 100,000 packaged records needs about 1,000 calls; one many times larger needs the
  Bulk API alternative above. The rehearsal measures the real time.
- The kit is only as right as the rehearsal: an org run against a pilot copy must confirm
  uninstall behavior with records still on the packaged record types, the Giving locks on
  insert, and file links (see `docs/contributor-guide/migration-kit.md`).
