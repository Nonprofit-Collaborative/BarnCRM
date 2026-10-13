# Architecture Decision Records

One file per decision, named `NNNN-kebab-title.md`. A settled decision is not re-opened
without a new ADR that supersedes it, and a Salesforce platform limitation that blocks
the plan gets an ADR recording the workaround (see `../README.md` for the full rule).

## Index

| # | Title | Status |
|---|---|---|
| [0000](0000-adr-template.md) | ADR template | Template |
| [0001](0001-product-name-and-namespace.md) | Product name "Open Impact" and deferred namespace | Re-opened (name), Accepted (namespace deferral) |
| [0002](0002-second-generation-managed-packages.md) | Second-generation managed packages with one shared namespace | Accepted |
| [0003](0003-core-plus-module-packages.md) | Core package plus separate module packages, feature flags for minor behavior | Accepted |
| [0004](0004-custom-gift-object-as-system-of-record.md) | Custom Gift object as the gift system of record, with optional mirrors | Accepted |
| [0005](0005-household-as-account-record-type.md) | Household as an Account record type with two membership modes behind one service | Accepted |
| [0006](0006-settings-storage-strategy.md) | Settings storage: custom settings, custom objects, and custom metadata | Accepted |
| [0007](0007-sf-cli-and-github-actions.md) | Salesforce CLI plus GitHub Actions, CumulusCI optional later | Accepted |
| [0008](0008-license-apache-2-0.md) | License: Apache-2.0 | Accepted |
| [0009](0009-no-industries-or-paid-add-on-dependency.md) | No Person Account, Industries, OmniStudio, Data Cloud, or Experience Cloud dependency | Accepted |
| [0010](0010-receipt-immutability.md) | Receipts are immutable; corrections void and reissue; refunds are negative linked gifts | Accepted |
| [0011](0011-evaluate-vendoring-a-rollup-library.md) | Evaluate vendoring a proven Apex rollup library before building one | Accepted; amended for rollups by `0082-barncrm-owns-its-rollup-engine.md` |
| [0012](0012-trunk-based-development.md) | Trunk-based development with squash merges and an always-releasable main | Accepted |
| [0013](0013-platform-only-org-shape-verification.md) | How the Platform-only org shape is provisioned and verified | Accepted |
| [0014](0014-cross-package-references-as-record-identifiers.md) | Core holds Giving record identifiers, not lookups | Accepted |
| [0015](0015-vendor-apex-rollup-behind-adapter.md) | Vendor apex-rollup as the aggregation core, behind a BarnCRM adapter | Superseded by `0082-barncrm-owns-its-rollup-engine.md` |
| [0016](0016-receipt-pdf-rendering.md) | Receipt PDFs are rendered by the Visualforce PDF rendering service, called from Apex | Proposed |
| [0017](0017-cross-package-mechanisms.md) | Cross-package mechanisms under one namespace: NamespaceAccessible, per-package settings objects, registry-driven trigger dispatch | Accepted |
| [0018](0018-module-tabs-and-apps.md) | Each module ships its own Lightning app; the Hub links to the module apps | Accepted |
| [0019](0019-custom-setting-picklist-keys-stored-as-text.md) | Nonprofit Settings picklist keys are stored as text | Accepted |
| [0020](0020-module-settings-pages-reached-by-navigation.md) | Module settings pages reached by navigation, Core pages by literal import | Accepted |
| [0021](0021-system-mode-writes-for-package-owned-data.md) | System-mode writes for package-owned data through dedicated writer classes | Accepted |
| [0022](0022-rollup-status-filter-includes-reversed-gifts.md) | Packaged giving rollups include reversed gifts, and count gifts rather than transactions | Accepted |
| [0023](0023-refunded-gifts-keep-their-soft-credits.md) | A refunded gift keeps its soft credits, and the negative gift reverses them | Accepted |
| [0024](0024-receipt-lock-survives-the-automation-switch.md) | The receipt lock survives the automation switch, and lifting it is a deliberate act in Setup | Accepted |
| [0025](0025-retention-reports-read-the-org-fiscal-year.md) | Retention reports read the org fiscal year, and the two fiscal years have to agree | Accepted |
| [0026](0026-retention-report-definitions.md) | What the retention reports count, and the one attribute they needed | Accepted |
| [0027](0027-seasonal-address-swap-runs-in-system-mode.md) | The seasonal address swap runs in system mode, gated at the controller | Accepted |
| [0028](0028-donor-levels-read-a-rollup-and-follow-the-total-down.md) | A donor level labels an existing rollup, and follows that total down | Accepted |
| [0029](0029-shipped-rollups-are-created-by-each-packages-post-install-script.md) | Shipped rollups are created by each package's post-install script | Accepted |
| [0030](0030-in-kind-gifts-are-a-gift-type-whose-value-never-enters-the-money-rollups.md) | An in-kind gift is a gift type carrying no amount, and its value is rolled up separately from money | Accepted |
| [0031](0031-refund-reverses-the-matched-donor-credit.md) | A refund of the employer's gift reverses the matched donor credit, along the link | Accepted |
| [0032](0032-acknowledgments-are-standard-email-plus-a-ledger.md) | Acknowledgments send standard email templates and keep a ledger, sharing no machinery with receipts | Accepted |
| [0033](0033-receipt-numbers-come-only-from-the-sequence.md) | A receipt number comes only from the sequence, so the field is package written | Accepted |
| [0034](0034-receipt-document-access-and-template-writes.md) | A receipt document is reached only through the records a Giving permission set governs | Accepted |
| [0035](0035-shipped-setting-defaults-are-applied-in-apex.md) | A setting that ships switched on is switched on in Apex, not by its field default | Accepted |
| [0036](0036-empty-household-delete-guard.md) | An empty household is deleted only when nothing outside BarnCRM depends on it | Accepted |
| [0037](0037-junction-mode-creates-households-automatically.md) | Junction mode creates a household for a new person, under the one setting that already says so | Accepted |
| [0038](0038-giving-nightly-jobs-are-scheduled-from-the-settings-console.md) | The Giving nightly jobs are scheduled from the settings console | Accepted |
| [0039](0039-health-check-findings-are-grouped-by-the-question-they-ask.md) | Health Check findings are grouped by the question they ask, not registered one by one | Accepted |
| [0040](0040-simple-rules-in-flow-engine-logic-in-apex.md) | Simple rules in Flow, engine logic in Apex, and customers switch ours off to run theirs | Accepted |
| [0041](0041-core-ships-no-contact-record-type.md) | Core ships no Contact record type | Accepted |
| [0042](0042-packaged-records-use-activities-not-chatter.md) | Packaged records use activities, not Chatter | Accepted |
| [0043](0043-record-pages-use-dynamic-forms.md) | Record pages use Dynamic Forms, with one fallback layout per object and no layout assignments | Accepted |
| [0044](0044-primary-contact-mirrors-the-primary-member.md) | The household's Primary Contact mirrors the primary member, person accounts included | Accepted (provisional) |
| [0045](0045-gift-batch-entry-keeps-its-own-lines.md) | Gift batch entry keeps its own lines rather than staging through the import framework | Accepted |
| [0046](0046-suites-and-packaging.md) | Two suites from the same packages, a tentative name, unlocked now and managed at listing | Accepted |
| [0047](0047-data-management-scope.md) | Data management runs in the org, compiles queries from a document, and is phased | Accepted |
| [0048](0048-health-check-fixes-create-or-set-never-delete.md) | Health Check fix buttons create or set, never delete, and ask first | Accepted (builder decision) |
| [0049](0049-xlsx-read-in-the-browser-without-sheetjs.md) | Excel workbooks are read in the browser without SheetJS | Accepted (builder decision) |
| [0050](0050-duplicates-use-the-orgs-own-duplicate-rules.md) | Duplicate detection uses the org's own duplicate rules, and BarnCRM ships none | Accepted (builder decision) |
| [0051](0051-inbound-gift-api-and-accounting-export.md) | The inbound gift API keeps a small permanent surface, and the accounting export marks nothing | Accepted |
| [0052](0052-gift-import-and-donation-matching.md) | Gift import through the entity processor seam, and donation matching | Accepted (builder decision) |
| [0053](0053-posted-gifts-and-closed-periods-are-locked.md) | Posted gifts and closed periods are locked by a rule that always runs | Accepted (builder decision) |
| [0054](0054-a-pending-gift-that-will-never-be-paid-is-cancelled.md) | A Pending gift that will never be paid is cancelled, not written off | Accepted |
| [0055](0055-automatic-resume-and-error-digest.md) | A pause ends through a one-time resume job, and the error digest counts and goes only to users | Accepted (builder decision) |
| [0056](0056-campaign-sync-keeps-its-link-on-the-appeal.md) | Campaign sync keeps its link on the appeal, writes with the saver's access, and is off until switched on | Accepted (builder decision) |
| [0057](0057-health-check-extension-for-dependent-packages.md) | A Health Check extension seam lets a dependent package add findings without Core depending on it | Accepted (builder decision) |
| [0058](0058-opportunity-mirror-keeps-its-link-on-the-gift-and-runs-one-way.md) | The Opportunity mirror keeps its link on the gift, runs one way at a time, and reconciles on a page | Accepted (builder decision) |
| [0059](0059-core-is-neutral.md) | Core is neutral: the nonprofit app, wording, giving and receipt settings and Setup Assistant steps live in Giving | Accepted (builder decision) |
| [0060](0060-product-name-is-barncrm.md) | The product name is BarnCRM (supersedes the name part of ADR-0001) | Accepted (owner decision) |
| [0061](0061-module-settings-first-save-takes-checkbox-defaults-from-metadata.md) | A module's first settings save takes its checkbox defaults from field metadata | Accepted (builder decision) |
| [0062](0062-core-names-other-products-only-when-detected.md) | Core shows nonprofit wording and other products' names only where they apply (amends ADR-0059 decision 5) | Accepted (owner decision) |
| [0063](0063-barncrm-api-names.md) | The `Nonprofit_*` API names become BarnCRM names before the first package version (supersedes ADR-0059 decision 6) | Accepted (owner decision) |
| [0064](0064-giving-ships-the-donor-record-pages.md) | Giving ships the donor record pages, with Dynamic Related Lists for giving (amends ADR-0043 for the giving lists) | Accepted (owner-approved UX review) |
| [0065](0065-receipt-letters-are-edited-as-rich-text.md) | Receipt letters are edited as rich text, and the package prints the letterhead | Accepted (owner-approved UX review) |
| [0066](0066-acknowledgment-rule-template-picker-and-generated-plan-keys.md) | Acknowledgment rules pick their template by name, and plan keys are generated | Accepted (owner-approved UX review) |
| [0067](0067-import-matches-a-person-only-by-their-first-name.md) | An import matches a person with a first name only by that first name | Accepted |
| [0068](0068-import-matching-per-entity-and-per-file-values.md) | Import matching per entity, a rule for several matches, and values for every row of a file | Accepted |
| [0069](0069-import-record-id-matching-and-match-only.md) | Import matching by Salesforce record ID, files that only match, and custom fields | Accepted (owner decision) |
| [0070](0070-empty-household-tidy-up-keeps-households-with-gifts.md) | The empty household tidy-up keeps a household that still has gifts (extends ADR-0036) | Accepted (owner decision) |
| [0071](0071-a-gift-keeps-the-household-it-was-given-to.md) | A gift keeps the household it was given to when the donor moves (amends R-G2) | Accepted (owner decision) |
| [0072](0072-suite-choice-is-the-first-setup-step.md) | The suite choice is a Core setting the Setup Assistant asks first | Accepted (builder decision) |
| [0073](0073-module-manager-turns-automation-off-and-never-installs.md) | The Module Manager switches a module's automation, links to installs, and counts before an uninstall | Accepted (builder decision) |
| [0074](0074-settings-console-picks-records-and-record-types.md) | The settings console picks records and record types instead of taking identifiers | Accepted (builder decision) |
| [0075](0075-health-check-schedules-every-nightly-job.md) | Health Check schedules every nightly job with one fix, and modules register theirs (amends ADR-0048) | Accepted (builder decision) |
| [0076](0076-saved-queries-are-private-and-shared-by-apex-managed-sharing.md) | Saved queries are private and shared by Apex managed sharing | Accepted (builder decision) |
| [0077](0077-bulk-update-runs-as-the-user-from-a-find-query.md) | Bulk update runs as the user, from a Find query, and is undone by the import undo | Accepted (builder decision) |
| [0078](0078-typed-find-queries-are-parsed-into-the-query-document.md) | Typed Find queries are parsed into the query document in the browser | Accepted (owner, as recommended) |
| [0079](0079-data-hygiene-checks-are-find-queries-built-at-request-time.md) | Data hygiene checks are Find queries built at request time | Accepted (builder decision) |
| [0080](0080-import-load-one-object.md) | Import loads one object: insert, update by record ID or upsert, with an allow-list and journaled creations | Accepted (builder decision) |
| [0081](0081-data-transform-document.md) | Column changes as a declarative transform document, and import matching through the org's duplicate rules | Accepted (builder decision) |
| [0083](0083-rollup-totals-in-the-target-record-currency.md) | Rollup totals are in the target record's currency | Accepted (owner decision) |
| [0082](0082-barncrm-owns-its-rollup-engine.md) | BarnCRM owns its rollup engine (supersedes ADR-0015, amends ADR-0011) | Accepted (owner decision) |
| [0084](0084-gift-entry-pays-a-scheduled-payment.md) | Gift entry screens suggest the scheduled payment a gift pays, and a person decides | Accepted (owner decision) |
| [0085](0085-custom-metadata-manager-edits-only-types-read-directly.md) | The custom metadata manager edits only types BarnCRM reads directly, and never a shipped row | Accepted (owner, as recommended) |
| [0086](0086-field-utilization-ships-in-core.md) | Field utilization ships in Core, counts in user mode, and keeps weekly snapshots | Accepted (builder decision, as recommended) |
| [0087](0087-whats-new-from-packaged-release-notes.md) | What's new is read from packaged release notes and remembered per person | Accepted (builder decision) |
| [0088](0088-unlocked-to-managed-migration-kit.md) | Pilots move from unlocked to managed packages with a command-line kit that reimports through the REST API | Proposed (builder decision) |
| [0089](0089-interaction-notes-are-completed-tasks.md) | Interaction notes are completed tasks logged through one packaged action | Accepted (builder decision) |
| [0090](0090-flow-templates-which-automations-get-one.md) | Flow templates: which automations get one, how they are named, and what they leave out (applies ADR-0040) | Accepted (builder decision) |
| [0091](0091-bulk-delete-from-a-find-query-with-undelete.md) | Bulk delete runs from a Find query, as the user, and is undone by undelete | Proposed (builder decision) |
| [0092](0092-merge-survivors-recalculated-after-the-merge.md) | Merge survivors' real-time totals are recalculated just after the merge | Accepted (builder decision) |
| [NEXT](NEXT-barncrm-app-is-a-console-app.md) | The BarnCRM app is a Lightning console app with a packaged logo | Accepted (owner request) |

ADRs 0001 to 0012 correspond to decisions D-01 to D-12 in the product plan's decision log
(Section 12). ADR-0013, ADR-0014, ADR-0018, ADR-0019, ADR-0020 and ADR-0021 are builder decisions
recorded under the platform-limitation rule in plan Section 9.3. ADR-0015 records the ADR-0011
evaluation outcome. ADR-0016 is proposed for the owner's decision at v0.4 (plan Section 11.2
item 6). ADR-0022 is a product owner decision on a defect found in G-02. ADR-0023 resolves the rule
collision ADR-0022 recorded as still open, between R-SC5 and R-SC6 in G-08. ADR-0024 is a product owner decision on the escalation ADR-0010
reserved to him by name, made after an access review found the receipt lock was switchable
from the settings console. ADR-0025 and ADR-0026 are builder decisions made while building
G-16, the retention reports. ADR-0027 is a builder decision made while building C-18.
ADR-0028 is a builder decision for G-14, answering the four questions donor levels cannot
be built without. ADR-0029 is a builder decision on a defect found in C-13 and
G-02: the shipped rollup definitions were never created at install. ADR-0030 is a
builder decision for G-18, and it answers the question ADR-0022 recorded as open
about a gift recorded at zero. ADR-0031 answers the question ADR-0023 left open and
sent to G-10: what a refund of the employer's gift does to the employee's matched
donor credit.
ADR-0032 is a builder decision for G-12, separating acknowledgments from
the receipting machinery they resemble. ADR-0033 is a builder decision on a defect a
security review found in G-13: staff could type a receipt number onto a gift, which
locked it, collided with the sequence, and left it unreceiptable.
ADR-0034 is a builder decision on three further defects the same review
found in G-13, and it amends the storage sentence in ADR-0016: a `ContentDocumentLink` is an
access control list, so a receipt document is linked only to the records a Giving permission
set governs. ADR-0038 is a builder decision on a defect found in G-07: nothing in a real org
called `GivingScheduler.scheduleAll`, so the Giving nightly jobs were built and never started;
the schedule is now started and stopped from the Nightly Jobs page of the settings console.
ADR-0039 is a builder decision made while refactoring C-11, and it records where a new
Health Check finding goes.
ADR-0040 is a product owner decision on how automation is built and customized while the
packages are unlocked.

ADR-0041 to ADR-0043 are product owner decisions on the record pages (plan Section 4).
ADR-0044 is a product owner decision, delegated and provisional, on how a household names its
primary person when people can be person accounts (plan Section 11.2, item 8).
ADR-0045 is a builder decision for G-17, recording why gift batch entry does not stage its
lines through the import framework the plan pointed at.
ADR-0046 is a product owner decision on the two suites, the tentative name and packaging
(plan Section 3 and Section 12, D-01 and D-02).
ADR-0047 is a product owner decision on the scope and phasing of data management: import,
find and bulk update (plan Section 4.9 and Section 12, D-13).
ADR-0048 is a builder decision for C-21 on which Health Check findings may carry a fix button;
orphaned records are detected there with no fix, by owner decision.
ADR-0049 is a builder decision for C-19 on reading Excel workbooks in the browser without
SheetJS.
ADR-0050 is a builder decision for C-20 on detecting duplicates with the org's own duplicate
rules, and on what a people merge keeps.
ADR-0051 is a builder decision for X-03, X-04 and X-06, recording the permanent surface of
the inbound gift API and why the accounting export marks no gift.
ADR-0052 is a builder decision for G-23 and G-24 on the entity processor seam, the undo of
imported gifts and the choices the plan leaves open for gift import and donation matching.
ADR-0053 is a builder decision for G-20 on what a posted gift and a closed period lock, who
may post, unpost and reopen, and how the lock meets imports, undo, gift batches and the API.
ADR-0054 is the owner's decision that a Pending gift that will never be paid is
cancelled rather than written off; it amends G-04, ADR-0022, ADR-0023 and ADR-0031.
ADR-0055 is a builder decision for C-23 on how a pause records its own end, and on who
receives the error digest and what it may say.
ADR-0056 is a builder decision for X-02 on where the Campaign sync link lives, why it writes
in the saver's user mode, and why it ships off until an administrator switches it on; it
amends ADR-0029, under which Connect also gains a post-install script.
ADR-0057 is a builder decision for G-20's follow-up on a Health Check extension seam:
`HealthCheckExtension` and a `Type.forName` resolver let a dependent package fold its own
findings into Core's one report without Core naming that package; it amends ADR-0021 with the
sharing exception `HealthCheckGivingSelector` needs to read gifts in a closed period org-wide.
ADR-0058 is a builder decision for X-01 on the Opportunity mirror: a single attribute on Gift
carries the link both directions, Gifts to Opportunities copies before save in the saver's user
mode with a headroom check ahead of NPSP's own automation, Opportunities to Gifts and the
catch-up run in a nightly job, and a reconciliation page replaces the packaged report type
Opportunity forbids; it amends ADR-0057 so `HealthCheckExtensions` also looks up Connect's
extension.
ADR-0059 is a builder decision for C-29 under ADR-0046: the seven Giving-only settings keys
move to `Giving_Settings__c`, the Setup Assistant gains an extension seam so a dependent
package can add or extend a step, the two receipt Health Check questions move to Giving's own
extension, Core's app and wording become neutral with a short list of named exceptions, and
API names do not change until the pre-package name pass.

## Adding a new ADR

1. **Take the next number, unless you are working on a branch alongside others.** Look at
   the highest number in this folder and add one. Zero pad to four digits. Numbers are never
   reused, even if an ADR is superseded.

   **On a parallel branch, do not pick a number at all: use `ADR-NEXT`.** Name the file
   `NEXT-your-kebab-title.md`, head it `# ADR-NEXT: Title`, cite it as `ADR-NEXT` everywhere
   in the body and in any code comment, and put its index row at the end of the table. The
   integrator assigns the real number once, at merge, with a single search and replace that
   cannot hit anything else.

   This exists because the alternative kept going wrong. Three branches in one day each took
   "the next free number" at the same moment and all landed on the same one. Renumbering at
   merge is easy; the hazard is the renumber itself, because a file often cites several ADRs
   and a search and replace for a real number rewrites the ones that were already correct.
   That happened twice, and once it silently repointed a correct citation at the wrong
   decision. `ADR-NEXT` is unambiguous by construction, so the replace is safe.
2. **Copy the template.** `cp 0000-adr-template.md NNNN-your-kebab-title.md` and fill in
   every section. Keep it between roughly 30 and 70 lines.
3. **Set the Status honestly.** `Proposed` when it awaits Brandon's confirmation,
   `Accepted` when it is in force. Never edit an Accepted ADR's Decision: write a
   successor and change the original's Status to `Superseded by ADR-NNNN`.
4. **Add a row to the index above**, in number order.
5. **Link it from the plan if it changes a plan decision.** When the ADR supersedes or
   modifies a decision in `docs/product-plan.md` Section 12, update that row in the plan's
   decision log to point at the ADR, so the plan and this folder never disagree about what
   is in force.
6. **Check the escalation list.** Decisions in plan Section 11.4 go to Brandon before an
   ADR is written, not after.
