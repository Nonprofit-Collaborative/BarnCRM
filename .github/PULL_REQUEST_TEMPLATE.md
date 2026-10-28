# Pull request

## Feature ID

<!-- For example: C-04 -->

## Summary

<!-- What does this change do, and why? -->

## Org shapes tested

- [ ] Platform only
- [ ] Sales or Service Cloud
- [ ] NPSP installed
- [ ] Nonprofit Cloud or Person Accounts

## Definition of done (Section 7.4)

- [ ] Canonical model updated first (Section 4.4).
- [ ] Metadata, Apex, LWC complete with tests passing on all org shapes.
- [ ] Settings for the feature exposed in the Settings console with descriptions; no Setup step required for normal use.
- [ ] Permission sets updated; no new permission requires cloning.
- [ ] Error paths logged to Error Log with human-readable messages.
- [ ] Admin-guide page written (what it does, how to turn it on, a five-minute walkthrough, common mistakes).
- [ ] Docs updated in this PR: Admin Guide page, User Guide page (if users touch it), Testing Guide script(s), `docs/overview.md` (if status or the module list changes); each index's "Applies to" line updated.
- [ ] Release note line written.
- [ ] Sample data updated if the feature adds objects.
- [ ] Reviewed by a second agent or human against the review checklist (Section 9.4).

## Repository rules

- [ ] No em dashes anywhere in this change.
- [ ] No hard-coded namespace anywhere in this change.
- [ ] No standard-object reference outside Mirror.
- [ ] Every new Apex test runs inside `System.runAs(TestUsers.admin())` (or `TestUsers.adminWith(...)` in a module), or says why not with `// runs-as: deploying user (reason)`. See docs/contributor-guide/ci.md, "Tests run as a user they create".

## Org tests

- [ ] Feature pull request: no org gate; Jest (`npm run test:unit`) and the `scripts/ci` checks passed locally, and the branch lands through a landing batch (plan D-141).
- [ ] Landing batch (`landing/batch-N`): the full `scripts/org/run-org-tests.sh` run passed on the head commit on both `barn-sales` and `oi-test`, run in parallel, so the `Org tests (local)` status is green. See docs/contributor-guide/ci.md, "The org test gate".

## DCO sign-off

- [ ] Every commit in this PR is signed off (`git commit -s`, or `git rebase --signoff` for an existing branch). See docs/contributor-guide/ci.md.

## Reviewer agent checklist (Section 9.4)

- [ ] Does it meet the definition of done (Section 7.4)?
- [ ] Could Maria do this without Setup and without the docs? If not, why not, and is that recorded?
- [ ] Are the numbers right? (Rollups recalculated in tests after every path: insert, update, delete, undelete, reparent, merge.)
- [ ] Does it work on the Platform-only org shape?
- [ ] Does it degrade gracefully when a module is off or a standard object is absent?
- [ ] Is anything overwritten on upgrade that an admin might have changed?
- [ ] Is the label language a nonprofit's language?
- [ ] Are the Overview, Admin Guide, User Guide and Testing Guide updated for this change (D-116)?
