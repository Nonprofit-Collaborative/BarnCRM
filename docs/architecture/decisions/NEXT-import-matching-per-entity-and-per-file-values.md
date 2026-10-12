# ADR-NEXT: Import matching per entity, a rule for several matches, and values for every row of a file

**Status:** Accepted
**Date:** 2026-10-12
**Source:** plan Section 4.9 ("Matching", "Import flow") and feature C-32; the default for
several matches is the owner decision of 2026-09-23 recorded there. Builder decisions: how
"most recently changed" is read, which fields can be chosen, and the order in which a row's
own value, a value for the file and a template default apply. Amends canonical model R-IT2
and R-IB12 (Sections 15 to 17).

## Context

Before C-32 a template held one matching rule for people (Email exact, Name plus postal
code, or External ID on whichever field the org marked first as an external identifier). An
organization was always matched on its exact name. Where several records held the key a row
was looked for by, the earliest created was taken, so a file could be loaded into the wrong
one of two duplicates without anybody seeing it. A template could hold default values, but
there was no way to say "every row of this file is from the Gala 2026 appeal" without editing
the file or the template.

## Decision

1. **Matching per entity.** A template holds a rule for people (Email exact, Name plus postal
   code, External ID) and one for organizations (Name exact, External ID). Under External ID
   the template names the field: one the administrator picks from the object's fields that
   are marked External ID or Unique, hold text or an email, and that the user may read (a
   contact field, or an account field where people are person accounts; an account field for
   organizations). The choice is checked against describe when it is saved and again when a
   row is matched; a field no longer eligible matches nobody and the run log says so. No field
   name is ever taken from the browser into a query without that check. An empty person field
   keeps the old behaviour (the first external identifier the user may read), so templates
   saved before C-32 work unchanged. An organization under External ID is looked for only
   among organization accounts, so a household or a person account holding the same value is
   never taken for it.
2. **Several matches.** Each template says what happens when the key a row is looked for by
   finds more than one record: **Reject the row** (the default and the value an empty field
   means) or **Use the most recently changed record**. It applies to people (the key narrowed
   to the row's first name when it gives one, the shared key when it does not, R-IB12) and to
   organizations. "Most recently changed" is the record's Last Modified Date as the chunk reads
   it; on a tie the later created wins, so one read always resolves the same way. In a dry
   run, a person an earlier chunk would create counts as a holder, as the commit will find
   them. Every row whose key found several records has its Several Matches box ticked,
   rejected or not, so the dry run lists every such row either way, and the run log says so
   once.
3. **Values for every row of a file.** The wizard can give the file values that apply to each
   of its rows. They are kept on the batch, not the template, so the dry run and the commit of
   that file use the same values and the next file starts without them. A row's own value
   wins, then the file's value, then the template's default: a file value fills a blank cell,
   as a template default does and as NPSP's batch defaults do. A file value cannot name a
   person, give a person's email, or set the field people are matched on, because every row
   would then be the same person. It can name an organization: every row of a staff list
   from one employer is meant to be that organization.

## Alternatives considered

- **Keep "earliest created wins".** Silent and stable, but it loads a file into whichever of
  two duplicates is older, which nobody chose; the owner chose rejection as the default.
- **"Most recently changed" as the default.** A wrong merge is harder to notice than a
  rejected row (owner decision 2026-09-23).
- **Freeze the chosen record in the dry run for the commit to reuse.** It would need the
  chosen record per row carried between passes; under Reject, which is the default, there is
  nothing to carry, and under the other choice the rows are listed for review anyway.
- **A file value overrides the row's own value.** Would make an export that already carries
  an appeal per row impossible to load with a fallback; a fill-the-blank rule covers "every row
  is Gala 2026" when the column is absent, which is the case the plan names.
- **Any field as a matching field.** A field that is neither External ID nor Unique can be
  held by many records by design, and matching on it is the several-matches case on every row.

## Consequences

- A row with no first name whose surname and postal code (or email) is held by a couple is
  now rejected by default rather than given the older partner. The admin guide says how to
  choose the other rule, and the duplicate scan (R-DP3) is where the duplicates are fixed.
- In a commit, an earlier chunk's update can change which record is the most recently
  changed, so under "Use the most recently changed" the commit may choose a different one of
  the several records than the dry run read. The row is ticked in both, and its counts (matched
  or updated) can differ. Under Reject the dry run and the commit agree.
- Five fields are added: on Import Template `Organization_Matching_Rule__c`,
  `Person_Match_Field__c`, `Organization_Match_Field__c` and `Several_Matches__c`; on Import
  Batch `File_Values_JSON__c`; on Import Row `Several_Matches__c`. `Matching_Rule__c` keeps
  its API name and is labelled Person Matching Rule.
- Affiliation resolved in Core and the purge of staged rows on commit, also listed under
  C-32 in the plan, are not part of this decision.
