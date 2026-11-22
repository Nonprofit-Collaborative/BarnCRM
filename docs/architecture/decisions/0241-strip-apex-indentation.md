# ADR-0241: Strip Leading Indentation From Apex at Deploy and Package-Build Time

**Status:** Accepted
**Date:** 2026-11-21
**Source:** Brandon, plan D-222 (AP-05). Builds on the Apex budget in `docs/contributor-guide/ci.md`
and on the tab indentation already adopted to cut the count (`.prettierrc`, `useTabs`).

## Context

An org counts every character of non-test Apex except comments toward its 6,000,000 character
limit (`ApexClass.LengthWithoutComments`), and BarnCRM installs as unmanaged source beside the
org's own code. The full suite measured 5,307,460 characters in the repository on 2026-11-21 (88
percent of the limit), and Core with every module is still growing. Indentation is a large share
of those characters even with tabs: about 405,000 of them are leading spaces and tabs.

## Decision

1. **The repository stays formatted.** Apex source is indented with tabs by Prettier, and that
   formatted copy is the readable source. Nothing in the repository changes.
2. **The copy sent to an org or into a package version loses its leading spaces and tabs on
   every line.** `scripts/packaging/strip-apex-indent.py` stages the project (`sfdx-project.json`,
   `.forceignore` and every package directory) into a temporary directory with every `.cls` and
   `.trigger` file stripped. Every other file, `-meta.xml` files included, is copied byte for
   byte. Leading whitespace is never removed from a line that begins inside a string literal.
3. **Newlines stay.** Line numbers in a stack trace, a debug log or a code coverage report are the
   line numbers in the repository source.
4. **Every deploy path uses the staged copy:** `scripts/org/deploy-packages.sh` (and so
   `run-org-tests.sh`, `create-scratch-org.sh` and the CI workflow's deploy), `scripts/org/seed-sample-data.sh`,
   `scripts/packaging/create-versions.sh` and the package builds of
   `scripts/org/package-upgrade-test.sh`. `STRIP_APEX_INDENT=0` turns it off for debugging.
5. **The budget is the stripped size.** `scripts/ci/check-apex-budget.py` measures what an org
   counts: the stripped Apex. Its caps are re-based to the stripped measure, its target applies
   to the stripped total, and it prints the raw total beside it.

## Consequences

- The full suite counts 4,902,193 characters (82 percent) instead of 5,307,460 (88 percent), about
  405,000 fewer: more room for the org's own code and for the modules still to come.
- **Code viewed in Setup (Developer Console, the class editor, a retrieved copy) appears without
  indentation.** It compiles and behaves identically. Anyone reading Apex reads the repository.
- A change made directly in an org and retrieved back arrives without indentation. Format it
  with Prettier before committing, as any retrieved source.
- A deploy copies the project (about 9,500 files) to a temporary directory first, a few seconds.
- Source tracking: a deploy through these scripts runs from the temporary copy, so a scratch
  org's tracking records live there and are discarded with it. `sf project deploy preview` and
  retrieve in the repository do not see those deploys. Use `STRIP_APEX_INDENT=0` for a
  tracking-based edit loop, or `sf project deploy start` directly from the repository.
- Code coverage and test results are unaffected: they are keyed by class name and line number.

## Alternatives considered

- **Strip the repository source itself.** Rejected: unreadable code and review diffs, and every
  contributor's editor would reindent it.
- **Ask Salesforce for a higher limit.** The limit is raisable by a support case, but a
  subscriber's org cannot rely on it, and an installed package should not need it.
- **Minify further (shorten names, join lines).** Rejected: changes line numbers and readability
  for a far larger risk than indentation carries.
