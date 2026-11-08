# Roadmap

Purpose: planned work with status, by release. Mirrors Section 6 (6.0a release plan, 6.1.5 competitive research) of the BMemory plan `specification/open-impact-product-plan.md`, which is canonical: change BMemory first, then this file and `docs/product-plan.md`. Feature status detail lives in `docs/barncrm-features.md`.

Status as of 2026-11-08: Batch C (releases 1.1 to 1.3) is in `main`: landing #1026 (e4069239) after the release gate passed on `oi-test` and `barn-sales` (5,296 of 5,296), then #1027 (Contact Point Sync bulk CPU) and #1028 (barn-npc-only test fixes); released to `barn-npc` at 2c26fd7b with the module tabs in the BarnCRM apps (D-188); next: `mwdbdevsb` Core deploy (owner approval), QA and UX, then statuses move to Shipped. Earlier, status as of 2026-11-07: Batch B is finished: `main` 4ca13cb2 (#1002, D-185) released to `barn-npc` and `mwdbdevsb`. Batch C waves 1 and 2 are built and integrated on `landing/batch-c` (ec73c41e, ADR-0175 to ADR-0185); the batch gate on `barn-sales` stopped at the org's custom app limit (owner decision pending); wave 3 (EV-13, EV-16 to EV-19, PB-03, PB-07, PB-08, Events sample data) is being built. Earlier, status as of 2026-11-06 (later): Batch B follow-ups 2 (D-184) landed as #979 (cd1410ae): vis-modules-18 module record pages, Households rename, Match Sources off by a setting, address deletion setting, shipped Organization record type, Relationships hidden while off, C-60 Automation tab, inventory, scan and deactivate tool; `mwdbdevsb` released with Batch B Core (ca99c753, Rollups removed per D-179); next: `barn-npc` release of #979, `mwdbdevsb` Core release on approval, then Batch C. Earlier, status as of 2026-11-06: all of Batch B is in `main`: the nonprofit stage (Giving, Programs, Volunteers, Funders, Logic Models usability and visual rollout, release 0.18) landed as #958 (ca99c753) after the owner QA fixes; the release gate passed on `barn-sales` and `oi-test` (4,914 of 4,914); released to `barn-npc` (all packages); `mwdbdevsb` not yet deployed (needs approval and the D-179 scope); next Batch C (Forms, Contact Point Sync, Events, Portal Builder). Earlier, status as of 2026-11-05: the Batch B Core stage (#912) and stage 2, Core follow-ups, Rollups and Mirror (#918) are in `main`; released to `barn-npc` (Core and universal modules) and `mwdbdevsb` (Core and Rollups); the owner QA round landed #923 to #930 in `main`, not yet deployed (D-179 to D-182); the nonprofit stage of Batch B is held until the QA fixes are done; then Batch C (Forms, Contact Point Sync, Events, Portal Builder). Earlier, status as of 2026-11-04: releases 0.15 to 0.17 (batch B) built and integrated on `landing/batch-b`; release 0.18 (usability and visual polish, architect-review fixes; D-170 to D-173) added to v1.0 and partly built: UX kit, help catalogs, logos, Core and Logic Models rollouts and the install and automation stack merged into `landing/batch-b` through #898; the nonprofit module rollouts (Giving, Programs, Volunteers, Funders, Logic Models part 3) are on hold behind Core, then universal modules, then nonprofit modules; messages move (AR-01) and the Apex trim pass still to build; Project Management module placed in release 1.17, Batch I (D-175). Nothing of batch B is in `main` yet. Earlier, status as of 2026-11-02: every v1.0 item (releases 0.15 to 0.17, batch B) built and integrated on `landing/batch-b`, not yet in `main` (status Built until the landing gate passes and it is squash-merged; D-167: all of v1.0 built before any testing cycle). Landing batch A (releases 0.12 to 0.14) landed in `main` (status Landed until the batch's release gate, deploys and QA are done); last shipped version 0.11; release plan adopted (D-155); competitive research added 48 features (D-156); the eleven research proposals approved and placed, v1.0 after Brandon's initial QA (D-157). History: `changelog.md` (newest first) and this file's earlier versions in git (`git log -p -- roadmap.md`; the last iteration-based version is at ef92381b).

## Rules (D-155 to D-157, plan 9.7 to 9.9)

- Each release: about 3 major and 3 to 6 minor enhancements. Each landing batch: 2 or 3 releases.
- Per batch: incremental gates on the landing branch; the whole-solution review (plan 9.8); then the release gate (`--release` on `barn-sales` and `oi-test`), `barn-npc` and `mwdbdevsb` deploys (Brandon's approval for each `mwdbdevsb` deploy), QA and UX. Each release ships its What's New record.
- Upkeep is automatic: new approvals are placed in a release; a move up or back that Brandon asks for is re-slotted and the affected releases rebalanced; statuses update as batches land.
- New features consistent with the vision may be added without Brandon's approval (D-156); new modules or editions, reversals of settled decisions or non-goals, and not-approved items go to him as proposals.
- New work follows the portability preferences toward BarnCRM for WordPress (plan 9.9) where they cost little.
- Status values: Planned, In progress, Built (PRs open, integrated on a landing branch), Landed (in `main`), Shipped (batch gate, deploys and QA done).
- Release 0.18 is the v1.0 candidate (D-170). v1.0 is tagged once Brandon's initial QA is complete, expected around or after 0.18 and before AppExchange approval (M-1, D-157). Later releases are 1.1 onward.

## Batches

| Batch | Releases | Theme |
|---|---|---|
| A | 0.12, 0.13, 0.14 | Access Explorer, admin visibility and Core follow-ups; Programs, solicitation pipeline, Logic Models, volunteer reminders |
| B | 0.15, 0.16, 0.17, 0.18 | Programs depth, Logic Models and Funders complete, Nonprofit Cloud mirror, Field Access Manager, usability and visual polish (0.18, D-170), architect-review fixes (0.18, D-172, D-173); 0.18 is the v1.0 candidate; namespace registration and a sandbox-only managed beta follow the v1.0 test cycle and precede the first production pilot (D-173) |
| C | 1.1, 1.2, 1.3 | Forms engine, Contact Point Sync, Event Management (core, then complete with call for speakers, sponsorship, check-in; moved up by Brandon, D-177), Portal Builder with the volunteer, speaker and donor portal templates (1.3, D-178; PB-01 waits on the item 30 terms check) |
| D | 1.4, 1.5, 1.6 | Migration Assistant, volunteer self-service, recurring donor health, engagement score, Giving minors, Archive by Query, generic merge, field history |
| E | 1.7, 1.8, 1.9 | Corporate Hub documents and compliance, Memberships, GDPR, Migrations |
| F | 1.10, 1.11, 1.12 | Board governance, board and member portals (Portal Builder moved to Batch C, D-178), grant management, Scholarships and Outbound Grants |
| G | 1.13, 1.14, 1.15 | Gala seating, multi-brand management, LWC Builder start, Address Verification and online donations (moved later by Brandon, D-177) |
| H | 1.16, 1.17 | LWC Builder complete, Territory Management, Grid tool; Backup Sets and files import last (D-157) |
| I | 1.18 | Project Management module, possibly a PSA tool (D-175); later by Brandon's direction |

## Releases

### 0.12 (Batch A): Access Explorer, admin visibility, Core follow-ups, Programs start

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-53 | Access Explorer | Major | Landed (batch A) | D-154 |
| C-56 | Setup Changes Log | Major | Landed (batch A) | D-156 |
| P-01 | Program, Service, Enrollment | Major | Landed (batch A) | v0.9 |
| C-50f1 | Super Transformer saved step lists | Minor | Landed (batch A) | D-154 |
| C-50f2 | Phone format preset with a digit-format step | Minor | Landed (batch A) | D-154 |
| C-54 | Weekly Admin Digest | Minor | Landed (batch A) | D-156 |
| C-55 | Record Inspector | Minor | Landed (batch A) | D-156 |
| C-49f1 | Import R5: Affiliation and Relationship templates, after an org check | Minor | Landed (batch A) | D-136 |
| QA-F1 | Platform-only coverage check before the next client deploy | Minor | Landed (batch A) | Plan 11.3 item 10 |

### 0.13 (Batch A): Programs attendance, solicitation pipeline, AI readiness

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| P-02 | Attendance and service delivery logging | Major | Landed (batch A) | v0.9 |
| G-26 | Solicitation pipeline (Opportunity-free asks) | Major | Landed (batch A) | D-156 |
| AIR-01 | AI-Readiness Export | Major | Landed (batch A) | D-154 |
| UX-F1 | Trim about 200 labels of 20 or more words | Minor | Landed (batch A) | D-140 |
| UX-F2 | Cosmos contrast check, "Data Hygiene" comments, Data Jobs section on the UX kit | Minor | Landed (batch A) | D-140 |
| C-53b | Permission compare and Modify All report in Access Explorer | Minor | Landed (batch A) | D-156 |
| G-28 | Saved donor segments with export | Minor | Landed (batch A) | D-156 |
| G-29 | Ask cadence reminders | Minor | Landed (batch A) | D-156 |
| G-30 | Pledge reminders | Minor | Landed (batch A) | D-156 |

### 0.14 (Batch A): Logic Models start, volunteer reminders, Programs minors

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| L-01 | Logic model builder | Major | Landed (batch A) | v0.9 |
| L-02 | Indicators on outputs and outcomes | Major | Landed (batch A) | v0.9 |
| V-10 | Volunteer shift reminders (the unfilled-shift nudge is V-10b) | Major | Landed (batch A) | D-156, D-165 |
| P-04 | Case notes | Minor | Landed (batch A) | v0.9 |
| P-05 | Program dashboard | Minor | Landed (batch A) | v0.9 |
| P-06 | Program roster template through C-49c (V-06 hours template moves to C-49c too) | Minor | Landed (batch A) | v0.9, D-154 |
| P-07 | Intake and eligibility fields | Minor | Landed (batch A) | v0.9 |
| P-08 | Participant privacy sharing preset | Minor | Landed (batch A) | v0.9 |
| V-11 | Suggested volunteers for a shift | Minor | Landed (batch A) | D-156 |

### 0.15 (Batch B): Logic Models complete, Programs depth

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| L-03 | Indicator sources | Major | Built (#820); landing B | v0.9 |
| P-10 | Participant service plans and goals | Major | Built (#828, #829); landing B | D-156 |
| P-11 | Cohorts, sessions and mass enrollment | Major | Built (#842, #843); landing B | D-156 |
| L-04 | Logic model report | Minor | Built (#827); landing B | v0.9 |
| G-19 | Donor scoring (RFM) as rollups | Minor | Built (#814); landing B | v0.9 |
| P-12 | Anonymous and aggregate service counts | Minor | Built (#811); landing B | D-156 |
| P-13 | Referrals in and out | Minor | Built (#811); landing B | D-156 |
| P-14 | Eligibility screening results | Minor | Built (#811); landing B | D-156 |
| UX-F3 | Module tab motifs | Minor | Built (#808); landing B | D-144 |
| QA-F2 | Ship-on checkbox settings added in an upgrade start on (Include Admin Summary, Ask Reminders) | Minor | Built (#831); landing B | D-166 |
| QA-F3 | Person account orgs: shift reminders, suggested volunteers, one ask donor field | Minor | Built (#832); landing B | D-166 |
| QA-F4 | Enrollments and service deliveries require a person account on every path | Minor | Built (#832); landing B | D-166 |
| QA-F5 | Nonprofit Cloud Program Management coexistence: Integrations, admin guide, Health Check info | Minor | Built (#832); landing B | D-166 |
| QA-F6 | Batch A QA text fixes | Minor | Built (#832); landing B | D-166 |

### 0.16 (Batch B): Funders start, Where Used

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| F-01 | Funder pipeline | Major | Built (#833 to #836); landing B | v0.10 |
| F-02 | Reporting requirements and deadlines | Major | Built (#837); landing B | v0.10 |
| C-59 | Where Used for BarnCRM setup | Major | Built (#823 to #825); landing B | D-156 |
| F-04 | Government award fields | Minor | Built (#839); landing B | v0.10 |
| F-05 | Multi-year award schedules | Minor | Built (#844, #845); landing B | v0.10 |
| F-06 | Funder report merge template | Minor | Built (#848); landing B | v0.10 |
| F-07 | Board dashboard | Minor | Built (#850); landing B | v0.10 |
| F-14 | Answer and boilerplate library | Minor | Built (#841); landing B | D-156 |

### 0.17 (Batch B): Funders complete, Nonprofit Cloud mirror, Field Access Manager

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| F-03 | Restricted fund tracking | Major | Built (#844, #847); landing B | v0.10 |
| X-07 | Gift Transaction mirror | Major | Built (#818, #822, #826, #830, #838); landing B | Plan 6.3 |
| C-65 | Field Access Manager (reverses the D-13 permission-management non-goal; ADR first) | Major | Built (#815 to #817); landing B | D-157 |
| F-08 | Deadline calendar view | Minor | Built (#849); landing B | v0.10 |
| L-06 | Link outcomes to grant deliverables | Minor | Built (#846); landing B | v0.10 |
| X-05 | NPSP coexistence: adopt household accounts | Minor | Built (#812, #813, #819); landing B | Plan 6.3 |
| C-57 | Picklist value usage | Minor | Built (#809); landing B | D-156 |
| C-58 | Technical debt checks | Minor | Built (#810); landing B | D-156 |
| C-60 | Automation inventory in the Data Dictionary; own Automation tab, whole-org inventory and scan, deactivate org flows and validation rules with snapshot and Restore (D-184, ADR-0174) | Minor | Landed (#821, #979) | D-156, D-184 |

### 0.18 (Batch B): Usability and visual polish, architect-review fixes (v1.0 candidate)

Added 2026-11-04 (D-170). v1.0 is everything through the last Batch B release. Every usability and visual finding is built here before any testing cycle (D-167, D-170); drag and drop is added to the existing control, never replaces it. Rollout order (Brandon, 2026-11-04): Core first, finished, tested and deployed to `mwdbdevsb`, then universal modules (Rollup Builder, Mirror, Connect), then nonprofit modules.

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| UX-V1 | Shared visual kit: status badge, notice, stat tile formats, progress meter, icon registry, visual standard in ux-kit.md | Major | Built (#856, #860); landing B | D-170 |
| UX-V2 | Usability fixes: admin and data tools | Major | In progress (merged #862, #863, #866, #869, #870, #877, #885, #889 to #892); landing B | D-170 |
| UX-V3 | Usability fixes: people, households and Giving | Major | In progress (people and Fundraising Home merged: #861, #864, #872, #873, #882; Giving workstreams and #879, #880 on hold) | D-170 |
| UX-V4 | Usability fixes: Volunteers, Programs, Logic Models, Funders (absorbs UX-F4) | Major | In progress (Logic Models merged: #883, #884; the rest on hold) | D-170 |
| UX-V5 | Record page tabs suite-wide | Minor | In progress | D-170 |
| UX-V6 | App logos for Programs, Funders and Logic Models; Fundraising badge recolored; brand color #007A9E | Minor | Built (#854, #855); landing B | D-170 |
| UX-V7 | Drag and drop on existing controls | Minor | In progress (c/barnDrag #860; transform steps #862; Find #891; Super Importer #892) | D-170 |
| UX-V8 | Help text in English JSON help catalogs per package, label cap 4,150 | Major | Built (#858, #859); landing B | D-171, D-172 |
| AR-01 | Messages move from labels to the help catalogs (about 2,400 labels after) | Major | Planned | D-172 |
| AR-02 | Install pre-check: edition, Apex room, label room, name collisions | Major | Built (#874 to #876); landing B | D-173 |
| AR-03 | Per-package Apex size budget in CI, plus a character trim pass on Apex | Major | In progress (budget built #874 to #876; trim pass planned) | D-173 |
| AR-04 | Install guide | Minor | Built (#874 to #876); landing B | D-173 |
| AR-05 | Purge defaults for Merge Journal, Setting Change, Import Batch and Journal, Field Utilization Snapshot | Minor | In progress (record retention defaults and Record Cleanup, #897) | D-173 |
| AR-06 | A per-release destructive manifest | Minor | Built (#874 to #876); landing B | D-173 |
| AR-07 | One nightly job dispatcher plus the hourly check | Major | Built (#894, #895, #897, #898); landing B | D-173 |
| AR-08 | BarnCRM Automation Control hierarchy custom setting; own flows on the Automation page | Major | Built (#887, #893, #896); landing B | D-173, D-174 |
| AR-09 | Trigger dispatcher errors only the affected record | Minor | Built (#868); landing B | D-173 |
| AR-10 | Household Upkeep blocked while NPSP households are in use | Minor | Built (#888); landing B | D-173 |
| AR-11 | Test hardening against org validation rules | Minor | Built (#874 to #876); landing B | D-173 |
| AR-12 | A `without sharing` register | Minor | Built (#874 to #876); landing B | D-173 |
| C-57b | Picklist value usage on large objects: grouped COUNT per value, Last Used in 20,000-record chunks, up to 1,000,000 records | Minor | Built (#853); landing B | D-170 |

### 1.1 (Batch C): Forms engine, Contact Point Sync

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-42a | Forms engine and builder (Forms module; ADR first) | Major | Landed (#1026) | D-157 |
| C-42b | Public forms on a Salesforce Site (guest-user security design; ADR first) | Major | Landed (#1026) | D-157 |
| C-45 | Contact Point Sync module (ADR first), incl. person accounts and household-move re-sync (D-186) | Major | Landed (#1026) | D-111 |
| C-42c | Forms: file upload, save and resume | Minor | Landed (#1026) | D-157 |
| C-61 | Duplicate Rules Starter | Minor | Landed (#1026) | D-156 |
| C-63 | Report subscription setup (feasibility check first) | Minor | Landed (#1026) | D-156 |
| C-69 | Radius Find | Minor | Landed (#1026) | D-157 |
| V-10b | Volunteer shift reminders: "still need you" nudge for unfilled shifts (split from V-10) | Minor | Landed (#1026) | D-165 |
| UX-F4 | Module UX kit pass: Programs, Giving, Volunteers and Logic Models pages (absorbed into UX-V1 and UX-V4, release 0.18, D-170) | Minor | Absorbed into UX-V1 and UX-V4 (D-170) | D-165 |

### 1.2 (Batch C): Event Management core

Moved up from the old 1.11 (Brandon, 2026-11-04, D-177): Events reuse the Forms engine right after it ships in 1.1.

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| EV-01 | Events (ADR first) | Major | Landed (#1026) | D-123 |
| EV-02 | Registrations and attendees on the Forms engine | Major | Landed (#1026) | D-123 |
| EV-04 | Tracks, sessions and agenda | Major | Landed (#1026) | D-123 |
| EV-03 | Ticket types | Minor | Landed (#1026) | D-123 |
| EV-05 | Speakers | Minor | Landed (#1026) | D-123 |
| EV-08 | Volunteer integration | Minor | Landed (#1026) | D-123 |
| EV-10 | Summit Events compatibility | Minor | Landed (#1026) | D-123 |
| EV-14 | Event reminders and No-Show status | Minor | Landed (#1026) | D-156 |
| EV-16 | Public event pages and online registration on a Salesforce Site, through the Forms public path (C-42b); no payments | Major | Landed (#1026) | D-186 |
| EV-19 | Event calendar: month and list views with filters | Minor | Landed (#1026) | D-186 |

CH-17 moved to release 1.10 with the board roster it generalizes (CH-09) (Brandon, 2026-11-07, D-186). EV-16 and EV-19 added to Batch C (Brandon asked for more Event Management in Batch C, D-186).

### 1.3 (Batch C): Event Management complete and Portal Builder

The Event items of the old 1.12, moved up with 1.2 (D-177). Portal Builder (PB-01) and the portal templates whose data already exists (PB-03, PB-07, PB-08) join them (Brandon, 2026-11-04, D-178). PB-01 starts only after the plan 11.2 item 30 terms check confirms option B; if it does not, the Portal Builder items are re-slotted. PB-02 (1.11), CH-18 and CH-19 (1.14), PB-09 (1.11), PB-06 (1.12) stay with their modules.

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| EV-06 | Call for speakers | Major | Landed (#1026) | D-123 |
| EV-09 | Sponsorship management | Major | Landed (#1026) | D-123 |
| EV-12 | QR check-in | Major | Landed (#1026) | D-156 |
| PB-01 | Portal Builder (ADR first): off-platform portal through one connecting user and a person-scoped API (D-187) | Major | Landed (#1026) | D-118, D-120, D-178, D-187 |
| EV-13 | Gala tables and seating (moved up from 1.13, D-186) | Major | Landed (#1026) | D-156, D-186 |
| EV-17 | Name badges and sign-in sheets | Minor | Landed (#1026) | D-186 |
| EV-18 | Post-event survey and follow-up | Minor | Landed (#1026) | D-186 |
| EV-11 | Event dashboard and conference template | Minor | Landed (#1026) | D-123 |
| EV-15 | Event appointments with hosts | Minor | Landed (#1026) | D-156 |
| PB-03 | Volunteer portal template (moved earlier) | Minor | Landed (#1026) | D-118, D-157, D-178 |
| PB-07 | Speaker portal template (EV-07) | Minor | Landed (#1026) | D-123, D-178 |
| PB-08 | Donor portal template | Minor | Landed (#1026) | D-156, D-178 |

### 1.4 (Batch D): Migration Assistant, volunteer self-service

C-46 Address Verification moved to release 1.15 (Brandon, 2026-11-04, D-177).

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| MIG-01 | Migration Assistant framework (plan 11.2 item 32 decisions first) | Major | Planned | D-125 |
| V-09 | Public volunteer sign-up on the Forms engine | Major | Planned | D-157 |
| MIG-10 | Integrations page: detected apps and migration links | Minor | Planned | D-125 |
| MIG-06 | Stripe receiver (X-08) and Zapier recipes | Minor | Planned | D-125 |
| MIG-08 | DLRS and NPSP rollups into Rollup Builder | Minor | Planned | D-125 |
| V-12 | Volunteer value rate | Minor | Planned | D-156 |
| V-13 | Volunteer recognition and milestones | Minor | Planned | D-156 |
| G-35 | Giving setup tabs move to Admin_Tabs | Minor | Planned | D-165 |

### 1.5 (Batch D): Recurring donor health, engagement score, Giving minors

G-34 online donation page moved to release 1.15 with C-46 (D-177), as did G-21 and G-31. G-27 stays here, after MIG-06 in 1.4.

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| G-27 | Recurring donor health | Major | Planned | D-156 |
| C-64 | Engagement score | Major | Planned | D-157 |
| G-32 | Wealth data fields and import template | Minor | Planned | D-156 |
| G-33 | Quick Gift Entry donor panel | Minor | Planned | D-156 |
| G-36 | One staff-facing word for Pledge versus Commitment (needs Brandon) | Minor | Planned | D-165 |
| G-37 | Pledge reminders on the GivingScheduler Nightly Jobs path (needs Brandon) | Minor | Planned | D-165 |

### 1.6 (Batch D): Archive, generic merge, field history, Volunteers minors

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-67 | Archive by Query (uses shipped tools; defines the file format Backup Sets reuse) | Major | Planned | D-157 |
| C-62 | Generic Record Merge | Major | Planned | D-156 |
| C-68 | Field History Keeper | Major | Planned | D-157 |
| V-14 | Shift minimum, maximum and waitlist | Minor | Planned | D-156 |
| V-15 | Minor volunteers and guardian consent | Minor | Planned | D-156 |
| V-16 | Group and standing sign-ups | Minor | Planned | D-156 |
| V-17 | Background check details on onboarding | Minor | Planned | D-156 |
| P-09 | Waitlists and capacity | Minor | Planned | Plan 5.4 |
| C-71 | Fold the remaining inline AuraHandledException blocks into UserErrors | Minor | Planned | D-165 |

### 1.7 (Batch E): Corporate Hub, documents and compliance

C-46 Address Verification is not a prerequisite (D-178): hub addresses are unverified until C-46 ships in 1.15.

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| CH-01 | Document and policy library (ADR first) | Major | Planned | D-118 |
| CH-03 | Compliance calendar | Major | Planned | D-118 |
| CH-04 | Shipped compliance templates | Major | Planned | D-118 |
| CH-02 | Policy acknowledgments | Minor | Planned | D-118 |
| CH-06 | Extra templates | Minor | Planned | D-118 |
| CH-07 | Required-policies set | Minor | Planned | D-118 |
| CH-08 | Contracts and renewals | Minor | Planned | D-118 |

### 1.8 (Batch E): Memberships, GDPR

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| G-22a | Memberships module: types, tiers, members (ADR first) | Major | Planned | D-157 |
| G-22b | Memberships: renewals, reminders, lapse handling | Major | Planned | D-157 |
| CH-05 | GDPR template set | Major | Planned | D-118 |
| G-22c | Memberships: benefits per tier | Minor | Planned | D-157 |
| G-22d | Memberships Essentials compatibility | Minor | Planned | D-157 |
| MIG-03 | V4S to Volunteers adapter | Minor | Planned | D-125 |

### 1.9 (Batch E): Migrations

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| MIG-02 | NPC Party Relationship Groups to households | Major | Planned | D-125 |
| MIG-04 | NPC gifts to Giving | Major | Planned | D-125 |
| MIG-05 | NPSP migration kit, with a Levels, Engagement Plans and rollups parity report | Major | Planned | D-125, D-156 |
| MIG-09 | PMM to Programs | Minor | Planned | D-125 |
| MIG-07 | DonorPerfect, Bloomerang, Little Green Light templates, then Neon, CiviCRM, Raiser's Edge NXT | Minor | Planned | D-125 |
| L-05 | Evidence log | Minor | Planned | Plan 5.7 |

### 1.10 (Batch F): Board governance

Portal Builder (PB-01) moved to release 1.3 (D-178); the board portal template (PB-02) follows in 1.11. CH-17 moved here from 1.2 with the board roster it generalizes (CH-09) (Brandon, 2026-11-07, D-186).

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| CH-09 | Board governance | Major | Planned | D-118 |
| CH-10 | Board meetings | Major | Planned | D-118 |
| CH-11 | Motions, votes and resolutions | Minor | Planned | D-118 |
| CH-12 | Conflict-of-interest disclosures | Minor | Planned | D-118 |
| CH-13 | Board giving participation | Minor | Planned | D-118 |
| CH-14 | Board dashboard | Minor | Planned | D-118 |
| CH-15 | Board skills and diversity matrix | Minor | Planned | D-156 |
| CH-16 | Meeting action items | Minor | Planned | D-156 |
| CH-17 | Committees and working groups (moved from 1.2, D-186) | Minor | Planned | D-156, D-186 |

### 1.11 (Batch F): Board and member portals, grant management

PB-03 moved to release 1.3 (D-178). PB-02 needs Portal Builder (1.3) and board governance (1.10); PB-09 needs Portal Builder (1.3) and Memberships (1.8).

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| PB-02 | Board portal template | Major | Planned | D-118 |
| F-09 | Grant Finder | Major | Planned | D-121 |
| PB-09 | Member directory portal template | Minor | Planned | D-157 |
| F-10 | Application tasks and checklists | Minor | Planned | D-121 |
| F-11 | Document tracking | Minor | Planned | D-121 |
| F-12 | Budget versus awarded | Minor | Planned | D-121 |
| F-13 | Renewals | Minor | Planned | D-121 |

### 1.12 (Batch F): Scholarships and Outbound Grants

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| SG-01 | Programs and cycles (ADR first) | Major | Planned | D-122 |
| SG-02 | Applications on the Forms engine | Major | Planned | D-122 |
| SG-03 | Reviewers and scoring | Major | Planned | D-122 |
| SG-04 | Awards | Minor | Planned | D-122 |
| SG-05 | Disbursements | Minor | Planned | D-122 |
| SG-06 | Recipient reporting | Minor | Planned | D-122 |
| SG-08 | Grantmaking dashboard | Minor | Planned | D-122 |
| PB-06 | Applicant portal template (SG-07) | Minor | Planned | D-122 |
| SG-09 | Conditional disbursements | Minor | Planned | D-156 |

### 1.13 (Batch G): Gala seating, multi-brand management, portal templates

PB-07 and PB-08 moved to release 1.3 (D-178). PB-04 and PB-05 need Portal Builder (1.3) and their data modules.

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-47a | Brand and Legal Entity records, many-to-many assignment | Major | Planned | D-119, D-120 |
| C-47b | Brand-aware outputs | Major | Planned | D-119, D-120 |
| PB-04 | Service portal template | Minor | Planned | D-118 |
| PB-05 | Partner portal template | Minor | Planned | D-118 |
| SG-10 | Reviewer panels and load balancing | Minor | Planned | D-156 |

### 1.14 (Batch G): Brand visibility, LWC Builder start, board portal follow-ups

CH-18 and CH-19 came from the old 1.12 (D-177): they need the board portal (PB-02, 1.11) and stay with the portal releases.

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-47c | Brand-restricted visibility (optional; ADR first) | Major | Planned | D-120 |
| LB-01 | Grid canvas builder (ADR first) | Major | Planned | D-120 |
| LB-02 | Runtime renderer | Major | Planned | D-120 |
| C-47d | Brand lookup in modules, Bulk Update and import mapping | Minor | Planned | D-119 |
| C-47e | Brand filters on list views, reports and dashboards | Minor | Planned | D-119 |
| C-47f | Receipt numbering per brand | Minor | Planned | D-119 |
| CH-18 | Board packet read tracking | Minor | Planned | D-156 |
| CH-19 | Board self-assessment | Minor | Planned | D-156 |

### 1.15 (Batch G): Address Verification, online donations

Moved later by Brandon (2026-11-04, D-177). G-34 still needs MIG-06 (1.4) and the Forms engine (1.1); G-27 stays in 1.5. G-21 and G-31 came from the old 1.3. C-46 is no longer a prerequisite of Corporate Hub or Portal Builder (D-178), so their addresses are unverified until it ships here.

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-46 | Address Verification module (ADR first) | Major | Planned | D-112 |
| G-34 | Online donation page handing off to the org's own Stripe or PayPal checkout | Major | Planned | D-157 |
| G-21 | Stock and planned gift types | Minor | Planned | Plan 5.2 |
| G-31 | Donor-advised fund and gift-source fields | Minor | Planned | D-156 |

### 1.16 (Batch H): LWC Builder complete, Territory Management, Grid tool

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| LB-03 | Building blocks | Major | Planned | D-120 |
| C-40 | Territory Management module (ADR first) | Major | Planned | D-98, D-120 |
| C-41 | Grid tool | Major | Planned | D-98 |
| LB-04 | Quick action and flow buttons | Minor | Planned | D-120 |
| LB-05 | Conditional visibility per block | Minor | Planned | D-120 |
| LB-06 | Export as LWC source | Minor | Planned | D-120 |
| C-41b | Saved grids | Minor | Planned | D-98 |
| C-40b | Round-robin and capacity routing | Minor | Planned | D-156 |

### 1.17 (Batch H): Backup Sets and files import (late by Brandon's direction)

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-66 | Backup Sets (on demand; scheduled runs wait for C-38; ADR first) | Major | Planned | D-157 |
| C-70 | Import files and attachments (ADR first) | Major | Planned | D-157 |
| G-22e | Memberships: certifications and continuing credits | Minor | Planned | D-157 |
| CH-20 | Meeting availability poll | Minor | Planned | D-156 |
| MIG-11 | Outbound Funds importer (only when installed) | Minor | Planned | D-156 |

### 1.18 (Batch I): Project Management module (later by Brandon's direction)

Brandon (2026-11-04, D-175): a PM module that handles projects in various ways, including Salesforce implementation projects, perhaps a PSA tool. A universal module (both editions proposed), so it follows the Core, universal, nonprofit order (D-38). The item list is provisional until the spec is written.

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| PM-01 | Module spec (Section 5) and ADR: project types, canonical model entries, whether it grows into a PSA tool | Major | Planned | D-175 |
| PM-02 | Projects, phases or milestones, and tasks with owners, dates, status and a progress view; any Account or Contact as client or stakeholder | Major | Planned | D-175 |
| PM-03 | Project templates, starting with a Salesforce implementation template | Major | Planned | D-175 |
| PM-04 | PSA layer, if the spec keeps it: time entries, resource assignment and utilization, budgets against actuals; billing only where it stays free of payment processing | Minor | Planned | D-175 |
| PM-05 | Project status report and a home card of open projects at risk | Minor | Planned | D-175 |

## Held

- C-38 scheduled imports and connections: on hold until Brandon starts it (D-39). The Google Sheets source for Super Importer and scheduled Backup Sets runs wait with it.

## Milestones and blocked

| ID | Milestone | Blocked on | Attaches to |
|---|---|---|---|
| M-0 | Device mobile run; 250,000-row scale run in a tier 2 sandbox (D-90) | A device; a tier 2 sandbox | Before M-1 |
| M-1 | v1.0: tagged once Brandon's initial QA is complete (in progress); expected around or after 0.18, before AppExchange approval | Brandon's initial QA | Around or after Batch B |
| M-2 | Namespace, Dev Hub, steward entity, first package versions; Volunteers install-link testing | M-1 (D-87) | After M-1 |
| M-3 | Beta cohort (was iteration v0.12) | M-2 | A 1.x batch |
| M-4 | Security review submission and AppExchange listing (was iteration v0.13; no AppExchange for now, D-24) | M-2, Brandon's go-ahead | A 1.x batch |

Open QA from batch 9: browser UX testing of the batch 8 screens (needs a browser tool); `mwdbdevsb` Error Log probe (awaiting Brandon's approval).

## Not approved (in no release)

Plan 6.1.1 item 6 (document builder); BarnCRM for WordPress as an edition (portability is a design preference meanwhile, plan 9.9); community processor webhooks (X-08) beyond the Stripe receiver; donor scoring maturity beyond G-19, G-26, G-29 and C-64; multi-currency; localization. The eleven plan 6.1.5 proposals were approved 2026-10-31 (D-157) and are placed above.

## Shipped iterations (history)

| Iteration | Theme | Status |
|---|---|---|
| v0.1 to v0.7 | Foundation, Giving, commitments, stewardship, import 2.0, Mirror, data management | Shipped |
| v0.8 | Volunteers (V-01 to V-08, C-24, C-30) | Built and tested unmanaged; install-link testing in M-2 |
| v0.9, v0.10 | Programs and Logic Models; Funders and NPC mirror | C-39 landed; the rest now in releases 0.12 to 0.18 |
| v0.11 | Hardening | Shipped 2026-10-29 (release gate on cbf35753; `barn-npc` and `mwdbdevsb` deployed); device mobile run in M-0 |
| v0.12, v0.13 | Beta, AppExchange | Superseded by milestones M-3 and M-4 (D-155) |

Since v0.11: batch 8 (#753, C-49 to C-52 Super Importer, Super Transform, Advanced Duplicate Management, Data Dictionary) and batch 9 (#758, QA v21 fixes) landed.
