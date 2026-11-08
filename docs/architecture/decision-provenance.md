# Claude-made and AI-influenced decisions in the BarnCRM plan

Generated 2026-11-06 from the plan (Sections 1 to 12) and the ADR index. Purpose: Brandon asked to identify decisions made by AI so they can be changed more flexibly. Classification is by text attribution only: "Brandon" means the row names him, quotes him, or says owner decision, request or approval; "Claude" means an engineering or design choice with no owner attribution; "Mixed" means Brandon approved a direction or accepted a recommendation ("as recommended", "agree", standing "proceed as recommended") and Claude chose the specifics. Mixed rows are the ones to revisit first, because Brandon approved without necessarily weighing the specifics.

Counts of D-rows: Brandon 104, Claude 22, Mixed 57 (total 183; D-174 to D-183 included, D-177 and D-178 listed out of order in the plan).

Rule (plan Section 12, D-184): Claude-made and Mixed items are flexible. Brandon can change one by saying so; the change is then recorded as a new D-row, with an ADR where the architecture changes. Since this snapshot: the non-goal "org-wide automation switches" was removed by D-184 (ADR-0174).

## (a) Section 12 decision log

| ID | Summary | Who | Evidence |
|---|---|---|---|
| D-01 | Product name "Open Impact" (chosen 2026-09-06), namespace candidate `openimpact` deferred and subject to verification; fallback name OpenCause. Name superseded 2026-09-23 | Mixed | Claude chose "Open Impact"; Brandon superseded the name 2026-09-23 and 2026-10-12 |
| D-02 | Second-generation managed packages with one shared namespace for the AppExchange listing; built and piloted as unlocked packages under the same namespace until then, foll | Mixed | Claude chose 2GP; Brandon amended to unlocked-until-listing (2026-09-23, ADR-0046) |
| D-03 | Core plus separate module packages for heavy domains; feature flags for minor behavior | Claude | no attribution |
| D-04 | Custom `Gift__c` as the gift system of record; Opportunity and Gift Transaction as optional mirrors in Connect (renamed BarnCRM Mirror, D-103) | Claude | no attribution |
| D-05 | Household as Account record type with two membership modes behind one service | Claude | no attribution |
| D-06 | Settings storage: protected hierarchy custom settings for toggles, custom objects for structured lists, custom metadata for shipped defaults materialized on install | Claude | no attribution |
| D-07 | `sf` CLI plus GitHub Actions; CumulusCI optional later | Claude | no attribution |
| D-08 | License: Apache-2.0 | Brandon | Brandon 2026-09-22 |
| D-09 | No Person Account, Industries, OmniStudio, Data Cloud, or Experience Cloud dependency anywhere | Claude | no attribution |
| D-10 | Receipts are immutable; corrections void and reissue; refunds are negative linked gifts | Claude | no attribution |
| D-11 | Rollup engine: evaluate vendoring a proven MIT-licensed Apex rollup library before building. Superseded by D-16: BarnCRM owns its rollup engine; the vendored library is r | Mixed | Claude chose vendoring; Brandon superseded by D-16 |
| D-12 | Trunk-based development, squash merges, `main` always releasable | Claude | no attribution |
| D-13 | Data management scope and phasing: an in-org tool with NPSP Data Importer parity, a Jetstream-style find and bulk update, and the useful dataimporter.io capabilities, the | Brandon | (Brandon, 2026-09-23; ADR-0047) |
| D-14 | Cancelled status for unpaid Pending gifts: a Pending gift that will never be paid is set to Cancelled, a non-money step with no negative gift, excluded from rollups, the  | Brandon | (Brandon, 2026-09-24; amends G-04) |
| D-15 | Second long-lived test org: a scratch org with Person Accounts enabled, alias `oi-pa`, kept until it expires and recreated after that, used for Person Account testing and | Brandon | (Brandon, 2026-09-24) |
| D-16 | BarnCRM owns its rollup engine . D2: definitions stay in `Rollup_Definition__c`, shipped defaults in `Rollup_Definition_Default__mdt`. D3: every affected total is recalcu | Mixed | Brandon approved own engine (2026-10-12); Claude wrote proposal D1 to D9, A1, A2 |
| D-17 | Import gaps closed: import matches by Salesforce record ID and offers a "match only, never create" option (resolves Section 11.2 item 15 as yes), and the import wizard ac | Mixed | Brandon approved ("proceed as"); design and specifics are Claude |
| D-18 | Rollup comparison recommendations adopted: new slices S15 (Metadata API connection spike), S16 (generate and deploy trigger) and S17 (remove trigger, with a Health Check) | Mixed | Brandon approved ("recommendation"); design and specifics are Claude |
| D-19 | Confidential interaction notes are not built: interaction notes stay completed standard Tasks that follow record visibility (Section 11.3) | Brandon | (Brandon, 2026-10-12) |
| D-20 | A gift stays credited to the household it was credited to when given: a donor moving households does not move past gifts. Household rollups reached through current member | Brandon | Brandon, 2026-10-12 |
| D-21 | "What's new" release notes (C-27) are labelled with the release they ship in; the first is "0.6" until a version is set | Brandon | (Brandon, 2026-10-12) |
| D-22 | ADRs accepted: unlocked-to-managed migration kit (ADR-0088); Flow templates (each automation ships a template or a documented reason it does not; ADR-0090); suite choice  | Brandon | (Brandon, 2026-10-12; ADR-0088, ADR-0090, ADR-0072, ADR-0073, ADR-0089, ADR-0074, ADR-0075) |
| D-23 | Platform capability recommendations adopted: keep LWC (watch Multi-Framework; an ADR is needed before adoption); audit the API 67.0 default access mode (in progress); Ape | Mixed | Brandon approved ("recommendation"); design and specifics are Claude |
| D-24 | Telemetry (C-26) deferred indefinitely . If an AppExchange listing happens later, prefer AppExchange App Analytics over building telemetry. Resolves open question 7 in Se | Brandon | Brandon, 2026-10-12: "There is no AppExchange for now so if telemetry is abou |
| D-25 | CMDT Manager scope: only Relationship Type is editable, and only the org's own rows; shipped rows are read only; it is a section of BarnCRM Settings (General), not a tab; | Mixed | Brandon approved ("standing instruction"); design and specifics are Claude |
| D-26 | Field utilization ships in Core: Core, not its own Analytics package; a weekly user-mode count on Sundays at 04:00; 13 months of snapshots; an object list of up to 255 ch | Mixed | Brandon approved ("standing instruction"); design and specifics are Claude |
| D-27 | Typed Find queries are parsed into the query document in the browser: the server never takes raw SOQL and checks the document exactly as for the visual builder | Mixed | Brandon approved ("standing instruction"); design and specifics are Claude |
| D-28 | Column changes are a declarative transform document, and import can match through the org's duplicate rules | Mixed | Brandon approved ("standing instruction"); design and specifics are Claude |
| D-29 | Health Check keeps its orphan findings after the Data Hygiene tab (C-28) ships | Mixed | Brandon approved ("standing instruction"); design and specifics are Claude |
| D-30 | A nightly rollup run is skipped, and logged, when a Recalculate all is already running at 2 AM | Mixed | Brandon approved ("standing instruction"); design and specifics are Claude |
| D-31 | Rollup operations slice: count distinct is its own operation; the text list delimiter is a picklist (comma, semicolon, new line); Any and None read no field; count distin | Mixed | Brandon approved ("standing instruction"); design and specifics are Claude |
| D-32 | Rollup Builder: the Recalculate all estimate uses 1,650 records a minute until the scale test measures it; S14 is built only if the scale test needs it | Mixed | Brandon approved ("standing instruction"); design and specifics are Claude |
| D-33 | Tests run as a permission-set user: `TestUsers.admin()` (and `adminWith(...)`) creates a user on the running user's profile with the BarnCRM permission sets; `scripts/ci/ | Mixed | Brandon approved ("standing instruction"); design and specifics are Claude |
| D-34 | C-37 part 2 choices: the bulk delete run limit defaults to 10,000 and is at most 48,000; `Bulk_Delete_Records` ships only in its own `BarnCRM_Bulk_Delete` permission set, | Mixed | Brandon approved ("standing instruction"); design and specifics are Claude |
| D-35 | Merge survivors' real-time totals are recalculated by a queueable just after the merge | Mixed | Brandon approved ("standing instruction"); design and specifics are Claude |
| D-36 | Import chooses a Person Account record type available to the running user; if there is none it creates nobody and logs one note | Mixed | Brandon approved ("standing instruction"); design and specifics are Claude |
| D-37 | Field utilization runs on demand from its own Field Utilization tab: pick an object, and its fields and their utilization are shown; there is no nightly or weekly job. Su | Brandon | owner decision, Brandon, 2026-10-13 |
| D-38 | Priority: existing Core features are thoroughly tested, optimized, improved and simplified, without removing functionality, before work moves to scheduled imports and con | Brandon | owner decision, Brandon, 2026-10-13 |
| D-39 | Platform features in the Core quality pass, and C-38 on hold: all 14 recommended platform features are part of the Core quality pass and are built in parallel now as Q-01 | Brandon | owner decision, Brandon, 2026-10-13 |
| D-40 | Retention and limits: Error Log entries older than 180 days are deleted; staged import rows are purged 90 days after their job finishes (amends Section 4.9, which purged  | Mixed | Brandon approved ("as recommended"); design and specifics are Claude |
| D-41 | Import scope: affiliations stay out of Core imports, and the spec and admin guide are corrected to match (amends C-32 and Section 4.9); import templates shipped in a late | Mixed | Brandon approved ("as recommended"); design and specifics are Claude |
| D-42 | "What's new" entries (C-27) are refreshed from the release notes as part of each release | Mixed | Brandon approved ("as recommended"); design and specifics are Claude |
| D-43 | The 9 components used only inside the BarnCRM Settings console are no longer offered in App Builder | Mixed | Brandon approved ("as recommended"); design and specifics are Claude |
| D-44 | The Fundraising Staff permission set group includes Giving Staff; closes Section 11.2 item 12 | Mixed | Brandon approved ("as recommended"); design and specifics are Claude |
| D-45 | The renamed import tab reads "Data Jobs" in Title Case; amends ADR-0047's "Data jobs" wording | Mixed | Brandon approved ("as recommended"); design and specifics are Claude |
| D-46 | A Dev Hub org snapshot `BarnPA` is taken from `oi-pa` | Brandon | owner approval, Brandon, 2026-10-13 |
| D-47 | Finish Core before version 1: duplicate rule matching and anything else unfinished in Core is finished before version 1, excluding the post-1.0 themes (Section 6.1) and C | Brandon | owner decision, Brandon, 2026-10-13 |
| D-48 | Core review recommendations approved: rollups recalculate only the definitions that marked a target, which needs an ADR and narrows ADR-0082 decision 2; Instantly-mode fi | Mixed | Brandon approved ("recommendation"); design and specifics are Claude |
| D-49 | Affiliations return to Core imports: a people import links each person to the organization on their row by an affiliation, as originally planned. Reverses the affiliation | Brandon | owner decision, Brandon, 2026-10-13 |
| D-50 | Data tools parity . Build: a Data Manager hub with one job history and Undo; an Org Optimizer page (Data Hygiene relabeled; sections Overview, Data quality, Duplicates mo | Brandon | owner decision, Brandon, 2026-10-13, from the dataimporter.io comparison |
| D-51 | The import tab label is "Import", reached from the Data Manager tab. Import and Bulk Update leave the app navigation; Find stays (amended by D-135: Find moves to Data Man | Brandon | owner decision, Brandon, 2026-10-13 |
| D-52 | Erase a person (right to be forgotten) is built in Core, with a Giving extension for gifts and receipts | Brandon | owner decision, Brandon, 2026-10-13 |
| D-53 | The Commitment page keeps Clone and Printable View off | Brandon | owner decision, Brandon, 2026-10-13 |
| D-54 | The Team Member (`Program_Staff`) and Coordinator (`Volunteer_Coordinator`) permission set groups get their module permission sets when those modules ship; until then the | Brandon | owner decision, Brandon, 2026-10-13 |
| D-55 | Shipped import templates are added at install and on upgrade; closes Section 11.2 item 14 | Brandon | owner decision, Brandon, 2026-10-13 |
| D-56 | Org gates may batch several PRs into one combined org run and deploy only changed metadata; every test that would have run still runs . Extended 2026-10-26: combined land | Brandon | owner decision, Brandon, 2026-10-13 |
| D-57 | Console app rollout: on the test orgs `oi-test`, `oi-pa` and `barn-core` Claude deletes and redeploys the app; on `barn-npc` and `mwdbdevsb` the owner switches Navigation | Brandon | owner decision, Brandon, 2026-10-13 (Claude executes) |
| D-58 | Logo: the blue barn icon is approved as is: barn walls #00A8D9 (the blue in the Blue Bottle Coffee logo file), roof and app header #007A9E (same hue, 4.91:1 against white | Brandon | owner decision, Brandon, 2026-10-13 |
| D-59 | Console tab icons: keep the page icons set by Q-07 | Brandon | owner decision, Brandon, 2026-10-13 |
| D-60 | Q-11: no Platform Cache for now; revisit after security review | Brandon | owner decision, Brandon, 2026-10-13 |
| D-61 | Q-09: User Access Policies are documented with samples, not packaged | Brandon | owner decision, Brandon, 2026-10-13 |
| D-62 | Setup prerequisites: avoid needing a Setup change wherever possible; when a BarnCRM feature does need one, the matching BarnCRM Settings section shows an instruction for  | Brandon | owner decision, Brandon, 2026-10-13 |
| D-63 | Field utilization on demand: no 13-month auto-cleanup and no Health Check entry for the old job | Brandon | owner decision, Brandon, 2026-10-13 |
| D-64 | ADR-0088 (unlocked-to-managed migration kit) and ADR-0091 (bulk delete from a Find query with undelete) are accepted; rollup S16 and S17 are deferred to after version 1;  | Brandon | owner decisions, Brandon, 2026-10-13 |
| D-65 | The coverage gate measures BarnCRM classes at 75% in total and per class, not org-wide; the 23 classes now below 75% are held at their current figures until tests lift th | Brandon | owner decision, Brandon, 2026-10-13 |
| D-66 | Q-05 wording and order: confirm buttons in standard order (Cancel, then the action); message-only toasts show the text as the bold main line; the Health Check finding tit | Brandon | owner decision, Brandon, 2026-10-13 |
| D-67 | Q-04: job finish notifications are on by default | Brandon | owner decision, Brandon, 2026-10-13 |
| D-68 | The four Q-14 agent-ready actions get their access through packaged permission sets and/or permission set groups, not a manual Setup step | Brandon | owner decision, Brandon, 2026-10-13 |
| D-69 | Q-14 scope accepted: the four action classes are global (permanent once managed); no Update Person action, since the standard Update Record action covers it; starting or  | Brandon | owner decision, Brandon, 2026-10-13 |
| D-70 | Record cards (Addresses, Affiliations, Relationships) that refuse a change for lack of access show a friendly message and write no Error Log entry; real failures are stil | Brandon | owner decision, Brandon, 2026-10-13 |
| D-71 | Rollup totals are recalculated just after the save by default (Background), with a "During the save" setting; modifies ADR-0082 decision 4 through a new ADR written on th | Mixed | Brandon approved ("as recommended"); design and specifics are Claude |
| D-72 | `RollupRecalcAction` is global so a subscriber's Flow Builder can use it; permanent once managed | Mixed | Brandon approved ("as recommended"); design and specifics are Claude |
| D-73 | Amended by D-83: the Record Inbound Gift action (`InboundGiftAction`) lives in the Connect package (renamed BarnCRM Mirror, D-103), which depends on Giving, so Giving's s | Mixed | Brandon approved ("as recommended"); design and specifics are Claude |
| D-74 | Setup notes for Giving and Connect (renamed BarnCRM Mirror, D-103) are shown on each module's own page, using Core's note component; keeps ADR-0020 | Mixed | Brandon approved ("as recommended"); design and specifics are Claude |
| D-75 | Reversed by D-82. The Bulk Update and Bulk Delete permission sets' 31 shared grants move into BarnCRM Find and Export | Mixed | Brandon approved ("as recommended"); design and specifics are Claude |
| D-76 | All BarnCRM triggers declare all seven contexts, with a CI check, after PR #229 merges | Mixed | Brandon approved ("as recommended"); design and specifics are Claude |
| D-77 | The unused label `Giving_SoftCredit_Duplicate` is deleted as a leftover | Mixed | Brandon approved ("as recommended"); design and specifics are Claude |
| D-78 | `Error_Log__c` sharing stays Read/Write: every permission set has View All, only Admin can edit | Mixed | Brandon approved ("as recommended"); design and specifics are Claude |
| D-79 | Stored household names use the org default language for joining words ("and", the list separator, "the late"), not the saving user's language | Mixed | Brandon approved ("as recommended"); design and specifics are Claude |
| D-80 | Plan corrections applied: the v0.3 row no longer lists NPSP import templates (they ship in v0.5); CI runs on one test org, not four org shapes; `TestDataFactory` is expos | Mixed | Brandon approved ("as recommended"); design and specifics are Claude |
| D-81 | Suites and packaging: BarnCRM ships as two suites from the same packages, the Impact Suite (Core plus Giving, with Programs, Logic Models, Volunteers, Funders and Connect | Brandon | owner decision, Brandon, 2026-09-23 |
| D-82 | D-75 is reversed: the Bulk Update and Bulk Delete permission sets keep their own data job read grants | Brandon | owner decision, Brandon, 2026-10-13 |
| D-83 | Connect's (renamed BarnCRM Mirror, D-103) Record Inbound Gift action gets its own small permission set granting only that action; amends D-73, which named Giving's sets | Brandon | owner decision, Brandon, 2026-10-13 |
| D-84 | Working agreement: present only Core findings and decisions until he starts work on the modules; module feedback and decisions are recorded in Section 11.5 (grouped by mo | Brandon | (Brandon, 2026-10-13) |
| D-85 | Working agreement: implement recommendations and tell him what is being changed, unless it is really important or contrary to something he asked for or instructed. Clarif | Mixed | Brandon approved ("recommendation"); design and specifics are Claude |
| D-86 | Erase a person: the preview lists activities and files for manual deletion, which are not erased automatically; Health Check skips erased people; PR #282 is accepted at i | Brandon | owner decision, Brandon, 2026-10-13 |
| D-87 | Release prerequisites come after piloting v1.0: namespace registration, the Dev Hub and the steward entity (11.2 items 1, 3, 4) are settled after a v1.0 pilot; until then | Brandon | (Brandon, 2026-10-13) |
| D-88 | Deleting people never deletes their household: a household emptied by deleting its people is kept in every membership mode; moving people still tidies it. Open option, ti | Brandon | (Brandon informed, 2026-10-13; canonical rule R-H12, landed in #377) |
| D-89 | A household left with no members after its people are deleted moves to the Recycle Bin, but only after its former members can no longer be restored from the Recycle Bin:  | Brandon | (Brandon, 2026-10-14) |
| D-90 | 25,000 rows is the scale bar for the pilot: the 250,000-row import run comes later, in a sandbox (Section 7.3) | Brandon | (Brandon, 2026-10-14) |
| D-91 | Salesforce-license-only permissions move out of BarnCRM Admin into the optional `BarnCRM_Access_Manager` permission set (ADR-0121, #406): Assign Permission Sets and View  | Claude | no attribution (ADR-0121) |
| D-92 | Product-branded names stay: BarnCRM Admin, Staff, Read Only, Duplicate Review and BarnCRM Settings. Superseded for the Core roles by D-97. | Brandon | (Brandon, 2026-10-14; closes Section 11.2 item 24) |
| D-93 | No end date on per-automation switches: they stay off until an admin turns them back on; the org-wide pause still expires (ADR-0055) | Brandon | (Brandon, 2026-10-14; closes Section 11.2 item 16) |
| D-94 | The pilot is a milestone below v1.0: no version number is attached to it; Brandon decides version numbers | Brandon | (Brandon, 2026-10-14) |
| D-95 | BarnCRM is open to any Salesforce org regardless of size, and extra valuable for small to mid-sized teams that lack the resources for many licenses and customization; it  | Brandon | (Brandon, 2026-10-14) |
| D-96 | Edition names: "BarnCRM is the suite of tools that come in two versions": the Nonprofit Edition (formerly "Impact Suite") and the Standard Edition (formerly "Community Su | Brandon | (Brandon, 2026-10-14) |
| D-97 | Core roles have neutral names: Program Staff becomes Team Member and Volunteer Coordinator becomes Coordinator, labels and descriptions only; API names `Program_Staff` an | Brandon | (Brandon, 2026-10-14; supersedes D-92 for the Core roles) |
| D-98 | Advanced Territory Management (C-40) and a Grid tool (C-41) are planned Core Super Tools, built after v1.0 . Amended 2026-10-26: C-40 becomes the optional module BarnCRM  | Brandon | (Brandon, 2026-10-14) |
| D-99 | Edition gates what Core shows: nonprofit modules (Giving, Volunteers, Programs, Funders, Connect; renamed BarnCRM Mirror, D-103) are shown and offered only in the Nonprof | Brandon | (Brandon, 2026-10-14) |
| D-100 | First-run setup and switches: on first install, a setup overlay covers BarnCRM Home and BarnCRM Settings until an admin completes it (edition, then "turn on all defaults" | Brandon | (Brandon, 2026-10-14) |
| D-101 | Modules versus features: features are installed with Core and can be switched on or off (Data Manager with Import, Find and Bulk Update; Duplicate Review; Org Optimizer a | Mixed | Brandon set modules vs features; Claude chose package layout and Rollup Builder move details |
| D-102 | Features off by default, modules installed from Settings, first-run setup: Core features are off on a new install and are turned on only in first-run setup or later on Se | Brandon | (Brandon, 2026-10-14 and 2026-10-15) |
| D-103 | The module BarnCRM Connect is renamed BarnCRM Mirror, API names included: package folder `packages/connect` becomes `packages/mirror`; `Connect_*` API names become `Mirro | Brandon | (Brandon, 2026-10-15) |
| D-104 | v0.8 Volunteers started and its design approved: modules start now, ahead of plan 6.0 item 3. (1) Hours totals through the BarnCRM Rollup Builder module: Volunteers depen | Mixed | Brandon approved Volunteers start and design (2026-10-17); Claude chose ADR-0127 to 0129 specifics |
| D-105 | Deleting a person removes that person's volunteer requirements and volunteer skills; merging two people keeps them | Claude | no attribution (integrator) |
| D-106 | Volunteers ships its own copies of the Core person pages (the ADR-0064 pattern), so the Volunteer Profile, readiness card and letter action appear on the Volunteers app's | Claude | no attribution (integrator) |
| D-107 | The Volunteers lapsing-volunteers report stays Contact-only, so it shows no rows in Person Account orgs | Claude | no attribution (integrator) |
| D-108 | Erasing a person deletes the hour letters and certificates BarnCRM generated for them (identified exactly, deleted in system mode after the access check) and lists them a | Claude | no attribution (integrator) |
| D-109 | Removing sample data never deletes a real person's rows: sign-ups, hours and skills a real person holds on a sample shift or skill are kept, the sample job or skill stays | Claude | no attribution (integrator) |
| D-110 | Preferred Phone in Core: a Preferred Phone picklist on the person (Home, Mobile, Work, Other) keeps the standard Phone in step with the chosen number, the same way Prefer | Brandon | (Brandon, 2026-10-25; C-43) |
| D-111 | Contact Point sync is a new optional module, BarnCRM Contact Point Sync, not Core: it keeps `ContactPointEmail`, `ContactPointPhone` and `ContactPointAddress` in step wit | Brandon | (Brandon, 2026-10-25; C-45) |
| D-112 | Address verification is a new optional module, BarnCRM Address Verification: bring-your-own provider key set in the BarnCRM Settings console (never only in Setup); verifi | Brandon | (Brandon, 2026-10-25; C-46; amends Section 4.7, which put third-party verification out of scope) |
| D-113 | Related-record duplicate matching in Core, steps 1 to 3: (1) configurable match sources in the BarnCRM Settings console (object, field, parent link to Contact or Account, | Brandon | (Brandon, 2026-10-25; C-44; Section 4.9) |
| D-114 | Erasing a person also empties Rejection Reason on their volunteer hours | Brandon | (Brandon, 2026-10-25; closes Section 11.2 item 28) |
| D-115 | Erasing a person keeps deleting the hour letters and certificates BarnCRM generated for them, as D-108 already says; no behaviour change | Brandon | (Brandon, 2026-10-25; closes Section 11.2 item 29) |
| D-116 | Documentation upkeep is a standing rule: an Overview (`docs/overview.md`), Admin Guide (`docs/admin-guide/`), User Guide (`docs/user-guide/`) and step-by-step Testing Gui | Brandon | (Brandon, 2026-10-25) |
| D-117 | Staff merges (household merge and duplicate contact merge) run the merge DML in system mode after BarnCRM's own permission check and a record edit-access check; no Delete | Brandon | Brandon, 2026-10-25 |
| D-118 | Two new optional modules for both editions, depending on Core only, planned after the Core quality pass and after C-45 and C-46, not scheduled to an iteration: Corporate  | Mixed | Brandon asked for the two modules (2026-10-25); Claude scoped Corporate Hub and Portal Builder |
| D-119 | Multi-brand management (C-47) is a planned Core feature for both editions, built after v1.0 and not scheduled to an iteration: brand records, a Brand lookup on records, b | Brandon | (Brandon, 2026-10-26) |
| D-120 | Modules, brands and portals . (1) Advanced Territory Management (C-40) becomes an optional module, BarnCRM Territory Management, for both editions, depending on Core only | Mixed | Brandon decided modules, brands, portals (2026-10-26); Claude chose specifics |
| D-121 | Funders gets a Grant Finder and full grant management, F-09 to F-13: Grants.gov search (free public API; paid directories such as Candid only through the org's own subscr | Brandon | (Brandon, 2026-10-26; Section 5.5) |
| D-122 | New optional module BarnCRM Scholarships and Outbound Grants: programs and cycles, applications, reviewers and scoring, awards, disbursements, recipient reporting, applic | Brandon | (Brandon, 2026-10-26; Section 5.11, SG-01 to SG-08; PB-06) |
| D-123 | New optional module BarnCRM Event Management: events and registrations, ticket types, tracks, sessions, speakers, call for speakers with review, speaker portal through Po | Brandon | (Brandon, 2026-10-26; Section 5.12, EV-01 to EV-11; PB-07) |
| D-124 | Rollup Builder: DLRS parity or better, being built now: standard objects as parent and child options, describe only (ADR-0136, consistent with ADR-0013); generated trigge | Brandon | (Brandon, 2026-10-26; Section 4.10) |
| D-125 | Integrations and migrations: the review's top 10 are post-1.0 roadmap items and its decisions O-1 to O-12 are open, deferred until after Core QA. Integrations wait until  | Mixed | Brandon deferred post-1.0 (2026-10-26); the review top 10 and O-1 to O-12 are Claude proposals |
| D-126 | Settings rules and layout: every Settings change saves org-wide (nothing per user or browser); every setting shows a changeable default, never blank (blank-means-not-chos | Mixed | Brandon rules (2026-10-26); recommended defaults are Claude |
| D-127 | Fiscal year start month and Organization Name are read from Salesforce Setup and shown read only in BarnCRM Settings, never set by hand; the organization address has six  | Brandon | (Brandon, 2026-10-26; ADR-0135) |
| D-128 | Households and addresses: household membership defaults to one household per person; an Address updates setting with three values, default "Everyone moves together"; butt | Brandon | (Brandon, 2026-10-26; Sections 4.6, 4.7) |
| D-129 | Rollup mode is set per rollup, with the default (Both) in BarnCRM Settings, Rollups section; instant processing defaults to "After the save" | Brandon | (Brandon, 2026-10-26; Section 4.10; consistent with D-71) |
| D-130 | Apps and setup: four apps (BarnCRM, BarnCRM Console, BarnCRM Admin, BarnCRM Admin Console), each with a logo (the admin variant distinct), and an App Navigation Style set | Brandon | (Brandon, 2026-10-26; Section 4.8) |
| D-131 | Gate process: combined landing batches with one full org gate per batch; a light gate (deploy plus Jest, no Apex test run) for screen, label and docs-only changes; a thir | Brandon | (Brandon, 2026-10-26; Section 9.6; extends D-56) |
| D-132 | Rollup Builder generated triggers are deployed by the admin: for objects BarnCRM does not own, the Builder generates a one-line trigger and its test; the admin deploys th | Brandon | (Brandon, 2026-10-26; ADR-0138; amends D-16 A2, D-18, D-64 and D-124; Section 4.10) |
| D-133 | Field Utilization Snapshot History and Data Manager clarity: the button is "Save Utilization Snapshot" and a Snapshot History list shows saved counts with compare, view a | Brandon | (Brandon, 2026-10-26; Sections 4.9, 6.1 item 10) |
| D-134 | Account record types: (1) the Household record type stays packaged and active and is always listed in Setup, but no user is ever given it (amended the same day, adjustmen | Mixed | Brandon approved all eight recommendations (2026-10-28); recommendations are Claude |
| D-135 | Find, Import and Bulk Update in Data Manager; Error Log last: Find is reached from a Find card in the Data Manager and leaves the app navigation, like Import and Bulk Upd | Brandon | (Brandon, 2026-10-28; amends D-51, D-130's admin app tab lists and D-133; Section 4.9) |
| D-136 | Import wizard "What Are You Importing?": (1) step one of the Import wizard becomes a page of choice cards: People and Organizations; Gifts (shown only when an active temp | Mixed | Brandon approved all seven recommendations (2026-10-28); recommendations are Claude |
| D-137 | Setup steps link directly to the Setup page: (1) every "Needs a Change in Setup" note, in BarnCRM Settings and on a module's settings page, has an Open in Setup button th | Mixed | Brandon asked (2026-10-28); the shared-module and Check Again mechanics are Claude |
| D-138 | Integrations page shows no install links: each product keeps its Learn More link only; the Install URL field is removed from the Integration App type and its shipped reco | Brandon | (Brandon, 2026-10-28; C-48, D-125) |
| D-139 | Core security review approved . Fix C-M1 (Read Only loses Merge_Settlement_Ready__e; the subscriber settles only records the event's CreatedById may edit), C-L1 (Error Lo | Mixed | Brandon "agree" (2026-10-28); findings and fixes are Claude |
| D-140 | Core UX plan approved and one name for the data-quality tool . (1) A small Core component kit of `c-barn-*` LWCs: `barnPageShell`, `barnToolTile` and `barnToolGrid`, `bar | Mixed | Brandon "agree" (2026-10-28); UX plan is Claude |
| D-141 | Batch testing: "I want the testing to be done in batches and optimized to go faster wherever prudent" and "I want this testing optimization for everything with this proje | Brandon | Brandon quoted: "I want the testing to be done in batches"; steps (1) to (5) are Claude mechanics |
| D-142 | Incremental and release gates: "I'd mostly like these initial tests to be as fast as possible with an end-to-end test of the entire new version once a significant new ver | Brandon | Brandon, 2026-10-28 |
| D-143 | Automation performance: "Yes please speed up automation for testing and performance. Feel free to consolidate/refactor as long as no functionality is lost." The product's | Brandon | Brandon quoted: "Yes please speed up automation" |
| D-144 | Admin navigation and tab icons, UX PR 2 . (1) Find, Import and Bulk Update stay off every app's navigation and open from their Data Manager cards (D-135); the Bulk Update | Brandon | (Brandon, 2026-10-28; settles the open point in D-140 item 2) |
| D-145 | Edition stored values: `BarnCRM_Settings__c.Suite__c` stores `Standard` and `Nonprofit` instead of `Community` and `Impact`, every `BarnCRM_Module` record's `Editions__c` | Brandon | (Brandon, 2026-10-29; amends D-96 and ADR-0122's "internal values unchanged") |
| D-146 | Tab Access Check runs hourly: the "BarnCRM Tab Access Check" scheduled job (`TabAccessScheduler`, cron `0 0 * * * ?`) runs every hour, so people given a role in Setup get | Brandon | (Brandon, 2026-10-29; amends ADR-0124's nightly schedule) |
| D-147 | No paid mentions: no paid options, tiers, add-ons, services or established sponsorships are mentioned in the package, the docs or the websites. Long-term strategy stays i | Brandon | (Brandon, 2026-10-29) |
| D-148 | Giving security decisions: acknowledgment emails honor Email Opt Out (an email gift whose recipient contact has HasOptedOutOfEmail is not emailed and the letter run thank | Brandon | (Brandon, 2026-10-29; ADR-0144) |
| D-149 | Custom-named households: Household Upkeep and Update All Household Names fill blank greetings only; Name and any greeting with a value are never changed. Owner approved.  | Brandon | (Brandon, 2026-10-30; rule R-H8) |
| D-150 | Super Importer fuzzy matching: object and field names are fuzzy matched only when no exact match exists, shown with an amber "Best guess, check it" badge that must be acc | Brandon | (Brandon, 2026-10-30; Section 11.2 item 34) |
| D-151 | Super Importer new-field creation: admins only; the app calls its own org's Metadata API through a one-time admin-set connection (ADR-0082 S15 pattern); the new field get | Brandon | (Brandon, 2026-10-30, "Approved to allow it"; Section 11.2 item 35; C-49d) |
| D-152 | Import row correction: a failed staged row is edited on screen with the original file values kept beside the corrections, then Retry This Row or Retry All Fixed Rows. Sup | Brandon | (Brandon, 2026-10-30; Section 11.2 item 36; C-49b) |
| D-153 | Staging retention and undo back from the trash, not create a redundant copy"; Section 11.2 item 37; C-49b): the retention options (delete once complete, after 30 days as  | Brandon | (Brandon, 2026-10-30, "Undo should be able to bring the deleted record(s) |
| D-154 | Super Importer landing batch additions: Advanced Duplicate Management (C-51: merge rules for which value wins, household-aware pairing, auto-merge of exact matches with u | Brandon | (Brandon, 2026-10-30) |
| D-155 | Release plan: every open, approved item is placed in a numbered release of about 3 major and 3 to 6 minor enhancements; each landing batch covers 2 or 3 releases, with th | Brandon | (Brandon, 2026-10-31; Section 6.0a, Section 9.7) |
| D-156 | Competitive research additions: Brandon gave standing authorization to add features consistent with the vision to the roadmap and releases without his approval. 48 ideas  | Mixed | Brandon gave standing authorization; Claude chose the 48 ideas |
| D-157 | Research proposals approved and v1.0 timing . Brandon: "Backup and Import should be fairly late additions compared to other functionality but otherwise all eleven researc | Mixed | Brandon approved proposals (quoted timing note); proposals are Claude |
| D-158 | ADR-0150 to ADR-0154 assigned at landing batch A (2026-10-31): ADR-0150 digit-format step and saved step lists (#771); ADR-0151 Programs module (#774; P-04 to P-08 cite i | Claude | no attribution (integrator) |
| D-159 | Setup notes whose change is done are hidden, not shown as Done | Brandon | (Brandon, 2026-10-31) |
| D-160 | Affiliation primary tie-break (C-49f1, #773): when several rows in one load are flagged primary, the higher Id wins by case-sensitive Id compare, so the last flagged row  | Claude | no attribution |
| D-161 | Donor segments (G-28, #778, #782) are saved Find queries | Claude | no attribution |
| D-162 | Reminder defaults: pledge reminders (G-30) and shift reminders (V-10) default off; ask reminders default on | Claude | no attribution |
| D-163 | Pledge reminder with a blank or bounced email address goes to the letter channel | Mixed | Brandon's recommended call in the pre-batch review; no direct quote |
| D-164 | Logic model stage change is refused when an arrow would point backward (L-01) | Claude | no attribution |
| D-165 | Batch A pre-batch review (Section 9.8, 2026-10-31): 23 QA fixes, 17 UX fixes and a simplification pass of about -1,650 net lines with no functionality removed; follow-ups | Claude | no attribution |
| D-166 | Batch A deployed to barn-npc 2026-11-01 (main a3a2e7f3, 4,028 of 4,028 tests) after four barn-npc-only test fixes (#806); functional QA there (no browser) passed every ba | Claude | no attribution |
| D-167 | Brandon 2026-11-02: all v1.0 development (releases 0.15 to 0.17, Batch B) is built before any testing cycle; landing, the release gate, barn-npc and mwdbdevsb deploys and | Brandon | Brandon 2026-11-02 |
| D-168 | Batch B build decisions: cohort membership is the enrollment's Cohort lookup (no junction object); session attendance is one Service_Delivery__c per person per session; g | Claude | no attribution (integrator) |
| D-169 | Owner decisions 2026-11-02: the bulk change tool is renamed Super Transformer (visible text only; replaces Super Transform wherever the plan names the tool); Health Check | Brandon | (Brandon) |
| D-170 | Usability and visual scope for v1.0: (1) Picklist value usage (C-57) on large objects counts in batches to keep the supported record count high: one grouped COUNT per val | Mixed | Brandon set scope (2026-11-04); items (1) and details are Claude |
| D-171 | Help text out of labels; open questions 42 to 45 . (a) Help, description and guidance prose moves out of custom labels into packaged English-only JSON help files (one sta | Brandon | (Brandon, 2026-11-04; Sections 6.0a, 11.2; amends D-168's "help paragraphs to links held") |
| D-172 | Help catalogs and messages . (a) Help and guidance prose lives in per-package English JSON help catalogs named `BarnHelp_<Package>.json` (ADR pending number, "help-text-j | Brandon | (Brandon, 2026-11-04; amends D-168 and D-171; Sections 4.14, 6.0a) |
| D-173 | Architect review of limits and runtime: all recommendations approved . (1) A per-package Apex size budget in CI, an install pre-check and a character trim pass; a managed | Mixed | Brandon approved all recommendations (2026-11-04); recommendations are Claude |
| D-174 | Platform Starter licenses are not a target: nothing has to be compatible with them, alongside the Professional Edition decision (Section 11.2, item 11). The trigger frame | Brandon | (Brandon, 2026-11-04) |
| D-175 | Project Management module for later: "Please also add to the roadmap for later a PM Module which can handle projects in various ways, including Salesforce implementation  | Brandon | (Brandon, 2026-11-04; Section 6.0a Release 1.18, Batch I) |
| D-176 | Giving Staff can delete Gift Allocations, so staff can correct a split without an admin; applied with the Giving v1.0 usability work (WS4, PRs #879 and #880) in the nonpr | Brandon | (Brandon, 2026-11-04: "Yes, givers can delete gift allocations.") |
| D-179 | mwdbdevsb scope: future mwdbdevsb deployments leave out the Volunteers module, Duplicate Management and the Rollup Builder (turned off and not installed there), and keep  | Brandon | (Brandon, 2026-11-05) |
| D-180 | Household duplicate pairs need household evidence: a pair from the org's Account duplicate rules is kept only with the same street and city or postal code, the same phone | Mixed | owner QA finding (2026-11-05); matching evidence rule is Claude (ADR-0168) |
| D-181 | Field Use shows Required, Default Value and At Default; required fields and checkboxes are counted | Mixed | owner request (2026-11-05); columns and counting are Claude (ADR-0169) |
| D-182 | Record Inspector opens on its own page: a BarnCRM Admin only tab and app page, with an Inspect This Record button on Contact and Account pages; the inline component stays | Mixed | owner request (2026-11-05); page design is Claude |
| D-177 | Release plan re-slot . Batch C is now 1.1 Forms engine and Contact Point Sync, 1.2 Event Management core, 1.3 Event Management complete (EV-06, EV-09, EV-12, EV-11, EV-15 | Brandon | Brandon, 2026-11-04: "Address verification and online donation pages can move |
| D-178 | C-46 Address Verification stops being a Portal Builder and Corporate Hub prerequisite, and portals move into Batch C: C-45 stays before Portal Builder and Corporate Hub.  | Brandon | (Brandon, 2026-11-04: "Yes"; amends D-118 and D-177) |
| D-183 | Owner answers 2026-11-06: the 2026-11-04 Batch C re-slot (D-177, D-178) stands; mwdbdevsb Batch B deploy approved with the D-179 removal of the Rollup Builder code there; | Mixed | Brandon answers 2026-11-06; some items Claude process notes |

## (b) Non-goals, "deliberately not", "never" and "out of scope" statements (Sections 1 to 5, plus Section 11.3 parking lot)

Who: Brandon = owner attribution or owner-made D-row; Unattributed = no owner marker (likely Claude); Superseded = Brandon has since reversed or amended it.

| Section | Quote (short) | Who | Evidence |
|---|---|---|---|
| 1.3 | Principles 1 to 8 (admin needs no Setup, "turn on only what you use", compatible with nothing special, opinionated defaults, upgrade-safe, built to be contributed to, nothing built that already exists) | Unattributed (plan baseline) | No owner marker; principle 4 rests on D-09 (Claude), principle 3 on D-03 (Claude). Principles 1 and 5 are echoed by Brandon D-62, D-126 |
| 1.5 | "Not a standalone product and not a multi-platform product... no non-Salesforce runtime is built here" | Unattributed | No owner marker. Brandon's WordPress-portability agreement (plan 9.9) already leans the other way |
| 1.5 | "Not an online giving platform, payment processor, email marketing tool, or donor portal... Experience Cloud portals are out of scope" | Unattributed, partly superseded | No owner marker. Brandon added Portal Builder (D-118) and online donation pages (D-177); Experience Cloud portals reason (license cost) is Claude's |
| 1.5 | "Not a replacement for Agentforce Nonprofit's Industries features" | Unattributed, partly superseded | Grantmaking part amended by Brandon D-122 |
| 1.5 | "Not a consulting accelerator or migration tool for partners... agency tooling is not the audience" | Unattributed | No owner marker; D-125 and C-48 later add migrations roadmap |
| 1.5 | "Not a general CRM. No sales pipeline, no B2B features beyond organizational donors and funders" | Unattributed | No owner marker; D-95 (any org size) and D-99 (Standard Edition for for-profits) pull against it |
| 3 (Suites) | Nonprofit-only modules "never offered" in Standard Edition | Brandon | D-99, D-81 |
| 4.2 / 4.5 | "Never require any Industries permission set license"; Core names no standard object | Unattributed | D-09 has no owner marker (Claude); ADR-0013 |
| 4.2 | Multi-currency and Platform Encryption "not supported in v1" | Unattributed | No owner marker |
| 4.2 | UI strings in labels, "English only in v1" | Unattributed (help text part Brandon D-171, D-172) | No owner marker for English only |
| 4.6 | Household record type "no user is ever given it"; households created only through BarnCRM's system-mode writer | Mixed | ADR-0141 / D-134 approved by Brandon "as recommended"; mechanism is Claude |
| 4.7 | "Third-party verification was out of scope" | Superseded | Brandon D-112 added Address Verification module |
| 4.7 | Core never reads or writes ContactPoint objects | Brandon | D-111 (Brandon, 2026-10-25) |
| 4.8 | Settings: org-wide only, never blank, read-only Setup values | Brandon | D-126, D-127 |
| 4.8 | Packaged permission sets "never meant to be cloned" | Unattributed | No owner marker |
| 4.9 | "What we deliberately do not build": metadata deploy, anonymous Apex, API exploration | Unattributed, partly superseded | No owner marker; Brandon D-151 allowed Metadata API calls for field creation, D-132 admin-deployed triggers, CMDT Manager deploys metadata |
| 4.9 | "...permission management (except Field Access Manager C-65)" | Unattributed, amended by Brandon | D-157 approved the C-65 exception |
| 4.9 | "...org-wide automation switches" | Unattributed (confirmed written by Claude) | Brandon 2026-11-06 finding; the plan itself already has an org-wide pause (C-23, ADR-0055) and per-automation switches (D-93), so the non-goal contradicts shipped behavior |
| 4.9 | "...org-to-org migration and backup" | Brandon, later amended | D-13 (Brandon, 2026-09-23); D-50 "D-13 still holds"; D-157 amends D-13 (backup becomes a late addition) |
| 4.9 | "v1 accepts no typed SOQL (owner decision, 2026-09-23)" | Brandon, later amended | D-27 accepted typed Find queries parsed in the browser (Mixed, standing instruction) |
| 4.9 | "CSV is the only export format in v1, by owner decision 2026-09-23" | Brandon | Owner decision 2026-09-23 |
| 4.9 | "a server-side export for larger sets is not built" (50,000 row default limit) | Unattributed | No owner marker |
| 4.9 | "Automation still runs... never pause automation themselves" during import and bulk update | Unattributed | No owner marker |
| 4.9 | "Queries are built from a document, never from text"; fields that can never be bulk updated or imported over | Unattributed | No owner marker (ADR-0078 / D-27 Mixed) |
| 4.9 | Staged import rows retention | Brandon | D-40, D-153 |
| 5.1 C-10 | Sample data never added by default in the real package | Brandon | "Brandon, 2026-10-12" |
| 5.1 C-39 | Confidential interaction notes not built | Brandon | D-19 (Brandon, 2026-10-12) |
| 5.1 C-48 | Mass Action Scheduler never listed; overlapping tools shown only if installed | Brandon | D-125 and owner memory note |
| 5.2 | "matching gift company data is out of scope" | Unattributed | No owner marker |
| 5.2 | Gift donor is Contact or Account, "never both"; refunds are new negative gifts, not edits | Unattributed | D-10 has no owner marker (Claude) |
| 5.2 | Receipts immutable | Unattributed | D-10 / ADR-0010 no owner marker (Claude); escalation rule 11.4 also Claude |
| 5.5 F-09 | Paid directories "never a BarnCRM-paid API" | Brandon | Brandon's no-paid-API rule, D-147 |
| 5.x LB-05 | Conditional block visibility is "a display rule, never a security control" | Unattributed | No owner marker |
| 5.12 EV-11 | Template opt-in, "never applied by default" | Unattributed | No owner marker |
| 11.3 | Parking lot: peer-to-peer fundraising, wealth screening, text-to-give, multi-org affiliate roll-up reporting, in-app AI assistant, email marketing beyond export | Unattributed | No owner marker ("good ideas, deliberately not now"); written by Claude |
| 11.3 | "Donor portal and online giving (license and PCI burden)" | Unattributed, partly superseded | D-118 Portal Builder, D-177 online donation pages |
| 11.3 | "Grantmaking as a funder" | Superseded | Reversed by Brandon D-122 |
| 11.4 | Builder must escalate: new package dependency, standard-object reference outside Mirror, required Setup step, household abstraction, versioning or namespace, receipt immutability, gift amount mutability | Unattributed | No owner marker; Brandon's D-62 covers only Setup steps |


## (c) ADRs

### (c1) Status is exactly "Accepted" (no owner marker): Claude-made engineering decisions

Caveat: some may have been approved in a batch by Brandon (for example D-22, D-25 to D-36 standing instruction) without the ADR status saying so; they are Claude-designed either way.

| ADR | Title |
|---|---|
| 0002 | Second-generation managed packages with one shared namespace |
| 0003 | Core package plus separate module packages, feature flags for minor behavior |
| 0004 | Custom Gift object as the gift system of record, with optional mirrors |
| 0005 | Household as an Account record type with two membership modes behind one service |
| 0006 | Settings storage: custom settings, custom objects, and custom metadata |
| 0007 | Salesforce CLI plus GitHub Actions, CumulusCI optional later |
| 0008 | License: Apache-2.0 |
| 0009 | No Person Account, Industries, OmniStudio, Data Cloud, or Experience Cloud dependency |
| 0010 | Receipts are immutable; corrections void and reissue; refunds are negative linked gifts |
| 0012 | Trunk-based development with squash merges and an always-releasable main |
| 0013 | How the Platform-only org shape is provisioned and verified |
| 0014 | Core holds Giving record identifiers, not lookups |
| 0017 | Cross-package mechanisms under one namespace: NamespaceAccessible, per-package settings objects, registry-driven trigger dispatch |
| 0018 | Each module ships its own Lightning app; the Hub links to the module apps |
| 0019 | Nonprofit Settings picklist keys are stored as text |
| 0020 | Module settings pages reached by navigation, Core pages by literal import |
| 0021 | System-mode writes for package-owned data through dedicated writer classes |
| 0022 | Packaged giving rollups include reversed gifts, and count gifts rather than transactions |
| 0023 | A refunded gift keeps its soft credits, and the negative gift reverses them |
| 0024 | The receipt lock survives the automation switch, and lifting it is a deliberate act in Setup |
| 0026 | What the retention reports count, and the one attribute they needed |
| 0027 | The seasonal address swap runs in system mode, gated at the controller |
| 0028 | A donor level labels an existing rollup, and follows that total down |
| 0029 | Shipped rollups are created by each package's post-install script |
| 0030 | An in-kind gift is a gift type carrying no amount, and its value is rolled up separately from money |
| 0031 | A refund of the employer's gift reverses the matched donor credit, along the link |
| 0032 | Acknowledgments send standard email templates and keep a ledger, sharing no machinery with receipts |
| 0033 | A receipt number comes only from the sequence, so the field is package written |
| 0034 | A receipt document is reached only through the records a Giving permission set governs |
| 0035 | A setting that ships switched on is switched on in Apex, not by its field default |
| 0036 | An empty household is deleted only when nothing outside BarnCRM depends on it |
| 0037 | Junction mode creates a household for a new person, under the one setting that already says so |
| 0038 | The Giving nightly jobs are scheduled from the settings console |
| 0039 | Health Check findings are grouped by the question they ask, not registered one by one |
| 0040 | Simple rules in Flow, engine logic in Apex, and customers switch ours off to run theirs |
| 0041 | Core ships no Contact record type |
| 0042 | Packaged records use activities, not Chatter |
| 0043 | Record pages use Dynamic Forms, with one fallback layout per object and no layout assignments |
| 0045 | Gift batch entry keeps its own lines rather than staging through the import framework |
| 0046 | Two suites from the same packages, a tentative name, unlocked now and managed at listing |
| 0051 | The inbound gift API keeps a small permanent surface, and the accounting export marks nothing |
| 0054 | A Pending gift that will never be paid is cancelled, not written off |
| 0067 | An import matches a person with a first name only by that first name |
| 0068 | Import matching per entity, a rule for several matches, and values for every row of a file |
| 0088 | Pilots move from unlocked to managed packages with a command-line kit that reimports through the REST API |
| 0091 | Bulk delete runs from a Find query, as the user, and is undone by undelete |
| 0130 | Contact relations are not native households in an org without native household groups (narrows ADR-0036) |
| 0131 | A module gives its sets to holders of a BarnCRM role, and Core asks it at Turn on and nightly |
| 0132 | A module lists its permission sets on the Access page by shipping Access Add-On rows |
| 0166 | One nightly job dispatcher runs every BarnCRM nightly job in sequence |
| 0168 | A household pair from the org's duplicate rules is shown only with household evidence (narrows 0050) |
| 0169 | Field Use shows required, default value and at default; required fields and checkboxes are counted |

### (c2) Status "builder decision" or Proposed (builder decision): also Claude-made, listed by number and title

| ADR | Title | Status |
|---|---|---|
| 0048 | Health Check fix buttons create or set, never delete, and ask first | Accepted (builder decision) |
| 0049 | Excel workbooks are read in the browser without SheetJS | Accepted (builder decision); amended by ADR-0146 |
| 0050 | Duplicate detection uses the org's own duplicate rules, and BarnCRM ships none | Accepted (builder decision) |
| 0052 | Gift import through the entity processor seam, and donation matching | Accepted (builder decision) |
| 0053 | Posted gifts and closed periods are locked by a rule that always runs | Accepted (builder decision) |
| 0055 | A pause ends through a one-time resume job, and the error digest counts and goes only to users | Accepted (builder decision) |
| 0056 | Campaign sync keeps its link on the appeal, writes with the saver's access, and is off until switched on | Accepted (builder decision) |
| 0057 | A Health Check extension seam lets a dependent package add findings without Core depending on it | Accepted (builder decision) |
| 0058 | The Opportunity mirror keeps its link on the gift, runs one way at a time, and reconciles on a page | Accepted (builder decision) |
| 0059 | Core is neutral: the nonprofit app, wording, giving and receipt settings and Setup Assistant steps live in Giving | Accepted (builder decision) |
| 0061 | A module's first settings save takes its checkbox defaults from field metadata | Accepted (builder decision) |
| 0072 | The suite choice is a Core setting the Setup Assistant asks first | Accepted (builder decision) |
| 0073 | The Module Manager switches a module's automation, links to installs, and counts before an uninstall | Accepted (builder decision) |
| 0074 | The settings console picks records and record types instead of taking identifiers | Accepted (builder decision) |
| 0075 | Health Check schedules every nightly job with one fix, and modules register theirs (amends ADR-0048) | Accepted (builder decision) |
| 0076 | Saved queries are private and shared by Apex managed sharing | Accepted (builder decision) |
| 0077 | Bulk update runs as the user, from a Find query, and is undone by the import undo | Accepted (builder decision) |
| 0079 | Data hygiene checks are Find queries built at request time | Accepted (builder decision) |
| 0080 | Import loads one object: insert, update by record ID or upsert, with an allow-list and journaled creations | Accepted (builder decision) |
| 0081 | Column changes as a declarative transform document, and import matching through the org's duplicate rules | Accepted (builder decision) |
| 0086 | Field utilization ships in Core, counts in user mode, and keeps weekly snapshots | Accepted (builder decision, as recommended); superseded in part by ADR-0101 (field utilization on demand) |
| 0087 | What's new is read from packaged release notes and remembered per person | Accepted (builder decision) |
| 0089 | Interaction notes are completed tasks logged through one packaged action | Accepted (builder decision) |
| 0090 | Flow templates: which automations get one, how they are named, and what they leave out (applies ADR-0040) | Accepted (builder decision) |
| 0092 | Merge survivors' real-time totals are recalculated just after the merge | Accepted (builder decision) |
| 0093 | Simple record reads in LWCs go through Lightning Data Service, not Apex | Proposed (builder decision) |
| 0094 | Configuration reads use the platform's own caches; Core ships no Platform Cache partition (amends ADR-0006 decision 1) | Accepted (builder decision) |
| 0095 | User access policies are documented definitions, not packaged components | Proposed (builder decision) |
| 0096 | First-visit tips are packaged In-App Guidance prompts, single step, managed in Setup | Proposed (builder decision) |
| 0097 | Every packaged record page places its own actions, and Giving's own pages their own related lists (amends ADR-0043) | Accepted (builder decision) |
| 0098 | Real-time rollups are recalculated just after the save, by default (modifies ADR-0082 decision 4) | Proposed (builder decision) |
| 0100 | A platform event starts the Rollup Queue after a save inside a Queueable | Accepted (builder decision) |
| 0104 | Core ships four agent-ready Flow actions, and no agent metadata | Accepted (builder decision, Q-14 approved by the owner) |
| 0105 | Health Check reschedules jobs whose owner was deactivated (amends ADR-0048, extends ADR-0075) | Accepted (builder decision) |
| 0110 | Erase a person anonymizes the record in place, as the user, with a module seam | Proposed (builder decision) |
| 0112 | Six more transform steps (map values, if then, keep part, first or last characters, shift a date, today), still a closed list with no evaluation | Proposed (builder decision) |
| 0113 | Import row rules: skip rows and one row per key decided at staging, and empty cells that clear a field only where a column says so | Proposed (builder decision) |
| 0114 | Delete by file is a one-object import operation that hands its dry run to the bulk delete job | Proposed (builder decision) |
| 0115 | Find's export to Files is a Batch Apex job that writes CSV parts the person owns | Proposed (builder decision) |
| 0116 | Rollup totals too large for a Queueable are recalculated by a batch over their source rows | Accepted (builder decision) |
| 0117 | A save that queues Rollup Queue entries and no processor asks again after it commits | Accepted (builder decision) |
| 0118 | A merge that cannot queue its tidy-up asks for it after commit | Accepted (builder decision) |
| 0119 | Import undo judges edits before it deletes, and a rollup's save is not an edit | Accepted (builder decision) |
| 0121 | Permissions only a Salesforce license can hold live in optional sets, never in a role | Accepted (builder decision) |
| 0138 | Instant totals on any object: the Builder generates the trigger, the admin deploys it (amends ADR-0082 decision 8) | Proposed (builder decision) |
| 0150 | A digit-format transform step, a shared fixture, and saved step lists | Proposed (builder decision) |
| 0157 | The Gift Transaction mirror copies gifts one way, in runs, with designations from each fund's link | Accepted (builder decision) |
| 0159 | Where Used reads BarnCRM's own setup records, and modules add theirs through an extension seam | Proposed (builder decision) |
