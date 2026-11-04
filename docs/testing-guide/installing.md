# Installing

Scripts for the install tools on [Installing BarnCRM](../admin-guide/installing.md): the
pre-check, the test list for a production install and the release destructive manifest. Run
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
