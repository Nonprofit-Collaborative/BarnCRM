# Migration kit (unlocked to managed)

The kit in `scripts/migration/` moves a production pilot from the unlocked packages to the
managed packages (C-31, ADR-0088 `0088-unlocked-to-managed-migration-kit.md`). The
administrator's procedure is [Moving a pilot to the managed packages](../admin-guide/moving-to-managed-packages.md);
this page is how the kit works and how to keep it right as the packages grow.

Nothing in the kit is packaged, and it never creates a package version.

## Files

| File | What it is |
|---|---|
| `scripts/migration/build_mapping.py` | Reads `packages/*/main/default/objects` and writes the mapping (JSON) |
| `scripts/migration/overrides.json` | The only hand-kept part: objects skipped, upsert keys, related standard records |
| `scripts/migration/migrate.py` | `check`, `export`, `reimport`, `verify` against an org, through `sf` |
| `scripts/migration/tests/` | Unit tests; no org needed (`python3 -m unittest discover scripts/migration/tests`) |

## The mapping

`build_mapping.py --packages core,giving,connect --output mapping.json` collects, for each
listed package:

- every custom object, with its fields, except formula fields, auto-number fields, and objects
  that hold no records (custom metadata types, platform events);
- the package's fields on Account and Contact, and their record types;
- a field added to another package's object (Connect's fields on `Gift__c` and `Appeal__c`)
  joins that object's entry.

Each object records its kind (`custom`, `standard`, or `setting` for a hierarchy custom
setting), its fields, its lookups and their targets, whether its Name is typed or
auto-numbered, and its upsert key if `overrides.json` names one. Objects are ordered so that a
master-detail parent and, where there is no cycle, a lookup parent come first. Names are held
without a namespace; `migrate.py --namespace` prefixes every name that ends in `__c` at run
time, which is safe because the mapping holds only packaged custom names.

## overrides.json

- `skip`: objects not copied, each with the reason printed by `build_mapping.py`. Today the
  import staging rows and the import undo journal (meaningless once every Id changes).
- `upsert_keys`: objects the managed install fills itself, with the unique field to match
  on, so reimport updates the shipped row instead of adding a second: automation switches and
  rollup definitions (both created by the post-install scripts), and the receipt number
  sequence (its counter must carry over exactly).
- `related`: standard records hung on packaged records that uninstall deletes with them: tasks
  and events (by `WhatId`) and file links (by `LinkedEntityId`).

A new object or field needs no change here. A new object that a post-install script seeds (a
`*PostInstall` class) needs an `upsert_keys` row naming a unique external Id field, or reimport
adds a second copy of each seeded record. Nothing detects a missing row automatically: a review
of any post-install change checks it. `build_mapping.py` refuses a key that is not a unique
external Id.

## How reimport works

1. **Standard records first.** Account and Contact keep their Ids through an uninstall, so
   their packaged fields are updated in place. Record types are matched by developer name.
2. **Custom records, in mapping order, through the sObject Collections API**, 200 a call,
   `allOrNone` false. Results come back in request order, so result *n* is the new Id of
   source row *n*. Each pair is appended to `id-map.csv` in the export folder as it arrives.
3. **Lookups and Id-holding text.** A lookup whose target is already loaded is translated on
   the way in. One whose target is not yet loaded (a cycle, or a self lookup) is left blank and
   filled in the second pass. Any Text or Long Text value that equals a source Id (15 or 18
   characters) of a copied record is translated the same way: ADR-0014 stores Giving record Ids
   as text in Core.
4. **Second pass.** One update per record that had anything deferred.
5. **Related records**: tasks and events are inserted with their `WhatId` translated; file
   links are recreated when the file still exists, and listed in `refused.csv` when it does
   not.

A rerun reads `id-map.csv` and skips every source row already mapped, so a stopped run is
resumed by running it again.

Protected hierarchy custom settings are exported to `settings.csv` (organization level
values only) when the source org lets the API read them, and never reimported: a managed
package's protected setting is not writable from outside the package.

## verify

`verify` exports the target org with the same mapping, translates every Id through
`id-map.csv`, and compares field by field with the original export. Differences expected from
the platform (auto-number names, audit fields without `--keep-audit-fields`, formula values) are
not compared, because they are not in the mapping.

## What an org rehearsal must confirm

The kit's unit tests run against a fake `sf`. The first rehearsal, on a full copy sandbox of a
real pilot, must confirm:

- that uninstalling Core succeeds while Accounts still carry the Household and Organization
  record types, and what those Accounts are left with;
- whether a protected custom setting of an unlocked package can be read through the API (if
  not, `settings.csv` is empty and the administrator's screenshots are the record);
- that Giving's receipt lock and posting lock accept inserted receipted and posted gifts for a
  user holding both override permissions, and that the receipt number sequence carries on
  from the migrated counter;
- that files linked to packaged records survive the uninstall (the kit relinks them if so);
- that the pause stops household creation and naming during reimport, so Accounts are not
  given a second household;
- the time and API calls per 10,000 records.

Record the results in the iteration's release notes and correct this page and the admin guide
page.
