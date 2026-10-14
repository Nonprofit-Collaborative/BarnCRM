# Editions

## What it does

BarnCRM is one suite of tools that comes in two editions. Both have the full core suite of
tools: people, households, relationships, addresses, imports with undo, Find and bulk update,
duplicate review, Org Optimizer, Health Check, settings and the rest of BarnCRM Core.

| Edition | For | What BarnCRM shows |
|---|---|---|
| **Standard Edition** | Any Salesforce org: businesses, clubs, associations, any organization | The core suite. No nonprofit modules are listed or offered anywhere. |
| **Nonprofit Edition** | Nonprofits, or any organization that wants the nonprofit tools | The core suite plus the nonprofit modules: Giving, Volunteers, Programs, Funders and Connect. |

The edition decides what BarnCRM shows and offers. It never installs, removes or changes
anything: every module is a separate package that you install yourself through Salesforce's
installer, and no records change when the edition changes.

You choose the edition once, in the first step of the [Setup Assistant](setup-assistant.md).
After that the step shows the edition you chose and no longer offers the choice, because
changing it later is rare and changes what everyone sees.

## What each edition shows

These are the places that depend on the edition.

| Where | Standard Edition | Nonprofit Edition |
|---|---|---|
| Setup Assistant, module step | Core, plus any module that is already installed | Core and all five nonprofit modules, each Present or Not installed with its Install link |
| BarnCRM Settings, General, Modules ([Module Manager](module-manager.md)) | The same list as the module step | The same list as the module step |
| BarnCRM home page, Modules card | The same list | The same list |
| Health Check, "The Gift Transaction mirror is in the Connect module" (Nonprofit Cloud orgs only) | Not shown | Shown when Connect is not installed |
| Setup Assistant, first step | Edition shown read-only | Edition shown read-only, with the Giving install link while Giving is not installed |

Before anyone has chosen an edition, BarnCRM shows what the Standard Edition shows.

A module that is installed keeps working whatever the edition: it stays listed, its own
settings sections, Setup Assistant steps, Health Check findings, What's New notes, roles and
tabs stay, and its automation keeps running. If a module was installed by mistake, turn it off
or uninstall it from the [Module Manager](module-manager.md); changing the edition does not.

## How to change the edition later

You need the **Manage BarnCRM Settings** permission (BarnCRM Admin has it). There are two
ways, and they do the same thing.

### In BarnCRM Settings (recommended)

1. Open the app launcher, type `BarnCRM`, and choose **BarnCRM**.
2. Click **BarnCRM Settings**, then **General** in the left navigation.
3. Find **Edition**. It shows the edition in force, for example "Standard Edition".
4. Click **Change edition** under it. It opens a short explanation and a button for the other
   edition, for example **Switch to the Nonprofit Edition**.
5. Click that button. A confirmation says what changes. Click **Change edition** to confirm,
   or **Cancel** to leave it as it is.

The change is saved at once and listed under **Recent changes** at the bottom of BarnCRM
Settings. Reload any open BarnCRM page to see the new module lists.

### In Salesforce Setup

1. Open **Setup**, type `Custom Settings` in Quick Find, and click **Custom Settings**.
2. Click **Manage** next to **BarnCRM Settings**.
3. Click **Edit** on the organization default row (the row under **Default Organization Level
   Value**).
4. Set **Edition** to `Community` for the Standard Edition or `Impact` for the Nonprofit
   Edition, exactly as written. These are the stored values; the names people read are
   Standard Edition and Nonprofit Edition.
5. Click **Save**.

Any other value is treated as no edition chosen. A change made in Setup is not listed under
Recent changes, so prefer BarnCRM Settings.

## Common mistakes

- **Expecting the Nonprofit Edition to install Giving.** It only offers it. Install Giving from
  the Setup Assistant's first step or from the Module Manager.
- **Switching to the Standard Edition to remove a module.** An installed module stays installed
  and keeps working. Turn it off or uninstall it in the Module Manager.
- **Typing `Standard` or `Nonprofit` in Setup.** The stored values are `Community` and `Impact`.
- **Looking for the choice in the Setup Assistant after the first run.** Starting the assistant
  again keeps the edition; change it in BarnCRM Settings as above.
