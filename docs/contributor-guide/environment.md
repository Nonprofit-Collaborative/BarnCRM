# Contributor environment

## Tool versions used to build this scaffold

- Salesforce CLI (`sf`) 2.150.6
- Salesforce Code Analyzer plugin 5.16.0
- `@salesforce/sfdx-plugin-lwc-test` 1.2.1
- Node v22.22.2 (npm 10.9.7)
- git 2.43.0
- OpenJDK 21.0.10 (needed by PMD, which the Code Analyzer runs)
- Python 3.11.15

## Requirements

- **Node**: use the current Node LTS line (22.x at the time of writing; check
  [nodejs.org](https://nodejs.org) for the active LTS before installing). Older LTS lines may
  work but are not tested.
- **Java 11 or newer**: required for PMD, which `sf code-analyzer` runs as part of the rule
  engine. Java 21 (as installed here) is fine; anything 11+ works.

## Install

```bash
npm install -g @salesforce/cli
sf plugins install code-analyzer
npm install
```

`npm install` pulls the devDependencies pinned in `package.json` (ESLint, Prettier,
`@salesforce/sfdx-lwc-jest`, husky, lint-staged, and their Salesforce-specific plugins) and
produces `package-lock.json`.

## Verify the toolchain

```bash
npm run lint
npm run test:unit
npm run prettier:verify
npm run check:namespace
npm run check:standard-objects
```

All five should pass with a clean checkout, even before any package has real metadata: `lint`
and `test:unit` pass with zero LWC components, and the two `check:*` scripts pass on an empty
`packages/` tree.

## Namespace registration

The namespace is deferred (ADR-0001): `sfdx-project.json` ships an empty namespace and no
source may contain a prefix literal. The mirror image of that rule matters just as much, and
`scripts/ci/check-namespace.sh` cannot catch it: a name written without a prefix is equally
wrong, because it works in the unmanaged scratch orgs and silently stops resolving the day the
namespace exists.

The rule, for anything whose API name gains a prefix when a package is namespaced (custom tabs,
Visualforce and Lightning pages, custom objects and fields, and Lightning page state keys):

- A Lightning web component never writes such a name itself, neither prefixed nor bare. No
  `apiName: 'Nonprofit_Settings'`, no `state: { c__section: ... }`.
- It obtains the name from Apex, on the response it already reads, and uses it verbatim.
- Apex builds it through `NamespaceUtil`, which asks the running package what its namespace is:
  `NamespaceUtil.prefix()` returns `mynamespace__` or an empty string, `qualify(apiName)` puts
  it in front of a packaged API name, and `stateKey(name)` returns the page state key, which is
  `c__name` when there is no namespace and `mynamespace__name` when there is.

Worked example: `HealthCheckService.Report` carries `settingsTabApiName` and `sectionStateKey`,
both computed in its constructor, and `healthCheckPanel` navigates with the two values the
report gave it. Nothing has to change in either place when the namespace is registered.

Apex referring to its own packaged metadata does not need any of this: the compiler resolves
`BarnCRM_Settings__c` inside the package regardless of namespace. Only names that cross into
strings, URLs, page state, or metadata lookups do.

## A note on `config/scratch-defs/person-accounts.json`

The product plan's repository layout (Section 4.3) lists this file as `npc.json`. Per Brandon's
instruction, it is named `person-accounts.json` in this repository instead: the file name says
what the org shape verifies (Person Accounts enabled) rather than a product-name shorthand.
