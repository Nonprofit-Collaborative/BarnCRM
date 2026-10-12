# Scratch orgs

Open Impact is verified against five org shapes, matching the license and package
configurations described in the product plan (Section 4.2). Each shape has a scratch org
definition in `config/scratch-defs/`. Four of them any Dev Hub can create; the fifth needs
an entitlement, and is described below.

## The shapes

| Shape           | Definition file                            | What it verifies                                                                                                                             |
| --------------- | ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Platform only   | `config/scratch-defs/platform-only.json`   | The floor: Core, Giving, Volunteers, Programs, and Funders all work with no Opportunity, Lead, Campaign, Case, or Product objects available. |
| Sales Cloud     | `config/scratch-defs/sales-cloud.json`     | Standard Sales/Service objects present; Connect's Opportunity mirror and Campaign sync have real targets.                                    |
| NPSP installed  | `config/scratch-defs/npsp.json`            | Sales Cloud plus NPSP installed; NPSP coexistence mode (Section 4.5).                                                                        |
| Person Accounts | `config/scratch-defs/person-accounts.json` | Person Accounts enabled, simulating the Agentforce Nonprofit shape; junction household mode is required here.                                |
| Nonprofit Cloud | `config/scratch-defs/nonprofit-cloud.json` | The real Agentforce Nonprofit shape, with the Nonprofit Cloud objects present. Needs an entitled Dev Hub: see below.                          |

### The Nonprofit Cloud shape needs an entitled Dev Hub

Scratch org features that map to a licensed product are granted only when the Dev Hub org
itself carries that entitlement. An ordinary Developer Edition Dev Hub creates the first four
shapes and refuses this one, listing the features it can grant, which is the quickest way to
find the right feature string for your entitlement.

Two things follow from that.

**The `NonprofitCloud` feature string in the definition file is unverified.** Nobody has run
this shape against an entitled Dev Hub yet. If creation fails naming an unknown feature, the
error lists what your Dev Hub can grant: take the right name from that list and correct
`config/scratch-defs/nonprofit-cloud.json`. That is the one line expected to need editing.

**Continuous integration does not run this shape at all.** An earlier version of this page
said it runs when `nonprofit-cloud` is named in an `SF_ORG_TEST_SHAPES` repository variable.
No such variable exists and nothing reads it: the workflow has no shape matrix, it deploys
into one long lived org named by `SF_TEST_ORG_AUTH_URL`. Running this shape in continuous
integration means creating an org from it by hand against an entitled Dev Hub and putting
that org's auth URL in the secret, in place of the current one.

**Most of what this shape would prove is already covered by Person Accounts**, which any Dev
Hub grants: junction membership, the person account paths through households, naming and
greetings, relationships, the sample data loader in junction mode. Coexistence mode is a
setting rather than something inferred at run time, so it can be set explicitly in the Person
Accounts shape. What genuinely needs this shape is `OrgShapeDetector` answering "is Nonprofit
Cloud installed" against a real org rather than a stub.

## A development org that lasts

**There is no permanent scratch org.** Salesforce caps one at 30 days and deletes it on the
day it expires, along with everything in it. `--days` above 30 is refused by the script with
that explanation rather than by the API with a less obvious one.

So "persistent" means one of two things here, and they are different tools.

### A 30 day development org, refreshed monthly

The closest thing to what most people mean, and the one to use unless you have a reason not
to. It is a real shape, created from the same definition CI uses, so what you see is what CI
sees.

```bash
scripts/org/create-scratch-org.sh person-accounts dev --days 30 --replace
```

`person-accounts` is the shape to use until a Nonprofit Cloud entitlement exists: it is the
closest an ordinary Dev Hub can get to the Agentforce Nonprofit shape the first customers
run.

That deploys Core, assigns the permission sets, and seeds the sample data, so the org is
usable rather than empty.

**Two settings make it behave like an Agentforce Nonprofit org**, and both are set in the app
rather than by the script, because walking through them is itself worth testing. Open the
Open Impact app; the Setup Assistant offers the coexistence mode it detected. Set it to
Agentforce Nonprofit coexistence, which moves household membership to the junction records
that person accounts need in the same save. Health Check will then report an org shape that
matches the mode. What still differs from a real Nonprofit Cloud org is that its objects are
absent, so `OrgShapeDetector` reports them missing; that difference is the reason the
`nonprofit-cloud` shape exists. When it prints the expiry date, put a reminder in your calendar for
a day or two before. Re-running the same command refreshes it.

`--replace` matters more than it looks. Without it, creating a second org under an alias that
is already taken moves the alias to the new org and leaves the old one alive, quietly
consuming one of the active scratch org slots a Developer Edition Dev Hub allows. `--replace`
deletes the previous one first.

**Anything you typed into the org is lost on refresh.** Configuration made in Setup, records
created by hand, notes. What survives is what is in this repository: the metadata, the
permission sets, and the sample data the seed script loads. If something is worth keeping,
it belongs in the repository, which is the same discipline the package needs anyway.

### A Developer Edition org, which really is permanent

Free from developer.salesforce.com, never expires, and holds its data indefinitely. Deploy
into it with `sf project deploy start --source-dir packages/core --target-org <alias>` rather
than through the create script, which is written for scratch orgs.

Use it for a demo environment, or for anything you want to keep for months. Two things it
does not give you. Its shape is fixed, so it cannot verify the platform only guarantee, the
Person Accounts path, or the NPSP and Nonprofit Cloud shapes: those are what the scratch org
definitions exist for. And it drifts, because nothing recreates it from source, so over months
it stops resembling a fresh install, which is exactly the state a subscriber will be in.

### Which to use

Use a 30 day scratch org for development and for anything you intend to trust. Use a Developer
Edition org for a long lived demo. Do not use either as the only place a piece of
configuration exists.

## Running the script

```bash
scripts/org/create-scratch-org.sh <shape> [alias] [--days N] [--no-sample-data] [--replace]
```

Example:

```bash
scripts/org/create-scratch-org.sh platform-only my-dev --days 14
```

This creates the scratch org, deploys `packages/core`, assigns every Core permission set it
finds, and (platform-only shape only) runs the license check described below. It then loads
sample data unless `--no-sample-data` is passed, and prints an `sf org open` hint. Target: under
ten minutes from a clean checkout, per the contributor experience target in Section 8.2 of the
product plan.

To remove a scratch org:

```bash
scripts/org/delete-scratch-org.sh <alias>
```

## The platform-only user check, explained

Salesforce scratch orgs always provision Sales Cloud objects, regardless of the requested
edition or features. There is no scratch-org setting that removes Opportunity, Campaign, Lead,
or Case from a scratch org. That means a scratch org's mere presence of those objects cannot be
used to prove Platform-only compatibility.

Instead, `create-scratch-org.sh` verifies Platform-only compatibility two ways:

1. **A CI static check** (`scripts/ci/check-standard-objects.sh`) fails the build if any file
   under `packages/core`, `packages/giving`, `packages/volunteers`, `packages/programs`, or
   `packages/funders` references a Sales/Service or Industries object at all. Source code, not
   the org, is the thing being checked.
2. **A runtime license check**, for the platform-only shape only: the script creates a user with
   the "Salesforce Platform" user license and the "Standard Platform User" profile (using
   `config/users/platform-user.json`, username
   `platformuser@<alias>.openimpact.test`), then assigns every permission set found under
   `packages/core/main/default/permissionsets` to that user with
   `sf org assign permset --on-behalf-of`. The "Standard Platform User" profile cannot see
   Sales/Service objects at all, so if a Core permission set were to grant field- or
   object-level access to something that license cannot see, the assignment fails loudly. A
   passing assignment is direct evidence that Core's permission sets are Platform-license-safe,
   not just that its source code looks clean.

## NPSP: manual install fallback

`scripts/org/install-npsp.sh` installs NPSP and its five dependency packages, in order
(Contacts & Organizations `npe01`, Households `npo02`, Recurring Donations `npe03`,
Relationships `npe4`, Affiliations `npe5`, then NPSP `npsp` itself), using
`sf package install --package <04t> --wait 30 --no-prompt --security-type AllUsers`.

As of 2026-09-07, this repository does not have verified 04t package version IDs for that
install chain: the NPSP GitHub releases page did not surface a confirmed, current GA version id
for the main package or ids for any of the five dependency packages, and
`install.salesforce.org` was not reachable for direct verification from the environment that
built this scaffold. Per the project's hard rule against inventing package IDs,
`NPSP_PACKAGE_IDS` in `scripts/org/install-npsp.sh` is left empty on purpose, and the script
exits with an explanatory message rather than guessing.

**Manual step, until the script is updated with verified IDs:** use the NPSP installer at
<https://install.salesforce.org/products/npsp>, logged in against the target scratch org, to
install NPSP and its dependencies. Once real, verified 04t ids are available, populate
`NPSP_PACKAGE_IDS` in `scripts/org/install-npsp.sh` in the order above.

## Sample data

`scripts/org/seed-sample-data.sh` loads `data/sample/plan.json` via `sf data import tree` if it
exists. It does not exist yet (tracked as C-10 in the product plan: 200 realistic households),
so until then the script prints `sample data not yet available (C-10)` and exits successfully.
