# ADR-NEXT: A module's first settings save takes its checkbox defaults from field metadata

**Status:** Accepted
**Date:** 2026-10-12
**Source:** plan Section 11.3, engineering follow-up 1; extends ADR-0035 to module settings
objects, under ADR-0059 (Core is neutral) and ADR-0021 (system mode writers)

## Context

ADR-0035 put the shipped value of every Core checkbox setting in Apex (`SHIPPED_DEFAULTS` in
`SettingsService`), because `getOrgDefaults()` on an org that has never saved returns every
checkbox as false. It left module settings objects open: "When a module needs a shipped
default, this decision is the shape to extend, not to copy."

Giving needed one. `Giving_Settings__c` ships three checkboxes on
(`Auto_Apply_Gifts_To_Installments__c`, `Automatic_Household_Soft_Credits__c`,
`Receipt_Print_Logo__c`). Their readers treat a missing record as on, but five Giving writers
(the acknowledgment run, the donor level stamp, the accounting period close, and the two
installment job run records) saved the record `getOrgDefaults()` returned. Whichever ran first,
usually a nightly job, stored all three as false and switched the features off, silently. The
console's own first save of a Giving key created a record with those checkboxes unset.

Core cannot name Giving's fields (ADR-0059), so a Core map of module fields is not available,
and the console save of a module key runs entirely in Core.

## Decision

Every first save of a settings object goes through `OrgSettingsSystemWriter`, which creates
the record from `SettingsService.firstSaveRecord(type)`:

- For `Nonprofit_Settings__c`, that is `SHIPPED_DEFAULTS`, unchanged (ADR-0035).
- For any other settings object, it is an empty record owned by the org plus the value of
  each custom checkbox as `type.newSObject(null, true)` loads it, which is the default the
  field metadata declares. No other field is taken from the declared defaults.

Writers save only the keys they own, on the record read under `FOR UPDATE`, never a whole
record. `scripts/ci/check-setting-defaults.py` fails a non-test class that hands a record taken
from `getOrgDefaults()` to DML.

## Alternatives considered

- **A `SHIPPED_DEFAULTS` map in each module, reached by Core through a `Type.forName`
  extension.** It is the literal reading of ADR-0035, but it adds an interface and a resolver
  for three values the field metadata already states, and a module that forgot to register
  its map would fail exactly as before.
- **A shipped value column on `Setting_Definition__mdt`.** Not every checkbox has a row, it
  adds a field to keep in step with the field metadata, and it needs a canonical model change
  for a value the platform already holds.
- **Read the describe default (`getDefaultValue`) at run time.** ADR-0035 rejected this for
  reads because it varies by field type and by formula defaults. Loading the defaults through
  `newSObject(null, true)` is the platform's own create path, and limiting it to checkboxes on
  a first save keeps the reads unchanged.
- **Fix only the five Giving writers.** The console's first save of a Giving key would still
  have created the record without the shipped values.

## Consequences

- A module that ships a checkbox on needs nothing in Core: its field metadata is the answer,
  and its readers must keep treating a missing record as the shipped value.
- Core keeps `SHIPPED_DEFAULTS`: it also serves Core's reads on an unsaved org, which this
  decision does not touch, and the gate already holds it to the field metadata.
- The Giving job run records now save in system mode through the same writer as Core's run
  records; they are package-owned keys on a protected setting, which ADR-0021 covers.
- The gate's check for raw settings saves is a pattern match. A save written another way can
  slip past it, and the first-save tests in `GivingSettingsFirstSaveTest` are the backstop.
