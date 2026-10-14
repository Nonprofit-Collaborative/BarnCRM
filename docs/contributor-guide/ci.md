# Continuous integration

This page explains what `.github/workflows/ci.yml` does, how the one long lived test org it
deploys into is configured, and how to sign off commits under the project's DCO policy. Open
work items, unmerged work and untested areas are listed at the end, under
"Handoff: open work and what still needs testing".

It used to say the workflow tests four org shapes. It does not, and has not since the org
tests moved to a single long lived org: there is no shape matrix, so exactly one shape is
exercised, whichever the test org was created from. Testing a second shape means a second
org and a second secret.

## Jobs

### `static`

Runs on every pull request and push to `main`, and on manual `workflow_dispatch`. No
Salesforce org is needed for this job. Steps:

1. `npm ci`
2. `npm run prettier:verify`
3. `npm run lint`. Besides the LWC rules, it holds the pure modules to plain JavaScript:
   each file in `PURE_MODULES` at the top of `eslint.config.js` (today the import wizard's
   `csv.js` and `xlsx.js`) fails lint if it imports `lwc`, `lightning/*` or `@salesforce/*`.
   A pure module is a helper inside a component bundle (its file name differs from the
   bundle's) that works on plain values only; add each new one to the list, and the config
   refuses to load if a listed file no longer exists, so a rename cannot drop a module out
   of the rule silently. Without the rule the next edit can pull in the platform and the
   module stops being reusable outside Salesforce or testable without stubs (plan Section
   4.4, portability at near-zero cost).
   The next workflow step, `npm run lint:slds`, runs Salesforce's SLDS linter
   (`@salesforce-ux/slds-linter`, pinned in `package.json`) over every component's HTML and
   CSS under `packages/`, failing the build on any SLDS 2 (Cosmos theme) finding: a
   hard-coded color, spacing, font size, shadow or radius instead of a `--slds-g-*` global
   styling hook, a deprecated `--lwc-*` design token, a private or unsupported hook, an
   override of an SLDS class, a retired class name (`--` modifiers instead of `_`), or the
   modal close button issue. The CLI exits 0 when it finds warnings only, and most SLDS 2
   findings are warnings, so the script passes only when the linter prints "No SLDS
   Violations found". `npx slds-linter lint packages --fix` applies the safe fixes; review
   each one.
4. `npm run test:unit:coverage`
5. `scripts/ci/check-namespace.sh`, failing the build if a hard-coded namespace prefix
   appears in source.
6. `scripts/ci/check-standard-objects.sh`, failing the build if a standard Salesforce
   object is referenced outside `packages/connect`, and separately if any Apex or metadata
   file names a Nonprofit Cloud object. The second half covers the fundraising objects, the
   objects a household is actually built out of there (`PartyRelationshipGroup`, whose Type
   of Household is what makes an Account a native household, and `AccountContactRelation`,
   which carries membership), and the contact point objects. It is checked in Apex and
   metadata only, because a component's JavaScript cannot reference an SObject and several of
   our own component names are the same words. This half was added after an audit found the
   gate matched `GiftTransaction` alone, so Core could have named the two objects Nonprofit
   Cloud households are made of and the build would have passed.
   It also checks Connect's object and field declarations (everything under
   `packages/connect/**/objects/`): Connect's Apex may name Campaign or Opportunity as strings,
   but a lookup, formula or field declared on one of those objects is resolved at deploy time
   and refuses the install where the object is absent. A folder named after a denied object
   fails, and so does a denied name in the file outside its prose (label, description, help
   text, values).
   The next workflow step, `scripts/ci/check-person-account-fields.py`, closes the gap both
   gates leave: a static reference to a Person Account field (`IsPersonAccount`,
   `PersonEmail`, `PersonMailingPostalCode`, any `__pc` or `__pr` field) anywhere under
   `packages/`. Apex comments and string literals are ignored,
   because holding the name as text and resolving it through describe is the allowed seam
   (`dynamic-apex.md`); a token such as `Account.PersonEmail`, a static SOQL query naming one,
   an `@salesforce/schema` import, a `field-name` attribute, or a metadata reference such as a
   permission set field grant fails. Custom metadata records are data and are skipped. There
   is no exemption marker.
7. `scripts/ci/check-object-allowlist.py`, failing the build if Apex or an `objects/`
   folder anywhere under `packages/` names a standard object that is not on the allowlist
   in that script. This is the other half of check 6 and the stronger shape: check 6 is a
   denylist, so it can only fail on a name somebody thought to write down, and the failure
   that matters is the object nobody thought of. A static Apex reference to an object a
   subscriber org does not have is a compile error, and one compile error in one class
   refuses the whole package, so the promise that Core installs on a Platform-only org
   (ADR-0009, ADR-0013) needs a gate where everything is forbidden unless it is listed.
   Each allowed name carries its reason on its own line in the script. Names are read only from positions where a bare identifier can be an
   SObject (`new X(`, `List<X>`, `X.SObjectType`, `FROM X`); the docstring says why that is
   narrower than every possible reference, and an unrecognized name always fails, so
   widening the patterns is safe.
   A line carrying the `// detection-only:` marker is skipped, the same marker check 6
   honours and for the same reason: a name held as a String constant, or inside the text
   of a query only run after a describe says the object is there, is not a compile-time
   reference and cannot refuse a deployment. That is the pattern ADR-0009 requires for an
   object a subscriber org may not have, so the gate permits the one shape the
   architecture insists on.
8. `scripts/ci/check-custom-metadata.py`, failing the build if a shipped custom metadata
   record names a field its type does not define. Such a record refuses the whole
   deployment, and nothing else in the suite sees it: the offline Apex compiler does not
   read custom metadata records. It also fails a record that uses the `xsd:` prefix
   without declaring `xmlns:xsd`, a label over 40 characters, and a missing label (see
   "Resolved 2026-09-22" below). And it compares each migration import template (key
   `npc_` or `npsp_`) with its sample export in `docs/admin-guide/samples/`: the Apex tests
   build rows from the template's own headings, so only this sees a misspelt heading.
   `scripts/ci/check-labels.py` does the same for custom labels: a name or short
   description over 80 characters, a value over 1000, or any of them missing, each of
   which only an org would otherwise report.
   `scripts/ci/check-metadata-lengths.py` (`npm run check:metadata-lengths`) covers the
   other limits only an org reports: a description over 255 characters on a custom
   permission, permission set, permission set group, FlexiPage, Lightning web component
   bundle, tab or app; a field label over 40, inline help over 510, a field or object
   description over 1000, a custom label value over 1000; two layout actions with the same
   sort order or name; a record page visibility rule that tests a lookup field itself (the
   platform refuses EQUAL and NE there, so test a field across it, such as
   `{!Record.Donor_Account__r.Name}`); a dynamic related list column value that names
   several fields instead of one per `valueListItems`; and an Apex class, interface or enum named after a reserved Apex type
   (Page, Package, Type, Object, Limit, Group, Case, Sort, Select, Trigger, System, Schema,
   Database). Lengths are counted with leading and trailing whitespace trimmed but the line
   breaks and indentation inside counted, as the platform does, so a description that
   Prettier wraps across lines needs a few characters of room.
9. `scripts/ci/check-symlinks.sh`, failing the build if a tracked file is a symlink
   pointing outside the repository or at an absolute path. Such a link resolves on the
   machine that committed it and dangles everywhere else, so every local check passes and
   CI fails. This ran because a stray `.tools` symlink, left in an agent worktree and swept
   in by `git add -A`, broke the offline Apex compile check on `main`.
10. `scripts/ci/check-permission-sets.py`, failing the build if a packaged permission set
   grants access to a class, tab, app, custom permission, object, record type or field that
   the repository does not ship, or a permission set group contains a set that is not there. A dangling grant refuses the whole deployment, and the
   permission sets are assembled by hand at every merge from each branch's integration
   file, so the reference and the metadata can drift apart silently. This ran because
   `BarnCRM_Admin` granted a `Household_Member__c` tab that was never created.
11. `scripts/ci/check-help-links.py`, failing the build if a Setting Definition's Learn
   more link points at a page that does not exist. `SettingsController` appends
   `Help_Path__c` to a base already ending in `docs/admin-guide/`, so a row storing
   `admin-guide/access.md` produces a 404 that nothing else notices: the value is a string,
   so it deploys, and it is only wrong once an administrator clicks it in an org looking for
   help. This ran because twelve of the thirty four shipped rows did exactly that.
12. `scripts/ci/check-adrs.py`, failing the build if a decision record's number disagrees
   with its own heading, if two records share a number, if a record is missing from the
   index, or if an `ADR-NEXT` placeholder survives to `main` (that placeholder is how a
   parallel branch avoids guessing a number, and the integrator assigns the real one at
   merge). Parallel branches pick the next free number at the same time and collide, so
   renumbering at merge is routine, and a renumber that renames the file but not the heading
   leaves a document that argues with itself. This ran because two branches both claimed
   0025 in one afternoon, and because ADR-0024 was written and never indexed, which is how
   the next author picks a number that is already taken.
13. `scripts/ci/check-components-reachable.py`, failing the build if a Lightning web
   component marked `isExposed` is on no flexipage, in no quick action, nested in no other
   component, and not named in the settings console import switch. Exposed means an
   administrator *could* place it, never that the package ships anywhere that does, and an
   unreachable component is a feature that does not exist however green its tests are. This
   ran because it has happened four times: the three C-15 to C-17 panels while their guides
   said "scroll to the card", `receiptSettings` named across a package boundary the console
   cannot cross, `receiptActions` while the receipts walkthrough said "click Issue receipt",
   and `commitmentSchedulePreview`, which no guide ever mentioned at all.
14. `scripts/ci/check-record-pages-assigned.py`, failing the build if a packaged record page
   flexipage is named by no `actionOverrides` assignment, or if an app assigns one for some
   of the form factors it declares and not the others. Item 12 proves a component is on a
   page and says so in its own header that it proves nothing about the page: a FlexiPage
   cannot name the record type it serves, that assignment lives in the Lightning app, and a
   page nothing assigns is never shown, so the component sits on a page nobody opens. Same
   defect class one level up, and the same symptom: it deploys, every test passes, and the
   administrator sees none of it until they wire it up by hand in the Lightning App Builder.
   This ran because `BarnCRM.app-meta.xml` carried no `actionOverrides` at all, so the
   household walkthrough failed at step 4 on every fresh install, and because
   `Gift_Record_Page` and `Commitment_Record_Page` were stranded the same way in Fundraising.
15. `scripts/ci/check-canonical-model.py`, failing the build if a shipped object or field
   is missing from `docs/architecture/canonical-model.md`. The canonical model is updated
   before an object or a field is added, so this is the gate that keeps it true. It checks
   both directions. Inside the model: no API name declared twice for one object, and no
   name used in prose that no table declares. Against the metadata: every folder under
   `packages/*/main/default/objects/` is named in the model, and every custom field shipped
   in it is named in backticks in a top-level section that also names that object. Until
   2026-10 only the first direction ran, so this line claimed more than the script did, and
   four custom metadata fields had shipped with no API name in the model.
   `scripts/ci/check-openapi.js` (`npm run check:openapi`) fails the build if
   `docs/architecture/reference/inbound-gift-api.openapi.yaml` does not parse as YAML, is
   not OpenAPI 3.1, has a `$ref` that resolves to nothing, an operation without a unique
   `operationId` or a response without a description, or has drifted from the Apex: its
   request properties and required list against `InboundGift`, its result properties
   against `InboundGiftResult`, its `outcome` and `errorCode` values against that class's
   constants, and its two length limits against `InboundGiftRequest`. The document is only
   read by integrators' tools, never by the build, so without this a broken file or a new
   field missing from it would ship and be found by a partner. It is not a full OpenAPI
   validator, which would need a network install; it reads the file with the `yaml`
   package already in `devDependencies`.
16. `scripts/ci/check-setting-defaults.py`, failing the build if a checkbox setting that
   ships switched on is not declared in `SettingsService.SHIPPED_DEFAULTS`, or is declared
   there with a value the field metadata disagrees with. A field's own `defaultValue` is
   applied by the platform when a record is created through the user interface, and never
   by `getOrgDefaults()`, which hands Apex a materialized record with every checkbox false.
   So a feature that ships on reads as switched off on every fresh install and does nothing,
   silently, which is a defect only an org run finds (ADR-0035). This ran because C-15 had
   been writing one side of every relationship since it merged: the reciprocal upkeep read
   its own shipped default as false.
   `scripts/ci/check-setting-object-explicit.py` fails the build if a Setting Definition
   record omits `Settings_Object__c`. A custom metadata default is applied only when a record
   is created, never when a record that omits the field is redeployed or upgraded, so an org
   keeps the value it first stored. The rename of the default to `BarnCRM_Settings__c` left
   such orgs pointed at the old object and every save refused with "That setting does not
   exist in this org".
   `scripts/ci/check-apex-access-modes.py` fails the build if packaged Apex (tests
   excepted) leaves its sharing or access mode to the platform default: a class
   with no `with`, `without` or `inherited sharing` keyword (an inner class only when it
   touches the database), an inline query with no `WITH USER_MODE` or `WITH SYSTEM_MODE`, a
   DML statement with no `as user` or `as system`, or a `Database` or `Search` method with no
   `AccessLevel`. A query string that carries its own `WITH` clause is marked with an
   `// Access mode:` comment on the call's line or the line above. From API version 67.0 a
   query or DML statement with no mode runs in user mode and a class with no keyword runs
   with sharing (Apex Developer Guide, Versioned Behavior Changes), so an elevated read that
   relied on the old system-mode default fails for a user without access, and only an org
   run as that user shows it.
   `scripts/ci/check-tests-run-as.py` fails the build if an `@IsTest` or `@TestSetup` method
   in Core, Giving or Connect (the vendored engine excepted) never calls `System.runAs` and
   carries no `// runs-as: deploying user (reason)` comment (a `@TestSetup` that only calls
   `TestUsers` is fine), or if a `TestUsers` call made in two or more test methods of a class
   is not also made in a `@TestSetup` of that class. See "Tests run as a user they create"
   below for why.
   `scripts/ci/check-test-relevance.py` fails the build if a test class (the vendored engine
   excepted) has neither `@IsTest(testFor='...')` nor `@IsTest(critical=true)` and is not in
   `scripts/ci/test-relevance-cross-cutting.txt`, or if a `testFor` names a class or trigger
   that is not in `packages/`. See "Relevant tests" below.
   `scripts/ci/check-lwc-apex-params.py` fails the build if a component calls an Apex method
   with an object literal whose keys are not that method's parameter names. The platform
   drops an unknown key without an error and the parameter arrives as null, and a Jest mock
   accepts any shape, so nothing else sees it (ADMIN-1, ADMIN-13).
17. `python3 -m unittest discover -s scripts/migration/tests`, the migration kit's unit tests
   (C-31, [Migration kit](migration-kit.md)). They need no org, and one of them builds the
   mapping from the real package source, so a new object or field that breaks it fails here.
18. `scripts/ci/check-flow-templates.py`, failing the build if a switchable Core automation
   has neither a Flow template (`Template_<registry name>`) nor a row on
   `docs/admin-guide/flow-templates.md` saying why it has none, or if a template ships active
   or not marked as a template (ADR-0040, ADR-0090).
   `scripts/ci/check-whats-new.py` warns (a build annotation, not a failure) when the newest
   version named in `docs/release-notes` has no `Release_Note` custom metadata record, so the
   What's New card would still show an older release. Run with `--release` it fails instead;
   the release checklist in `docs/release-notes/README.md` runs it that way.
   `scripts/ci/check-deploy-readiness.py` (unit tests in `scripts/ci/tests`) fails the build
   on deploy errors the org gate would otherwise only find after starting: a Core folder not
   named in `CORE_STAGED` in `scripts/org/deploy-packages.sh`, a custom object whose
   `enableSharing`, `enableBulkApi` and `enableStreamingApi` are not all equal, or a custom
   object without `nameField`, `label` or `pluralLabel`, or a permission set that grants
   Create on a platform event (`__e`) without Read. The rules are listed in its header.
19. A grep check that fails the build if any tracked file contains an em dash character.
20. Installs the Salesforce CLI and the `code-analyzer` plugin, then runs
   `sf code-analyzer run --workspace packages --rule-selector Recommended --severity-threshold 2`.
   The results are uploaded as a build artifact (`code-analyzer-results.html` and
   `code-analyzer-results.json`) even if the job fails, so anyone can download and read
   them from the workflow run page.

If `packages/` has no Apex or JavaScript yet, Code Analyzer may report nothing to scan.
That is expected in the early scaffold and is not a failure.

### One command for every offline check

`bash scripts/ci/run-offline-checks.sh` runs every check that needs no org, in CI's order:
each `scripts/ci/*.py`, each `scripts/ci/check-*.sh`, the offline Apex compile check, the
OpenAPI check, the migration kit tests, the em dash scan, `npm run lint`,
`npm run prettier:verify`, `npm run lint:slds` and `npx sfdx-lwc-jest --silent`. It prints one
`PASS` or `FAIL` line per check and, for a failure only, the last 30 lines of that check's
output. The exit status is non-zero if anything failed. If `node_modules` is missing it tells
you to run `npm ci` and stops.

- `--fast` skips Jest and Code Analyzer.
- `--allow-adr-next` counts a `check-adrs.py` failure as a pass when the only problems are
  unnumbered `NEXT-*.md` decision records, so a branch with a new ADR reads clean.
- `--analyzer` also runs `sf code-analyzer run --severity-threshold 2` on the Apex and
  JavaScript files changed against `origin/main`. It is slow, so it is off by default.

### Run the same checks locally, before you push

Every gate above except the org tests runs on a laptop, and all of them are fast (the org
tests run on a laptop too, through the gate script described under "The org test gate"):

```
npm run prettier:verify
npm run lint
npm run lint:slds
npm run test:unit
npm run check:namespace
npm run check:standard-objects
npm run check:object-allowlist
npm run check:custom-metadata
npm run check:metadata-lengths
npm run check:symlinks
npm run check:permission-sets
npm run check:help-links
npm run check:adrs
npm run check:components-reachable
npm run check:record-pages-assigned
npm run check:canonical-model
npm run check:openapi
npm run check:setting-defaults
npm run check:flow-templates
npm run check:tests-run-as
npm run check:test-relevance
npm run check:apex
npm run check:analyzer
```

`check:analyzer` is the one most easily forgotten, because it is the slowest and needs the
Salesforce CLI with the `code-analyzer` plugin. It is also the one that enforces a
non-negotiable: zero high or critical findings before merge. Skipping it locally means
finding out from a red build.

## Connecting a Dev Hub

Until a Dev Hub is connected, the `org-tests` job skips every shape and no Apex test has
ever been executed. This is the setup, once, by someone with administrator access to the org
being used as the Dev Hub.

A Dev Hub is not special. Any Salesforce org can be one, including a free Developer Edition,
and its edition does not constrain the scratch orgs it creates. Use a development org, never a
production org holding real constituent data: the credential below grants full API access to
whatever org it names.

1. **Enable Dev Hub in the org.** Setup, then Quick Find, then Dev Hub, then switch Enable Dev
   Hub on. The switch cannot be turned off again, which is why this belongs in a development
   org. Nothing else on that page is needed yet: second generation packaging stays off until
   the namespace question is settled (plan Section 4.3).
2. **Install the Salesforce CLI locally**, if it is not already there: `npm install -g @salesforce/cli`, then `sf --version`.
3. **Log in to the org and mark it the default Dev Hub.** `sf org login web --alias devhub --set-default-dev-hub` opens a browser; sign in as the administrator of that org.
4. **Check it took.** `sf org list` shows `devhub` with a Dev Hub marker. `sf org display --target-org devhub` shows the username and instance you expect.
5. **Prove it can create a scratch org before involving continuous integration.** `scripts/org/create-scratch-org.sh platform-only smoke --days 1` creates the org, deploys Core and assigns the permission sets. If that fails, fix it here rather than in a build log. Delete it with `scripts/org/delete-scratch-org.sh smoke`.
6. **Read out the authentication URL.** `sf org display --target-org devhub --verbose --json` prints a `sfdxAuthUrl` field. **That string is a credential**: it carries a refresh token and anyone holding it has API access to the org. Do not paste it into a commit, an issue, or a chat window.
7. **Store it as a repository secret.** In GitHub: Settings, then Secrets and variables, then Actions, then New repository secret. Name it exactly `SF_DEVHUB_AUTH_URL` and paste the value from step 6.
8. **Create the test org and store its secret**, which is the next section. The Dev Hub alone does not run any test: it is what lets you create the org that does. Expect failures on the first run that reaches the Apex tests: several hundred have been written and none has ever executed.

To rotate or revoke, re-run steps 3 and 6 and replace the secret, or revoke the connected app
session in the org under Setup, Connected Apps OAuth Usage.

### The test org is one long lived org, not a new one per run

`org-tests` deploys into a single org named by the `SF_TEST_ORG_AUTH_URL` secret. It does not
create or delete anything. If the secret is unset the job skips with a warning and no Apex
test runs.

That is a deliberate trade, and it is worth being clear about what it costs. A fresh scratch
org per run is a clean room: what passes, passes against exactly what this repository
contains. A long lived org accumulates. Deleted metadata is not removed by a deploy, so a
class or field you deleted here still exists there; a test can pass because of something left
behind by an earlier run. When a result looks surprising, recreating the org is the first
thing to try, not the last.

Two consequences follow.

**It expires, and then every run fails at login.** The org is a scratch org, and Salesforce
caps those at 30 days. Every run prints the days remaining and warns from a week out;
`scripts/org/check-org-expiry.sh` does that and never fails a build on its own. Refreshing the
org means replacing the secret, because a new org has new credentials.

**One org means one shape.** The four shape definitions still exist and still matter, but this
job exercises whichever shape the org was created from. Use `person-accounts` unless you have
a reason not to: it is the closest an ordinary Dev Hub gets to the Agentforce Nonprofit orgs
the first customers run. Testing a second shape means a second org and a second secret.

### Creating the test org and connecting it

Do this on your own machine, after the Dev Hub steps above.

The project's test org uses the alias `oi-test`. It is the org the gate script runs against
and the org the `SF_TEST_ORG_AUTH_URL` secret names, so a manual `org-tests` run and a local
gate run test the same org and cannot disagree because of a difference between orgs.

1. **Create it**, 30 days, from the shape you want to test:
   `scripts/org/create-scratch-org.sh person-accounts oi-test --days 30 --replace`
   This deploys Core, assigns the permission sets and seeds the sample data. Note the expiry
   date it prints.
2. **Store its auth URL** as the repository secret `SF_TEST_ORG_AUTH_URL`. The auth URL is a
   credential, exactly like the Dev Hub one, so pipe it straight into the secret rather than
   displaying it:
   `sf org display --target-org oi-test --verbose --json | jq -r .result.sfdxAuthUrl | gh secret set SF_TEST_ORG_AUTH_URL --repo Nonprofit-Collaborative/BarnCRM`
3. **Run `scripts/org/run-org-tests.sh oi-test`** on a pushed commit (see "The org test
   gate"), or dispatch the CI workflow by hand to have `org-tests` deploy both packages into
   the org and run the Apex tests there.
4. **Check the shape it reports.** The run prints what shape the org actually is, read from
   the org itself, before it deploys anything. Confirm it says the shape you meant to create.
   Nothing else in this repository records which definition the org came from, so that line
   in the build log is the record.

Refreshing it monthly is the same two commands: re-run step 1 with `--replace`, then redo
step 2 with the new auth URL. Anything typed into the org by hand is lost at that
point, which is the discipline the package needs anyway: what matters belongs in this
repository.

### The second test org (`oi-pa`)

The maintainer approved a second scratch org on 2026-09-24, alias `oi-pa`, created from
`person-accounts.json` on the `devhub` Dev Hub. It expires 2026-10-24 and is recreated from the
same definition when it does. `oi-test` expires 2026-10-23. Neither is the Platform-only
shape: both have Person Accounts, and ADR-0013 notes that even a Platform-only scratch org
keeps the standard objects, so no org run proves Core without them. The static checks and
review do that.

`oi-pa` is not named by any secret, so the `org-tests` workflow never uses it. It exists so
local gate runs and Person Account testing can go on while `oi-test` is busy or stuck. The
gate script works against either: `scripts/org/run-org-tests.sh oi-pa` posts the same
`Org tests (local)` status. No other org is used for testing without the maintainer's
approval.

Both orgs need the System Administrator profile to hold a person account record type, or the
tests that create real person accounts fail with `PersonAccountTestShape.NO_PERSON_TYPE_FOR_USER`
(PEOPLE-29). `create-scratch-org.sh` does this for the `person-accounts` and `nonprofit-cloud`
shapes; for an org created before that, run `scripts/org/grant-person-record-type.sh <alias>`
once.

When several people or agents share these orgs, take turns: one deploy or test run per org at
a time. A deploy from one branch while another branch's tests run leaves the org holding a
mix of the two.

### The org test gate

A pull request that changes deployable source cannot merge into `main` until its Apex tests
have passed in an org on its exact head commit. The `main` ruleset requires three checks:
`Static checks`, `DCO sign-off check`, and the commit status `Org tests (local)`.

That last one is posted from your machine, not by a GitHub runner:

```
scripts/org/run-org-tests.sh <org alias>
```

It deploys the commit you have checked out with `scripts/org/deploy-packages.sh`, runs every
Apex test class in that commit's source (assigning no permission set to you first: see "Tests
run as a user they create" below), and
posts `Org tests (local)` on that commit: success only when every test passed, failure
otherwise. Its description starts "Full run:". It names the test classes rather than running
every test in the org, because the test org is shared: another branch's deploy can leave its
own test classes behind, and those would fail on code this commit does not contain. The
vendored rollup engine's own tests (531 methods, about 70 seconds) are left out: no BarnCRM
runtime path calls the engine, ADR-0082 deletes it in slice S9, and they test the upstream
project. Its classes are still deployed.
The results are written to `test-results/org-tests.json`, which git ignores.

**Every full run checks code coverage.** The tests are enqueued with coverage on, so the org
records it, and the run is followed by polling its `AsyncApexJob` every `TEST_POLL_SECONDS`
(30) for up to `TEST_WAIT_MINUTES` (90). The results are then fetched without coverage, and
coverage is read separately from the org's per-class totals (`ApexCodeCoverageAggregate`
through the Tooling API, a few hundred rows). Only Apex in the commit's source counts: not test
classes, not the vendored engine, not whatever another branch left in the shared org. The run
fails, with every test passed, when:

- BarnCRM's total coverage is under `COVERAGE_TOTAL_FLOOR` (75%), or
- a class is under `COVERAGE_CLASS_FLOOR` (75%), unless it is listed in
  `scripts/org/coverage-floor-exceptions.txt`, in which case it may not fall below the figure
  recorded there. That list holds the 23 classes that were under 75% when the floor came in
  (four had no coverage at all). Raise a figure when tests improve it, and remove the line
  once the class reaches 75%; the run says which ones have.

Per-class figures (covered lines, total lines, percent, floor, result) are written to
`test-results/coverage.tsv`, and the status description carries the total and the count of
classes under their floor, for example "Full run: 2700/2700 passed on oi-test, coverage 90%, 0
class(es) under floor". The org-wide figure (`ApexOrgWideCoverage`) is recorded in that file
for information only: it counts the vendored engine, whose tests the gate no longer runs, and
anything other branches left in the org, so it cannot judge one commit.

**The relevant-tests run, for iteration.** `scripts/org/run-org-tests.sh <alias> --relevant`
(or `ORG_TESTS_MODE=relevant`) does the same staged deploy, then deploys again only the Apex
the branch changed since its merge base with `origin/main` (`RELEVANT_BASE` to change it), plus
the `critical=true` test classes, with `sf project deploy start --test-level RunRelevantTests`.
Salesforce runs the tests in that payload, the tests that depend directly on it, and the
classes whose `testFor` names something in it (see "Relevant tests" below). `RunRelevantTests`
exists only for deployments, not for `sf apex run test`, which is why this mode deploys. It
posts a different status, `Org tests (relevant, local)`, whose description starts "Relevant
tests only, not the merge gate", and the `main` ruleset does not require it: a relevant run can
never stand in for the full gate. Results go to `test-results/org-tests-relevant.json`.

The full run stays the merge gate. `RunRelevantTests` is beta, follows direct Apex references
only, and selects nothing for a change to an object, a flow, a permission set or a label, all
of which a Core test can fail on. Use the relevant run while a branch is moving and the full
run on the head you intend to merge.

Three rules make the status worth trusting:

- **It belongs to one commit.** A new push has no status, so the pull request is blocked
  again until someone reruns the script. A pass on an earlier commit never carries over.
- **It refuses a dirty working tree.** The status is posted on `HEAD`, so the code tested
  has to be the code at `HEAD`. Commit or stash first.
- **It refuses an unpushed commit**, which GitHub could not attach a status to anyway. It
  checks before deploying, so you find out in a second rather than after the run.

A pull request that changes nothing under `packages/`, `scripts/org/`, `config/`, or
`sfdx-project.json` (documentation, the workflow itself, a Dependabot bump of an action) has
nothing an org run could catch. The `Org tests not needed` job posts the status for it, so it
needs no org run. A pull request from a fork gets a read-only token and cannot post it that
way, so a maintainer runs the script for it, which is the right outcome for untested code from
outside anyway.

**Test classes run in parallel**, each in a transaction that rolls back, and each as a user it
creates for itself (see "Tests run as a user they create" below), not as the user who started
the run. That also keeps classes from colliding over what the platform keeps per user, which
used to make tests fail now and then for no reason in their own code when every class ran as
the same person. Two such collisions were found: a permission set assignment to the running
user (one row per person and set, so a second insert is refused), and a saved file (it goes
into the user's private library, and a save is refused with `INVALID_CROSS_REFERENCE_KEY,
invalid cross reference id: []` while another transaction on that library rolls back). The
few tests marked `// runs-as: deploying user` still share the running user, so they must do
neither. The gate gives that user no BarnCRM permission set, so they must need none either: a
describe or field access check counts (three classes that check field access while parsing a
filter or an import row failed this way and now run as a `TestUsers` user). A test that saves
a receipt, letter or logo file runs as
`ReceiptTestDataFactory.issuer()`.

**A test run that returns no results is retried once.** When `sf apex run test` comes back
with no test results and its output names `UNKNOWN_EXCEPTION` or a platform or network error
(or is empty), the script waits `TEST_RETRY_WAIT_SECONDS` (300 by default) and runs the tests
once more. A run with any result, including real failures, is never retried. Deploy stages
that stall are resubmitted too: see "Stalled deploys" under `org-tests`.

**At about 2,200 tests the sf CLI used to run out of memory reading the results.** The Node
process aborted with `JavaScript heap out of memory` after every stage had deployed. The cause
was the per-test code coverage that `--code-coverage` pulls into the result, not the
passing-test detail: in a 2,805-test run, coverage was 102 MB of the 313 MB result against
1.1 MB for the tests themselves. Fetching the results without coverage and reading the
per-class totals separately (above) removes that payload, so the script no longer raises the
Node heap to 8 GB. If the CLI still crashes, or returns empty or unreadable output, or the run
is still going after `TEST_WAIT_MINUTES`, the script prints "sf CLI crashed, rerun", exits 3,
does not retry, and posts no status (it used to post a failure reading `0 of 0 failed`).
Rerun the gate.

**One test depends on Salesforce's own duplicate matching.**
`DuplicateServiceTest.theStandardRuleForPeopleFindsIdenticalTwinsOnce` asks the platform's
matching service about two identical contacts inserted in the same test. In a full parallel
run it has failed once with no pair found, and passed when its class was rerun alone. A
failure of that test alone, on a change that does not touch duplicates, is a reason to rerun
the gate, not to change the code.

**The org allows a fixed number of test classes per rolling 24 hours** (`DailyAsyncApexTests`
in `sf org list limits`). Several gate runs in a day can use it up, and then every run,
including the gate, fails at once with `UNKNOWN_EXCEPTION` before any test starts.
`--synchronous` runs of one class still work, one at a time for the whole org.

While you iterate, use `sf apex run test --class-names <Class> --target-org <alias>` for one
class, or the relevant-tests run above for a branch; the full run is the final run before
merge, not the inner loop.

### Tests run as a user they create

From API version 67.0 a query or DML statement with no access mode runs in user mode, and
that includes the plain `insert` and `[SELECT ...]` in a test class. A test that runs as
whoever deploys or runs it passes only where that person already holds the BarnCRM
permission sets. The gate above used to assign them, so the gate alone never showed the problem; a
check-only deploy to a real sandbox, as an administrator without them, failed 565 of 1008
Core tests ("fields being inaccessible", "No such column", "Record Type ID: this ID value
isn't valid for the user", "You need the Manage BarnCRM Settings permission"). A subscriber
running the tests, or a different administrator, would see the same.

So every test is self-contained:

- Every `@IsTest` method and every `@TestSetup` method runs its body inside
  `System.runAs(TestUsers.admin())` in Core, and `System.runAs(TestUsers.adminWith('Giving_Admin'))`
  in Giving and Connect. `TestUsers` (Core, `@IsTest`, namespace accessible) creates a user
  on the running user's own profile and assigns the packaged permission sets by their bare
  name, preferring the ones in this package's namespace. `withPermissionSets(names)` takes any
  other list. It keeps one user per list of sets per transaction, and finds the user a
  `@TestSetup` made again in every test method, so setup data and the test share an owner.
- Each test method is a transaction of its own, so a user made only inside test methods is
  inserted again, with its permission set assignments, in every one (about 330 ms each,
  roughly 7.5 minutes of a gate run before this was fixed). A class whose test methods use
  a `TestUsers` user in more than one method creates it once in a `@TestSetup`; when there
  is no other setup, that is a method whose body is just the call, such as
  `TestUsers.admin();`, and it needs no `runAs`.
- A Core test whose code calls into whichever modules are installed (the sample data loader
  counts and removes each module's records) runs as `TestUsers.adminWithInstalledModules()`:
  BarnCRM Admin plus the admin permission set of each module the org has, and `admin()` in
  an org with Core alone.
- The profile stays the running user's so a test keeps what an administrator's profile gave
  it before (View All Data over Giving's Private objects, Manage Users for the tests that
  create people) and loses only the dependence on permission set assignments. A test that has
  something to prove about least privilege still builds its own user with
  `TestDataFactory.createUser` on the Standard User profile, inside the outer `runAs`.
- Users and permission set assignments are setup objects. `TestUsers` writes them in a
  context of their own; a test that creates more people does the same with a nested
  `System.runAs(new User(Id = UserInfo.getUserId()))`, as before.
- A test that touches no data and no permission dependent code (a parser, an in-memory
  calculation) may run as the deploying user, and says so with
  `// runs-as: deploying user (reason)` above the class, or inside one method.
  `scripts/ci/check-tests-run-as.py` fails the build on any other test method without
  `System.runAs`.

The gate is the proof that a branch is self-contained: it assigns no permission set, so it
runs the tests as whoever starts it, and that user should hold none of the BarnCRM, Giving or
Connect permission sets. On `barn-core` the running user holds none. If you hold them in your
own org, remove them (or run as a user who lacks them), so the run shows what a subscriber's
administrator would see.

### Relevant tests

Spring '26 (API 66.0) added the `RunRelevantTests` test level (beta) to deployments: Salesforce
runs the tests in the deployment, the tests that depend directly on the Apex being deployed, and
any test class that asks to be included. It follows direct references only, so a test that
reaches a class through a trigger, the automation registry or `Type.forName` is missed. Two
class-level `@IsTest` parameters close that gap, and every test class carries one:

- `@IsTest(testFor='ApexClass:HouseholdService, ApexClass:HouseholdMergeService')` runs the
  class whenever one of the named classes (or `ApexTrigger:Name`) is in the deployment. It adds
  to what the platform selects; it never narrows it. Name the classes the test exercises, not
  every class it touches on the way.
- `@IsTest(critical=true)` runs the class on every relevant-tests deployment, whatever changed.
  Five classes carry it, one smoke test for each core path: `SettingsControllerTest` (settings
  console save), `HouseholdServiceTest` (a new person gets a household), `GiftRealTimeRollupTest`
  (a saved gift moves its totals), `ImportProcessorBatchTest` (an import commit) and
  `FindControllerTest` (Find and export). Together they take about 110 seconds of the full run's
  35 minutes. Add another only for a path that has to be proven on every change, since each one
  runs every time.

A test class with neither, because no Apex change should select it (a test of validation rules
or of a test utility), is listed in `scripts/ci/test-relevance-cross-cutting.txt` with its reason.
`scripts/ci/check-test-relevance.py` (static check 16) holds every new test class to this, and
fails when a `testFor` names a class or trigger that is not in `packages/`, so a rename cannot
leave a test pointing at nothing. Test utilities with no test method (`TestDataFactory`,
`TestUsers`) are skipped. The vendored rollup engine is outside the check.

### `org-tests`

Runs only on manual `workflow_dispatch`, after `static` succeeds, against the one long lived
org described above. It used to run on every push to `main` too. Now that the gate above has
already run the full suite on the same commit before it could merge, that second run only
cost CI minutes, so it is kept for a deliberate check against the secret's org. It
authenticates from `SF_TEST_ORG_AUTH_URL`, prints how many days that org has left, prints
which shape the org actually is (`scripts/org/report-org-shape.sh`, which asks the org for
the same five facts `OrgShapeDetector` reads, through the Tooling API so it works before the
packages deploy), deploys
`packages/core` and then `packages/giving`, runs the Apex tests, and uploads the results. It
creates nothing and deletes nothing.

**What the org actually is, read from the org on 2026-09-08:** Enterprise Edition, Person
Accounts yes, Sales Cloud yes, NPSP no, Nonprofit Cloud no. So it is the
`person-accounts.json` shape, which is what the setup steps above recommend and the closest
an ordinary Dev Hub gets to the Agentforce Nonprofit orgs the first customers run.

That is the good news and the caveat in one line. **The Platform-only shape is never
exercised**, and ADR-0013 makes running on a Platform-only org a requirement rather than a
preference. This org has Sales Cloud and Person Accounts, so a Core component that
accidentally depends on either would deploy here and pass here, and fail at the first
customer who has neither. `scripts/ci/check-standard-objects.sh` is the only thing standing
between the package and that mistake, and it is a grep. Testing the Platform-only shape
means a second org and a second secret; until then, treat every green org test as evidence
about one shape and no other.

The deploy goes in stages through `scripts/org/deploy-packages.sh`: Core (one stage per object under `packages/core/main/default/objects`, then
custom metadata, then labels, then static resources with custom permissions, then Apex, then
flows, then everything that wires the two together: permission sets and groups, layouts, flexipages,
applications, tabs, quick actions, Lightning components), then Giving. A failed stage asks the
org for the component level report, by job id, in human form and then as JSON. After the last
stage the script runs
`RollupService.ensureDefaults()` as anonymous Apex, because a source deployment runs no
post-install script and would otherwise leave the org without the rollup definitions a real
install creates (ADR-0029). Before the first stage the script fails if a folder under
`packages/core/main/default` is named by no stage: Core's flows were never deployed until
2026-10-13 because no stage named `flows`.

That is not tidiness. The first deploy this project ever attempted sent all 982 components in
one request and came back with `UNKNOWN_EXCEPTION`, zero components deployed, zero component
errors, and a Salesforce ErrorId. A failure with nothing attached to it tells you nothing
about which of 982 things caused it. In stages, the same failure names a stage. The order also
matches how the packages depend on each other: Giving depends on Core.

An `UNKNOWN_EXCEPTION` with zero component errors is a Salesforce side failure rather than
something wrong with a component. Quote the ErrorId to Salesforce support.

**Stalled deploys (2026-09-24).** From about 13:00 UTC, on oi-test, one stage per run (a
different one each time) left its DeployRequest in Status Pending with a null StartDate. The
blocking `--wait 30` then timed out (`ClientTimeoutError`) and failed the gate; the org was
also reporting "Too many concurrent Apex compilations during resource mitigation".
`sf project deploy cancel` reported Canceled, but the tooling DeployRequest stayed Pending, and
about ten such requests remain there. Resubmitting the same stage deploys normally. So each
stage is now submitted with `--async` and followed with `sf project deploy report` every
`POLL_SECONDS` (15): a job still Pending with no start after `STALL_SECONDS` (300) is logged
as `STALLED DEPLOY`, cancelled (best effort) and resubmitted once. A second stall fails the
stage, naming both job ids. A job that has started is not a stall and keeps the 30 minute
limit (`DEPLOY_WAIT_MINUTES`). Component errors are reported exactly as before. The script
prints how many stalls it recovered before "Every stage deployed".

Two client side faults were seen the same day and are handled too. A single report call hung
for about 290 seconds on oi-test while its deploy finished in 2, so every report call is
abandoned after `REPORT_TIMEOUT_SECONDS` (60). A stage on oi-pa failed on `Error (10): fetch
failed` while the org reported that deploy Succeeded, so a transient client error (fetch
failed, `ECONNRESET`, `ETIMEDOUT`, socket hang up, a 5xx) on a submit or a report is retried
after a short backoff and never taken as a result. After a submit error, the newest
DeployRequest created in the last minute is followed if there is one (the org lock means it
is ours), so a stage is never deployed twice; otherwise the stage is resubmitted, up to three
submits. Twenty unreadable reports in a row (`REPORT_FAILURE_LIMIT`) fail the stage.

**Resolved 2026-09-22: the cause was in our files, not the platform.** 146 of the custom
metadata records wrote `xsi:type="xsd:string"` (and `xsd:boolean`, `xsd:double`) without
declaring the `xsd` prefix on the root element. The metadata API rejects such a record while
parsing, before any component is examined, and reports it as `UNKNOWN_EXCEPTION` with zero
component errors. Deploying each custom metadata type on its own with the prefix declared
(run 170 on `experiment/cmdt-by-type`) got past "Preparing" for the first time and reported
ordinary component errors instead: 16 labels over the 40 character limit and one label given
as an attribute. The next stage then named 44 custom labels whose short descriptions ran past
80 characters. All are fixed, and `check-custom-metadata.py` and `check-labels.py` now fail on each
of these before a deploy is attempted. The history below is kept because the size theory it describes
was wrong, and the way it was wrong is worth remembering: a failure with no component errors
can still be a defect in a component, when the defect stops the file being read at all.

**It is not transient here, whatever the general advice says.** This failure came back four
times across four separate runs before 2026-09-09, always on the Core stage, always with zero
components deployed and zero component errors, and always with the same trailing code in the
ErrorId (`-315522575`) behind a different leading number each time. It then hit that same
undivided Core stage twice more on 2026-09-09, on two separate pushes to main, once at 904
components. A three-way split (data model, Apex, UI and permissions) went in immediately
after, to see whether a smaller request avoided it. The very next run failed again, on the
data model stage alone, at 853 components: close enough to 904 and 982 that a specific bad
file stopped being the likely explanation. Three deploys of substantially different content
(mostly Apex the first two times, mostly custom fields and their sub-components the third)
failing in the same shape once each got into the same few-hundred-to-thousand range reads as
a size effect rather than a component defect, though nothing about this failure can be
proven from the client side, so treat that as the working theory, not a settled fact.

Ten occurrences, none resolved by re-running: six identical failures on Core (four documented
before 2026-09-09, two more that day), the data-model stage's failure right after the first
split, a further one after that, the config stage's failure once objects had been cleared, and
custom metadata's failure alone once config had been split three ways. `scripts/org/deploy-packages.sh`
now prints only the component failures on a failed stage, and points at the resolution above.

The data model stage was then split again, into two runtime-balanced halves of
`packages/core/main/default/objects` plus a third stage for custom metadata and the remaining
data-model metadata types. That halving is what stopped being useful evidence: across four
consecutive pushes, all fixing real component-level errors the org had newly started
reporting (list view defects, not deploy-shape ones), the same 10-object, 139-file half kept
failing with the zero-component `UNKNOWN_EXCEPTION` every single time, while the other
11-object, 144-file half deployed clean every one of those four runs. Both halves stayed the
same size and the same content across all four runs, because `balanced_split` only reacts to
file *counts*, which never changed; only file *content* did. Two comparably sized groups
behaving oppositely and consistently four times running is evidence against a size effect,
not for one: it points at something specific to one or more objects inside the failing half,
not at the request being too big.

Objects now deploy one at a time, each its own stage, rather than another same-content
halving that would only repeat the last four results. That worked immediately: every object
deployed clean on the next run, and Address__c's own two real component errors (an invalid
`length` on a `TextArea` field, and that same field listed in a compact layout, which no text
area field may be) turned out to be what the opaque failure had been hiding on that object,
not the platform fault recurring.

With every object clear, the fault moved to the next stage in line: the four config
directories (custom metadata, labels, static resources, custom permissions), deployed
together, hit it at 568 components. File count badly misled here: roughly 70 files across all
four looked nowhere near a risk, but `packages/core/main/default/labels/CustomLabels.labels-meta.xml`
is one file holding 388 individual label components, each one its own component for deploy
purposes. Config was split into three stages: custom metadata alone, labels alone (isolating
that one file), and static resources with custom permissions together, since both are a
handful of components on any count.

Custom metadata alone, about 60 records, failed the same way, confirmed identical on a manual
re-run: same zero components, zero errors, same ErrorId trailing code. This is the point where
size stops being a workable explanation for the occurrence in front of us: 61 files is nowhere
near the few-hundred-to-thousand range every prior failure carried, and it is the first time a
stage this small has failed on its own. The working theory shifts from request size to request
*rate*: every stage in this script is its own blocking deploy call, run immediately after the
previous one reports done, against the one persistent org, with no gap between them. If the
org's deploy engine needs a moment after a deploy completes before it can safely accept the
next one, back to back calls would reproduce exactly this. Untested and not the only remaining
explanation, but cheap and non-destructive to try: every `deploy_stage` call paused (15
seconds, `STAGE_PAUSE_SECONDS`) after a successful deploy, before the next stage started. The
pause is now off by default: see "Faster deploys" below. Apex and UI/permissions are unchanged, because neither has failed yet.

**If a stage fails again, keep the pattern rather than guessing at a safe size.** Read
`scripts/org/deploy-packages.sh`'s own header, which is updated at each split with what the
run actually showed, split whichever stage actually failed the same way (narrower, on what
that stage carried, not a round number picked in advance, and never just another same-size,
same-content split of a stage that has already failed that way more than once), and update
both this section and that header with the new count before pushing. Guessing a threshold and
pre-splitting everything to be safe is not the goal: each split should answer a question the
previous failure actually raised.

**Faster deploys: the fast settings are the defaults.** The stages cost about 36 requests,
each followed by a 15 second pause: about 9 minutes of sleep per run before any submit or poll
time. Both faults that drove the splitting were later traced to real defects (the Account to
`Import_Batch__c` order, now computed, and the unparseable custom metadata resolved on
2026-09-22), so neither the pause nor the per-object split has evidence behind it any more.
The full gate with both dropped took about 12 minutes end to end on oi-test on 2026-10-13,
clean, so both are now the defaults:

- `STAGE_PAUSE_SECONDS` defaults to 0: no pause between stages. Set it (for example to 15) to
  bring the pause back.
- `DATA_MODEL_STAGES` defaults to `combined`: every Core object in one request. If that request
  fails with component errors, the run stops as usual. If it fails with none (the opaque
  `UNKNOWN_EXCEPTION`), the script falls back to one object per stage in the same run.
  `DATA_MODEL_STAGES=per-object` always deploys one object per stage.

If the opaque fault comes back, run with `STAGE_PAUSE_SECONDS=15 DATA_MODEL_STAGES=per-object`
and record in this section and the script header what the run showed.

Two things constrain when it runs, both because there is one org rather than one per run.

It runs **on a push to `main`, or on a manual run** from the Actions tab (Run workflow), which
is how to retry after changing a secret without inventing a commit to do it. Deploying a pull request's code into the test org would
leave that org holding unmerged work, and the next run against main would inherit it. Pull
requests get the static checks, which is where most of the signal is.

It carries a **single global concurrency group**, `org-tests-persistent`, so two runs never
deploy at once, and `cancel-in-progress` is **false**. Cancelling a deploy partway through
would leave the org holding half a package, and unlike a scratch org that is thrown away, that
state persists into the next run. Runs queue instead; GitHub keeps only the newest waiting one.

The first version of this got the second point wrong: a global group with cancel-in-progress
set to true meant an unrelated Dependabot run cancelled main's job after every step had
already passed, which showed up as a cancelled build on a commit that was fine.

### `dco`

Checks that every commit being merged (or every pushed commit, on a push to `main`) has
a `Signed-off-by:` trailer. Merge commits are exempt. See "Signing off commits" below.

## Offline Apex checking

`scripts/ci/check-apex-offline.sh` gives feature agents compile-level feedback on Apex
without needing a scratch org or Dev Hub. It is not yet wired into `.github/workflows/ci.yml`.

It runs `CheckForIssues` from `apex-ls` (the nawforce/apex-dev-tools Apex language
server, `io.github.apex-dev-tools:apex-ls` on Maven Central) against the whole
`packages/` tree, using the repo's root `sfdx-project.json`. On first run it resolves the
jar and its dependencies from Maven Central via Maven and caches them under `.tools/`
(gitignored); later runs reuse the cache and need no network access. Requires Java 21+
and, for the first run only, Maven, both already present in the standard dev and CI
environment.

Run it from anywhere in the repo:

```
scripts/ci/check-apex-offline.sh
```

It exits non-zero if any errors are found, and prints each error with file, line, and
column. What it catches:

- Syntax errors.
- Type errors (incompatible assignment, incompatible return type, wrong argument types,
  and similar).
- References to unknown classes, methods, and variables.

What it does not catch:

- Unknown fields in SOQL queries (for example `[SELECT Missing__c FROM Thing__c]` where
  `Missing__c` does not exist passes with no error). Field-level SOQL validation still
  needs an org, for example through `sf code-analyzer` at deploy time or an actual
  deploy to a scratch org.
- Anything that is only enforced at runtime (CRUD/FLS, governor limits, trigger order of
  execution, and so on).

## Detection-only exemptions

`scripts/ci/check-standard-objects.sh` fails the build when Core, Giving, Volunteers,
Programs, or Funders names a standard object the Platform-license floor does not have
(Opportunity, Campaign, Lead, Case), a Person Account field, or an Industries object
(ADR-0009, ADR-0013).

Detecting that one of those exists is not the same as depending on it. Core has to tell an
administrator what is installed in their org: that is the Health Check (plan Section 4.8),
and it is how the coexistence mode is recommended (plan Section 4.5). Detection is done
with `Schema.getGlobalDescribe()` and field maps, against names held in String constants,
so nothing is bound at compile time and Core still deploys on an org where those objects
are absent. The grep cannot tell the difference, so it is told explicitly.

An Apex line (`*.cls` or `*.trigger`) carrying the comment

```
// detection-only: <reason>
```

is exempt from the check. Rules:

- The marker works only in Apex, and only on the line it is written on.
- Use it on constant declarations. A constant is inert; an expression is not.
- The reason is written for a reviewer, not for the script. Say what the constant detects
  and what reads it.
- Every exempted line is printed on every run, under the heading "Detection-only
  exemptions", whether the check passes or fails. The list is meant to be read: if it grows,
  something is wrong.
- The marker does not make a compile-time reference legal. `Opportunity.Name` with the
  marker appended still stops Core deploying on a Platform-only org, and no CI check will
  catch it before the org shape matrix does.

As of v0.1 the marker appears on four constant declarations in `OrgShapeDetector` (the NPSP
namespace prefix, the Person Account indicator field, the Industries gift object, and the
standard Sales Cloud object) and nowhere else. Three of the four are printed as exemptions:
the NPSP prefix is not a name the grep looks for, and carries the marker only so that the
four detection constants read alike.

### Import template column headings

A shipped import template (`customMetadata/Import_Template_Default.*.md-meta.xml`) is exempt
as a whole file, and only that custom metadata type is. Its mapping document names the columns
of a file exported from another system, and a Data Loader export of NPSP or Nonprofit Cloud
heads its columns with that system's field paths, for example
`GiftTransaction.OriginalAmount` or `npe01__Opportunity__r.Campaign.Name`. The importer
compares those words with a file's header row as text; nothing resolves them against the
org's schema, so they bind nothing and cannot refuse a deployment. The script prints each such
file under "Import template column headings, not references" on every run. Test classes get
no such exemption: a test of a migration template reads the headings from the shipped
mapping rather than spelling them out.

The exemption is decided on the file's path, never on a line's content, so an Apex comment that
names such a path is still checked. It covers whole files, which is safe only while the type
has no MetadataRelationship field: a value in such a field is resolved against the org at
deploy time, so if the type ever gains one, revisit the exemption.

`check-namespace.sh` treats the same files the same way in its prefixed-component check,
because an NPSP export heads its columns with NPSP's own prefixed names (`npe01__`, `npsp__`).
It lists them and does not fail on them. Its pattern is anchored to the path part of each
`grep -rn` line, so a line in any other file that names such a path is still checked. Its
literal `barncrm__` check still covers them.

## What happens when the secrets are missing

The `org-tests` job checks for the secret first. If it is empty, every org-dependent
step is skipped and the job posts a `::warning::` explaining why, instead of failing.
`static` (lint, unit tests, Code Analyzer, namespace and standard-object checks) still
runs and still gates merges regardless of whether the secret is set. This means a fork
without access to the secret can still open a pull request and get useful signal; only the
live org work is skipped.

Two secrets are involved and they do different jobs. `SF_DEVHUB_AUTH_URL` lets a machine
create scratch orgs; nothing in continuous integration uses it now that the test org is long
lived, and it is kept because creating and refreshing that org needs it.
`SF_TEST_ORG_AUTH_URL` names the org the tests actually run in, and is the one `org-tests`
requires.

## Setting the `SF_DEVHUB_AUTH_URL` secret

This secret holds a Salesforce SFDX auth URL for the Dev Hub the `org-tests` job uses to
spin up scratch orgs. Only repository maintainers with a Dev Hub-enabled org should set
this.

1. Authenticate to the Dev Hub locally:

   ```
   sf org login web --alias devhub
   ```

2. Get its auth URL:

   ```
   sf org display --target-org devhub --verbose --json
   ```

   Copy the `result.sfdxAuthUrl` value from the JSON output. Treat this value as a
   credential: it grants access to the Dev Hub. Do not paste it into a file that gets
   committed, and do not paste it into chat, an issue, or a pull request.

3. In the GitHub repository, go to **Settings > Secrets and variables > Actions > New
   repository secret**. Name it `SF_DEVHUB_AUTH_URL` and paste the auth URL as the
   value.

The workflow writes this secret to a temporary file only inside the CI runner, uses it
once with `sf org login sfdx-url --sfdx-url-file`, and deletes the file immediately
afterward. The auth URL itself is never written to any file that is committed or
uploaded as an artifact.

## Reading Code Analyzer results

Every `static` run uploads a `code-analyzer-results` artifact containing:

- `code-analyzer-results.html`: a readable report, open it in a browser.
- `code-analyzer-results.json`: the same findings in machine-readable form.

Download the artifact from the workflow run's Summary page under **Artifacts**. Each
finding lists a severity (1 Critical through 5 Info), the rule, the file and line, and a
description.

### Severity threshold policy

The `static` job runs Code Analyzer with `--severity-threshold 2`, meaning the command
(and the job) fails if any finding is severity 1 (Critical) or 2 (High). Lower-severity
findings are reported but do not fail the build. The policy is zero high or critical
findings on every pull request; do not raise the threshold to make a build pass, fix the
finding or, if it is a false positive, suppress that specific rule with a documented
reason.

## Signing off commits (DCO)

BarnCRM uses the Developer Certificate of Origin instead of a CLA. Every commit must
carry a `Signed-off-by:` trailer with your name and email, certifying you have the right
to submit the change under the project's license.

Sign off a single commit:

```
git commit -s -m "Your commit message"
```

Sign off every commit on an existing branch that is missing the trailer:

```
git rebase --signoff main
git push --force-with-lease
```

Git has no built-in setting that adds the trailer to every `git commit` automatically,
but you can get the same effect with a local alias so you never have to remember the
flag:

```
git config --global alias.ci "commit -s"
```

Then use `git ci` instead of `git commit`. If you prefer, a `prepare-commit-msg` hook
that appends the trailer works too; either is fine as long as every commit ends up
signed off before it reaches CI.

The `dco` CI job checks every commit in a pull request (or every pushed commit, on a
push to `main`) for the trailer and fails with a list of offending commits and a fix
hint if any are missing.

Merge commits are the one exception: the job passes `--no-merges`, so a commit that git
wrote to join two branches is not checked. A merge commit carries no authored content,
so there is nothing for anybody to certify the origin of; the certification belongs on
the commits the merge brings in, and every one of those is still checked. The Developer
Certificate of Origin's own tooling makes the same exemption. Signing a merge anyway,
with `git merge --signoff`, is harmless and costs nothing, so integrators who want an
unbroken chain of trailers can keep doing it.

## Handoff: open work and what still needs testing

Recorded 2026-09-26, when development moved from one maintainer session to shared Claude
Code users. Everything below is pushed to GitHub; nothing lives only on a local machine.
Remove each item from this list in the PR that finishes it.

Last checked 2026-10-12: nothing below has changed since 2026-09-26. `main` is at PR #178, the
C-29 stack is still open and needs a gate run on its new top head, Dependabot #179 is merged,
and #180 is open. The plan's Section 0 carries the same build-state summary.

### Waiting to merge: C-29 neutral Core (PRs #163 to #174)

- Branches `feature/c-29-neutral-core-1` to `-12`, stacked; top head
  `ffcf5b6562c39f837578dec6f04a69bdc528d790`. Review approved. ADR-0059 is already numbered.
  That head merged `main` in on 2026-10-12 (no conflicts); the earlier head was `3da9276`.
- Not yet tested cleanly: the last `Org tests (local)` status, on `3da9276`, was `failure`. Of two
  full runs, one hit the sf CLI heap crash, and the other passed 2,234 of 2,235; the one failure
  was the flaky `DuplicateServiceTest.theStandardRuleForPeopleFindsIdenticalTwinsOnce`,
  which passed 16 times out of 16 when run alone.
- To land it:
  1. Run one full gate from a clean detached worktree at the top head, with
     `scripts/org/run-org-tests.sh oi-test` (or `oi-pa`).
     If only the flaky test fails, rerun the gate.
  2. Fast-forward each lower branch to the top head:
     `git push origin ffcf5b6562c39f837578dec6f04a69bdc528d790:refs/heads/feature/c-29-neutral-core-N`
     for N = 1 to 11.
  3. Wait for the CI checks. The jest test `setupStepFields` "opens the tab a navigation field
     names" fails about one full parallel run in five (it passes alone); if it is the only static
     failure, re-run the job once.
  4. Squash-merge the bottom PR:
     `gh pr merge 163 --squash --match-head-commit ffcf5b6562c39f837578dec6f04a69bdc528d790`.
     The stacked PRs close as merged.

### Never tested

- Core installed without Giving, in any org. Every gate run deploys all three packages.
- The Platform-only shape. Both test orgs (`oi-test`, `oi-pa`) have Person Accounts, and
  ADR-0013 notes that even a Platform-only scratch org keeps the standard objects. Only the
  static checks (`check-standard-objects.sh`) and review cover it.

### Work items

These are also recorded, in the same detail, in plan Section 11.3 (parking lot). Remove an item
from both when its PR merges. Item numbers match the plan's and are kept when an item is
removed, so a list may start above 1.

2. **Log unrecognized checkbox values in imports.** `ImportRowProcessor.convertCheckbox` reads
   only `true`, `yes` and `1` as true. The new rule:
   - **True:** `true`, `yes`, `y`, `1`, `x`, `checked`, `on`, `t`.
   - **False:** `false`, `no`, `n`, `0`, `off`, `f`.
   - **Blank:** no change.
   - **Anything else:** skip the field, with a note in the run log.

   Update the admin guide first. Add tests, including a 200-row bulk case.

### Next on the roadmap

Product plan Section 6 is the source of truth:
- **X-07 Gift Transaction mirror.** It shares `ConnectSync` with X-01.
- **v0.7 items:**
  - C-32: import matching and per-file values;
  - C-33: load one object;
  - C-34: Find query builder;
  - C-35: bulk update, which depends on C-34.

  Before C-34, the query compiler needs a security review and scale tests.

### Owner questions

The owner questions raised while building v0.5 and v0.6 are plan Section 11.2, items 14 to 27,
each with the default that shipped and a recommendation.

### Working notes for new contributors

- **Test orgs:** `oi-test` and `oi-pa` are on the maintainer's Dev Hub. A contributor who
  cannot reach them needs their own Dev Hub and org, and the maintainer's approval for any
  new org, as described earlier on this page. Both expire soon: `oi-test` on 2026-10-23 and
  `oi-pa` on 2026-10-24. Recreating `oi-pa` from `person-accounts.json` is pre-approved;
  replacing `oi-test` also means updating the `SF_TEST_ORG_AUTH_URL` secret.
- **The gate:** run it from a clean, detached worktree at the pushed head. The script checks
  for a clean tree only when it starts.
- **Staging:** stage by explicit path. A synced checkout can create untracked copies named
  like `file 2.md`.

## Scratch org snapshots

Snapshots shorten recreating a test org from a full deploy (many minutes, and the stalled deploys
described above) to creating an org from saved state. They are a local convenience: nothing in
continuous integration creates or uses one.

**Dev Hub requirements.** The Dev Hub must have Scratch Org Snapshots turned on (Setup, Dev Hub,
enable scratch org snapshots; the orchestrator confirms the exact label). Snapshot count and the
snapshot's own lifetime are limited and set by Salesforce; check the current values with
`sf org list snapshot` and Salesforce's scratch org snapshot documentation before relying on a
snapshot older than a few weeks. The source org must be an active scratch org of that Dev Hub.
A snapshot cannot be created from an org that is not a scratch org.

**Commands.**

```bash
scripts/org/create-snapshot.sh oi-pa BarnPA              # snapshot an existing org (refreshes if BarnPA exists)
scripts/org/create-org-from-snapshot.sh person-accounts oi-pa --days 7 --replace
scripts/org/create-org-from-snapshot.sh platform-only barn-core --days 7
sf org list snapshot                                      # status and names
```

**Owner approval.** Creating a snapshot and creating any scratch org need the owner's approval.
Pre-approved without asking: recreating `oi-pa` or `barn-core` (expires 2026-10-15) when it
expires. Replacing `oi-test` also means updating the `SF_TEST_ORG_AUTH_URL` secret, because the
new org has a new auth URL.

**When to refresh.** After any change under `packages/` that the next test run needs (a snapshot
does not track the repository), after the Dev Hub or the Salesforce release changes the shape,
and before the snapshot's own expiry. The script warns when `packages/` changed after the
snapshot date. Sample data is seeded into the source org before the snapshot, so it carries over.

**After creating an org from a snapshot,** run `scripts/org/run-org-tests.sh <alias>` once and
check the shape line it prints, as for any new org.
