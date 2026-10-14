# ApexGuru and Scale Center

Two Salesforce performance tools that look at what static analysis cannot: how Apex and
queries behave in a real org. Both are optional and manual. Neither is a CI gate.

## ApexGuru (Code Analyzer engine)

ApexGuru is Salesforce's hosted Apex analysis. The Code Analyzer `apexguru` engine zips the
Apex files under `packages/`, sends them to a Salesforce service, and returns violations.

What the repo ships:

- `config/code-analyzer-apexguru.yml`: engine settings (a longer timeout). It is not
  auto-loaded, so the required CI run (`npm run check:analyzer`) is unaffected.
- `scripts/org/run-apexguru.sh <org-alias> [report-dir]`: runs the engine and writes
  `apexguru-results.html`, `apexguru-results.json` and `apexguru-run.log` (default folder
  `apexguru-results/`, untracked). It exits 1 if the scan was skipped, so a quiet skip is not
  mistaken for a clean result.

How it behaves (read from Code Analyzer plugin 5.16, ApexGuru engine 0.43):

- It needs a logged-in org. It uses the CLI login for the alias to mint a short-lived token
  from the org (`/ide/auth`), then calls a Salesforce service. No org login, no scan, so it
  cannot run in CI without an org auth secret. We do not add one: it is a manual step.
- It is opt-in. The `Recommended` and `all` selectors never include it; only
  `--rule-selector apexguru` (or the tag `apex-guru`) does.
- It analyzes Apex only, and only the files in the workspace. The service decides which
  rules fire; the engine lists 22 known rules plus `apexguru-other` for new ones.
- Source code leaves the machine (to Salesforce). Fine for this open-source repo.
- Whether an org's edition or a trial is entitled to ApexGuru is decided by Salesforce
  server side. Salesforce documents ApexGuru for production orgs and Full Copy sandboxes,
  with some editions excluded (for example Government Cloud Plus). We could not verify
  `barn-npc` offline: if the run reports a 403 or "not enabled", enable ApexGuru in
  Setup (search "ApexGuru") or try a different org, and record the outcome in `architecture.md`.

### When to run it

Before each release, against `barn-npc` (the Nonprofit Cloud trial, a production-type org):

```
scripts/org/run-apexguru.sh barn-npc apexguru-results
```

Run it from a clean worktree at the release candidate. Only the source files are read; it
does not deploy anything or change the org. Some findings (for example `ExpensiveMethods`)
are based on the org's observed runtime, so a trial org with little traffic reports mostly
static patterns. Treat it as a second opinion next to PMD, not a replacement.

### Reading the results

Open `apexguru-results.html`. Each row has a rule, severity, file and line.

| Severity | Rules (examples) | What to do |
| -------- | ---------------- | ---------- |
| High | `SoqlInALoop`, `DmlInALoop`, `ExpensiveMethods`, `SchemaGetGlobalDescribeNotEfficient`, `SoqlWithoutPlatformCache` | Treat like a Code Analyzer high finding: fix or justify in the release notes before release |
| Moderate | `SoqlInALoopOneHop`, `Redundant Soql`, `SoqlWithApexFilter`, `Soql Aggregation` | Fix when the code is hot (triggers, batches); otherwise log an issue |
| Low | `SoqlWithoutAWhereClauseOrLimitStatement`, `ExpensiveDebugStatements`, `SortingInApex` | Review; many are deliberate (settings queries with a `LIMIT 1` elsewhere) |

Judge each finding against the code. Known false-positive shapes here: the vendored rollup
engine (not ours to change, see ADR-0015), queries on Custom Settings (cached by the
platform), and `SoqlWithoutPlatformCache` where a cache would break the Platform-only
org rule (ADR-0013). Record findings you reject with the reason in the release notes under
"ApexGuru". Never add suppressions to make the report clean.

## Scale Center

Scale Center is a Salesforce Setup tool for production and Full Copy sandboxes. Salesforce
documents it for production and Full Copy; Partial Copy is not stated in what we could find, so
confirm with the owner's org before relying on it. It is org-side only: nothing in this repo
calls it.

What it gives:

- Apex and SOQL performance insights from the org's real traffic (slowest transactions,
  expensive queries, CPU and limit trends). Overlaps with ApexGuru.
- Load testing: it can replay recorded production traffic or run a defined load against a
  sandbox and report response times and failures. Salesforce limits this to approved sandboxes
  and requires a request or enablement from Salesforce; it is not available in scratch orgs or
  Developer sandboxes.

How it ties to the scale test plan ([scale-and-mobile-test-plan.md](scale-and-mobile-test-plan.md)):

| Plan step | Scale Center use |
| --------- | ---------------- |
| Tier 1, `oi-test` | None. Scratch orgs do not have it. Use `AsyncApexJob` and debug logs as the plan says |
| Tier 2, Partial or Full Copy sandbox (owner must provide) | After the bulk loads and batch runs, open Scale Center in that sandbox and read the Apex and SOQL insights for the run window. Add the slowest transactions and queries to the "Scale test" section of the release notes |
| Interactive pages (household with 30 members, contact with 500 gifts) | If Scale Center load testing is enabled for the sandbox, run it against those pages and record p95 response time next to the 5 second target |

Run ApexGuru against the tier 2 org alias too when it is a production-type or Full Copy org:
runtime based findings are only meaningful after the load.

## Org checks the orchestrator must make

1. `scripts/org/run-apexguru.sh barn-npc apexguru-results`: confirms the trial org is
   entitled to ApexGuru. Record the result (ran, or the exact error) in `architecture.md`.
2. Ask the owner which sandbox type will host tier 2 and whether Scale Center is visible in
   its Setup (search "Scale Center").
