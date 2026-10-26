# Before you test

Set up a test org once, then run the scripts in this guide against it. Everything here uses the
scripts in `scripts/org/`; for how they work, see
[Scratch orgs](../contributor-guide/scratch-orgs.md).

## Create a test org

You need the Salesforce CLI (`sf`), a Dev Hub connected to it, and a clean checkout of `main`
(see [Environment](../contributor-guide/environment.md)). Run every command from the
repository root.

Pick a shape. Run the smoke list on the Person Accounts shape; run the full regression list on
both shapes below before a release.

| Shape | Command | Use it for |
|---|---|---|
| Person Accounts | `scripts/org/create-scratch-org.sh person-accounts <alias> --days 30 --no-sample-data` | The default. Closest to an Agentforce Nonprofit org; Opportunity and Campaign exist, so Mirror can be tested. |
| Platform only | `scripts/org/create-scratch-org.sh platform-only <alias> --days 30 --no-sample-data` | Proving Core and the modules work with no Sales or Service objects, and that every Core permission set fits a Salesforce Platform license (the script checks this itself). |

The other shapes (`sales-cloud`, `npsp`, `nonprofit-cloud`) exist in `config/scratch-defs/`;
use them only when a script asks for them. `nonprofit-cloud` needs an entitled Dev Hub.

The script creates the org, deploys Core, gives your login user every Core permission set, and
prints the expiry date. A scratch org lasts at most 30 days. To start again from a clean org,
run the same command with `--replace`, which deletes the old org first.

`--no-sample-data` is deliberate: the sample data must be loaded after the modules are
deployed, or it loads without gifts or volunteer records (see [Load sample data](#load-sample-data)).

A sandbox works too: deploy into it with the next step, skip anything that says "scratch org",
and never load sample data into a sandbox that holds real people.

## Deploy the modules

`create-scratch-org.sh` deploys Core only. To deploy every module (Rollup Builder, Giving,
Volunteers, Mirror) on top:

```bash
scripts/org/deploy-packages.sh <alias>
```

Then give your login user the module admin permission sets:

```bash
sf org assign permset --target-org <alias> --name Rollup_Builder_Admin --name Giving_Admin --name Volunteers_Admin --name Opportunity_Mirror --name Campaign_Sync --name Accounting_Export --name Inbound_Gift_API --name Record_Inbound_Gift_Action
```

To test Core alone (the Standard Edition with nothing else installed), skip this step and use a
separate org.

## Load sample data

```bash
scripts/org/seed-sample-data.sh <alias>
```

It loads 200 households, their contacts, 25 organizations, connections and affiliations, and,
with the modules deployed, gifts, funds, appeals, commitments and volunteer records. It waits
until every background job has finished, which takes a few minutes with Giving installed.
Loading twice is refused; remove the set first (script T-SA-07 in
[Setup Assistant](setup-assistant.md) covers removal through the app).

Then, with Giving installed, open **BarnCRM Settings**, **Rollups**, and select
**Recalculate**, so giving totals are filled in before you test them.

Sample data detail and the names in it (for example **The Garcia Family** and the **Staff
Household**): [Sample data](../admin-guide/sample-data.md).

## Test users

Run each script as the user its **Prerequisites** line names. Your login user is the
**admin**. Create the other two once per org.

| User | Role in the app | Permission sets it ends up with |
|---|---|---|
| admin | Your login user (System Administrator) | BarnCRM Admin and every Core set (from the create script), plus the module sets above |
| staff | **Team Member** role, plus the **Giving Staff** extra permission (or the **Fundraising Staff** role instead) | BarnCRM Staff, Giving Staff, Volunteers Staff (follows the role) |
| read-only | **Read Only** role, plus the **Giving Read Only** extra permission | BarnCRM Read Only, Giving Read Only, Volunteers Read Only (follows the role) |

Steps:

1. Create the two users from the CLI. Give staff the **Standard User** profile (on the
   platform-only shape, **Standard Platform User**). Give read-only the Salesforce **Read Only**
   profile: a profile that can edit accounts and contacts would override the BarnCRM Read Only
   set, and the read-only negative scripts would wrongly pass.

   ```bash
   sf org create user --target-org <alias> --set-alias <alias>-staff profileName="Standard User" LastName="Staff Tester" Username="staff@<alias>.barncrm.test" Email="staff@<alias>.barncrm.test"
   sf org create user --target-org <alias> --set-alias <alias>-ro profileName="Read Only" LastName="Read Only Tester" Username="readonly@<alias>.barncrm.test" Email="readonly@<alias>.barncrm.test"
   ```

2. Give the roles in the app, which also tests the Access page: open **BarnCRM Settings**,
   **Access**, find each user in **Find a person**, choose the role, and select **Give access**.
   Add the Giving set under the extra permissions on the same page. The Volunteers and Rollup
   Builder sets are not listed there: they follow the role, given automatically when the role
   is given on this page (and by the nightly access check). See
   [Access](../admin-guide/access.md).

   Or assign the permission sets from the CLI. This assigns the sets directly rather than the
   role, so name the Volunteers set too:

   ```bash
   sf org assign permset --target-org <alias> --on-behalf-of staff@<alias>.barncrm.test --name BarnCRM_Staff --name Giving_Staff --name Volunteers_Staff
   sf org assign permset --target-org <alias> --on-behalf-of readonly@<alias>.barncrm.test --name BarnCRM_Read_Only --name Giving_Read_Only --name Volunteers_Read_Only
   ```

3. Log in as a test user: `sf org open --target-org <alias>-staff` (or `<alias>-ro`). Use a
   private browser window for each user so sessions do not mix. To get a password instead,
   run `sf org generate password --target-org <alias> --on-behalf-of <username>`.

Feature permission sets (**BarnCRM Bulk Update**, **BarnCRM Bulk Delete**, **BarnCRM Erase
People**, **BarnCRM Duplicate Review** and the rest) are given to the staff and read-only users
only when a script says so. Many negative scripts depend on those users not having them. The
admin already holds every Core set, these included, because the create script assigns them all:
that is more than a real BarnCRM Admin holds, so test a permission's absence with the staff
user, never the admin.

The create script has no switch to leave sets off: the gate needs them all. To test what an
admin sees without a feature set (for example a BarnCRM Admin who cannot erase people or review
duplicates), use one of these:

- **A second admin user (preferred).** Create a third user as in step 1 with the **System
  Administrator** profile, then give it only the **BarnCRM Admin Group** role on the Access page.
  It holds what a real BarnCRM Admin holds and none of the extra permissions. Give it one extra
  permission at a time when a script needs it.
- **Your login user, for one script.** On the Access page, under **Extra permissions**, select
  **Remove** beside your name for the set you are testing, run the script, then give it back.
  Sets not listed there (BarnCRM Access Manager and the tab sets) are removed in Setup, Users,
  your user, **Permission Set Assignments**, and added back the same way.

## Edition modes

BarnCRM has two editions: the **Standard Edition** (Core, no nonprofit modules offered) and the
**Nonprofit Edition** (Core plus Giving and the other nonprofit modules). The edition is chosen
once, in the first-run setup window, and decides what BarnCRM shows and offers; it never
installs or removes anything. See [Editions](../admin-guide/editions.md).

- Most scripts assume the **Nonprofit Edition**. Choose it the first time you open the app
  (script T-SA-01 in [Setup Assistant](setup-assistant.md)).
- Scripts that check what the Standard Edition hides say so in their prerequisites. Switch with
  **BarnCRM Settings**, **General**, **Edition**, **Change edition**, and switch back afterwards.

## Record results

Copy this table into a file or spreadsheet per test run. One row per script.

```text
Build: main at <short sha>    Org: <alias>, shape <shape>    Tester: <name>    Date: <yyyy-mm-dd>

| Script | Result (Pass / Fail / Blocked / Skipped) | Failed step | Issue | Notes |
|---|---|---|---|---|
| T-HH-01 | Pass | | | |
| T-IMP-03 | Fail | 4 | #NNN | Undo left 2 contacts |
```

- **Pass**: every step's expected result happened.
- **Fail**: a step's result differed. Record the first failing step and stop that script.
- **Blocked**: a prerequisite failed (for example the org would not deploy), so the script could
  not run.
- **Skipped**: not run this time, with the reason.

Get the short sha with `git rev-parse --short HEAD` on the checkout you deployed.

## Report a failure

Report bugs and give feedback through GitHub: open
<https://github.com/Nonprofit-Collaborative/BarnCRM/issues/new/choose> and choose the **Bug
report** template (or the feature request template for feedback). [SUPPORT.md](../../SUPPORT.md)
says what to include. Fill the bug report in like this:

- **What happened**: the actual result, word for word where there is a message. Add a
  screenshot.
- **What you expected**: the expected result from the script.
- **Steps to reproduce**: the script ID and failing step number (for example "T-GIFT-04, step
  6"), plus any data you entered that differs from the script.
- **Org shape**: Person Accounts is "Agentforce Nonprofit or Person Accounts"; platform-only is
  "Platform only".
- **BarnCRM version**: no package version exists yet, so write `main at <short sha>`.
- **Module**: the package the script tests. Rollup Builder is not in the list: choose "Not
  sure" and name it in the description.
- **Error Log message**: if the app showed an error, open **BarnCRM Settings**, **Error Log**,
  and copy the newest entry. See [Error log](../admin-guide/error-log.md).

Never put donor or other personal data in an issue, a screenshot or an attachment: test orgs
hold sample data only, so copy from those. Report a security problem privately, as
[SECURITY.md](../../SECURITY.md) describes, never in a public issue.
