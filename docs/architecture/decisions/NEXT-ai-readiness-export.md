# ADR-NEXT: AI-Readiness Export: a browser-built pack, no AI calls, sensitive fields left out by default

**Status:** Proposed
**Date:** 2026-10-31
**Source:** plan Section 6.1 item 7 and release 0.13 item AIR-01 (decision D-154). Reuses C-52
(Data Dictionary), Field Utilization, the Data Quality checks and Find's paged export (canonical
model R-SQ3); admin guide `ai-readiness-export.md`.

## Context

Plan principle 5 (Section 1.3) makes clean, governed data the AI strategy, and the working
agreements forbid calling a paid AI API. Nonprofits still want to ask an AI tool of their
choice about their data, and the tool needs the data model explained (types, picklist values,
lookups, completeness) as much as the records. Records about people carry privacy risk, and
BarnCRM cannot know which AI tool the organization uses or what it keeps. AIR-01 asks for
documented export schemas and a canonical-model JSON export.

## Decision

1. **A section of Org Optimizer, not a new tool or service.** The AI-Readiness Export section
   is shown to holders of Manage BarnCRM Settings. It reads through existing controllers only:
   `DataDictionaryController.describeObject`, Field Utilization's plan and counts (through the
   shared `dictionaryKit` module, which the Data Dictionary now uses too), `DataHygieneController
   .getChecks` and `FindController.exportPage`. Each keeps its own permission check, user mode
   and limits. No new Apex, object, field or setting.
2. **No outside call.** The pack is built in the browser and downloaded as one zip
   (`xlsxWriter.writeZip`, the workbook's own zip writer). Nothing is sent to an AI service or
   saved in Salesforce.
3. **The pack.** `README.md` (plain language, from custom labels), `schema.json` (the
   canonical-model JSON, format `barncrm-ai-readiness-export` version 1, documented in the admin
   guide), `data-dictionary.csv` (the C-52 layout) and, when asked, `data/<Object>.csv` headed
   by API names with Id first, read through Find's export in queries of at most 20 fields joined
   by Id, each object stopping at the Find export row limit.
4. **Sensitive fields left out by default.** A framework-free module (`aiReadinessPack`, plan
   Section 9.9) flags fields by type (email, phone, encrypted, long text) and API name (person
   names, birth date, address parts, identity and financial numbers, private details). Each
   flagged field starts at Leave Out; the admin may choose Mask or Keep. A masked value is
   `masked-` and ten hexadecimal characters of an HMAC-SHA-256 under a key generated for the
   pack and never exported, so equal values match within a pack and cannot be reversed or
   matched across packs.

## Alternatives considered

- **Call an AI service for the admin.** Conflicts with the no paid AI API rule and puts data in
  a service the organization did not choose.
- **Build the pack on the server (export to Files).** Find's server export already exists for
  one query, but a multi-file pack would need a new job, a zip in Apex heap and stored files of
  personal data. The browser path reuses Find's paged export and stores nothing.
- **A plain hash for masking.** A salt-free hash of a phone number or name is reversible by
  guessing; a per-pack HMAC key is not.
- **Flag nothing and let the admin choose every field.** Most organizations would export
  everything; a default of Leave Out for likely personal fields is the safer start.

## Consequences

- The flags are a heuristic. The admin guide says so and asks the admin to read the list; a
  custom field with an unrevealing name is not flagged.
- Large objects are bounded by the Find export row limit and browser memory, as Find's own
  browser export is. Organizations with more need Find's export to Files or a data tool.
- `schema.json` is a contract for outside tools: its `formatVersion` changes only when a key is
  removed or changes meaning, and the admin guide documents every key.
