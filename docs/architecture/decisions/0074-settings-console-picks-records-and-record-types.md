# ADR-0074: The settings console picks records and record types instead of taking identifiers

**Status:** Accepted (owner approved the UI/UX review item, builder decision on the shape)
**Date:** 2026-10-12
**Source:** plan Section 2.3 ("no setting requires knowing an API name"), UI/UX review item 4;
extends ADR-0017 and ADR-0020

## Context

The BarnCRM Settings console renders each `Setting_Definition__mdt` row by its data type:
Checkbox, Text, Number, Picklist, DateTime or Component. Several shipped settings hold a value
Maria cannot know or should not have to type, so they were Text or Number rows:

- Giving's default fund and default appeal hold a record Id.
- Connect's Opportunity mirror record types hold record type developer names, comma separated.
- Giving's logo delivery route accepts exactly three phrases.
- Core's fiscal year start month is a number from 1 to 12.

The last two have a fixed set of answers and fit the existing Picklist type. The first two
depend on the org's own records and record types, which a shipped list cannot name.

## Decision

1. `Data_Type__c` gains two values, and `Setting_Definition__mdt` gains `Record_Object__c`,
   the object the row is about, named without a namespace prefix:
   - **Record**: the console renders `lightning-record-picker` for that object and stores the
     chosen record's Id. The Setup Assistant already picks the same records this way.
   - **RecordTypeList**: the console renders a checkbox group of the object's active record
     types, labelled as in Setup, read from describe (no query), and stores the chosen
     developer names separated by commas. None ticked is stored as empty.
2. `SettingsService`, which every write of a setting passes through, refuses a Record value
   whose Id is not of that object, and a RecordTypeList value naming a record type the object
   does not have, with the existing invalid value message. A direct call to the controller
   cannot store what the console would never offer.
3. A row whose `Record_Object__c` names an object this org does not have is left out of the
   console, as a row whose settings object is missing already is.
4. Fixed answer settings use the existing Picklist type: the fiscal year month by name, and
   the logo delivery route's three phrases.

## Alternatives considered

- **A per-setting custom component (Component rows).** Rejected: each would repeat the
  console's load, save and audit, which is the reason the console exists (ADR-0020 keeps
  components for whole pages).
- **An options provider class per module, found with `Type.forName`.** Not needed: describe
  answers record types for any object, and the record picker searches any object, so Core
  needs no knowledge of Giving or Connect beyond the object name the row carries.
- **A dual listbox for record types.** Rejected for a list that is usually two to five items;
  a checkbox group is simpler to read and works on a phone.

## Consequences

- Settings change history still records the stored value, so a Record row's change shows an
  Id. Acceptable for an audit trail; naming the record there is a later improvement.
- A record picked and later deleted leaves the setting pointing at nothing; the picker then
  shows empty and the module's own guard (for example "No default fund is set") still runs.
- The receipt logo and signature file Ids stay Text rows: they are uploaded in the Setup
  Assistant, and a picker over files is not built here.
