# Module Manager

## What It Does

The Module Manager is one list of the BarnCRM modules your org is offered, with what each one
is doing and the one thing you can do next with it: install it, turn it on, turn it off, or
see what removing it would delete. It lives in BarnCRM Settings, so you never have to look for
a module's state in Salesforce Setup.

Every module is a separate package. A module that is not installed leaves nothing behind in
your org. BarnCRM never installs or removes a package for you: Salesforce does not let one
app do that, and you should see and approve what goes into your org.

When Rollup Builder or Giving is installed and the org also runs DLRS or Rollup Helper, the
list starts with **Other Rollup Tools**: one line per tool, saying it is a separate rollup tool
whose rollups BarnCRM does not manage. See
[DLRS and Rollup Helper in the Same Org](rollups.md#dlrs-and-rollup-helper-in-the-same-org).

## How to Turn It On

There is nothing to turn on.

1. Open the app launcher, type `BarnCRM`, and choose **BarnCRM Admin**.
2. Click **BarnCRM Settings**, then **Modules** in the left navigation.

Everyone who can open BarnCRM Settings sees the list. You need the **Manage BarnCRM
Settings** permission to install, turn on, turn off, or check what an uninstall would delete.

Which modules are listed depends on the edition chosen in first-run setup (see
[BarnCRM Settings, First-run setup](barncrm-settings.md#first-run-setup)). The Standard Edition (or no edition chosen yet) lists
Core and BarnCRM Rollup Builder. The Nonprofit Edition lists all eight: Core, BarnCRM Rollup
Builder, BarnCRM Giving, BarnCRM Volunteers, BarnCRM Programs, BarnCRM Logic Models, BarnCRM
Funders and BarnCRM Mirror. A module that is installed is always listed, whatever the edition. See
[Editions](editions.md).

The modules that only the Nonprofit Edition offers (Giving, Volunteers, Programs, Logic Models,
Funders and Mirror; the module catalog decides, not a fixed list) are grouped in their own section at the
bottom of the list, titled **Nonprofit Modules**. Core and the modules both editions offer come
first. The section has a **Show Nonprofit Modules** checkbox, ticked by default. Clear it and
the nonprofit modules are hidden from the list; the checkbox stays so you can tick it again.
The choice is saved for the whole org, needs the **Manage BarnCRM Settings** permission to
change (others see the checkbox greyed out), and hides rows only: it installs, removes and
turns off nothing. If any of the hidden modules is installed, a line under the checkbox says
"Installed nonprofit modules hidden: " and how many, so an installed module never disappears
without a sign. A Standard Edition org that has no nonprofit module installed lists none, so it
shows no section.

No module is installed with Core or by first-run setup: a module is installed only when you
install it from this section. An installed module's row links to its own app, where it has
one. Rollup Builder has no app of its own: its **Rollup Builder** tab is in the **BarnCRM
Admin** apps. Volunteers has a Settings tab in its app, where its settings live; Giving's
BarnCRM Fundraising app has no Settings tab, and Mirror has no app of its own. (Some module settings
still show in BarnCRM Settings for now; they move to the module's app in a later release.) Core's own
features are turned on in General instead (see
[BarnCRM Settings, Features](barncrm-settings.md#features-general)).

## A Five-Minute Walkthrough

Maria's org has Core and Giving installed. She wants to see the list, pause Giving while she
cleans up her data, and check what removing a module would cost.

1. Open **BarnCRM Settings**, **Modules**. Each row has the module's name, a status, a
   **What this module does** link, and its actions:
   - **Installed**: installed and working, with a link to the module's own app. Core is
     always installed and on.
   - **Installed and off**: installed, and its automation is not running.
   - **Not installed**: not in your org.
2. On a **Not installed** row, click **Install**. Salesforce's install screen opens in a new
   tab. Choose who to install for (**Install for Admins Only** is the safe choice), click
   **Install**, and wait for Salesforce's email. Come back and click **Check again**: the row
   says **Installed**. If a row says "No install link is published for this module yet.", there is
   no version to install yet; read about it with **What this module does**. Until BarnCRM
   publishes package versions, every **Not installed** row says this and none has an **Install**
   link; the link appears once a version exists. If it says "Install these
   first: BarnCRM Rollup Builder. This module needs them.", install the modules it names
   first: Salesforce refuses Giving, Volunteers, Funders and Mirror until BarnCRM Rollup Builder is
   installed, and Funders and Mirror until Giving is too.
3. On the **Giving** row, click **Turn Off**. The row says **Installed and off**. Giving's
   automation stops: new gifts are not added to totals and no acknowledgment is queued, until
   you turn it back on. Automation that protects your records, such as the lock on a posted
   gift, keeps running. Your records stay exactly as they are.
4. Click **Turn On**. The row says **Installed** again, Giving's automation runs again with every switch on
   the Automation page as you left it, and you are given the module's administrator access
   (for Giving, the Giving Admin permission set) if you did not have it. Giving it takes
   Salesforce's Assign Permission Sets permission, which a system administrator has and a
   BarnCRM Admin gets from **BarnCRM Access Manager** (see [Access](access.md)); without it
   the module still turns on and an administrator assigns the set in Setup.
5. On the **Giving** row, click **What an Uninstall Deletes**. A short report lists each kind
   of record the module owns and how many of each your org has, for example `Gift: 1,204`.
   A count with a `+`, for example `2,300+`, means at least that many: Salesforce lets one
   page read only 50,000 records in total, so the report shares that between the kinds of
   record and stops counting a large one early. Read it, then click **Open Installed
   Packages** to uninstall in Salesforce Setup, where Salesforce asks you to confirm.

Turning a module off does not hide its tabs: Salesforce does not let an app change tab
visibility. To hide a module from a colleague, take away its role on the
[Access](access.md) page.

## When a Module's Setup Never Ran

Install BarnCRM and its modules as packages. Each package runs its own setup steps when it is
installed and at every upgrade: it creates its automation switches, import templates and
shipped totals, gives the installer its administrator access, and so on. Copying the source
into an org by hand skips those steps, and the module then works only in part.

A row whose setup steps never ran says "Its setup steps never ran, which happens when source
is copied in by hand. Finish Setup runs the steps a package install runs." With the **Manage
BarnCRM Settings** permission you also see a **Finish Setup** button on that row. Click it: the
module's install steps run for the whole org, with you standing in for the installer, and the
notice goes away. For Core, the install gives the BarnCRM Admin role to the installer; Finish
Setup gives it to you only when you also hold Salesforce's **Assign Permission Sets** (or
**Manage Users**) permission, as giving a role on the Access page does, and otherwise runs the
other steps without it. The steps only add what is missing, so pressing it twice does no harm. It is
recorded under **Recent Changes** in BarnCRM Settings. Health Check reports the same thing (see
[Health Check](health-check.md#how-a-fix-button-works)).

Finish Setup is a recovery step for an org built from copied source, not a way to install
BarnCRM: install the packages.

## Common Mistakes

- **Expecting Show Nonprofit Modules to remove or pause anything.** It only hides rows. A
  hidden module that is installed keeps working, and it is counted in the line under the
  checkbox.
- **Expecting Turn off to remove the module.** It pauses the module's automation and keeps
  every record. Use Salesforce's uninstall, after reading the report, to remove it.
- **Expecting Turn off to hide the tabs.** It does not. Change the person's role on the
  Access page.
- **Uninstalling without reading the report.** An uninstall deletes every record the module
  owns, and the fields it added to people, households and organizations. Export what you
  need first.
- **Looking for a version number.** Salesforce does not tell an app which version of another
  package is installed. Click **Open Installed Packages** to see versions in Setup.
- **Turning off a module that another one needs.** Mirror works with Giving's gifts: turning
  Giving off stops the automation Mirror relies on. Turn Mirror off first, or leave both on.
- **Turning off BarnCRM Rollup Builder and expecting Giving's totals to keep up.** Turning it
  off stops every rollup at once, Giving's gift totals included: no save, Flow, queue run,
  nightly run or Recalculate updates a total while it is **Installed and off**, a
  recalculation already running stops, and nothing is processed while it is off. The values
  already on your records stay. **Turn On** puts every total right: it starts the totals that
  waited and a recalculation of every active rollup in the background. The check on a
  rollup's save (**Check rollups before saving**) pauses with the module; a rollup saved while
  it is off that cannot be calculated is skipped by that recalculation and logged in the Error
  Log. See [Rollups](rollups.md).
