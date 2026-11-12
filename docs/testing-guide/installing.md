# Installing

Scripts for the install tools on [Installing BarnCRM](../admin-guide/installing.md): the
pre-check, the test list for a production install, the release destructive manifest and the
package install-and-upgrade test. Run
them from a copy of the repository at the build under test, with the Salesforce CLI and
Python 3.

## T-INST-01: Pre-Check on an Org That Has BarnCRM

**Purpose:** confirm the pre-check reads an org without changing it and reports each check.
**Prerequisites:** the test org (`<alias>`) with every module deployed.

| Step | Action | Expected result |
|---|---|---|
| 1 | Run `python3 scripts/org/install-precheck.py <alias>`. | It starts "BarnCRM install pre-check for <alias>" and lists the eight packages. No line shows a login, token or URL. |
| 2 | Read the Edition, Apex, Objects and Labels lines. | **Edition** is PASS for an Enterprise or Developer Edition org. **Apex** shows the org's own code plus BarnCRM's per package and a percentage of 6,000,000. **Labels** and **Objects** show a count against 5,000 and the edition's allowance. |
| 3 | Read the Names line. | One WARN saying BarnCRM is already in this org, with a count per kind (ApexClass, CustomLabel and so on). No FAIL. |
| 4 | Read the last line. | "Result: 0 fail, ..." and the exit status (`echo $?`) is 0. |

## T-INST-02: Pre-Check Finds a Name the Org Already Uses

**Purpose:** confirm a name collision fails the check before an install.
**Prerequisites:** a new scratch org without BarnCRM (`<alias>-bare`), where you may change setup.

| Step | Action | Expected result |
|---|---|---|
| 1 | In Setup, add a Checkbox field **Deceased** to Contact (API name `Deceased__c`). | The field is saved. |
| 2 | Run `python3 scripts/org/install-precheck.py <alias>-bare --modules core`. | The packages listed are `core` only. |
| 3 | Read the Names lines. | "FAIL  Names: 1 CustomField name(s) the org already uses" with `Contact.Deceased__c` below it. |
| 4 | Read the last line. | "Result: 1 fail, ..." and "Fix every FAIL before installing."; the exit status is 1. |
| 5 | Run it with `--modules giving`. | The packages listed are `core, rollups, giving`: the ones Giving needs are added. |

**Cleanup:** delete the scratch org.

## T-INST-03: Test List and Destructive Manifest

**Purpose:** confirm the production test list and the release destructive manifest.
**Prerequisites:** none (no org).

| Step | Action | Expected result |
|---|---|---|
| 1 | Run `python3 scripts/org/list-package-tests.py core rollups`. | One test class name per line (about 280), ending in `Test`; `TestDataFactory` is not listed. |
| 2 | Run `python3 scripts/org/list-package-tests.py nothing`. | A usage line naming the packages and "unknown: nothing"; exit status 2. |
| 3 | Run `python3 scripts/org/build-destructive-manifest.py HEAD HEAD --out /tmp/same`. | "0 component(s) removed"; `/tmp/same/destructiveChangesPost.xml` lists no members. |
| 4 | Run it from an older commit to `HEAD` that removed a class (for example a batch's starting commit). | A count per type, and the removed class appears in `destructiveChangesPost.xml` as an `ApexClass` member. A removed record type is printed instead, with "delete it in Setup". |

## T-INST-04: Package Upgrade Test Plan

**Purpose:** confirm the package install-and-upgrade test shows what it would do and refuses
to run before the namespace exists. See [CI](../contributor-guide/ci.md), "Package install
and upgrade test".
**Prerequisites:** none (no org).

| Step | Action | Expected result |
|---|---|---|
| 1 | Run `scripts/org/package-upgrade-test.sh --from HEAD --to HEAD`. | "Refusing to run: the namespace in sfdx-project.json is empty." and the exit status is 2. Nothing is created. |
| 2 | Run it again with `--plan --shapes platform,npc`. | "PLAN ONLY: nothing below is run, created or written." The packages are listed Core first, Rollup Builder before Giving, Volunteers and Mirror, and Giving before Mirror. A Readiness list follows, with MISSING lines (namespace, package aliases, post-install scripts, global entry points). Exit status 0. |
| 3 | Read the N-1 path line. | "REFUSED for managed (a beta cannot be upgraded)". |
| 4 | Add `--promote-from` and read the Versions section. | A `promote-n1` step after each `build-n1` step, each with "PROMOTION IS PERMANENT". |
| 5 | Run with `--plan --type unlocked --packages giving --shapes platform`. | Only Core, Rollup Builder and Giving. A `setup-n1` and a `setup-n` step for each, after the installs and after the upgrades. |
| 6 | Run `git worktree list` before and after step 2. | The same list: the plan added nothing. |

## T-INST-05: After a Real Package Upgrade

**Purpose:** check by hand what the scripted upgrade test cannot see: install links, guided
installs in Module Manager, and the pages after an upgrade.
**Prerequisites:** a run of `scripts/org/package-upgrade-test.sh ... --keep-orgs` that passed
(its `summary.md` says PASS), and its kept scratch org for the shape under test. Log in with
`sf org open --target-org <alias>`. The script runs only once the namespace is registered
(plan D-87, D-173).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Setup**, **Installed Packages**. | Every chosen BarnCRM package is listed under one namespace, at the version the report names as N. |
| 2 | Open **BarnCRM Settings**, **Modules**. | Each installed module says **Installed**. A module that is not installed shows an **Install** link (not "No install link is published for this module yet.") once a released version exists. |
| 3 | On a **Not installed** row that needs another module first (for example Mirror without Giving), read the row. | "Install these first: ..." names the missing module. |
| 4 | Click **Install** on a module with no missing dependency, and follow Salesforce's screens with **Install for Admins Only**. Come back and click **Check again**. | Salesforce's install page opens in a new tab and the install finishes. The row says **Installed**, and no row says its setup steps never ran. |
| 5 | Open **Health Check** and click **Run now**. | No error findings. The result matches the script's `health-n` step. |
| 6 | Open BarnCRM Home, a household, a person and (with Giving) a gift from the sample data. | Pages load without an error toast; totals on the household and person are filled in, as before the upgrade. |
| 7 | Open the **Error Log** tab. | No row since the org was created, matching the `error-log-n` step. |
| 8 | If the run used `--uninstall-check`, open **Modules** again. | The uninstalled module says **Not installed**, and Core's pages still work. |

**Cleanup:** delete the kept scratch org (`sf org delete scratch --target-org <alias> --no-prompt`).
