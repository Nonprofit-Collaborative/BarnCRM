# Browser Smoke Tests (Playwright)

Plan item Q3. A short Playwright suite that opens BarnCRM in a real browser, signed in to a
scratch org, and checks that every page loads clean. It catches what Jest and Apex tests cannot:
a page that fails in Lightning itself (a tab that does not open, a component that throws on load,
an Apex call a page makes that fails in a real org, an error toast or "Sorry to interrupt" panel).

It runs locally only, like the org gate. CI never runs it: it needs a signed-in org.

## What It Covers

- `e2e/smoke.spec.js`: for every BarnCRM Lightning app (`packages/*/main/default/applications/`)
  and every tab in it, opens the tab inside that app (`/lightning/app/c__<App>/n/<Tab>` for a
  Lightning page tab, `/o/<Object>/list` for an object tab). It checks that the app is the one
  shown, the main region loads (visible, holds text, no spinner, content stopped changing), no
  error toast, error alert, "Sorry to interrupt", "Something went wrong" or Lightning component
  error panel shows, and no console error names a BarnCRM component. The list comes from the
  metadata, so it never drifts. Skipped, with the reason in the summary: an app or tab not in
  the org (module not deployed), a tab hidden for the running user (feature off), and the
  Salesforce-only Reports and Dashboards tabs.
- `e2e/release-1-24.spec.js`: deeper checks for release 1.24's pages: Advanced Reporting home and
  its report builder, Advanced Reporting under Data in BarnCRM Settings, Payments Setup, Address
  Verification Setup, and Health Check showing Run Remaining Checks exactly when a run left
  checks. Nothing in the suite saves a record; opening pages is the only change it makes.

Console errors that do not name a BarnCRM component are listed in the summary, not failed.
Salesforce's own noise is dropped first; the list, with the reason for each, is `PLATFORM_NOISE`
in `e2e/lib/lightning.js`. Add to it only for a message seen on a page with no BarnCRM code.

## How to Run

```bash
npm install                                  # once: installs @playwright/test
npx playwright install chromium              # once per machine, if the browser is missing
bash scripts/org/run-e2e.sh barn-sales       # every test
bash scripts/org/run-e2e.sh barn-sales -g "Fundraising"   # extra arguments go to Playwright
```

The alias is any sf CLI alias for a test org whose default user has the BarnCRM admin permission
sets. Use `barn-sales` for development runs; never point it at a production org or a sandbox
you have not been cleared to open. The script prints a pass, fail and skip count, the skip
reasons, and each failure. Full results are in `e2e-results/results.json`, with a screenshot of
each failure under `e2e-results/artifacts/`. A full run on `barn-sales` takes a few minutes.

A failure is a finding: report it or fix the product. Never weaken an assertion to make a run
pass.

## The Session URL Rule

Sign-in uses `sf org open --url-only` inside the test runner (`e2e/global-setup.js`). That URL
carries a live session id, so:

- never print, log or write it to a file, a test title, a screenshot name or a report;
- traces and video stay off in `playwright.config.js` (a trace records every request);
- the saved browser session, `e2e-results/.auth/<alias>.json`, holds session cookies: it is
  gitignored with the rest of `e2e-results/`; never commit, attach or share it.

Errors from the sign-in step are rethrown with every URL removed. Keep it that way when you
change it.
