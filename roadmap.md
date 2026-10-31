# Roadmap

Purpose: planned work with status, by release. Mirrors Section 6 (6.0a release plan, 6.1.5 competitive research) of the BMemory plan `specification/open-impact-product-plan.md`, which is canonical: change BMemory first, then this file and `docs/product-plan.md`. Feature status detail lives in `docs/barncrm-features.md`.

Status as of 2026-10-31: main at ef92381b; last shipped version 0.11; release plan adopted (D-155); competitive research added 48 features (D-156). History: `changelog.md` (newest first) and this file's earlier versions in git (`git log -p -- roadmap.md`; the last iteration-based version is at ef92381b).

## Rules (D-155, D-156, plan 9.7)

- Each release: about 3 major and 3 to 6 minor enhancements. Each landing batch: 2 or 3 releases.
- Per batch: incremental gates on the landing branch; then the release gate (`--release` on `barn-sales` and `oi-test`), `barn-npc` and `mwdbdevsb` deploys (Brandon's approval for each `mwdbdevsb` deploy), QA and UX. Each release ships its What's New record.
- Upkeep is automatic: new approvals are placed in a release; a move up or back that Brandon asks for is re-slotted and the affected releases rebalanced; statuses update as batches land.
- New features consistent with the vision may be added without Brandon's approval (D-156); new modules or editions, reversals of settled decisions or non-goals, and not-approved items go to him as proposals.
- Status values: Planned, In progress, Landed (in `main`), Shipped (batch gate, deploys and QA done).
- Release 0.17 completes the v1.0 scope; it is tagged v1.0 when the pilot (M-1) passes. Later releases are 1.1 onward.

## Batches

| Batch | Releases | Theme |
|---|---|---|
| A | 0.12, 0.13, 0.14 | Access Explorer, admin visibility and Core follow-ups; Programs, solicitation pipeline, Logic Models, volunteer reminders |
| B | 0.15, 0.16, 0.17 | Programs depth, Logic Models and Funders complete, Nonprofit Cloud mirror; v1.0 candidate |
| C | 1.1, 1.2, 1.3 | Contact Point Sync, Address Verification, Migration Assistant, recurring donor health, generic merge, Corporate Hub |
| D | 1.4, 1.5, 1.6 | Board governance, migrations, Portal Builder and Board portal, grant management |
| E | 1.7, 1.8, 1.9 | Scholarships and Outbound Grants, Event Management |
| F | 1.10, 1.11, 1.12 | Gala seating, multi-brand management, LWC Builder, Territory Management, Grid tool |

## Releases

### 0.12 (Batch A): Access Explorer, admin visibility, Core follow-ups, Programs start

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-53 | Access Explorer | Major | In progress | D-154 |
| C-56 | Setup Changes Log | Major | Planned | D-156 |
| P-01 | Program, Service, Enrollment | Major | Planned | v0.9 |
| C-50f1 | Super Transform saved step lists | Minor | Planned | D-154 |
| C-50f2 | Phone format preset with a digit-format step | Minor | Planned | D-154 |
| C-54 | Weekly Admin Digest | Minor | Planned | D-156 |
| C-55 | Record Inspector | Minor | Planned | D-156 |
| C-49f1 | Import R5: Affiliation and Relationship templates, after an org check | Minor | Planned | D-136 |
| QA-F1 | Platform-only coverage check before the next client deploy | Minor | Planned | Plan 11.3 item 10 |

### 0.13 (Batch A): Programs attendance, solicitation pipeline, AI readiness

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| P-02 | Attendance and service delivery logging | Major | Planned | v0.9 |
| G-26 | Solicitation pipeline (Opportunity-free asks) | Major | Planned | D-156 |
| AIR-01 | AI-Readiness Export | Major | Planned | D-154 |
| UX-F1 | Trim about 200 labels of 20 or more words | Minor | Planned | D-140 |
| UX-F2 | Cosmos contrast check, "Data Hygiene" comments, Data Jobs section on the UX kit | Minor | Planned | D-140 |
| C-53b | Permission compare and Modify All report in Access Explorer | Minor | Planned | D-156 |
| G-28 | Saved donor segments with export | Minor | Planned | D-156 |
| G-29 | Ask cadence reminders | Minor | Planned | D-156 |
| G-30 | Pledge reminders | Minor | Planned | D-156 |

### 0.14 (Batch A): Logic Models start, volunteer reminders, Programs minors

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| L-01 | Logic model builder | Major | Planned | v0.9 |
| L-02 | Indicators on outputs and outcomes | Major | Planned | v0.9 |
| V-10 | Volunteer shift reminders | Major | Planned | D-156 |
| P-04 | Case notes | Minor | Planned | v0.9 |
| P-05 | Program dashboard | Minor | Planned | v0.9 |
| P-06 | Program roster template through C-49c (V-06 hours template moves to C-49c too) | Minor | Planned | v0.9, D-154 |
| P-07 | Intake and eligibility fields | Minor | Planned | v0.9 |
| P-08 | Participant privacy sharing preset | Minor | Planned | v0.9 |
| V-11 | Suggested volunteers for a shift | Minor | Planned | D-156 |

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

### 0.17 (Batch B): Funders complete, Nonprofit Cloud mirror (v1.0 candidate)

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| F-03 | Restricted fund tracking | Major | Planned | v0.10 |
| X-07 | Gift Transaction mirror | Major | Planned | Plan 6.3 |
| F-08 | Deadline calendar view | Minor | Planned | v0.10 |
| L-06 | Link outcomes to grant deliverables | Minor | Planned | v0.10 |
| X-05 | NPSP coexistence: adopt household accounts | Minor | Planned | Plan 6.3 |
| C-57 | Picklist value usage | Minor | Planned | D-156 |
| C-58 | Technical debt checks | Minor | Planned | D-156 |
| C-60 | Automation inventory in the Data Dictionary | Minor | Planned | D-156 |

### 1.1 (Batch C): Contact points, addresses, Migration Assistant

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-45 | Contact Point Sync module (ADR first) | Major | Planned | D-111 |
| C-46 | Address Verification module (ADR first) | Major | Planned | D-112 |
| MIG-01 | Migration Assistant framework (plan 11.2 item 32 decisions first) | Major | Planned | D-125 |
| MIG-10 | Integrations page: detected apps and migration links | Minor | Planned | D-125 |
| MIG-06 | Stripe receiver (X-08) and Zapier recipes | Minor | Planned | D-125 |
| MIG-08 | DLRS and NPSP rollups into Rollup Builder | Minor | Planned | D-125 |
| C-61 | Duplicate Rules Starter | Minor | Planned | D-156 |
| C-63 | Report subscription setup (feasibility check first) | Minor | Planned | D-156 |

### 1.2 (Batch C): Recurring donor health, generic merge, Giving and Volunteers minors

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| G-27 | Recurring donor health | Major | Planned | D-156 |
| C-62 | Generic Record Merge | Major | Planned | D-156 |
| G-21 | Stock and planned gift types | Minor | Planned | Plan 5.2 |
| G-31 | Donor-advised fund and gift-source fields | Minor | Planned | D-156 |
| G-32 | Wealth data fields and import template | Minor | Planned | D-156 |
| G-33 | Quick Gift Entry donor panel | Minor | Planned | D-156 |
| V-12 | Volunteer value rate | Minor | Planned | D-156 |
| V-13 | Volunteer recognition and milestones | Minor | Planned | D-156 |

### 1.3 (Batch C): Corporate Hub, documents and compliance

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| CH-01 | Document and policy library (ADR first) | Major | Planned | D-118 |
| CH-03 | Compliance calendar | Major | Planned | D-118 |
| CH-04 | Shipped compliance templates | Major | Planned | D-118 |
| CH-02 | Policy acknowledgments | Minor | Planned | D-118 |
| CH-06 | Extra templates | Minor | Planned | D-118 |
| CH-07 | Required-policies set | Minor | Planned | D-118 |
| CH-08 | Contracts and renewals | Minor | Planned | D-118 |
| V-14 | Shift minimum, maximum and waitlist | Minor | Planned | D-156 |
| V-15 | Minor volunteers and guardian consent | Minor | Planned | D-156 |

### 1.4 (Batch D): Corporate Hub, GDPR and board governance

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| CH-05 | GDPR template set | Major | Planned | D-118 |
| CH-09 | Board governance | Major | Planned | D-118 |
| CH-10 | Board meetings | Major | Planned | D-118 |
| CH-11 | Motions, votes and resolutions | Minor | Planned | D-118 |
| CH-12 | Conflict-of-interest disclosures | Minor | Planned | D-118 |
| CH-13 | Board giving participation | Minor | Planned | D-118 |
| CH-14 | Board dashboard | Minor | Planned | D-118 |
| CH-15 | Board skills and diversity matrix | Minor | Planned | D-156 |
| CH-16 | Meeting action items | Minor | Planned | D-156 |

### 1.5 (Batch D): Migrations

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| MIG-02 | NPC Party Relationship Groups to households | Major | Planned | D-125 |
| MIG-04 | NPC gifts to Giving | Major | Planned | D-125 |
| MIG-05 | NPSP migration kit, with a Levels, Engagement Plans and rollups parity report | Major | Planned | D-125, D-156 |
| MIG-03 | V4S to Volunteers adapter | Minor | Planned | D-125 |
| MIG-09 | PMM to Programs | Minor | Planned | D-125 |
| MIG-07 | DonorPerfect, Bloomerang, Little Green Light templates, then Neon, CiviCRM, Raiser's Edge NXT | Minor | Planned | D-125 |
| V-16 | Group and standing sign-ups | Minor | Planned | D-156 |
| V-17 | Background check details on onboarding | Minor | Planned | D-156 |
| P-09 | Waitlists and capacity | Minor | Planned | Plan 5.4 |

### 1.6 (Batch D): Portal Builder and grant management

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| PB-01 | Portal Builder (ADR first) | Major | Planned (blocked: plan 11.2 item 30 terms check) | D-118, D-120 |
| PB-02 | Board portal template | Major | Planned | D-118 |
| F-09 | Grant Finder | Major | Planned | D-121 |
| F-10 | Application tasks and checklists | Minor | Planned | D-121 |
| F-11 | Document tracking | Minor | Planned | D-121 |
| F-12 | Budget versus awarded | Minor | Planned | D-121 |
| F-13 | Renewals | Minor | Planned | D-121 |
| CH-17 | Committees and working groups | Minor | Planned | D-156 |
| CH-18 | Board packet read tracking | Minor | Planned | D-156 |

### 1.7 (Batch E): Scholarships and Outbound Grants

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| SG-01 | Programs and cycles (ADR first) | Major | Planned | D-122 |
| SG-02 | Applications | Major | Planned | D-122 |
| SG-03 | Reviewers and scoring | Major | Planned | D-122 |
| SG-04 | Awards | Minor | Planned | D-122 |
| SG-05 | Disbursements | Minor | Planned | D-122 |
| SG-06 | Recipient reporting | Minor | Planned | D-122 |
| SG-08 | Grantmaking dashboard | Minor | Planned | D-122 |
| PB-06 | Applicant portal template (SG-07) | Minor | Planned | D-122 |
| SG-09 | Conditional disbursements | Minor | Planned | D-156 |

### 1.8 (Batch E): Event Management core

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| EV-01 | Events (ADR first) | Major | Planned | D-123 |
| EV-02 | Registrations and attendees | Major | Planned | D-123 |
| EV-04 | Tracks, sessions and agenda | Major | Planned | D-123 |
| EV-03 | Ticket types | Minor | Planned | D-123 |
| EV-05 | Speakers | Minor | Planned | D-123 |
| EV-08 | Volunteer integration | Minor | Planned | D-123 |
| EV-10 | Summit Events compatibility | Minor | Planned | D-123 |
| EV-14 | Event reminders and No-Show status | Minor | Planned | D-156 |

### 1.9 (Batch E): Event Management complete, check-in, donor portal

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| EV-06 | Call for speakers | Major | Planned | D-123 |
| EV-09 | Sponsorship management | Major | Planned | D-123 |
| EV-12 | QR check-in | Major | Planned | D-156 |
| EV-11 | Event dashboard and conference template | Minor | Planned | D-123 |
| PB-07 | Speaker portal template (EV-07) | Minor | Planned | D-123 |
| EV-15 | Event appointments with hosts | Minor | Planned | D-156 |
| PB-08 | Donor portal template | Minor | Planned | D-156 |
| CH-19 | Board self-assessment | Minor | Planned | D-156 |
| CH-20 | Meeting availability poll | Minor | Planned | D-156 |

### 1.10 (Batch F): Gala seating, multi-brand management, portal templates

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| EV-13 | Gala tables and seating | Major | Planned | D-156 |
| C-47a | Brand and Legal Entity records, many-to-many assignment | Major | Planned | D-119, D-120 |
| C-47b | Brand-aware outputs | Major | Planned | D-119, D-120 |
| PB-03 | Volunteer portal template | Minor | Planned | D-118 |
| PB-04 | Service portal template | Minor | Planned | D-118 |
| PB-05 | Partner portal template | Minor | Planned | D-118 |
| SG-10 | Reviewer panels and load balancing | Minor | Planned | D-156 |
| MIG-11 | Outbound Funds importer (only when installed) | Minor | Planned | D-156 |
| L-05 | Evidence log | Minor | Planned | Plan 5.7 |

### 1.11 (Batch F): Brand visibility and LWC Builder start

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-47c | Brand-restricted visibility (optional; ADR first) | Major | Planned | D-120 |
| LB-01 | Grid canvas builder (ADR first) | Major | Planned | D-120 |
| LB-02 | Runtime renderer | Major | Planned | D-120 |
| C-47d | Brand lookup in modules, Bulk Update and import mapping | Minor | Planned | D-119 |
| C-47e | Brand filters on list views, reports and dashboards | Minor | Planned | D-119 |
| C-47f | Receipt numbering per brand | Minor | Planned | D-119 |

### 1.12 (Batch F): LWC Builder complete, Territory Management, Grid tool

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

## Held

- C-38 scheduled imports and connections: on hold until Brandon starts it (D-39). The Google Sheets source for Super Importer waits with it.

## Milestones and blocked

| ID | Milestone | Blocked on | Attaches to |
|---|---|---|---|
| M-0 | Device mobile run; 250,000-row scale run in a tier 2 sandbox (D-90) | A device; a tier 2 sandbox | Before M-1 |
| M-1 | v1.0 pilot of release 0.17; tagged v1.0 when it passes | Pilot org | After Batch B |
| M-2 | Namespace, Dev Hub, steward entity, first package versions; Volunteers install-link testing | M-1 (D-87) | After M-1 |
| M-3 | Beta cohort (was iteration v0.12) | M-2 | A 1.x batch |
| M-4 | Security review submission and AppExchange listing (was iteration v0.13; no AppExchange for now, D-24) | M-2, Brandon's go-ahead | A 1.x batch |

Open QA from batch 9: browser UX testing of the batch 8 screens (needs a browser tool); `mwdbdevsb` Error Log probe (awaiting Brandon's approval).

## Proposals for Brandon (plan 6.1.5; in no release until approved)

| # | Proposal | Needs Brandon because | Impact | Effort |
|---|---|---|---|---|
| 1 | Forms engine first (C-42), reused by V-09, events, applications, portals | C-42 not approved; guest-user design | 5 | XL |
| 2 | Volunteer self-service first (V-09 and PB-03 earlier) | V-09 not approved; guest-user design | 5 | M |
| 3 | Online donation landing handing off to the org's own Stripe or PayPal checkout | Needs C-42 and the X-08 decision (O-5) | 5 | XL |
| 4 | Memberships module (with Memberships Essentials compatibility, member directory, certifications later) | New module (G-22, 6.1.1 item 5) | 4 | L |
| 5 | Engagement score across gifts, hours, events, activity | 6.1.1 item 14 not approved | 4 | M |
| 6 | Field Access Manager | Reverses the permission-management non-goal (D-13) | 4 | M |
| 7 | Backup Sets | 6.1.1 item 17 not approved; schedule needs C-38 | 4 | M |
| 8 | Archive by Query | 6.1.1 item 15 not approved | 4 | M |
| 9 | Field History Keeper | 6.1.1 item 10 not approved | 3 | L |
| 10 | Radius Find | 6.1.1 item 9 not approved | 3 | M |
| 11 | Import files and attachments | Files import not approved (D-50) | 3 | L |

## Not approved (in no release)

Plan 6.1.1 items 5 (Memberships Essentials compatibility), 6 (document builder), 9 (map and radius search), 10 (field history), 14 (engagement score), 15 (archiving), 17 (scheduled backup); Memberships (G-22); Forms (C-42); BarnCRM for WordPress; public volunteer sign-up (V-09); community processor webhooks (X-08) beyond the Stripe receiver; donor scoring maturity beyond G-19, G-26 and G-29; multi-currency; localization.

## Shipped iterations (history)

| Iteration | Theme | Status |
|---|---|---|
| v0.1 to v0.7 | Foundation, Giving, commitments, stewardship, import 2.0, Mirror, data management | Shipped |
| v0.8 | Volunteers (V-01 to V-08, C-24, C-30) | Built and tested unmanaged; install-link testing in M-2 |
| v0.9, v0.10 | Programs and Logic Models; Funders and NPC mirror | C-39 landed; the rest now in releases 0.12 to 0.17 |
| v0.11 | Hardening | Shipped 2026-10-29 (release gate on cbf35753; `barn-npc` and `mwdbdevsb` deployed); device mobile run in M-0 |
| v0.12, v0.13 | Beta, AppExchange | Superseded by milestones M-3 and M-4 (D-155) |

Since v0.11: batch 8 (#753, C-49 to C-52 Super Importer, Super Transform, Advanced Duplicate Management, Data Dictionary) and batch 9 (#758, QA v21 fixes) landed.
