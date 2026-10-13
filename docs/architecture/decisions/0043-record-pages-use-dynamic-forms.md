# ADR-0043: Record pages use Dynamic Forms, with one fallback layout per object and no layout assignments

**Status:** Accepted; the related-lists rule is amended for Giving's lists on the donor record
pages by ADR-0064 (Giving ships the donor record pages), and for record pages of objects the
shipping package owns by ADR-NEXT (every packaged record page places its own actions)
**Date:** 2026-09-23
**Source:** product owner decision (Brandon), plan Section 4 and feature C-08

## Context

The packaged record pages (Account, Contact, Gift, Commitment) showed their fields through
the record detail component, which renders whichever page layout the viewing user's profile
is assigned. A package cannot rely on that: it ships no profiles, an installing org owns its
profiles and their layout assignments, and on Account and Contact the org's own layout is
the one assigned. So the fields a packaged page showed were the org's, not ours, and a
household and an organization needed two layouts to differ at all.

## Decision

- **Record pages show fields with Dynamic Forms.** Each packaged record page places its
  fields in `flexipage:fieldSection` components instead of the record detail component.
  Where records of one object differ, a section or field carries a visibility rule: on
  `Account_Record_Page` the Name and Greetings section shows only for
  `{!Record.RecordType.DeveloperName}` Household and Website only for Organization; on
  `Gift_Record_Page` the In-kind Gift section shows only for Type In-kind.
- **Actions the package owns are placed on the page.** `Account_Record_Page` uses Dynamic
  Actions (Edit, Merge or split for households, Delete), because no packaged Account layout
  is assigned to anyone.
- **One minimal fallback page layout per object.** It holds the fields a user enters, which
  the New and Edit windows still read, plus the related lists and actions the record page
  takes from the layout. Fields the package maintains are on the record page only. Account
  has one layout for both record types.
- **Related lists stay in the layout**, read by the related list container, rather than
  one Dynamic Related List component per list: one component instead of many, and an
  org's own layout keeps working on Account and Contact.
- **No profile layout assignments are packaged.** No Profile metadata ships.
- Record pages are activated in the Lightning app (`actionOverrides`, Large and Small), not
  per profile.

## Alternatives considered

- **Keep the record detail component and ship profile layout assignments.** Rejected:
  profiles belong to the installing org, and a package cannot assign layouts to profiles it
  does not know.
- **Dynamic Related List components.** Rejected for now: about 20 lines of metadata per
  list against one container, for no behavior the container lacks.

## Consequences

- A field added to an object is placed on its record page in the Lightning App Builder or
  the flexipage source, not only on the layout. Review checks both.
- An org that assigns its own record page, or opens a record outside the packaged apps, sees
  its assigned layout; the fallback keeps that usable.
- Test orgs need a destructive deploy of the layouts removed here.
