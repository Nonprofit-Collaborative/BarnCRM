# ADR-NEXT: What's new is read from packaged release notes and remembered per person

**Status:** Accepted (builder decision)
**Date:** 2026-10-12
**Source:** plan Section 5, feature C-27 "In-app What's new after upgrade"; builds on ADR-0006
(settings storage), ADR-0017 (each package owns its settings), ADR-0021 (system mode writes)
and ADR-0059 (Core is neutral)

## Context

C-27 asks for a card on the BarnCRM home page that tells each person what changed after an
upgrade. That needs two stores: the notes themselves, which ship with the packages, and, for
each person, which release they have already seen.

The notes have to arrive with the upgrade, need no external call (plan Section 4.13), and come
from more than one package: Giving or Connect may describe their own changes, while Core may not
name them (ADR-0059). The per-person record has to be readable and writable by any BarnCRM user,
including one holding only the Read Only role, and it must never change what anybody else sees.

## Decision

1. **The notes are a Core custom metadata type, `Release_Note__mdt`, one record per note.**
   Each record carries a release version, a headline, optional details (one point per line), an
   optional sort order and an optional module name. Any package that depends on Core may ship
   records of the type; Core reads all of them and never names one.
2. **One version numbering for every package.** `Version__c` is the product release, such as
   0.12, not a package version number, because a release ships its packages together.
3. **Versions compare as numbers, part by part.** 0.12 is newer than 0.9, a missing part counts
   as zero, and a version that is not dot separated whole numbers is ignored rather than failing
   the card (canonical model R-WN3).
4. **The last version a person dismissed is stored in a new protected hierarchy custom setting,
   `Whats_New_Seen__c`, with user-level records only.** It is written by `WhatsNewSeenWriter` in
   system mode, for the running user only, with a value Core computed from the shipped notes, so
   it meets the conditions of ADR-0021.
5. **A person who has never dismissed sees only the current release's notes**, not the whole
   history; after that, every release newer than the one they dismissed.

## Alternatives considered

- **A static resource holding the notes as a file.** Not queryable, and one file per package
  would have to be found by name, which Core may not do for a module it cannot depend on.
  Custom metadata is queried in one statement across every installed package.
- **A field on `BarnCRM_Settings__c`.** A user-level record of that setting would shadow the
  organization's values for that person: every `getInstance()` read of a household or import
  setting would return the person's mostly empty record instead of the org default.
- **A custom object, one record per person.** Needs object and field permissions in every
  permission set, sharing, a tab-less object to maintain and a delete story for departed users,
  to hold one short value per person. A hierarchy custom setting does it with no permission
  grants and no query.
- **Mark seen automatically on first view.** A person who opens the page and looks away would
  never see the notes; an explicit Dismiss is clearer.

## Consequences

- **Note text is not translated in this version.** The notes are plain text fields on the
  records, not custom labels, so only the card's heading, introduction, button and version line
  can be translated; the notes are English only. Revisit when the first non-English cohort org
  asks; the likely route is a label name in a note field.
- A release that ships no Release Note record shows nothing new, which is the correct result.
- Writing notes is part of each release's definition of done: whoever writes the release note
  line (plan Section 7.4) also ships the matching record.
- A person dismissing in two tabs at the same moment can hit a duplicate user-level record; the
  second dismiss reports an error and the first has already stored the version. Accepted as
  harmless.
