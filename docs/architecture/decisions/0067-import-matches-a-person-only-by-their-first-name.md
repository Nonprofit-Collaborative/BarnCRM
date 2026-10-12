# ADR-0067: An import matches a person with a first name only by that first name

**Status:** Accepted
**Date:** 2026-10-12
**Source:** product owner decision (Brandon), plan Section 11.2 item 17, option (a); amends
canonical model R-IB12

## Context

Under the Email and Name + Postal matching rules, an import row's person was found first by
the rule's key narrowed to their first name, and failing that by the shared key alone when
exactly one record held it. With only John Smith at a postal code, a "Jane Smith" row at the
same code therefore matched John, and the update renamed him Jane. The dry run showed it only
as an Updated row. The same happened under the Email rule for a shared email, and within one
file when an earlier row created John. Where several records held the key (a couple), the row
was already created rather than guessed (R-IB12).

## Decision

A row's person with a first name is matched only to a record (in the org, created by an
earlier chunk, or created by an earlier row of the chunk) whose key and first name both agree.
Any other holder of the key, whether it has another first name or none, is somebody else: the
person is created, and nobody is renamed. The shared key alone finds a person only when the
row gives no first name (the earliest holder), and a blank incoming value never clears a
stored one, so that row renames nobody either.

First names are compared after trimming, collapsing runs of inner spaces and lower casing.
Nothing else is normalized: accents, initials ("J." for John) and short forms ("Bob" for
Robert) are different names. The External ID rule is unchanged. Only import matching changes:
the duplicate scan (ADR-0050) proposes pairs and never renames, and the inbound gift API
matches a donor by email only to attach a gift, so neither shares the flaw.

## Alternatives considered

- **Keep the old rule (option b).** A file with one differently spelled first name silently
  renames a real person, which is worse than a duplicate: undo restores it, but only if
  somebody notices.
- **Short-form matching (option c, "Bob" is "Robert").** Needs a nickname table per language,
  still guesses, and was declined by the owner.
- **Match a holder with a blank first name.** Fills the blank, but a second row in the same
  chunk with another first name would then take the same record and rename it again; refusing
  keeps one simple rule.
- **Match initials ("J." for John).** "J." is also Jane; it is a guess of the same kind.

## Consequences

- A file spelling first names differently from the org creates people instead of renaming
  them. The dry run's "would create" count shows it before the commit, and the duplicate scan
  proposes the pairs afterwards (R-DP3). The admin guide (`importing.md`,
  `migrating-from-npsp.md`) says so.
- A record with a blank first name is not found by a row that gives one; such data is better
  fixed before an import, or merged after.
- The dry run and the commit still decide alike: both use `findPerson` and `keyToShare`, and
  the digests a dry run writes are unchanged in shape.
- Undo is unaffected: a person the import created is removed as before, and fewer existing
  people have their first name journaled and restored.
