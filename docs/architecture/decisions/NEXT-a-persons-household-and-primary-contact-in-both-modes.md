# ADR-NEXT: A person's household, and the Primary Contact, in both membership modes

**Status:** Accepted (owner default, D-85)
**Date:** 2026-10-13
**Source:** Core quality pass on households and people (PEOPLE-4, PEOPLE-10, PEOPLE-12,
PEOPLE-27); canonical model R-H1, R-H2, R-H10, R-M3

## Context

Four gaps in the household rules left the answer depending on how a person arrived:

- **Junction mode, a contact saved with its account set to a household.** The household was
  named on the record but no membership row joined the person to it, so the household did
  not count them, name them or show them. An import or a hand save that filled Account
  Name produced a person who looked attached and was not.
- **A person in two households and primary in neither.** The question "which household is
  this person's" was answered with whichever membership row the query happened to return
  first, so a gift's household soft credit and the person's household panel could change
  between two reads.
- **Contact mode, the Primary Contact.** Any contact could be typed into a household's
  Primary Contact, including somebody from another household, and a household created
  automatically for a person was left with no Primary Contact, while junction mode marks
  that person the primary member.
- **Person Account orgs, adding a new person from the household panel.** The panel always
  created a contact, which in an org that stores people as accounts is the wrong kind of
  record.

## Decision

1. **Junction mode: naming a household on a new contact joins it.** A contact inserted with
   its account set to a household gets one membership row in that household, after insert,
   as an ordinary member (not primary: who is primary stays a decision, R-H10). An account
   that is an organization, which in junction mode is an employer, or a native Nonprofit
   Cloud household, is left alone. Automatic creation runs after this, so the person is not
   given a second household.
2. **A person's household is their primary membership, else their earliest current one**
   (R-M3). Earliest is by Start Date, a membership with no Start Date counting as earliest,
   then by the row created first. A person with any current membership always has a
   household. Where a data load has made a person primary in more than one household, the
   earliest of those is the answer, so it is stable.
3. **Contact mode: the Primary Contact is a member.** Setting or changing a household's
   Primary Contact to somebody whose account is not that household is refused before save,
   with a message saying why. Clearing it, and saving a household whose primary has since
   left, are never refused. The check reads the contact in system mode (ADR-0021): it is a
   question about the household's membership, not about what the saver can see. The
   automatic household made for a new person names that person its Primary Contact.
4. **Person Account orgs: the household panel creates a person account** when the org
   stores people as accounts, households use the flexible (junction) way of belonging, and
   the running user has a person record type they can create with. Otherwise it creates a
   contact, as before. Contact mode always creates a contact: a person account cannot
   belong to a household by reference.

## Alternatives considered

- **Junction mode: treat a contact's account as its household outright.** Rejected: in
  junction mode the account is an employer as often as a household, which is why the mode
  exists.
- **Choose the person's household by name or by most recent membership.** Rejected: the
  earliest membership is the one the person has had longest, and it does not change when a
  second household is joined.
- **Contact mode: validate the Primary Contact with a validation rule.** Rejected: a
  validation rule cannot read whether the contact belongs to this household without a
  formula path that breaks for a new household, and it could not be bypassed by the
  package's own writes.
- **Always create a contact from the panel.** Rejected: in a Person Account org that leaves a
  person stored the wrong way, invisible to the org's own person account views.

## Consequences

- Imports in junction mode that name a household on a contact now produce a counted member.
  The import's own later join (when it also adds the person) finds the existing current
  membership and adds nothing.
- A hand edit of Primary Contact to a non-member in contact mode now fails where it used to
  succeed. Existing data is not changed or flagged.
- The org gate must confirm the person account path on a Person Account org (oi-pa), since
  the offline tests can only check it where such a record type exists.
