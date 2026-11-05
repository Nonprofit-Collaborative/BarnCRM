# ADR-0164: Help and guidance prose in packaged JSON catalogs, not custom labels

**Status:** Proposed (owner request, Brandon, 2026-11-04; awaits owner confirmation)
**Date:** 2026-11-04
**Source:** owner request 2026-11-04 ("change the long help and guidance paragraphs to not use
labels and for the JSON to only be available in English for now ... the unmanaged package needs
to work for orgs for quite a while"); plan Section 4.1 (unlocked now, managed at listing),
Section 4.14 (labels, translation-ready), Section 9.9 (portability), D-168 (label budget).
Amends Section 4.14 "All labels in Custom Labels from day one" for help prose only.

## Context

Salesforce allows 5,000 custom labels per org. Labels from an installed managed package do not
count toward that limit, but BarnCRM ships as source and unlocked or unmanaged installs for a
long time before a managed listing, and every label of such an install uses the org's own room.
On 2026-11-04 the packages held 4,501 labels (Core 2,600; Rollup Builder 407; Giving 718;
Mirror 191; Programs 214; Volunteers 155; Logic Models 109; Funders 107), against a CI cap of
4,500. An org that already uses a couple of thousand labels could not install the suite.

Classifying every label (analysis kept with the build notes): 2,395 are UI strings (titles,
buttons, column headers, field-like labels, status words), 1,597 are messages (errors, toasts,
validation, log lines, run results, notices), 112 are content BarnCRM writes into records,
emails, letters, receipts and files, 16 are help named by metadata, and 381 are help and
guidance prose (intros, descriptions, explanations, empty-state explanations, setup notes,
tooltips). Help prose is the text a translator and a contributor edit most, the longest, and
the only kind whose wording never needs to be a platform label: nothing in Setup shows it.

## Decision

1. **Help and guidance prose lives in one JSON static resource per package.**
   `BarnHelp_Core`, `BarnHelp_Rollups`, `BarnHelp_Giving`, `BarnHelp_Volunteers`,
   `BarnHelp_Programs`, `BarnHelp_LogicModels`, `BarnHelp_Funders`, `BarnHelp_Mirror`, each
   `packages/<dir>/main/default/staticresources/BarnHelp_<Package>.json`, content type
   `application/json`, shaped `{ "languages": ["en"], "texts": { "<key>": "<text>" } }`. A
   package with no help prose ships no catalog. Keys are the API names the texts had as custom
   labels (`Core_OrgOptimizer_Intro`), so a reference still says what it is and where it shows.
   Text moved from labels is moved word for word.
2. **English only for now, translation-ready.** A translation is a second resource,
   `BarnHelp_<Package>_<language>` (`BarnHelp_Giving_fr`, `BarnHelp_Giving_fr_CA`), listed in the
   English file's `languages` and holding only the keys it translates. Readers try the user's
   regional language, then the language, then English; a key missing everywhere reads as empty
   text. No translation ships yet. Listing languages in the English file means a user whose
   language has no translation never costs a request.
3. **A framework-free loader in Core, a thin Salesforce wrapper, one fetch per package per
   page.** `c/barnHelpCatalog` (no `lightning/*` or `@salesforce/*` import; plan 9.9) holds the
   store: a promise per package shared by every caller, language fallback, `{0}` formatting,
   and synchronous `text()` once loaded. `c/barnHelpText` supplies the resource URL (Core's own
   `@salesforce/resourceUrl/BarnHelp_Core`, with the name swapped for another package, keeping
   any namespace prefix and so hard-coding none), the user's language and `fetch`, and exports
   `helpText(package, key, ...args)`, `loadHelp(packages)` and `isHelpLoaded(packages)`.
   A component that shows help sets `helpReady = isHelpLoaded(...)`, calls `loadHelp(...)` in
   `connectedCallback` when it is not, and wraps its template in `<template lwc:if={helpReady}>`,
   so its first render already has the text and later components on the page render at once.
   Help read while the page renders comes from getters, never from a class field or module
   constant, which would be read before the catalog arrives.
4. **`c-barn-help` reads a catalog by key.** `<c-barn-help help-package="Core"
   help-key="...">` fills the popover from the catalog; `content` still takes any text. The
   popover is the same `lightning-helptext`, so its screen reader name and behavior do not
   change. Inline help moved from labels keeps its element and any `aria-describedby` link to it:
   only where the words come from changes.
5. **Apex reads the same files through `BarnHelp`.** `BarnHelp.text(package, key)` and
   `BarnHelp.text(package, key, args)` (Core, `@NamespaceAccessible` for modules) read a package's
   resources in one query per transaction, cached, filtered by this package's namespace
   (`NamespaceUtil.prefix()`, empty today), in system mode: a static resource is packaged text
   every user is meant to read, and reading `StaticResource` in user mode needs a setup
   permission most users lack. The user's language follows the same fallback. Apex uses it only
   where Apex returns help to the UI (Setup Assistant step descriptions, feature descriptions,
   job and segment descriptions, Custom Metadata Manager help, add-on descriptions).
6. **Missing help never breaks a page.** A missing key, resource, translation or a failed
   fetch reads as empty text; the browser warns once per missing key in the console, and Apex
   returns an empty string. `scripts/ci/check-help-text.py` makes a missing key a build failure
   instead of a blank.
7. **What stays a custom label.** UI strings (every title, button, tab, column header, field
   label, short status word), every message (errors, toasts, validation, confirmations, log
   lines, run results, notices, and sentences with `{0}` placeholders about the current state),
   content BarnCRM writes into records, emails, letters, receipts and files, and any text named
   where JSON cannot reach: FlexiPage and Flow metadata, custom metadata records that name a label
   (`Access_Add_On__mdt.Description_Label__c`, Setting Definitions), Aura and Visualforce.
8. **CI keeps it that way.** `scripts/ci/check-help-text.py` fails when a key a call names
   (`helpText('<Package>', '<key>')`, `BarnHelp.text('<Package>', '<key>')`, `help-key`) is not
   in that package's catalog, when a call names its key with anything but a literal, when code
   reads another module's catalog, when a catalog key is used nowhere or is also a label, when a
   translation is not listed or holds a key English lacks, and on any em or en dash.
   `scripts/ci/check-label-budget.py` lowers its cap to the new count plus a small margin and
   fails on a new label that reads as help prose (a sentence whose name ends in a help word such
   as `Intro`, `Help`, `Description`, `Hint`, `Note`, `Empty`, `Why`, `What`, `Steps` or `Text`),
   pointing to the catalog.

## Alternatives Considered

- **Shorten long help to one sentence plus a Learn More link (D-168 fallback).** Rejected as the
  main lever: it loses guidance on the screen, and still costs a label per sentence.
- **Move only prose over 120 or 200 characters.** Rejected: it frees 140 or 22 labels, and leaves
  two places for the same kind of text.
- **Ship the catalogs as JavaScript modules** (synchronous import, no gating). Rejected: Apex
  cannot read them, a module per language would be loaded whatever the user's language, and the
  static resource is the plain JSON a WordPress port can read as is.
- **A zipped resource per package with `en.json` inside.** Rejected: Apex would need to unzip it
  to read help, and a single JSON file per language is as easy to translate.
- **Move messages too.** Not decided here: messages are 1,597 labels and the bigger lever (see
  Consequences), but the owner asked to keep them as labels. This design reads any key, so it
  would serve them unchanged if that is decided.

## Consequences

- Moving the 381 help prose labels leaves 4,120 labels for the full suite, 2,354 for Core alone
  (the Standard Edition) and 2,734 for Core with Rollup Builder. Core alone, or with Rollup
  Builder, installs beside an org's own 2,000 labels; the full suite still needs the org to use
  fewer than about 880. The remaining room is in messages (1,597); moving all sentences would
  leave 2,411 for the full suite.
- The CI label cap drops from 4,500 to 4,150.
- A component with help renders once its package's catalog is in (one request per package per
  page, then the browser cache); with the catalog missing it renders without the help.
- Translators get help prose as JSON beside labels as Translation Workbench strings, both keyed
  by the same names.
- Jest maps `c/barnHelpText` to a stand-in that reads a key as `c.<key>`, as the label stub does,
  so tests keep their expectations; a test that needs real wording sets it.
- Section 4.14's "all labels in Custom Labels" now reads "all UI strings and messages in Custom
  Labels; help prose in the packaged help catalogs" (plan entry for the owner).
