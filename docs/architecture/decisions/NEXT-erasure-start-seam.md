# ADR-NEXT: An optional erasure start seam, so Contact Point Sync copies addresses once

**Status:** Accepted (owner decision)
**Date:** 2026-11-09
**Source:** Batch C pre-batch review (plan 9.8). Owner decision, Brandon, 2026-11-09: "please
start the Contact Point Sync and Core reviewer fix to prevent double addresses updates now."
Amends ADR-0110 (erase a person anonymizes in place) and ADR-0176 (Contact Point Sync).

## Context

Erasing a person (ADR-0110, canonical model R-ER1 to R-ER10) deletes their addresses and then
ends their household memberships before it clears the person. With Contact Point Sync installed
(ADR-0176), each of those changes synced the person's address copies on its own, so one erasure
read and wrote the same copies twice; on Nonprofit Cloud that is several queries a sync.

`PersonErasureExtension.erase` is asked only after Core has changed everything, so a module had
no way to know an erasure was under way while it was happening. Changing that interface would
break every module that implements it (Giving, Volunteers, Programs), and Core may not bypass a
module's automations by name.

## Decision

1. Core adds a second, optional interface, `PersonErasureStartExtension`, with
   `beforeErase(Id personId)` and `afterErase(Id personId)`. `PersonErasureExtension` is
   unchanged, so every existing implementer compiles untouched.
2. `PersonErasure` asks each registered extension that also implements the new interface:
   `beforeErase` after every check has passed (permission, name, access, blocked fields) and
   before Core changes anything; `afterErase` in the run's `finally`, whether the run succeeded or
   failed. A refused erasure never reaches `beforeErase`. The preview runs the same path inside
   its rolled back savepoint.
3. Contact Point Sync registers `ContactPointErasureExtension` last in
   `PersonErasureExtensions.EXTENSION_CLASSES`. `beforeErase` holds that one person's address
   copies (by the id erased and, for a person account, the contact behind it). While held, its
   address and membership handlers leave that person out and note that a sync was due; everyone
   else in the household is synced as before. Its `erase` ends the hold and, only when a handler
   noted a sync was due, makes the person's address copies once from the final state. Its
   `afterErase` ends the hold without syncing, so a failed run never leaves syncing off.
4. The end state is unchanged: the copies left after an erasure are the ones the two syncs left.
   Email and phone copies still follow the person's own save. A switched off or paused handler
   notes nothing, so it still copies nothing.

## Alternatives considered

- **A new method on `PersonErasureExtension`.** Rejected: every implementer would have to change
  in the same release.
- **Core bypasses the Contact Point Sync automations during an erasure.** Rejected: Core may not
  name a module's automations, and the copies would then be left to the module anyway.
- **Use `fieldsToKeep` as the start signal.** Rejected: it is a question, asked without the
  person's id, and nothing would end the hold when a run is refused.

## Consequences

- New Core interface `PersonErasureStartExtension`; new class `ContactPointErasureExtension` in
  Contact Point Sync.
- An erasure with Contact Point Sync makes one address sync for the person instead of two.
- Nothing a user sees changes, so the guides are unchanged.
