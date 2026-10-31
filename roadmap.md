# Roadmap

Purpose: planned work with status, by release. Mirrors Section 6 (6.0a release plan) of the BMemory plan `specification/open-impact-product-plan.md`, which is canonical: change BMemory first, then this file and `docs/product-plan.md`. Feature status detail lives in `docs/barncrm-features.md`.

Status as of 2026-10-31: main at ef92381b; last shipped version 0.11; release plan adopted (D-155). History: `changelog.md` (newest first) and this file's earlier versions in git (`git log -p -- roadmap.md`; the last iteration-based version is at ef92381b).

## Rules (D-155, plan 9.7)

- Each release: about 3 major and 3 to 6 minor enhancements. Each landing batch: 2 or 3 releases.
- Per batch: incremental gates on the landing branch; then the release gate (`--release` on `barn-sales` and `oi-test`), `barn-npc` and `mwdbdevsb` deploys (Brandon's approval for each `mwdbdevsb` deploy), QA and UX. Each release ships its What's New record.
- Upkeep is automatic: new approvals are placed in a release; a move up or back that Brandon asks for is re-slotted and the affected releases rebalanced; statuses update as batches land.
- Status values: Planned, In progress, Landed (in `main`), Shipped (batch gate, deploys and QA done).
- Release 0.15 completes the v1.0 scope; it is tagged v1.0 when the pilot (M-1) passes. Later releases are 1.1 onward.

## Batches

| Batch | Releases | Theme |
|---|---|---|
| A | 0.12, 0.13 | Access Explorer and Core follow-ups; Programs and Logic Models start |
| B | 0.14, 0.15 | Logic Models and Funders complete; Nonprofit Cloud mirror; v1.0 candidate |
| C | 1.1, 1.2, 1.3 | Contact Point Sync, Address Verification, Migration Assistant, Corporate Hub |
| D | 1.4, 1.5, 1.6 | Migrations, Portal Builder and Board portal, grant management, Scholarships and Outbound Grants |
| E | 1.7, 1.8, 1.9 | Event Management, portal templates, multi-brand management |
| F | 1.10, 1.11 | LWC Builder, Territory Management, Grid tool |

## Releases

### 0.12 (Batch A): Access Explorer, Core follow-ups, Programs start

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| AX-01 | Access Explorer (who can see and edit what, and why) | Major | Planned (next batch) | D-154 |
| P-01 | Program, Service, Enrollment | Major | Planned | v0.9 |
| P-02 | Attendance and service delivery logging | Major | Planned | v0.9 |
| C-50f1 | Super Transform saved step lists | Minor | Planned | D-154 |
| C-50f2 | Phone format preset with a digit-format step | Minor | Planned | D-154 |
| C-49f1 | Import R5: Affiliation and Relationship templates, after an org check | Minor | Planned | D-136 |
| UX-F1 | Trim about 200 labels of 20 or more words | Minor | Planned | D-140 |
| UX-F2 | Cosmos contrast check, "Data Hygiene" comments, Data Jobs section on the UX kit | Minor | Planned | D-140 |
| QA-F1 | Platform-only coverage check before the next client deploy | Minor | Planned | Plan 11.3 item 10 |

### 0.13 (Batch A): Logic Models and AI readiness

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| L-01 | Logic model builder | Major | Planned | v0.9 |
| L-02 | Indicators on outputs and outcomes | Major | Planned | v0.9 |
| AIR-01 | AI-Readiness Export | Major | Planned | D-154 |
| P-04 | Case notes | Minor | Planned | v0.9 |
| P-05 | Program dashboard | Minor | Planned | v0.9 |
| P-06 | Program roster template through C-49c (V-06 hours template moves to C-49c too) | Minor | Planned | v0.9, D-154 |
| P-07 | Intake and eligibility fields | Minor | Planned | v0.9 |
| P-08 | Participant privacy sharing preset | Minor | Planned | v0.9 |

### 0.14 (Batch B): Logic Models complete, Funders start

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| L-03 | Indicator sources | Major | Planned | v0.9 |
| F-01 | Funder pipeline | Major | Planned | v0.10 |
| F-02 | Reporting requirements and deadlines | Major | Planned | v0.10 |
| L-04 | Logic model report | Minor | Planned | v0.9 |
| G-19 | Donor scoring (RFM) as rollups | Minor | Planned | v0.9 |
| F-04 | Government award fields | Minor | Planned | v0.10 |
| F-05 | Multi-year award schedules | Minor | Planned | v0.10 |
| UX-F3 | Module tab motifs | Minor | Planned | D-144 |

### 0.15 (Batch B): Funders complete, Nonprofit Cloud mirror (v1.0 candidate)

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| F-03 | Restricted fund tracking | Major | Planned | v0.10 |
| X-07 | Gift Transaction mirror | Major | Planned | Plan 6.3 |
| F-06 | Funder report merge template | Minor | Planned | v0.10 |
| F-07 | Board dashboard | Minor | Planned | v0.10 |
| F-08 | Deadline calendar view | Minor | Planned | v0.10 |
| L-06 | Link outcomes to grant deliverables | Minor | Planned | v0.10 |
| X-05 | NPSP coexistence: adopt household accounts | Minor | Planned | Plan 6.3 |

### 1.1 (Batch C): Contact points, addresses, Migration Assistant

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-45 | Contact Point Sync module (ADR first) | Major | Planned | D-111 |
| C-46 | Address Verification module (ADR first) | Major | Planned | D-112 |
| MIG-01 | Migration Assistant framework (plan 11.2 item 32 decisions first) | Major | Planned | D-125 |
| MIG-10 | Integrations page: detected apps and migration links | Minor | Planned | D-125 |
| MIG-06 | Stripe receiver (X-08) and Zapier recipes | Minor | Planned | D-125 |
| MIG-08 | DLRS and NPSP rollups into Rollup Builder | Minor | Planned | D-125 |

### 1.2 (Batch C): Corporate Hub, documents and compliance

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| CH-01 | Document and policy library (ADR first) | Major | Planned | D-118 |
| CH-03 | Compliance calendar | Major | Planned | D-118 |
| CH-04 | Shipped compliance templates | Major | Planned | D-118 |
| CH-02 | Policy acknowledgments | Minor | Planned | D-118 |
| CH-06 | Extra templates | Minor | Planned | D-118 |
| CH-07 | Required-policies set | Minor | Planned | D-118 |
| CH-08 | Contracts and renewals | Minor | Planned | D-118 |

### 1.3 (Batch C): Corporate Hub, GDPR and board governance

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| CH-05 | GDPR template set | Major | Planned | D-118 |
| CH-09 | Board governance | Major | Planned | D-118 |
| CH-10 | Board meetings | Major | Planned | D-118 |
| CH-11 | Motions, votes and resolutions | Minor | Planned | D-118 |
| CH-12 | Conflict-of-interest disclosures | Minor | Planned | D-118 |
| CH-13 | Board giving participation | Minor | Planned | D-118 |
| CH-14 | Board dashboard | Minor | Planned | D-118 |

### 1.4 (Batch D): Migrations

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| MIG-02 | NPC Party Relationship Groups to households | Major | Planned | D-125 |
| MIG-04 | NPC gifts to Giving | Major | Planned | D-125 |
| MIG-05 | NPSP migration kit | Major | Planned | D-125 |
| MIG-03 | V4S to Volunteers adapter | Minor | Planned | D-125 |
| MIG-09 | PMM to Programs | Minor | Planned | D-125 |
| MIG-07 | DonorPerfect, Bloomerang, Little Green Light templates | Minor | Planned | D-125 |

### 1.5 (Batch D): Portal Builder and grant management

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| PB-01 | Portal Builder (ADR first) | Major | Planned (blocked: plan 11.2 item 30 terms check) | D-118, D-120 |
| PB-02 | Board portal template | Major | Planned | D-118 |
| F-09 | Grant Finder | Major | Planned | D-121 |
| F-10 | Application tasks and checklists | Minor | Planned | D-121 |
| F-11 | Document tracking | Minor | Planned | D-121 |
| F-12 | Budget versus awarded | Minor | Planned | D-121 |
| F-13 | Renewals | Minor | Planned | D-121 |

### 1.6 (Batch D): Scholarships and Outbound Grants

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

### 1.7 (Batch E): Event Management core

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| EV-01 | Events (ADR first) | Major | Planned | D-123 |
| EV-02 | Registrations and attendees | Major | Planned | D-123 |
| EV-04 | Tracks, sessions and agenda | Major | Planned | D-123 |
| EV-03 | Ticket types | Minor | Planned | D-123 |
| EV-05 | Speakers | Minor | Planned | D-123 |
| EV-08 | Volunteer integration | Minor | Planned | D-123 |
| EV-10 | Summit Events compatibility | Minor | Planned | D-123 |

### 1.8 (Batch E): Event Management complete, portal templates

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| EV-06 | Call for speakers | Major | Planned | D-123 |
| EV-09 | Sponsorship management | Major | Planned | D-123 |
| EV-11 | Event dashboard and conference template | Minor | Planned | D-123 |
| PB-07 | Speaker portal template (EV-07) | Minor | Planned | D-123 |
| PB-03 | Volunteer portal template | Minor | Planned | D-118 |
| PB-04 | Service portal template | Minor | Planned | D-118 |
| PB-05 | Partner portal template | Minor | Planned | D-118 |

### 1.9 (Batch E): Multi-brand management

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-47a | Brand and Legal Entity records, many-to-many assignment | Major | Planned | D-119, D-120 |
| C-47b | Brand-aware outputs | Major | Planned | D-119, D-120 |
| C-47c | Brand-restricted visibility (optional; ADR first) | Major | Planned | D-120 |
| C-47d | Brand lookup in modules, Bulk Update and import mapping | Minor | Planned | D-119 |
| C-47e | Brand filters on list views, reports and dashboards | Minor | Planned | D-119 |
| C-47f | Receipt numbering per brand | Minor | Planned | D-119 |

### 1.10 (Batch F): LWC Builder

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| LB-01 | Grid canvas builder (ADR first) | Major | Planned | D-120 |
| LB-02 | Runtime renderer | Major | Planned | D-120 |
| LB-03 | Building blocks | Major | Planned | D-120 |
| LB-04 | Quick action and flow buttons | Minor | Planned | D-120 |
| LB-05 | Conditional visibility per block | Minor | Planned | D-120 |
| LB-06 | Export as LWC source | Minor | Planned | D-120 |

### 1.11 (Batch F): Territory Management and Grid tool

| ID | Item | Size | Status | Source |
|---|---|---|---|---|
| C-40 | Territory Management module (ADR first) | Major | Planned | D-98, D-120 |
| C-41 | Grid tool | Major | Planned | D-98 |
| C-41b | Saved grids | Minor | Planned | D-98 |

## Held

- C-38 scheduled imports and connections: on hold until Brandon starts it (D-39). The Google Sheets source for Super Importer waits with it.

## Milestones and blocked

| ID | Milestone | Blocked on | Attaches to |
|---|---|---|---|
| M-0 | Device mobile run; 250,000-row scale run in a tier 2 sandbox (D-90) | A device; a tier 2 sandbox | Before M-1 |
| M-1 | v1.0 pilot of release 0.15; tagged v1.0 when it passes | Pilot org | After Batch B |
| M-2 | Namespace, Dev Hub, steward entity, first package versions; Volunteers install-link testing | M-1 (D-87) | After M-1 |
| M-3 | Beta cohort (was iteration v0.12) | M-2 | A 1.x batch |
| M-4 | Security review submission and AppExchange listing (was iteration v0.13; no AppExchange for now, D-24) | M-2, Brandon's go-ahead | A 1.x batch |

Open QA from batch 9: browser UX testing of the batch 8 screens (needs a browser tool); `mwdbdevsb` Error Log probe (awaiting Brandon's approval).

## Not approved (in no release)

Plan 6.1.1 items 5 (Memberships Essentials compatibility), 6 (document builder), 9 (map and radius search), 10 (field history), 14 (engagement score), 15 (archiving), 17 (scheduled backup); Memberships (G-22); Forms (C-42); BarnCRM for WordPress; public volunteer sign-up (V-09); community processor webhooks (X-08) beyond the Stripe receiver; donor scoring maturity; multi-currency; localization; L-05; P-09.

## Shipped iterations (history)

| Iteration | Theme | Status |
|---|---|---|
| v0.1 to v0.7 | Foundation, Giving, commitments, stewardship, import 2.0, Mirror, data management | Shipped |
| v0.8 | Volunteers (V-01 to V-08, C-24, C-30) | Built and tested unmanaged; install-link testing in M-2 |
| v0.9, v0.10 | Programs and Logic Models; Funders and NPC mirror | C-39 landed; the rest now in releases 0.12 to 0.15 |
| v0.11 | Hardening | Shipped 2026-10-29 (release gate on cbf35753; `barn-npc` and `mwdbdevsb` deployed); device mobile run in M-0 |
| v0.12, v0.13 | Beta, AppExchange | Superseded by milestones M-3 and M-4 (D-155) |

Since v0.11: batch 8 (#753, C-49 to C-52 Super Importer, Super Transform, Advanced Duplicate Management, Data Dictionary) and batch 9 (#758, QA v21 fixes) landed.
