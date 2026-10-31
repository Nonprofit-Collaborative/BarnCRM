# Roadmap

Purpose: planned work with status, by release. Mirrors Section 6 (6.0a release plan, 6.1.5 competitive research) of the BMemory plan `specification/open-impact-product-plan.md`, which is canonical: change BMemory first, then this file and `docs/product-plan.md`. Feature status detail lives in `docs/barncrm-features.md`.

Status as of 2026-10-31: landing batch A (releases 0.12 to 0.14) landed in `main` (status Landed until the batch's release gate, deploys and QA are done); last shipped version 0.11; release plan adopted (D-155); competitive research added 48 features (D-156); the eleven research proposals approved and placed, v1.0 after Brandon's initial QA (D-157). History: `changelog.md` (newest first) and this file's earlier versions in git (`git log -p -- roadmap.md`; the last iteration-based version is at ef92381b).

## Rules (D-155 to D-157, plan 9.7 to 9.9)

- Each release: about 3 major and 3 to 6 minor enhancements. Each landing batch: 2 or 3 releases.
- Per batch: incremental gates on the landing branch; the whole-solution review (plan 9.8); then the release gate (`--release` on `barn-sales` and `oi-test`), `barn-npc` and `mwdbdevsb` deploys (Brandon's approval for each `mwdbdevsb` deploy), QA and UX. Each release ships its What's New record.
- Upkeep is automatic: new approvals are placed in a release; a move up or back that Brandon asks for is re-slotted and the affected releases rebalanced; statuses update as batches land.
- New features consistent with the vision may be added without Brandon's approval (D-156); new modules or editions, reversals of settled decisions or non-goals, and not-approved items go to him as proposals.
- New work follows the portability preferences toward BarnCRM for WordPress (plan 9.9) where they cost little.
- Status values: Planned, In progress, Landed (in `main`), Shipped (batch gate, deploys and QA done).
- Release 0.17 is the v1.0 candidate. v1.0 is tagged once Brandon's initial QA is complete, expected around or after 0.17 and before AppExchange approval (M-1, D-157). Later releases are 1.1 onward.

## Batches

| Batch | Releases | Theme |
|---|---|---|
| A | 0.12, 0.13, 0.14 | Access Explorer, admin visibility and Core follow-ups; Programs, solicitation pipeline, Logic Models, volunteer reminders |
| B | 0.15, 0.16, 0.17 | Programs depth, Logic Models and Funders complete, Nonprofit Cloud mirror, Field Access Manager; v1.0 candidate |
| C | 1.1, 1.2, 1.3 | Forms engine, Contact Point Sync, Address Verification, Migration Assistant, volunteer self-service, online donations, recurring donor health, engagement score |
| D | 1.4, 1.5, 1.6 | Archive by Query, generic merge, field history, Corporate Hub documents and compliance, Memberships, GDPR |
| E | 1.7, 1.8, 1.9 | Migrations, board governance, Portal Builder, board, volunteer and member portals, grant management |
| F | 1.10, 1.11, 1.12 | Scholarships and Outbound Grants, Event Management |
| G | 1.13, 1.14 | Gala seating, multi-brand management, LWC Builder start |
| H | 1.15, 1.16 | LWC Builder complete, Territory Management, Grid tool; Backup Sets and files import last |

## Releases

### 0.12 (Batch A): Access Explorer, admin visibility, Core follow-ups, Programs start

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-53 | Access Explorer | Major | Landed (batch A) | D-154 |
| C-56 | Setup Changes Log | Major | Landed (batch A) | D-156 |
| P-01 | Program, Service, Enrollment | Major | Landed (batch A) | v0.9 |
| C-50f1 | Super Transform saved step lists | Minor | Landed (batch A) | D-154 |
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
| V-10 | Volunteer shift reminders | Major | Landed (batch A) | D-156 |
| P-04 | Case notes | Minor | Landed (batch A) | v0.9 |
| P-05 | Program dashboard | Minor | Landed (batch A) | v0.9 |
| P-06 | Program roster template through C-49c (V-06 hours template moves to C-49c too) | Minor | Landed (batch A) | v0.9, D-154 |
| P-07 | Intake and eligibility fields | Minor | Landed (batch A) | v0.9 |
| P-08 | Participant privacy sharing preset | Minor | Landed (batch A) | v0.9 |
| V-11 | Suggested volunteers for a shift | Minor | Landed (batch A) | D-156 |

### 0.15 (Batch B): Logic Models complete, Programs depth

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| L-03 | Indicator sources | Major | Planned | v0.9 |
| P-10 | Participant service plans and goals | Major | Planned | D-156 |
| P-11 | Cohorts, sessions and mass enrollment | Major | Planned | D-156 |
| L-04 | Logic model report | Minor | Planned | v0.9 |
| G-19 | Donor scoring (RFM) as rollups | Minor | Planned | v0.9 |
| P-12 | Anonymous and aggregate service counts | Minor | Planned | D-156 |
| P-13 | Referrals in and out | Minor | Planned | D-156 |
| P-14 | Eligibility screening results | Minor | Planned | D-156 |
| UX-F3 | Module tab motifs | Minor | Planned | D-144 |

### 0.16 (Batch B): Funders start, Where Used

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| F-01 | Funder pipeline | Major | Planned | v0.10 |
| F-02 | Reporting requirements and deadlines | Major | Planned | v0.10 |
| C-59 | Where Used for BarnCRM setup | Major | Planned | D-156 |
| F-04 | Government award fields | Minor | Planned | v0.10 |
| F-05 | Multi-year award schedules | Minor | Planned | v0.10 |
| F-06 | Funder report merge template | Minor | Planned | v0.10 |
| F-07 | Board dashboard | Minor | Planned | v0.10 |
| F-14 | Answer and boilerplate library | Minor | Planned | D-156 |

### 0.17 (Batch B): Funders complete, Nonprofit Cloud mirror, Field Access Manager (v1.0 candidate)

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| F-03 | Restricted fund tracking | Major | Planned | v0.10 |
| X-07 | Gift Transaction mirror | Major | Planned | Plan 6.3 |
| C-65 | Field Access Manager (reverses the D-13 permission-management non-goal; ADR first) | Major | Planned | D-157 |
| F-08 | Deadline calendar view | Minor | Planned | v0.10 |
| L-06 | Link outcomes to grant deliverables | Minor | Planned | v0.10 |
| X-05 | NPSP coexistence: adopt household accounts | Minor | Planned | Plan 6.3 |
| C-57 | Picklist value usage | Minor | Planned | D-156 |
| C-58 | Technical debt checks | Minor | Planned | D-156 |
| C-60 | Automation inventory in the Data Dictionary | Minor | Planned | D-156 |

### 1.1 (Batch C): Forms engine, Contact Point Sync

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-42a | Forms engine and builder (Forms module; ADR first) | Major | Planned | D-157 |
| C-42b | Public forms on a Salesforce Site (guest-user security design; ADR first) | Major | Planned | D-157 |
| C-45 | Contact Point Sync module (ADR first) | Major | Planned | D-111 |
| C-42c | Forms: file upload, save and resume | Minor | Planned | D-157 |
| C-61 | Duplicate Rules Starter | Minor | Planned | D-156 |
| C-63 | Report subscription setup (feasibility check first) | Minor | Planned | D-156 |
| C-69 | Radius Find | Minor | Planned | D-157 |
| V-10b | Volunteer shift reminders: "still need you" nudge for unfilled shifts (split from V-10) | Minor | Planned | D-165 |
| UX-F4 | Module UX kit pass: Programs, Giving, Volunteers and Logic Models pages | Minor | Planned | D-165 |

### 1.2 (Batch C): Address Verification, Migration Assistant, volunteer self-service

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-46 | Address Verification module (ADR first) | Major | Planned | D-112 |
| MIG-01 | Migration Assistant framework (plan 11.2 item 32 decisions first) | Major | Planned | D-125 |
| V-09 | Public volunteer sign-up on the Forms engine | Major | Planned | D-157 |
| MIG-10 | Integrations page: detected apps and migration links | Minor | Planned | D-125 |
| MIG-06 | Stripe receiver (X-08) and Zapier recipes | Minor | Planned | D-125 |
| MIG-08 | DLRS and NPSP rollups into Rollup Builder | Minor | Planned | D-125 |
| V-12 | Volunteer value rate | Minor | Planned | D-156 |
| V-13 | Volunteer recognition and milestones | Minor | Planned | D-156 |
| G-35 | Giving setup tabs move to Admin_Tabs | Minor | Planned | D-165 |

### 1.3 (Batch C): Online donations, recurring donor health, engagement score

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| G-34 | Online donation page handing off to the org's own Stripe or PayPal checkout | Major | Planned | D-157 |
| G-27 | Recurring donor health | Major | Planned | D-156 |
| C-64 | Engagement score | Major | Planned | D-157 |
| G-21 | Stock and planned gift types | Minor | Planned | Plan 5.2 |
| G-31 | Donor-advised fund and gift-source fields | Minor | Planned | D-156 |
| G-32 | Wealth data fields and import template | Minor | Planned | D-156 |
| G-33 | Quick Gift Entry donor panel | Minor | Planned | D-156 |
| G-36 | One staff-facing word for Pledge versus Commitment (needs Brandon) | Minor | Planned | D-165 |
| G-37 | Pledge reminders on the GivingScheduler Nightly Jobs path (needs Brandon) | Minor | Planned | D-165 |

### 1.4 (Batch D): Archive, generic merge, field history, Volunteers minors

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

### 1.5 (Batch D): Corporate Hub, documents and compliance

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| CH-01 | Document and policy library (ADR first) | Major | Planned | D-118 |
| CH-03 | Compliance calendar | Major | Planned | D-118 |
| CH-04 | Shipped compliance templates | Major | Planned | D-118 |
| CH-02 | Policy acknowledgments | Minor | Planned | D-118 |
| CH-06 | Extra templates | Minor | Planned | D-118 |
| CH-07 | Required-policies set | Minor | Planned | D-118 |
| CH-08 | Contracts and renewals | Minor | Planned | D-118 |

### 1.6 (Batch D): Memberships, GDPR

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| G-22a | Memberships module: types, tiers, members (ADR first) | Major | Planned | D-157 |
| G-22b | Memberships: renewals, reminders, lapse handling | Major | Planned | D-157 |
| CH-05 | GDPR template set | Major | Planned | D-118 |
| G-22c | Memberships: benefits per tier | Minor | Planned | D-157 |
| G-22d | Memberships Essentials compatibility | Minor | Planned | D-157 |
| MIG-03 | V4S to Volunteers adapter | Minor | Planned | D-125 |

### 1.7 (Batch E): Migrations

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| MIG-02 | NPC Party Relationship Groups to households | Major | Planned | D-125 |
| MIG-04 | NPC gifts to Giving | Major | Planned | D-125 |
| MIG-05 | NPSP migration kit, with a Levels, Engagement Plans and rollups parity report | Major | Planned | D-125, D-156 |
| MIG-09 | PMM to Programs | Minor | Planned | D-125 |
| MIG-07 | DonorPerfect, Bloomerang, Little Green Light templates, then Neon, CiviCRM, Raiser's Edge NXT | Minor | Planned | D-125 |
| L-05 | Evidence log | Minor | Planned | Plan 5.7 |

### 1.8 (Batch E): Board governance and Portal Builder

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| CH-09 | Board governance | Major | Planned | D-118 |
| CH-10 | Board meetings | Major | Planned | D-118 |
| PB-01 | Portal Builder (ADR first) | Major | Planned (blocked: plan 11.2 item 30 terms check) | D-118, D-120 |
| CH-11 | Motions, votes and resolutions | Minor | Planned | D-118 |
| CH-12 | Conflict-of-interest disclosures | Minor | Planned | D-118 |
| CH-13 | Board giving participation | Minor | Planned | D-118 |
| CH-14 | Board dashboard | Minor | Planned | D-118 |
| CH-15 | Board skills and diversity matrix | Minor | Planned | D-156 |
| CH-16 | Meeting action items | Minor | Planned | D-156 |

### 1.9 (Batch E): Board, volunteer and member portals, grant management

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| PB-02 | Board portal template | Major | Planned | D-118 |
| F-09 | Grant Finder | Major | Planned | D-121 |
| PB-03 | Volunteer portal template (moved earlier) | Minor | Planned | D-118, D-157 |
| PB-09 | Member directory portal template | Minor | Planned | D-157 |
| F-10 | Application tasks and checklists | Minor | Planned | D-121 |
| F-11 | Document tracking | Minor | Planned | D-121 |
| F-12 | Budget versus awarded | Minor | Planned | D-121 |
| F-13 | Renewals | Minor | Planned | D-121 |

### 1.10 (Batch F): Scholarships and Outbound Grants

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

### 1.11 (Batch F): Event Management core

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| EV-01 | Events (ADR first) | Major | Planned | D-123 |
| EV-02 | Registrations and attendees on the Forms engine | Major | Planned | D-123 |
| EV-04 | Tracks, sessions and agenda | Major | Planned | D-123 |
| EV-03 | Ticket types | Minor | Planned | D-123 |
| EV-05 | Speakers | Minor | Planned | D-123 |
| EV-08 | Volunteer integration | Minor | Planned | D-123 |
| EV-10 | Summit Events compatibility | Minor | Planned | D-123 |
| EV-14 | Event reminders and No-Show status | Minor | Planned | D-156 |
| CH-17 | Committees and working groups | Minor | Planned | D-156 |

### 1.12 (Batch F): Event Management complete, check-in, donor portal

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| EV-06 | Call for speakers | Major | Planned | D-123 |
| EV-09 | Sponsorship management | Major | Planned | D-123 |
| EV-12 | QR check-in | Major | Planned | D-156 |
| EV-11 | Event dashboard and conference template | Minor | Planned | D-123 |
| PB-07 | Speaker portal template (EV-07) | Minor | Planned | D-123 |
| EV-15 | Event appointments with hosts | Minor | Planned | D-156 |
| PB-08 | Donor portal template | Minor | Planned | D-156 |
| CH-18 | Board packet read tracking | Minor | Planned | D-156 |
| CH-19 | Board self-assessment | Minor | Planned | D-156 |

### 1.13 (Batch G): Gala seating, multi-brand management

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| EV-13 | Gala tables and seating | Major | Planned | D-156 |
| C-47a | Brand and Legal Entity records, many-to-many assignment | Major | Planned | D-119, D-120 |
| C-47b | Brand-aware outputs | Major | Planned | D-119, D-120 |
| PB-04 | Service portal template | Minor | Planned | D-118 |
| PB-05 | Partner portal template | Minor | Planned | D-118 |
| SG-10 | Reviewer panels and load balancing | Minor | Planned | D-156 |

### 1.14 (Batch G): Brand visibility and LWC Builder start

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-47c | Brand-restricted visibility (optional; ADR first) | Major | Planned | D-120 |
| LB-01 | Grid canvas builder (ADR first) | Major | Planned | D-120 |
| LB-02 | Runtime renderer | Major | Planned | D-120 |
| C-47d | Brand lookup in modules, Bulk Update and import mapping | Minor | Planned | D-119 |
| C-47e | Brand filters on list views, reports and dashboards | Minor | Planned | D-119 |
| C-47f | Receipt numbering per brand | Minor | Planned | D-119 |

### 1.15 (Batch H): LWC Builder complete, Territory Management, Grid tool

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

### 1.16 (Batch H): Backup Sets and files import (late by Brandon's direction)

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-66 | Backup Sets (on demand; scheduled runs wait for C-38; ADR first) | Major | Planned | D-157 |
| C-70 | Import files and attachments (ADR first) | Major | Planned | D-157 |
| G-22e | Memberships: certifications and continuing credits | Minor | Planned | D-157 |
| CH-20 | Meeting availability poll | Minor | Planned | D-156 |
| MIG-11 | Outbound Funds importer (only when installed) | Minor | Planned | D-156 |

## Held

- C-38 scheduled imports and connections: on hold until Brandon starts it (D-39). The Google Sheets source for Super Importer and scheduled Backup Sets runs wait with it.

## Milestones and blocked

| ID | Milestone | Blocked on | Attaches to |
|---|---|---|---|
| M-0 | Device mobile run; 250,000-row scale run in a tier 2 sandbox (D-90) | A device; a tier 2 sandbox | Before M-1 |
| M-1 | v1.0: tagged once Brandon's initial QA is complete (in progress); expected around or after 0.17, before AppExchange approval | Brandon's initial QA | Around or after Batch B |
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
| v0.9, v0.10 | Programs and Logic Models; Funders and NPC mirror | C-39 landed; the rest now in releases 0.12 to 0.17 |
| v0.11 | Hardening | Shipped 2026-10-29 (release gate on cbf35753; `barn-npc` and `mwdbdevsb` deployed); device mobile run in M-0 |
| v0.12, v0.13 | Beta, AppExchange | Superseded by milestones M-3 and M-4 (D-155) |

Since v0.11: batch 8 (#753, C-49 to C-52 Super Importer, Super Transform, Advanced Duplicate Management, Data Dictionary) and batch 9 (#758, QA v21 fixes) landed.
