# ADR-0108: A second primary member is refused on a single save, and tolerated in a load

**Status:** Accepted (owner default, D-85)
**Date:** 2026-10-13
**Source:** Core quality pass on households and people (PEOPLE-25 follow-up); canonical
model R-M3, R-M6; builds on ADR-0044 (Primary Contact mirrors the primary member)

## Context

R-M3 says at most one current member of a household is primary. Until now nothing refused a
second one: the canonical model tolerated two primaries "which only a data load can
produce", mirrored the first in member order and changed no row. But a person can produce
two just as easily, by ticking Is Primary on a membership record by hand, and then the
household's Primary Contact silently stays on somebody else.

Refusing every second primary would make loads newly fail. A Data Loader file or an import
that brings in a household's members in one go can hold two primaries today, and refusing
those rows would lose people from the load, which is worse than the tolerance it replaces.

## Decision

1. **A single save by a person is refused.** A save of exactly one Household Member record
   that makes it a current primary member of a household that already has another current
   primary member is refused before the save, on Is Primary, with
   `Core_Households_ErrorSecondPrimary`, which points to Make primary. "Makes it" means a new
   current primary row, or an edit that ticks Is Primary, moves the row to another
   household, or brings an ended primary row back. An ended primary does not count.
2. **A load is tolerated and settled the existing way.** A save of more than one record, or
   one whose request arrives through the SOAP, REST or Bulk APIs, or runs in batch,
   queueable, future or scheduled Apex (read from `Request.getQuiddity()`), is not
   refused. With two current primaries, upkeep mirrors the first in R-H5 order and
   changes no row, as before.
3. **Package paths are unaffected.** Automatic creation, a move, a merge and Make primary
   each give a household at most one primary already (Make primary moves the flag in one
   save of several rows), so none of them is refused.
4. **System mode read** under ADR-0021: a primary the user cannot see still holds the flag.

## Alternatives considered

- **Refuse every second primary, in bulk too.** Rejected: loads that work today would lose
  rows.
- **Clear the older primary automatically.** Rejected: which person is primary is a decision
  somebody makes (R-H10), and silently moving it changes who letters go to.
- **A validation rule.** Rejected: it cannot see the other rows of the household.
- **Single row only, without the request check.** Rejected: a load's last chunk can be one
  row, and Data Loader or an integration saving one row at a time would newly fail.

## Consequences

- A person ticking Is Primary on a second member gets a clear refusal instead of a Primary
  Contact that does not follow.
- Two primaries can still arrive by a load; Make primary is how they are tidied.
- The org gate must confirm the request type a Lightning record page save reports (expected
  AURA or SYNCHRONOUS, neither a load) and that an API load of one row is let through.
