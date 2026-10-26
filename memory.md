# Memory

Purpose: project context, decisions and rationale not derivable from code or git. Mirrors Sections 11 (open questions, parking lot) and 12 (decision log) of the BMemory plan `specification/open-impact-product-plan.md`, which is canonical: change BMemory first, then this file and `docs/product-plan.md`. Architecture decisions are recorded as ADRs in `docs/architecture/decisions/`; this file points to them rather than copying them.

Last refreshed from BMemory 2026-10-25 (through D-116; open questions 28 and 29 resolved by D-114 and D-115).

## Decision log (plan Section 12)

| ID | Date | Decision |
|---|---|---|
| D-01 | 2026-09-06, 2026-09-23, 2026-10-12 | Product name: "Open Impact" working title, then BarnCRM (cleared 2026-10-12); namespace deferred (ADR-0046) |
| D-02 | 2026-09-06, amended 2026-09-23 | Second-generation managed packages with one namespace for the listing; unlocked packages until then (ADR-0046) |
| D-03 | 2026-09-06 | Core plus separate module packages; feature flags for minor behavior |
| D-04 | 2026-09-06 | Custom `Gift__c` is the gift record; Opportunity and Gift Transaction are optional mirrors in Connect (renamed BarnCRM Mirror, D-103) |
| D-05 | 2026-09-06 | Household is an Account record type with two membership modes behind one service |
| D-06 | 2026-09-06 | Settings: hierarchy custom settings for toggles, custom objects for lists, custom metadata for shipped defaults |
| D-07 | 2026-09-06 | `sf` CLI plus GitHub Actions; CumulusCI optional later |
| D-08 | 2026-09-22 | License Apache-2.0 |
| D-09 | 2026-09-06 | No Person Account, Industries, OmniStudio, Data Cloud or Experience Cloud dependency |
| D-10 | 2026-09-06 | Receipts immutable (void and reissue); refunds are negative linked gifts |
| D-11 | 2026-09-06, superseded 2026-10-12 | Vendor a rollup library before building; superseded by D-16 |
| D-12 | 2026-09-06 | Trunk-based development, squash merges, `main` always releasable |
| D-13 | 2026-09-23 | Data management scope and phasing: in-org import, Find and bulk update; new v0.7 iteration (ADR-0047) |
| D-14 | 2026-09-24 | Cancelled status for unpaid Pending gifts (amends G-04) |
| D-15 | 2026-09-24 | Second long-lived test org `oi-pa` (Person Accounts), gated locally |
| D-16 | 2026-10-12 | BarnCRM owns its rollup engine; apex-rollup removed after a clean comparison run (new ADR, supersedes ADR-0015) |
| D-17 | 2026-10-12 | Import matches by record ID, "match only" option, custom fields in the wizard (C-32); pledge payment picker in gift entry |
| D-18 | 2026-10-12 | Rollup comparison recommendations: slices S15 to S17, operations slice after S8, deferred items listed |
| D-19 | 2026-10-12 | Confidential interaction notes not built; notes stay completed Tasks |
| D-20 | 2026-10-12 | A gift stays credited to the household it was given to (amends R-G2; new ADR) |
| D-21 | 2026-10-12 | "What's new" notes (C-27) are labelled by release; first is "0.6" |
| D-22 | 2026-10-12 | New ADRs accepted: migration kit, Flow templates, suite choice first, Module Manager, interaction notes as Tasks, settings record pickers, Health Check schedules nightly jobs |
| D-23 | 2026-10-12 | Platform capabilities: keep LWC, audit API 67.0 access modes, Apex Cursors, GraphQL in new screens, AI-ready action descriptions, cheap portability steps; avoid Data 360, Heroku AppLink, Functions and similar |
| D-24 | 2026-10-12 | Telemetry (C-26) deferred indefinitely: no AppExchange for now; if listed later, prefer AppExchange App Analytics |
| D-25 | 2026-10-12 | CMDT Manager: only the org's own relationship types editable; a BarnCRM Settings (General) section, not a tab; permission set without Customize Application or Modify Metadata (ADR-0085) |
| D-26 | 2026-10-12 | Field utilization ships in Core: weekly user-mode count Sundays 04:00, 13 months kept, Account, Contact and custom objects only (ADR-0086) |
| D-27 | 2026-10-12 | Typed Find queries parsed in the browser into the query document; the server never takes SOQL text (C-36, ADR-0078) |
| D-28 | 2026-10-12 | Column changes as a declarative transform document; import matching through the org's duplicate rules (C-37 part 1, ADR-0081) |
| D-29 | 2026-10-12 | Health Check keeps its orphan findings alongside the Data Hygiene tab (C-28) |
| D-30 | 2026-10-12 | Nightly rollup run skipped and logged when a Recalculate all is already running (rollup S8) |
| D-31 | 2026-10-12 | Rollup operations: count distinct its own operation, delimiter picklist, Any and None read no field, count distinct into plain numbers only, unfit target refused |
| D-32 | 2026-10-12 | Rollup Builder estimate uses 1,650 records a minute until measured; S14 only if the scale test needs it |
| D-33 | 2026-10-12 | Tests run as a permission-set user (`TestUsers`, on the running user's profile), checked by `check-tests-run-as.py` |
| D-34 | 2026-10-13 | C-37 part 2: bulk delete run limit default 10,000 (at most 48,000); `Bulk_Delete_Records` only in its own `BarnCRM_Bulk_Delete` permission set; undo until the earlier of the import undo window and 15 days; bulk update refuses a transform result the field cannot take (ADR-0091) |
| D-35 | 2026-10-13 | Merge survivors' real-time totals recalculated by a queueable just after the merge (ADR-0092) |
| D-36 | 2026-10-13 | Import uses a Person Account record type available to the running user; with none, it creates nobody and logs one note (#221) |
| D-37 | 2026-10-13 | Field utilization runs on demand from its own Field Utilization tab; no scheduled job, history or tracked list (supersedes those parts of ADR-0086 and D-26; ADR on `feature/field-utilization-on-demand`) |
| D-38 | 2026-10-13 | Priority: a Core quality pass (test, optimize, improve, simplify, nothing removed) comes before C-38 and the non-core modules |
| D-39 | 2026-10-13 | All 14 recommended platform features join the Core quality pass as Q-01 to Q-14, built in parallel now (`feature/q-NN-<slug>`; Q-14 optional, approved); C-38 on hold until Brandon is ready to start the next version |
| D-40 | 2026-10-13 | Error Log entries older than 180 days deleted; staged import rows purged 90 days after their job finishes; both adjustable in BarnCRM Settings; every number setting has a minimum and a maximum |
| D-41 | 2026-10-13 | (affiliation part reversed by D-49) Affiliations stay out of Core imports (spec and admin guide corrected; amends C-32); import templates shipped in later versions added to existing orgs on upgrade, not only through Health Check |
| D-42 | 2026-10-13 | "What's new" entries (C-27) refreshed from the release notes as part of each release |
| D-43 | 2026-10-13 | The 9 components used only inside the BarnCRM Settings console are no longer offered in App Builder |
| D-44 | 2026-10-13 | Fundraising Staff permission set group includes Giving Staff (closes plan 11.2 item 12) |
| D-45 | 2026-10-13 | The renamed import tab reads "Data Jobs" in Title Case (amends ADR-0047 wording) |
| D-46 | 2026-10-13 | Dev Hub snapshot `BarnPA` from `oi-pa` approved (Q-12) |
| D-47 | 2026-10-13 | Duplicate rule matching and anything else unfinished in Core finished before version 1 (not post-1.0 themes or C-38); inventory done 2026-10-14 (#401 to #408) |
| D-48 | 2026-10-13 | Core review recommendations approved: rollups recalculate only definitions that marked a target (ADR needed; narrows ADR-0082 decision 2); Instantly-mode fiscal-window rollups in the nightly run; Recalculate now checks budget and queues; import commit runs the previewed template; organizations created only for passing rows; people import reads values like Load one object; bulk delete undo covers deleted empty households; Health Check on Home shows last result plus Run now; one shared LWC helper module; faster test runs; namespace-safe object resolution. Code coverage still checked automatically on every gate, read via ApexCodeCoverageAggregate |
| D-49 | 2026-10-13 | Affiliations return to Core imports: a people import links each person to the organization on their row by an affiliation. Reverses the affiliation part of D-41; plan Section 4.9 and C-32 restored |
| D-50 | 2026-10-13 | Data tools parity (D-13 still holds): Data Manager hub with one job history and Undo; Org Optimizer page (Data Hygiene relabeled; Overview, Data quality, Duplicates moved from Settings, Field utilization embedded only here, Health Check on demand, Errors, Storage and limits, Unused setup admin-only, Automation and jobs); full results file; trial import (default 25 rows, a setting, per-file override, rest in the same job and undo); delete from a file of IDs; more transform steps; lookups and update matching on any Text, Email or Phone field; skip rows and one row per key; empty cells clear the field (off by default, journaled); delimiter and worksheet choice; download before delete; retry rejects into the same job; server-side export (C-36 remainder, in v1); parent and child loads. Not approved: seeding templates, files import. Scheduling and connectors stay C-38 on hold |
| D-51 | 2026-10-13 | Import tab label is "Import" (amends D-45 for the tab), reached from Data Manager; Import and Bulk Update leave the app navigation; Find stays; job object label stays "Data Job" |
| D-52 | 2026-10-13 | Erase a person (right to be forgotten) built in Core, with a Giving extension for gifts and receipts |
| D-53 | 2026-10-13 | Commitment page: Clone and Printable View stay off |
| D-54 | 2026-10-13 | Team Member (`Program_Staff`) and Coordinator (`Volunteer_Coordinator`) groups get their module permission sets when those modules ship |
| D-55 | 2026-10-13 | Shipped import templates added at install and on upgrade (closes Section 11.2 item 14) |
| D-56 | 2026-10-13 | Org gates may batch several PRs into one combined org run and deploy only changed metadata; every test that would have run still runs |
| D-57 | 2026-10-13 | Console app: on oi-test, oi-pa and barn-core Claude deletes and redeploys the app; on barn-npc and mwdbdevsb the owner switches Navigation Style to Console in App Manager |
| D-58 | 2026-10-13 | Logo: blue barn icon approved as is, replacing red #B3261E: walls #00A8D9 (the blue in the Blue Bottle Coffee logo file), roof and app header #007A9E (4.91:1 against white); set on feature/console-app-icon at 4047fc85 |
| D-59 | 2026-10-13 | Console tab icons: keep the page icons set by Q-07 |
| D-60 | 2026-10-13 | Q-11: no Platform Cache for now; revisit after security review |
| D-61 | 2026-10-13 | Q-09: user access policies documented with samples, not packaged |
| D-62 | 2026-10-13 | Setup prerequisites: avoid Setup changes; when a feature needs one, the matching BarnCRM Settings section shows an instruction for it. Q-10 tips are turned off in Setup under this rule |
| D-63 | 2026-10-13 | Field utilization on demand: no 13-month auto-cleanup, no Health Check entry for the old job |
| D-64 | 2026-10-13 | ADR-0088 and ADR-0091 accepted; rollup S16 and S17 deferred to after v1; per-automation switch end date stays; neutral labels and one app stay |
| D-65 | 2026-10-13 | Coverage gate measures BarnCRM classes at 75% total and per class (not org-wide); the 23 low classes held at current figures until tests lift them |
| D-66 | 2026-10-13 | Q-05: confirm buttons Cancel then action; message-only toasts show the text as the bold main line; Health Check finding title not bold in the confirm |
| D-67 | 2026-10-13 | Q-04: job finish notifications on by default |
| D-68 | 2026-10-13 | The four Q-14 agent-ready actions get access through packaged permission sets and/or groups, not a manual Setup step |
| D-69 | 2026-10-13 | Q-14 scope: the four action classes are global (permanent once managed); no Update Person action (standard Update Record covers it); starting or committing imports from an assistant is out of scope |
| D-70 | 2026-10-13 | Record cards (Addresses, Affiliations, Relationships) that refuse a change for lack of access show a friendly message and write no Error Log entry; real failures still logged (Q-06) |
| D-71 | 2026-10-13 | Rollup totals recalculated just after the save by default (Background), with a "During the save" setting (Q-01, PR #256); modifies ADR-0082 decision 4 via a new ADR written on that branch (number assigned at merge) |
| D-72 | 2026-10-13 | RollupRecalcAction is global so subscriber Flow Builder can use it (permanent once managed) |
| D-73 | 2026-10-13 | (amended by D-83: InboundGiftAction lives in Connect (renamed BarnCRM Mirror, D-103), which depends on Giving, so Giving's sets cannot grant it) Giving's Record Inbound Gift action is granted by Giving's packaged permission sets, like D-68 |
| D-74 | 2026-10-13 | Setup notes for Giving and Connect (renamed BarnCRM Mirror, D-103) shown on each module's own page, using Core's note component (keeps ADR-0020) |
| D-75 | 2026-10-13 | (reversed by D-82) The Bulk Update and Bulk Delete sets' 31 shared grants move into BarnCRM Find and Export (PLATFORM-17) |
| D-76 | 2026-10-13 | All BarnCRM triggers declare all seven contexts, with a CI check, after PR #229 merges (PLATFORM-18) |
| D-77 | 2026-10-13 | The unused label Giving_SoftCredit_Duplicate is deleted as a leftover |
| D-78 | 2026-10-13 | Error_Log__c sharing stays Read/Write (all sets have View All; only Admin can edit; Read would break Mark as seen on others' entries) |
| D-79 | 2026-10-13 | Stored household names use the org default language for joining words ("and", list separator, "the late"), not the saving user's language |
| D-80 | 2026-10-13 | Plan corrections applied (closes Section 11.2 item 27): v0.3 row without NPSP import templates (v0.5); one test org, not four org shapes; TestDataFactory is @NamespaceAccessible (ADR-0017); X-07 at v0.6; D-14 cites ADR-0053 and ADR-0054; C-25 note says built, in main; 11.3 item 6 release note done (v0.7-draft-advanced-find.md); v0.11 accessibility, mobile and translation built, not merged (PRs #273 to #276), device mobile run open. Section 4.1 Nonprofit Hub entry still open |
| D-81 | 2026-09-23, numbered 2026-10-13 | Suites and packaging: Impact Suite (Core plus Giving, other modules offered) and Community Suite (Core alone); one install to start, guided installs after; Core neutral; unlocked now, managed at listing |
| D-82 | 2026-10-13 | D-75 reversed: the Bulk Update and Bulk Delete sets keep their own data job read grants (moving them would let Find and Export holders read every data job and the undo journal) |
| D-83 | 2026-10-13 | Connect's (renamed BarnCRM Mirror, D-103) Record Inbound Gift action gets its own small permission set granting only that action (amends D-73) |
| D-84 | 2026-10-13 | Working agreement: present only Core findings and decisions until the owner starts the modules; module notes go in plan Section 11.5, grouped by module. Goal now: Core v1.0 complete |
| D-85 | 2026-10-13 | Working agreement: implement recommendations and tell the owner what is being changed, unless really important or contrary to his instructions. Module reviews or audits already in flight can finish; their findings are not processed with him now unless they relate to Core |
| D-86 | 2026-10-13 | Erase a person: the preview lists activities and files for manual deletion (not erased automatically); Health Check skips erased people; PR #282 accepted at its size |
| D-87 | 2026-10-13 | Release prerequisites after a v1.0 pilot: namespace registration, the Dev Hub and the steward entity (Section 11.2 items 1, 3, 4) settled after piloting v1.0; no package version until then; upgrade-path tests wait for the first version |
| D-88 | 2026-10-13 | Deleting people never deletes their household, in every membership mode (R-H12, #377); moving people still tidies it. Reason: deleting a parent purges children deleted before it from the Recycle Bin, so deleted people could not be restored. Open option, tidy later after the Recycle Bin window: decided by D-89 (landed in #408) |
| D-89 | 2026-10-14 | A household left with no members after its people are deleted moves to the Recycle Bin, but only after its former members can no longer be restored from the Recycle Bin: a nightly Core job, on by default, switchable in Nonprofit Settings; households with other child records are kept and reported. Amends D-88, which protects restoring deleted people. Landed 2026-10-14 (#408, ADR-0120) |
| D-90 | 2026-10-14 | 25,000 rows is the scale bar for the pilot (Brandon); the 250,000-row import run comes later, in a sandbox (plan 7.3) |
| D-91 | 2026-10-14 | Salesforce-license-only permissions (Assign Permission Sets, View All Users) move out of BarnCRM Admin into the optional `BarnCRM_Access_Manager` permission set, which has no role; `Duplicate_Review` stays Sales/Service-only (ADR-0121, #406). Reason: Core runs on a Platform-only license (ADR-0013) |
| D-92 | 2026-10-14 | Product-branded names stay (Brandon; closes Section 11.2 item 24): BarnCRM Admin, Staff, Read Only, Duplicate Review, BarnCRM Settings. Superseded for the Core roles by D-97 |
| D-93 | 2026-10-14 | No end date on per-automation switches (Brandon; closes Section 11.2 item 16): they stay off until an admin turns them back on; the org-wide pause still expires (ADR-0055) |
| D-94 | 2026-10-14 | The pilot is a milestone below v1.0; Brandon decides version numbers |
| D-95 | 2026-10-14 | BarnCRM is open to any Salesforce org regardless of size, and extra valuable for small to mid-sized teams that lack the resources for many licenses and customization; it comes with powerful tools preloaded. The pilot is likewise open to any org size (not limited to one to ten users). The Nonprofit Edition is described as "like NPSP for Nonprofit Cloud", plus other useful tools (Brandon) |
| D-96 | 2026-10-14 | Edition names (Brandon): BarnCRM is one suite of tools in two editions, the Nonprofit Edition (formerly Impact Suite) and the Standard Edition (formerly Community Suite, for any other Salesforce org). Both have the full core suite of tools; the Nonprofit Edition is the Standard Edition plus the nonprofit tools (Giving and the other nonprofit modules); the Standard Edition is never called reduced, basic or a subset. Rejected: "Community Edition" (clashes with Salesforce Community Cloud and the Trailblazer Community; usually means a cut-down free tier). "Nonprofit Edition" already named the Setup Assistant toggle, so there is one meaning. Supersedes the names in D-81 (kept as written), ADR-0046 and ADR-0072 (ADR-0122) |
| D-97 | 2026-10-14 | Core roles have neutral names (Brandon; supersedes D-92 for the Core roles): Program Staff becomes Team Member and Volunteer Coordinator becomes Coordinator, labels and descriptions only; API names `Program_Staff` and `Volunteer_Coordinator` unchanged; BarnCRM Admin, Read Only and Giving's Fundraising Staff unchanged (ADR-0123, #413). Reason: Core is the whole Standard Edition (D-96); the names must fit any organization |
| D-98 | 2026-10-14 | Advanced Territory Management (C-40) and a Grid tool (C-41) are planned Core Super Tools, built after v1.0 (Brandon). Reason: common paid add-ons small teams cannot afford |
| D-99 | 2026-10-14 | Edition gates what Core shows (Brandon): nonprofit modules (Giving, Volunteers, Programs, Funders, Connect; renamed BarnCRM Mirror, D-103) are shown and offered only in the Nonprofit Edition; installed modules keep working; the module-to-edition mapping is data-driven. The edition is chosen once (first-run setup); afterwards it is changed only from BarnCRM Settings > General > Change edition (with confirmation) or Setup > Custom Settings. Volunteers moves from both editions to the Nonprofit Edition. Amends ADR-0072 and ADR-0062 decision 4 (ADR-0124, #426) |
| D-100 | 2026-10-14 | First-run setup and switches (Brandon): on first install a setup overlay covers BarnCRM Home and BarnCRM Settings until an admin completes it (edition, then "turn on all defaults" or choose); non-admins see that an administrator must finish setup. General shows the edition and a panel of modules and features with on/off switches; when a feature or module is off, its app tabs and Settings menu are hidden (tab visibility through permissions). Amended by D-102 |
| D-101 | 2026-10-14 | Modules versus features (Brandon): features are installed with Core and can be switched on or off (Data Manager with Import, Find and Bulk Update; Duplicate Review; Org Optimizer and Health Check). Modules are separate packages not installed with Core, installed from BarnCRM Settings, shown only for their editions, each with its own console app and Settings tab, each named "BarnCRM <name>" (Giving, Volunteers, Programs, Funders, Connect (renamed BarnCRM Mirror, D-103), Rollup Builder). "Super Tools" is a website and marketing name only. The Rollup Builder and rollup engine move out of Core into a new both-editions module, BarnCRM Rollup Builder, so orgs using DLRS or Rollup Helper can run them alongside BarnCRM; BarnCRM Giving depends on it (ADR-0125, rollup-builder-module). Landed 2026-10-15 in #438 (squash 4ed86f12) |
| D-102 | 2026-10-14, 2026-10-15 | Features off by default, modules installed from Settings, first-run setup (Brandon; amends D-100): Core features are off on a new install and are turned on only in first-run setup or later on Settings > General; turning one on is one-way, with a warning above the switches. Tabs and Settings menus stay hidden until their feature is on (packaged `BarnCRM_Tab_*` permission sets kept in step by a sync). Upgraded orgs count as every feature on. Modules are installed only from Settings > Modules, which then shows "Installed" with a link to the module's app. A blocking first-run window on Home and Settings asks an admin for the edition, then "turn on all the default core features" or "let me choose"; others see that an administrator needs to finish setup. A new install holds all Core automation, household creation included, until first-run setup turns features on; turning Household Upkeep on catches up people added before setup. Landed in #426 (ADR-0124) |
| D-103 | 2026-10-15 | The module BarnCRM Connect is renamed **BarnCRM Mirror**, API names included (Brandon): package folder `packages/connect` becomes `packages/mirror`; `Connect_*` API names become `Mirror_*`. ADR-0126 (rename-connect-to-mirror) |
| D-104 | 2026-10-17 | v0.8 Volunteers started and its design approved (Brandon; ADR-0127 to ADR-0129 on main): modules start now, ahead of plan 6.0 item 3. Owner approved the recommended option for each. (1) Hours totals through the BarnCRM Rollup Builder module: Volunteers depends on Core and Rollup Builder and ships its own rollup definition defaults. (2) Hour letters and certificates use Volunteers' own small letter generator (HTML-to-PDF like receipts), not Giving's receipts engine, so Volunteers needs no Giving. (3) Volunteer fields live on the person (Contact and Account) and ship with Volunteers; onboarding steps are a child record (`Volunteer_Requirement__c`); skills come from an admin list with a junction. (4) Four permission sets (Admin, Coordinator with `Manage_Volunteers` to approve hours, Staff, Read Only), given to holders of the matching BarnCRM roles by an access sync. (5) Recurring shifts: a schedule record and a nightly job keep shifts created to a rolling horizon (default 8 weeks); edits change only future shifts with no sign-ups. (6) Hours approval is a status on the hours record (Submitted, Approved, Rejected), approved hours locked, only approved hours counted. (7) v0.8 is done when built and tested unmanaged; install-link testing waits for the first package versions. Volunteers is nonprofit-only (D-99), never offered in the Standard Edition. |
| D-105 | 2026-10-18 | Deleting a person removes that person's volunteer requirements and volunteer skills; merging two people keeps them (Volunteers V-05; taken as recommended by the integrator, owner may amend). |
| D-106 | 2026-10-18 | Volunteers ships its own copies of the Core person pages (the ADR-0064 pattern), so the Volunteer Profile, readiness card and letter action appear on the Volunteers app's person pages; a copy can drift from Core's page (taken as recommended by the integrator, owner may amend). |
| D-107 | 2026-10-18 | The Volunteers lapsing-volunteers report stays Contact-only, so it shows no rows in Person Account orgs; a report type has a single base object (taken as recommended by the integrator, owner may amend). |
| D-108 | 2026-10-20 | Erasing a person deletes the hour letters and certificates BarnCRM generated for them (identified exactly, deleted in system mode after the access check) and lists them as Deleted; every other File stays, listed by Core as Kept (#506, amends the 2026-10-20 entry) (taken as recommended by the integrator, owner may amend). |
| D-109 | 2026-10-20 | Removing sample data never deletes a real person's rows: sign-ups, hours and skills a real person holds on a sample shift or skill are kept, the sample job or skill stays, and removal stops with the reason in the Error Log (taken as recommended by the integrator, owner may amend). |
| D-110 | 2026-10-25 | Preferred Phone in Core (Brandon; C-43): a Preferred Phone picklist on the person (Home, Mobile, Work, Other) keeps the standard Phone in step with the chosen number, as Preferred Email does (R-C6). Reason: closes a gap with NPSP `npe01__PreferredPhone__c` |
| D-111 | 2026-10-25 | Contact Point sync is a new optional module, BarnCRM Contact Point Sync, not Core (Brandon; C-45): keeps `ContactPointEmail`, `ContactPointPhone` and `ContactPointAddress` in step with the person's email and phone fields and `Address__c`. A new ADR before build. Reason: Core stays free of those objects (ADR-0110, ADR-0013, `check-standard-objects.sh`) |
| D-112 | 2026-10-25 | Address verification is a new optional module, BarnCRM Address Verification (Brandon; C-46; amends plan Section 4.7, which put it out of scope): bring-your-own provider key in the BarnCRM Settings console; verifies `Address__c` and writes Verification Status and Latest Verified Date (R-AD6 placeholders). No provider bundled, no paid service by BarnCRM |
| D-113 | 2026-10-25 | Related-record duplicate matching in Core, steps 1 to 3 (Brandon; C-44; plan Section 4.9): configurable match sources (object, field, parent link, normalization); shipped sources for the three Contact Point objects and `Address__c`, active only when the object exists (dynamic SOQL); the duplicate scan adds pairs to the review list with a reason naming the source, and import matching uses the same sources. Not included: a save-time warning. Reason: Salesforce duplicate and matching rules cannot see related objects |
| D-114 | 2026-10-25 | Erasing a person also empties Rejection Reason on their volunteer hours (Brandon; closes Section 11.2 item 28) |
| D-115 | 2026-10-25 | Erasing a person keeps deleting the generated volunteer hour letters and certificates, as D-108 says; no behaviour change (Brandon; closes Section 11.2 item 29) |
| D-116 | 2026-10-25 | Documentation upkeep is a standing rule: Overview, Admin Guide, User Guide and Testing Guide updated in the same PR as any feature change; each index has an "Applies to" line naming a main commit (Brandon; Sections 7.4 and 9.4) |

D-25 to D-33 (2026-10-12) and D-34 to D-36 (2026-10-13) were accepted under the owner's standing instruction "proceed as recommended"; the owner may amend them. D-37 to D-47 are Brandon's own decisions (D-40 to D-46 "yes, as recommended").

## Open questions still open (plan Section 11.2)

- 1: Namespace registration (deferred; blocks package versions only). Settled after a v1.0 pilot (D-87).
- 3: Dev Hub type (Partner Business Org or Developer Edition with a planned migration). Settled after a v1.0 pilot (D-87).
- 4: Steward entity. Settled after a v1.0 pilot (D-87).
- 7: Telemetry (C-26): resolved 2026-10-12, deferred indefinitely (D-24).
- 12: Permission set groups that contain only the staff set: resolved 2026-10-13, Fundraising Staff includes Giving Staff (D-44).
- 14: Shipped import templates: resolved 2026-10-13, added at install and on upgrade (D-55).
- 16: Per-automation switches: dropped 2026-10-14 (Brandon); no end date, they stay off until turned on (D-93).
- 19 to 22: Opportunity mirror defaults (NPSP mode direction, deleted gift, double thanks, record-type filter).
- 23: A separate nonprofit app in Giving.
- 24: Neutral labels for nonprofits: accepted 2026-10-14 (Brandon); the product-branded "BarnCRM ..." names stay (D-92).
- 27: Plan corrections: resolved 2026-10-13, applied (D-80).
- 28: Whether erasing a person also empties Rejection Reason on their volunteer hours: resolved 2026-10-25 (Brandon), yes (D-114).
- 29: Whether erasing a person keeps or deletes the volunteer hour letters and certificates BarnCRM generated (deleted today, D-108). Raised 2026-10-25; Brandon asked what hour letters are (V-08, D-104). Resolved 2026-10-25 (Brandon): keep today's behaviour, erasure deletes them (D-115).
- Provisional (confirm when the owner tests): 8 primary person through the person contact, 9 guards only, 10 membership-mode switch guard only.

## Parking lot (plan Section 11.3)

Donor portal and online giving; email marketing beyond export; grantmaking as a funder; peer-to-peer; wealth screening; text-to-give; multi-org roll-up reporting; an in-app AI assistant; confidential interaction notes (D-19); Nonprofit Cloud household migration (X-09, until an org asks). Engineering follow-ups (plan 11.3, recorded 2026-09-27): 1 settings writers, 3 dynamic Apex, 4 CLI heap and 6 BarnCRM rename merged with #181; 5 small review items landing (#203 in #217); 2 (log unrecognized checkbox values in imports) has no branch yet. Work items from the 2026-10-12 landing (plan 11.3): rollup S9 after a clean comparison run; C-35 adopting the C-37 transforms, then bulk delete (done, #219); "Data Jobs" relabel (Title Case, D-45); `FieldUtilizationJob` in `NightlyJobs` (dropped, D-37); test self-containment follow-ups; version for `v1.x-draft-advanced-find.md`; ADR-0088 still Proposed; org checks for `barn-npc` (`main` deployed there 2026-10-13 and passes; confirm the rest by hand); `mwdbdevsb` real validation on hold.

## Module notes (plan Section 11.5; not presented until each module starts, D-84)

- Giving: receipt PDFs kept after Erase a person, deleted by hand (D-52); 66 label descriptions need the placeholder sweep; `HouseholdSoftCreditRecompute` chains one Queueable per household (stops after 5 in Developer Edition, trial and scratch orgs; candidate fix: a batch or a ready event); `GiftLookupSelector.selectHouseholdsWithGifts` semi-join runs without sharing (IDs only), to confirm against the Giving design; deleting the default fund leaves every new gift refused with "No default fund is set" (candidate: refuse the delete, or Health Check flags it); no supported way to re-split an existing gift's allocations except the gift entry screen (totals are validated after each DML statement).
- Connect: 38 label descriptions need the placeholder sweep.

## Working agreements (owner instructions)

- Cross-package class construction (2026-10-15, #446): a class one package builds by name (trigger handlers, registered module extensions) needs an explicit `@NamespaceAccessible` public no-arg constructor; the implicit one is not accepted by `check-cross-package-visibility.py`.

- Merge authority (2026-09-23): squash-merge without asking when every required check (Static checks, DCO sign-off, Org tests (local)) is green on the head, threads are resolved and nothing is open; hold and ask on an owner question, a failing or skipped check, or a design doubt. Report merges afterwards.
- Test orgs (2026-09-23, 2026-09-24, 2026-10-12): only `oi-test`, `oi-pa`, `barn-core` and `barn-npc` (Nonprofit Cloud trial, never default; deploy approved once the landing batches, Builder and test self-containment merge); any other org needs approval; recreating `oi-pa` on expiry is pre-approved; agents share each org through a lock, one deploy or test run at a time.
- Sandbox `mwdbdevsb` (2026-10-12): real built-out org; never the default; check-only first; ask before every deploy; no data changes, destructive deploys or scheduled jobs without approval; Core only. Real deploy on hold ("Wait until the other tasks are completed then deploy to barn-npc").
- Standing instruction (2026-10-12): "PR, merge, and continue building all the core functionality until it's ready for the test deploy to barn-npc"; decisions inside that work are taken as recommended and recorded (D-25 to D-33).
- Gate from a clean worktree (2026-09-24): run `scripts/org/run-org-tests.sh` only from a dedicated detached worktree at the pushed head.
- Naming (2026-10-12): short prefix is "barn-" (for example `barn-core`), never "bc-".
- Synced folder: never `git add -A`; stage by path; check for ` 2.` files before pushing.
- BMemory writes go through the BMemory MCP gateway, not git (2026-10-12); `_meta/` paths need asking.
- Root project docs (2026-10-12): `changelog.md` logs every Claude change in the same session; `roadmap.md` and this file mirror the BMemory plan.
