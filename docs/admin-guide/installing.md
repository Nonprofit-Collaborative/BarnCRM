# Installing BarnCRM

> **Not for production orgs:** BarnCRM is in pilot. We do not recommend installing pilot or testing versions in a production Salesforce org. Use a sandbox, a free Developer Edition org or a scratch org. The production steps below are for when a release says it is ready for production.

## 1. What It Does

Until BarnCRM is on AppExchange, you install it from its source code with the Salesforce
command line. This page says which Salesforce orgs it runs in, how to check yours first, how
to install, and how to take a later release.

### Supported Editions

| Salesforce edition or license | Supported | Why |
|---|---|---|
| Enterprise Edition, including Nonprofit Cloud (Agentforce Nonprofit) and Power of Us orgs | Yes | |
| Unlimited Edition (and the older Performance Edition) | Yes | |
| Developer Edition | Yes | A free org for trying BarnCRM. Its data storage is small, so load the sample data in moderation. |
| Salesforce Platform and Lightning Platform Plus licenses (staff without Sales or Service Cloud) | Yes | Core and every module run in a Platform-only org. |
| Professional Edition | No | Salesforce runs Apex code in Professional Edition only from a security-reviewed AppExchange package, and BarnCRM is not one yet. |
| Lightning Platform Starter licenses | No | A Starter user can use only 10 custom objects, and every BarnCRM role needs more. |
| Group, Essentials and Starter editions | No | No Apex code. |

### How Much Room It Takes

BarnCRM installed from source counts toward your org's limits, beside your own work.
Salesforce does not count an AppExchange (managed) package this way, so the numbers below
stop mattering once BarnCRM is on AppExchange.

| Package | Apex code (characters) | Custom labels | Custom objects and settings |
|---|---|---|---|
| Core | 2,336,034 | 2,354 | 22 |
| Rollup Builder | 456,862 | 380 | 4 |
| Giving | 708,095 | 656 | 25 |
| Volunteers | 202,668 | 151 | 11 |
| Programs | 181,195 | 203 | 12 |
| Logic Models | 58,027 | 106 | 5 |
| Funders | 116,136 | 100 | 7 |
| Mirror | 221,010 | 170 | 1 |
| Contact Point Sync | 43,980 | 2 | 2 |
| **Every package** | **4,324,007** | **4,122** | **89** |
| **Org limit** | 6,000,000 (can be raised) | 5,000 | 200 Enterprise, 2,000 Unlimited, 400 Developer |

Measured 2026-11-04. The install pre-check below measures the release you are installing,
against your org.

**More room for Apex code.** If the pre-check says your Apex code will not fit, install fewer
modules, or ask Salesforce for a higher limit: open a case with Salesforce Support from the
Help menu, asking to increase the Apex code character limit (Salesforce Help article "Increase
Apex Code Character Limit"). Support decides; raises above 10,000,000 characters get a closer
look.

## 2. How to Turn It On

This is done from a computer's command line. You need:

1. The Salesforce CLI (`sf`, version 2) and Python 3.9 or later.
2. The BarnCRM repository at the release you are installing (`git clone`, then `git checkout`
   the release tag named in its release notes).
3. Your org connected to the CLI: `sf org login web --alias myorg` (for a sandbox add
   `--instance-url https://test.salesforce.com`), as a System Administrator.

### Step 1: Run the Pre-Check

```
python3 scripts/org/install-precheck.py myorg --modules core,rollups,giving
```

Name the modules you plan to install; the ones they need are added (Giving adds Core and
Rollup Builder). Leave `--modules` out to check every module. It only reads from your org,
changes nothing and prints nothing about your login. Each line is PASS, WARN or FAIL:

- **Edition:** your edition is supported, and no users are on Platform Starter.
- **Apex, Labels, Objects:** your own Apex code, custom labels and custom objects plus
  BarnCRM's fit your org's limits. WARN means it fits with little room to spare.
- **Names:** no object, field on a standard object, list view, class, label, tab, static
  resource, component, page, permission set or flow that BarnCRM ships has the same name as
  one your org already has. A deploy would quietly change a same-named item of yours, or
  fail on it.
- **Test fit:** active validation rules and required fields on Account and Contact, which
  BarnCRM's tests can trip during a production install (see
  [If a Test Fails](#if-a-test-fails)).

Fix every FAIL before installing. If you have support's higher Apex limit, add
`--apex-limit <characters>`.

### Step 2: Install

**In a sandbox, a Developer Edition org or a scratch org**, one command deploys the packages in
stages and runs their setup steps:

```
scripts/org/deploy-packages.sh myorg
```

Add `--core-only` for Core alone (the Standard Edition).

**In a production org**, validate first, then deploy what was validated. Production runs
Apex tests on every deploy that carries code. By default those are all the tests in your org,
your own included, so one of your own old failing tests would stop BarnCRM's install. Run only
BarnCRM's tests instead (`RunSpecifiedTests`); `list-package-tests.py` lists them for the
packages you name:

```
sf project deploy validate --target-org myorg \
  --source-dir packages/core --source-dir packages/rollups --source-dir packages/giving \
  --test-level RunSpecifiedTests \
  --tests $(python3 scripts/org/list-package-tests.py core rollups giving) \
  --wait 120
sf project deploy quick --job-id <the Id the validation printed> --target-org myorg --wait 60
```

Name the same packages in both places. With `RunSpecifiedTests`, each BarnCRM class needs 75%
test coverage from those tests, which they give.

A deploy is not an install, so BarnCRM's setup steps have not run yet. Run them:

```
sf org assign permset --name BarnCRM_Admin --target-org myorg
echo 'CorePostInstall.runAsSourceDeploy();' | sf apex run --target-org myorg
```

Then open **BarnCRM Settings**, **Modules**, and choose **Finish Setup** on each module you
installed (see [Module Manager](module-manager.md#when-a-modules-setup-never-ran)).

### Step 3: Set It Up

Open the BarnCRM app and follow the first-run setup window and the
[Setup Assistant](setup-assistant.md).

### Upgrading to a Later Release

A release is installed the same way, with two differences:

1. **Removed items.** A deploy adds and updates but never deletes, so each release lists the
   items it removed in a destructive manifest. Build it from the release you have to the one
   you are installing, naming your modules:

   ```
   python3 scripts/org/build-destructive-manifest.py <your release> <new release> \
     --packages core,rollups,giving --out destructive
   ```

   Then add `--post-destructive-changes destructive/destructiveChangesPost.xml --ignore-warnings`
   to the deploy (both commands in production). It lists any removed record type on screen:
   delete that one in Setup.
2. **What a release overwrites.** A release replaces every item BarnCRM ships, whole. A change
   you made to one of them is lost: a record page, page layout, list view, permission set,
   picklist value on a BarnCRM field, validation rule, flow template, or an object's sharing
   setting. Your records, everything saved in BarnCRM Settings, and items you made yourself
   are kept. So never edit a shipped item: clone it (a record page, a permission set, a list
   view) and change the clone.

If a deploy stops with "This schedulable class has jobs pending or in progress", delete
BarnCRM's jobs in Setup, **Scheduled Jobs**, and deploy again. Then run Core's setup step above,
and use the fix on Health Check's **Nightly Jobs Are Not Scheduled** finding (see
[Health Check](health-check.md)) to schedule them again. `deploy-packages.sh` does this for you.

### Moving to AppExchange Later

A source install cannot be upgraded in place to BarnCRM's AppExchange (managed) packages when
they exist: Salesforce has no way to turn installed source into a package. The move is the one
on [Moving a Pilot to the Managed Packages](moving-to-managed-packages.md): copy BarnCRM's
records off, remove the source install, install the packages and load the records back. Plan
for it before you put real data in.

## 3. A Five-Minute Walkthrough

1. Connect a sandbox: `sf org login web --alias trial --instance-url https://test.salesforce.com`.
   You see "Successfully authorized".
2. Run `python3 scripts/org/install-precheck.py trial --modules core`. You see one line per
   check and a Result line, for example "Result: 0 fail, 1 warn, 6 pass."
3. Read each WARN. A Labels or Apex WARN means the org is near a limit; a Test fit WARN names
   validation rules to look at before a production install.
4. Run `scripts/org/deploy-packages.sh trial --core-only`. Each stage prints as it deploys,
   then Core's setup steps run.
5. Open the BarnCRM app. The first-run setup window opens.

## 4. Common Mistakes

**The pre-check says "FAIL Names".** Your org already has an item with a name BarnCRM ships,
such as an Address object or a Deceased field on Contact. Do not install over it: a deploy
changes your item to BarnCRM's (or fails), and BarnCRM then reads and writes your records.
Rename your item, or leave out the module that ships the name, then run the pre-check again.

**The install stops with "Apex code character limit exceeded".** Your own code and BarnCRM's
do not fit in the Apex limit. Install fewer modules, or ask Salesforce support for more room
(see [More room for Apex code](#how-much-room-it-takes)).

**The production install runs your org's own tests and one of them fails.** The deploy ran
with the default test level. Run it again with `--test-level RunSpecifiedTests` and the test
list, as above.

### If a Test Fails

BarnCRM's tests create people and organizations. A validation rule or a required field you
added to Account or Contact can refuse those records and fail a test, which stops a production
install. BarnCRM's test data fills any required text, number, date or picklist field you added,
and saves past duplicate rules. It cannot fill a required lookup, and nothing lets a test skip
a validation rule. If a test fails on one of yours, the failure names the rule or field. Make
the rule skip your installing user while you install (for example, with a condition on the
user), or make the field required on the page layout instead of on the field, then validate
again. The pre-check's Test fit lines list what to look at before you start.
