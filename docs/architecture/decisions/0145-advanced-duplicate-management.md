# ADR-0145: Advanced duplicate management: fuzzy household-aware pairing, merge rules, auto-merge with undo

**Status:** Accepted (owner decision, 2026-10-30)
**Date:** 2026-10-30
**Source:** plan D-154 (Brandon, 2026-10-30), feature C-51, plan Section 6.1.1 item 4. Builds on
ADR-0050 `0050-duplicates-use-the-orgs-own-duplicate-rules.md`, ADR-0133
`0133-related-record-matching.md` and ADR-0139 `0139-duplicate-matching-tool.md`. Amends
canonical model R-DP1 (BarnCRM now compares names itself) and R-DP4 (an administrator may merge
exact matches in bulk).

## Context

The Duplicate Matching tool proposes pairs the org's duplicate rules and the match sources find,
and merges households one pair at a time. An administrator with hundreds of obvious duplicates
(the same name and email, imported twice) has to open each one. The platform's matching rules
compare names only by their own fuzzy methods, cannot weigh household membership, and never
decide which value wins: the platform's merge keeps the survivor's values unless a person picks
each field. The owner approved three additions (D-154): merge rules for which value wins,
household-aware pairing, and auto-merge of exact matches with undo.

## Decision

1. **One shared fuzzy string scorer, `FuzzyMatch`.** `normalize` lowercases, turns punctuation
   into spaces and collapses spacing; `score(a, b)` answers 0 to 1: 1 when the normalized values
   are equal (or equal once spaces are removed, so "FirstName" and "First Name" are the same),
   otherwise Jaro-Winkler on the normalized values. `bestMatch(value, candidates, threshold)`
   picks the closest candidate at or above a threshold. It reads no data, so the importer's
   header matching (C-49e) reuses it unchanged.
2. **Household-aware fuzzy pairing in the scan.** Each people chunk of the duplicate scan also
   asks `FuzzyPairing`: people sharing a last name or an email with someone in the chunk are
   scored on their full names. A pair at or above the Fuzzy Name Match setting (default 90
   percent) is proposed when the two share an email or a phone number (digits), or are in
   different households and share a mailing postal code. In one household, where similar names
   are usually family (Daniel and Danielle), two people with nothing else in common are proposed
   only when their names are the same once normalized. Two people whose birthdates are both
   filled in and differ are never paired. The pair joins the review list
   like any other, with a reason ("Similar names (94%), same household"), and still names an
   active Contact rule as R-DP6 pairs do.
3. **Merge rules decide which value wins.** `Merge_Rule__mdt` holds one row per person field:
   Keep master, Not blank, Most recent, Oldest record or Most complete. A field with no active
   row follows the Merge Rule For Other Fields setting (default Not blank: the survivor keeps
   its values and fills its blanks). A rule on a compound address (`MailingAddress`,
   `OtherAddress`) moves its parts together. Rows are saved through the custom metadata manager
   (ADR-0085) and listed on the Custom metadata page.
4. **Auto-merge of exact matches, previewed first.** On the Duplicate Matching tab's Auto-Merge
   area an administrator previews the open people suggestions in the review list that meet the
   Exact Match For Auto-Merge setting (default Name and email; also Name and phone, Name, email
   and phone, Name and birthdate), with the survivor and the values that will change, then runs
   the merge as a batch in user mode. The survivor is the person whose household has more
   members (they stay with their family), else the older record. Households are never
   auto-merged; the household merge stays one pair at a time.
5. **Every auto-merge is journaled and can be undone.** One `Merge_Journal__c` row per merge
   records the run, both identifiers, the survivor's values the rules changed and the related
   records the merge moved. Undo, for a whole run, undeletes the merged-away person from the
   Recycle Bin (never a recreated copy), puts back each value still as the merge left it and
   moves each related record still on the survivor back. Anything it cannot restore (the person
   is no longer in the Recycle Bin, a value changed since, a related record deleted or locked)
   is written on the journal row and shown on the tab.

## Alternatives considered

- **Merge rules as one settings text field.** Rejected: a 255 character setting holds a dozen
  rules at most, and the custom metadata manager already validates and saves typed rows.
- **Auto-merge straight from a fresh org-wide search.** Rejected: it would be a second matcher
  beside the review list; building on the suggestions keeps one list a person can see and
  dismiss from.
- **Undo by recreating the merged record from the journal.** Rejected by the owner: a copy has a
  new identifier and loses history; the Recycle Bin restores the real record.
- **Auto-merge households too.** Rejected for now: the household merge needs a person's field
  choices and moves memberships, gifts and addresses; a wrong household merge costs far more.

## Consequences

- R-DP1 now has two additions (match sources and name scoring) and R-DP4 allows a bulk merge,
  but only of exact matches, only after a preview, and only with undo.
- Undo is bounded by the Recycle Bin (15 days, or until emptied); the tab says so.
- Related records whose link field cannot be changed (a master-detail link that does not allow
  reparenting) are not journaled; undo names their objects.
- Three settings join the Duplicate Matching section; one custom metadata type and one object
  are added.
