# Open Impact

A free, open source suite of Salesforce managed packages that gives small and medium nonprofits an easy, complete, and trustworthy way to run fundraising, constituents, and programs.

## What this is

Open Impact is a set of free apps that install into your organization's Salesforce account and turn it into a working nonprofit database. It is built for small and medium nonprofits: roughly $250K to $10M in annual revenue, 2 to 50 staff, one to ten Salesforce users, and no full-time Salesforce administrator. The person who sets it up is a development director, an operations manager, or an executive director who is comfortable with spreadsheets and modern web apps. If that is you (in our documentation we call you Maria), you are the person this product is designed for, and you should not need a consultant to use it.

Nonprofits on Salesforce are currently stuck between two options, and neither one fits a small team. The Nonprofit Success Pack (NPSP), which thousands of organizations run on, stopped being developed in March 2023, and since December 2025 it is no longer bundled for new Power of Us applicants. Its replacement, Agentforce Nonprofit, is more capable underneath but is widely reported as hard to set up and hard to administer: rollup totals run through scheduled batch processing rather than anything an admin can adjust, the permission model requires cloning managed permission sets that get overwritten at every release, and it does not carry over NPSP's household conventions, address history, or donor levels. Organizations without an implementation budget are left between a frozen product and an over-engineered one. Open Impact exists to give them a third option.

Open Impact handles the everyday work of a development office: households and the people in them, gifts and the funds they are given to, receipts and year-end statements, importing the spreadsheet you have been keeping, and settings you change on a page in the app rather than in Salesforce Setup. Beyond that core, it is modular: volunteers, programs, funder and grant tracking, and connections to other systems are separate packages that you install only if you use them, so a module you do not turn on leaves nothing behind in your org. It runs on whatever Salesforce licenses you already have, including plain Platform licenses, Sales and Service Cloud, an org with NPSP already installed, and an org on Agentforce Nonprofit. It requires no paid add-ons.

Three things matter more to us than shipping features fast. First, the numbers have to be right: giving totals, receipts, and fund balances are the product's reputation, so every rollup shows you when it was last calculated instead of quietly going stale. Second, upgrades must be safe: nothing you configure is overwritten when a new version arrives, and nothing we ship is something you have to clone to use. Third, it is genuinely open: the source is public, the software is free, there is no paid tier, and no data leaves your Salesforce org (there are no external callouts by default, and optional usage telemetry is anonymous, opt-in, and off unless you turn it on).

Open Impact is in early development. The current work is v0.1, the foundation and the household model, and there is nothing installable yet: no package versions exist, and the namespace is not registered. Everything here is source code, a detailed product plan, and architecture decisions in the open. If you run a nonprofit and this sounds like what you need, the most useful thing you can do right now is watch the repository, open an issue describing how your organization works and what has been painful, and tell us which of the four Salesforce setups above you are on. If you write code or administer Salesforce, see the contributor guide below.

## Status

- Phase 0 (planning and repository setup) complete.
- v0.1 (foundation and households) in progress.
- No releases yet. No package versions exist and nothing is installable.
- Namespace pending: development is namespace-agnostic until the namespace is registered.
- Name pending: "Open Impact" is a placeholder working title. A collision with an existing open source foundation was found, so a replacement will be chosen and vetted for availability before any public use (see docs/product-plan.md Section 8.3).
- Governance for v0.x: benevolent dictator (the project owner), moving to a maintainers group with a documented decision process by v1.0.

## Packages

Open Impact is a Core package plus optional module packages that depend on Core.

| Package | Contains | Depends on | First ships |
|---|---|---|---|
| Core | Constituent model (Contacts, Accounts, Households, Relationships, Affiliations, Addresses), the Open Impact app, Settings framework and UI, Module Manager, permission sets, trigger framework, error log, rollup engine, Import framework, health check | (none) | v0.1 |
| Giving | Gifts, funds and allocations, commitments and installments, soft credits, tributes, matching gifts, appeals, acknowledgments and receipts, giving rollups and dashboards, gift batches | Core | v0.2 |
| Connect | Adapters: Opportunity mirror (NPSP and Sales Cloud), Campaign sync, Gift Transaction mirror (Agentforce Nonprofit), inbound gift REST API, accounting export | Core, Giving | v0.6 |
| Volunteers | Volunteer profiles, jobs, shifts, sign-ups, hours, skills | Core | v0.7 |
| Programs | Programs, services, enrollments, attendance, service deliveries, light case notes, outcomes | Core | v0.8 |
| Funders | Funder pipeline (grants received and applied for), reporting deadlines, restricted fund tracking, government award compliance fields | Core, Giving | v0.9 |
| Events | Simple event registration and attendance for non-fundraising events | Core | post-1.0 |

## Runs on

Every release is tested by CI against four org shapes:

- Platform only (Salesforce Platform or Lightning Platform Plus licenses, no Opportunity, Campaign, Case, or Lead objects). This is the floor: Core, Giving, Volunteers, Programs, and Funders all work here.
- Sales and Service Cloud (Enterprise Edition via Power of Us).
- An org with NPSP installed (coexistence mode: adopt existing NPSP household accounts, optionally mirror gifts to Opportunities).
- Agentforce Nonprofit (Person Accounts likely enabled; household junction mode, optional Gift Transaction mirror).

## For contributors

```bash
git clone https://github.com/Nonprofit-Collaborative/OpenImpact.git
cd OpenImpact
npm install
scripts/org/create-scratch-org.sh platform-only
npm test
```

Other scratch org shapes: `sales-cloud`, `npsp`, `person-accounts`.

Start with [docs/contributor-guide/environment.md](docs/contributor-guide/environment.md), then [docs/contributor-guide/scratch-orgs.md](docs/contributor-guide/scratch-orgs.md) and [docs/contributor-guide/ci.md](docs/contributor-guide/ci.md). Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request; it covers the definition of done, the code rules, and the DCO sign-off every commit needs.

## Documentation

- [docs/product-plan.md](docs/product-plan.md): the full product plan, roadmap, and engineering standards.
- [docs/architecture/](docs/architecture/): the canonical data model and architecture decision records (`docs/architecture/decisions/`).
- [docs/admin-guide/](docs/admin-guide/): one page per feature, written for nonprofit administrators.
- [docs/contributor-guide/](docs/contributor-guide/): environment setup, scratch orgs, CI, and the [dynamic Apex conventions](docs/contributor-guide/dynamic-apex.md) for reaching objects and classes an org may not have.
- [docs/release-notes/](docs/release-notes/): what shipped in each iteration.

## Governance and license

Governance is BDFL (the project owner decides) for v0.x, with a maintainers group and a documented decision process by v1.0. Contributions are accepted under the Developer Certificate of Origin: sign your commits with `git commit -s`. There is no contributor license agreement.

Open Impact is licensed under the [Apache License, Version 2.0](LICENSE) (Decision D-08, confirmed 2026-09-22). Apache-2.0 is permissive and carries an explicit patent grant, which protects both the organizations that install Open Impact and the people who contribute to it. Attribution notices are in [NOTICE](NOTICE).

Third party code carried in this repository is licensed separately by its authors. There is one such component today: [apex-rollup](https://github.com/jamessimone/apex-rollup) (Copyright (c) 2019 James Simone, MIT), vendored under [`packages/core/vendor/apex-rollup/`](packages/core/vendor/apex-rollup/) with its license text alongside it.

"Open Impact" is the project name. The name and any associated logo are the project's marks, and the fallback name if a conflict appears is OpenCause. Distinctiveness rests on the pair of words and a consistent visual identity, so please do not use the name or marks for a fork, a derivative product, or a service in a way that suggests it is the official project.

## Not goals

- Not a standalone or multi-platform product. The data model is written to be portable, but no non-Salesforce runtime is built here.
- Not an online giving platform, payment processor, email marketing tool, or donor portal. We integrate with those; we do not replace them.
- Not a replacement for Agentforce Nonprofit's Industries features. Orgs that want them keep them, and we coexist.
- Not a consulting accelerator or partner migration tool. A nonprofit can migrate itself with our importer.
- Not a general CRM. No sales pipeline and no B2B features beyond organizational donors and funders.
