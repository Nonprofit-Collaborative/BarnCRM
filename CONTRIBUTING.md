# Contributing to BarnCRM

Thank you for being here. BarnCRM is a free, open source suite of Salesforce managed packages for small and medium nonprofits, and it is built to be contributed to: small modules, clear contracts between them, a scratch org that works in under ten minutes, and documentation written as part of every feature rather than after it.

The project is at Phase 0 / v0.1. Nothing is installable yet, no package versions exist, and the namespace is not registered, so contributions right now are source, docs, tests, and design feedback.

## Who contributes

In our plan the contributor persona is Sam: an open source developer or a Salesforce administrator who wants to clone the repo, spin up a scratch org, run the tests, and understand one module without reading all of them. Sam should never have to read the whole codebase or guess at conventions. If you find yourself doing either, that is a bug in this document or in the contributor guide, and an issue about it is a real contribution.

Administrators are contributors too. You do not need to write Apex to make this product better.

## Ways to help

- **Open an issue.** Use https://github.com/Nonprofit-Collaborative/BarnCRM/issues/new/choose and see [SUPPORT.md](SUPPORT.md) for the templates and what to include. Never post personal or donor data. Describe how your organization works, what is painful today in NPSP or Agentforce Nonprofit, and which Salesforce setup you are on. Concrete stories shape the roadmap more than feature requests do.
- **Improve the docs.** The admin guide (`docs/admin-guide/`) is written for Maria, an operations manager with no technical background. If a page assumes knowledge she does not have, fix it or say so.
- **Test on an org shape.** We support four: Platform only, Sales and Service Cloud, an org with NPSP installed, and Person Accounts enabled (the Agentforce Nonprofit shape). Reports from a shape you actually run are valuable.
- **Write code.** Look for `good first issue` labels. Every module has its own README with its objects, its services, and how to test it alone.

## Getting set up

Read [docs/contributor-guide/environment.md](docs/contributor-guide/environment.md) first. The short version:

```bash
git clone https://github.com/Nonprofit-Collaborative/BarnCRM.git
cd BarnCRM
npm install
scripts/org/create-scratch-org.sh platform-only
npm test
```

The scratch org script takes one of four shapes: `platform-only`, `sales-cloud`, `npsp`, `person-accounts`. It creates the org, deploys source, and loads sample data. Target: clone to a running scratch org with sample data in under ten minutes, one script, no manual Setup steps. If it takes longer than that for you, open an issue.

More detail: [docs/contributor-guide/scratch-orgs.md](docs/contributor-guide/scratch-orgs.md) and [docs/contributor-guide/ci.md](docs/contributor-guide/ci.md).

## Branching and pull requests

- Trunk-based development. `main` is always releasable.
- One feature branch per issue, branched from `main`.
- Squash merge. Release branches (`release/0.x`) exist only when a hotfix is needed on a promoted version.
- Keep pull requests under roughly 800 changed lines. Larger ones get split.
- One feature per pull request. Unrelated cleanups belong in their own PR.
- Do not invent features. If something seems missing, add it to the parking lot (product plan Section 11.3) with a sentence of justification and carry on with the work in hand.
- When a platform limitation blocks the plan, record an ADR with the workaround and continue. Do not silently change the design.

## Definition of done

A feature is done when all of these are true (product plan Section 7.4):

- [ ] Canonical model updated first (`docs/architecture/canonical-model.md`, Section 4.4 of the plan).
- [ ] Metadata, Apex, and LWC complete, with tests passing on all four org shapes.
- [ ] Settings for the feature exposed in the Settings console with descriptions; no Setup step required for normal use.
- [ ] Permission sets updated; no new permission requires cloning.
- [ ] Error paths logged to the Error Log with human-readable messages.
- [ ] Admin-guide page written: what it does, how to turn it on, a five-minute walkthrough, common mistakes.
- [ ] Release note line written.
- [ ] Sample data updated if the feature adds objects.
- [ ] Reviewed by a second person or agent against this checklist (plan Section 9.4).

## Code rules

CI enforces what it can; reviewers enforce the rest.

- Apex is `with sharing` by default. Every DML and query that touches user-facing data runs in user mode (`WITH USER_MODE` or `Security.stripInaccessible`).
- Bulkified. No SOQL or DML in loops. Governor-limit safety proven by tests that insert 200 records per DML context.
- One trigger per object, routed through the trigger framework, with bypassable handlers.
- No hard-coded IDs. No `Test.isRunningTest()` branches in production logic.
- Every `@AuraEnabled` method validates its input and returns a typed result or a structured error the UI can render.
- Every SOQL query lives in a Selector; business logic lives in a `*Service`; cross-package calls go through `global` service interfaces only.
- User-facing text comes from Custom Labels, never from string literals in code or markup.
- LWC: no third-party JavaScript except vetted static resources (SheetJS for import parsing is the only pre-approved one; anything else needs a recorded decision). Jest tests for every component with logic.
- LWC styling is SLDS 2 (Cosmos theme): base components and SLDS utility classes first; any component CSS uses SLDS 2 global styling hooks (`--slds-g-*`) only, never hard-coded colors, spacing, font sizes, shadows or radii, `--lwc-*` tokens, or overrides of `slds-*` classes. `npm run lint:slds` enforces it in CI.
- Apex test coverage target is 90 percent per package. The platform minimum of 75 percent is not the target.
- Salesforce Code Analyzer (PMD, ESLint, retire-js, Graph Engine for FLS and CRUD) must pass with zero high or critical findings.

## Naming conventions

- Objects and fields: `PascalCase__c`, module-neutral API names (the namespace disambiguates). Labels use the language a nonprofit uses: "Gift" not "Donation Transaction", "Fund" not "General Accounting Unit".
- Apex: one class per responsibility, with role suffixes: `*Service`, `*Selector`, `*Domain` or `*TriggerHandler`, `*Controller`, `*Batch`, `*Queueable`, `*Schedulable`, `*Test`.
- LWC: component names describe the screen, for example `settingsConsole`, `householdNamingPreview`, `importWizard`.
- Custom labels: `Module_Screen_Purpose`, for example `Giving_ReceiptPage_IssuedStamp`.
- Custom permissions: `Manage_BarnCRM_Settings`, `Enter_Gifts`, `Issue_Receipts`, `Manage_Volunteers`, `Manage_Programs`, `View_Funder_Pipeline`.

## The four non-negotiables

CI has a check for each of these, and a pull request that trips one does not merge.

1. **Namespace-agnostic.** No namespace prefix hard-coded anywhere: Apex, SOQL, LWC imports, Flow, custom labels, static resources, permission set files. Use relative references inside the package and `Schema` describes for anything dynamic.
2. **No standard object outside Mirror.** No hard reference to Opportunity, Campaign, Case, Lead, or any Industries object in Core, Giving, Volunteers, Programs, or Funders. Mirror may reference them, and only behind dynamic Apex (`Schema.getGlobalDescribe`, `Type.forName`) and generic `sObject` code so it degrades gracefully where the objects are absent. The patterns to copy are in [docs/contributor-guide/dynamic-apex.md](docs/contributor-guide/dynamic-apex.md).
3. **No Setup-only settings.** If a setting could live in the in-app Settings console, it lives there. Setup is only for things Salesforce does not allow an app to do, and then the Setup Assistant deep-links to it with instructions.
4. **Code Analyzer clean.** Zero high or critical findings on every pull request.

CI also runs Prettier, ESLint, Jest, Apex tests on the four org shapes, and the DCO sign-off check.

## Documentation is part of the feature

Write the admin-guide page **before** the LWC. If the page is hard to write, the feature is too complicated: simplify the feature. Every feature also needs a release note line, written for Maria rather than for developers.

## Sign your commits (DCO)

We use the Developer Certificate of Origin instead of a contributor license agreement. Sign off every commit:

```bash
git commit -s -m "Add household naming preview"
```

That adds a `Signed-off-by: Your Name <you@example.com>` line. It means you certify that you wrote the contribution or otherwise have the right to submit it under the project's license, and that you are willing for it to be distributed as part of the project. The full text is at [developercertificate.org](https://developercertificate.org/).

If CI tells you a commit is missing a sign-off:

```bash
# most recent commit
git commit --amend -s --no-edit && git push --force-with-lease

# several commits on your branch
git rebase --signoff main && git push --force-with-lease
```

## Style for docs and labels

- Use the language a nonprofit uses, not Salesforce jargon or developer jargon.
- Refer to the personas by name where it helps: Maria (operations manager), David (development director), Priya (program coordinator), Tom (executive director), Jen (board treasurer or bookkeeper), Sam (contributor). Use them in user stories, tests, and docs.
- No em dashes. Use colons, commas, or parentheses.
- Plain, warm, concrete sentences. Say what a person does and what happens next.
- Every error message says what went wrong and what to do about it.

## How decisions get made

- Architectural decisions are recorded as ADRs in `docs/architecture/decisions/`, numbered and titled (`NNNN-title.md`). If you make a call that a future contributor would otherwise have to reverse-engineer, write one.
- Good ideas that are deliberately not being built now go in the parking lot, product plan Section 11.3, with a sentence of justification.
- Some decisions are not the contributor's to make: the list is in product plan Section 11.4. Escalate those to the maintainer rather than deciding in a pull request.
- Governance is BDFL (the project owner) for v0.x, moving to a maintainers group with a documented decision process by v1.0.

## Code of conduct

Participation is covered by our [Code of Conduct](CODE_OF_CONDUCT.md). Please read it.

## License

BarnCRM is licensed under the [Apache License, Version 2.0](LICENSE) (Decision D-08). By contributing with a DCO sign-off, you agree that your contribution is offered under that license.
