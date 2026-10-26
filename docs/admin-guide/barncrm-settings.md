# BarnCRM Settings

## What it does

BarnCRM Settings is the one page where
everything about how BarnCRM behaves is changed: how households are named, which
automations run, who has access, and how this org fits alongside anything you already had.
Settings are grouped into sections on the left, every setting has a plain-language
description under it, and there is a search box for when you
remember the word but not the section.

You never need Salesforce Setup for a normal day. When something genuinely can only be
done in Setup, the setup checklist on the Hub home page sends you there with instructions,
and the section of this page that depends on it says so at the top (see "When a section
needs a change in Setup" below).

A module with an app of its own can also show its settings there, on their own: the
**Volunteer Settings** tab is this page showing only the Volunteers settings. They are the
same settings, so a change in either place shows in both. The Rollup Builder module has no
settings tab: its settings are in the **Rollups** section of this page (**Default rollup
mode**, **When instant totals are calculated** and **Time of the nightly run**). Saving a new
**Time of the nightly run** moves the scheduled nightly rollup run at once (see
[Rollups](rollups.md#how-the-nightly-run-works)).

The footer of the page has a **Report a problem or give feedback** link. It opens the
BarnCRM support page on GitHub in a new tab.

## How to turn it on

There is nothing to turn on, but there is one permission to give out.

1. Open the **BarnCRM** app and click the **BarnCRM Settings** tab.
2. If you can change values, you already have the **Manage BarnCRM Settings**
   permission. If you see a notice at the top of the page saying you can read but not
   change settings, you do not.
3. To give someone the permission, add them to the **BarnCRM Admin** role on the Access
   page. That role carries Manage BarnCRM Settings. Staff and read-only roles do not, on
   purpose: settings change how the whole org behaves.

Everyone can open the page and read it. That is deliberate: David should be able to see
how greetings are configured before he asks Maria to change them.

## First-run setup

Until BarnCRM's first-run setup is finished, the BarnCRM home page and this page both show
the same setup window in front of everything else, and nothing behind it can be used.

**On a new install, BarnCRM's automation does nothing until first-run setup is finished.**
Every Core feature starts off, so its automation is held: no household is created for a new
contact, no address is copied, no reciprocal relationship is made, no primary affiliation is
set and no preferred email is filled in. Households are caught up automatically: when
**Household Upkeep** is turned on (in first-run setup or in **General**), BarnCRM gives a
household to every person added while it was off, in the background, usually within a few
minutes, exactly as it would have when they were saved. That includes people stored as
accounts (Person Accounts) when your org uses the flexible way of belonging to a household:
each gets a household of their own and is its primary member. In the simple way a person
stored as an account is given no household, on save or in the catch-up. A person who already
belongs to a household is left in it, and nobody is caught up while **Create households
automatically** is off. The other four features are not caught up: records added or imported before
Addresses, Relationships, Affiliations or Preferred Email is on are not processed when it is
turned on, so finish first-run setup before you add or import people. An org upgraded from an
earlier release keeps every feature on and is not held.

- **Someone with the BarnCRM Admin role** (Manage BarnCRM Settings) sees two questions:
  1. **Which edition**: Standard Edition or Nonprofit Edition (see [Editions](editions.md)).
     This is the only place the edition is asked; the Setup Assistant's first step then shows
     it read-only.
  2. **What to turn on**: **Turn on all the default core features** (every feature on, the
     usual choice), or **Let me choose features**, which lists the features described below,
     all ticked. Untick what you do not want yet.

  Click **Finish setup**. What you left ticked is turned on fully: its tabs, its settings and
  its automations. Finishing also gives the tool tabs (Data Manager, Import, Find, Org
  Optimizer, Bulk Update) of every feature that is on to everyone holding a BarnCRM role, within
  a few minutes, and starts the nightly tab access check if it is not already scheduled. What
  you unticked stays off, and you can turn it on later in **General**.
  You land on **General** in BarnCRM Settings, and the setup window never shows again on
  either page. No module is installed by first-run setup: install modules later from the
  **Modules** section.
- **Anyone else** sees "An administrator needs to finish setting up BarnCRM." and nothing
  else, on both pages, until an administrator finishes.

An org that had already chosen an edition before this release never sees the window, and an
upgraded org with no edition is given the recommended one by the upgrade. If someone set the
edition in Salesforce Setup on a new install, the window still shows, with that edition
already selected, because the features have not been chosen yet. Finishing with every feature
unticked still finishes setup: the window does not come back.

If BarnCRM was deployed from its source rather than installed as a package, the deploy script
runs the same install steps once Core is in, so a fresh org gets first-run setup exactly as
above. An org that has already saved BarnCRM Settings or holds a household is treated as an
upgrade: nothing you chose changes. To run the steps by hand, run
`CorePostInstall.runAsSourceDeploy();` as anonymous Apex (it is safe to run again).

## Features (General)

Features come with BarnCRM Core. On a new install every feature is off until you turn it on,
in first-run setup or here. An org upgraded from a release before features existed has every
feature on, so nothing it already used disappears.

The **General** section starts with **Edition** (read-only, see [Editions](editions.md)) and
then **Features**: one row per feature, each with a short description and its state. Above
the rows a warning says that **a feature cannot be turned off once it is turned on**. A
feature that is off has a **Turn on** button, which asks you to confirm before it does
anything; a feature that is on just says **On**. Only people with Manage BarnCRM Settings see
the Turn on buttons.

While a feature is off its tabs are hidden for everyone, its rows in this page are hidden (a
section left empty disappears), and its automations do not run. Turning it on shows its tabs
to the people who should see them, shows its settings, and starts its automations.

| Feature | What it covers | Hidden or stopped while off |
|---|---|---|
| Data Manager | Data Manager, Import, Find and Bulk Update | Those four tabs and the Import section |
| Duplicate Review | Duplicate suggestions and review | The Duplicates row in Households |
| Org Optimizer and Health Check | The Data Hygiene tab and Health Check | The Data Hygiene tab, the Health section and the three "unused" thresholds in General |
| Household upkeep | Creating, naming and tidying households | Its three automations and the household naming and tidy-up rows |
| Addresses | Address capture and the default address | Its three automations and the Addresses section |
| Relationships | Keeping both sides of a relationship in step | Its automation and the Relationships section |
| Affiliations | The primary affiliation | Its automation |
| Preferred email and phone | Copying the preferred email into the standard email and the preferred phone into the standard phone | Its three automations |

Rules that enforce data (relationship, affiliation and rollup definition checks) belong to no
feature and always run. Once a feature is on, the Automation section still lets you pause any
single automation for fine-grained control; that is not turning the feature off.

**How tab hiding works.** Salesforce shows a tab to anyone holding a permission set that
grants it, and an app cannot hide a tab any other way. So each feature tab has its own small
packaged permission set (for example **BarnCRM Tab: Find**) that grants only that tab, and
BarnCRM gives it, once the feature is on, to the people who should see the tab: whoever holds
a role or extra permission that used to include the tab (BarnCRM Admin for all five, Find and
Export for Find, Data Manager and Data Hygiene, Bulk Update or Bulk Delete for Bulk Update and
Data Manager). BarnCRM keeps these in step when a feature is turned on, when a role or extra
permission is given or removed on the Access page, after every upgrade, and every night (for
roles given in Setup or by user access policies). A large org may take a few minutes to catch
up. Do not assign the BarnCRM Tab permission sets by hand: the nightly run removes them from
anyone who should not have them.

## Modules

Modules are separate packages, not installed with Core. The **Modules** section lists the
modules your edition offers (see [Editions](editions.md)), plus any module already installed:

- A module that is not installed shows **Not installed** with **Install**, which opens
  Salesforce's installer, and **What this module does**.
- An installed module shows **Installed** and a link to its own app, where it has one.
  Volunteers has a Settings tab in its app, and the Rollup Builder's settings are in the
  **Rollups** section of BarnCRM Settings; Giving's Fundraising app has no Settings tab, and Mirror has no app. (Some module
  sections still show in BarnCRM Settings for now; they move to the module's app in a later
  release.)

The modules are BarnCRM Rollup Builder (both editions), and BarnCRM Giving, BarnCRM
Volunteers, BarnCRM Programs, BarnCRM Funders and BarnCRM Mirror (Nonprofit Edition). The
Standard Edition lists no Nonprofit Edition module that is not installed. BarnCRM Rollup
Builder ships as its own package, installed from this section like the others. See the
[Module Manager](module-manager.md) for what else you can do with an installed module.

## A five-minute walkthrough

Start with the sample data loaded. Steps 1 to 6 are Maria. Step 7 is David.

1. Open the app launcher, type `BarnCRM`, and choose **BarnCRM**. The home page
   opens with the **Setup checklist**.
2. Click the **BarnCRM Settings** tab. The console opens with the section list on the
   left and the first section showing on the right. The sections are General, Modules,
   Organization, Households, Relationships, Addresses, Giving, Receipts, Rollups, Automation,
   Error Log, Access, Import, and Health. You only see the ones that have something in them,
   and a feature that is off hides its sections: Giving and
   Receipts come with the Giving module, and Giving also adds the receipt details to the
   Organization section, so BarnCRM Core on its own shows fewer. General starts with
   **Edition**, shown read-only: it is chosen once in first-run setup, and the
   **Change edition** link under it is the way to change it later (see
   [Editions](editions.md)).
3. Click in the **Search settings** box and type `greeting`. Results appear as you type. If
   the search cannot run, the box says so and asks you to try again, instead of saying nothing
   matches.
   Every setting whose name, description, or section mentions greeting is listed, which
   includes the household formal and informal greeting settings.
4. Click the result **Formal greeting pattern**. The console jumps to the Households
   section and to the **Preview and Recompute** panel. The three household naming
   patterns (household name, formal greeting, informal greeting) are edited only in that
   panel, not as separate rows, so the panel is where the search result takes you. The
   panel's own text explains the patterns; the household naming page of this admin guide
   gives the longer explanation.
5. Change the value in the panel. For example, put `{Salutation} {FirstName} {LastName}` in
   the formal greeting pattern, watch the preview update, then click the panel's **Save**.
   A confirmation appears saying the patterns are saved. The new value is in effect
   immediately: the next contact you add gets the new greeting, with no waiting and no
   cache to clear. The settings console's own **Save** button is for the other settings in
   the section, such as whether people who have died stay in the household name.
6. Open the **General** section and scroll to **Recent Changes** at the bottom of the page.
   It shows on **General** only, whichever section the change was made in. Your change is the first row,
   showing the setting by the name you see on this page, the old value, the new value, your
   name, and the time. Nothing is ever changed silently: one row is written per setting you
   actually changed, and saving a page without changing anything writes nothing. Ticking or
   skipping a step in the setup checklist is not a settings change, so it is not listed.
7. Now sign in as David, who has the Team Member role and not Manage BarnCRM
   Settings. He opens the same tab and sees the same sections and the same values, with a
   notice across the top: "You can read these settings but not change them. Ask your
   administrator for the Manage BarnCRM Settings permission." Every control is greyed
   out and there is no Save button. He can still read every description and follow every
   Learn more link.

## Your organization's address

The **Organization** section shows your mailing address as one **Organization Address**
block, laid out like a Salesforce address: **Street**, **Street 2**, then **City**, **State**
and **Zip Code** on one row, then **Country**. Like the household naming patterns, the block
has its own **Save address** button, and its changes appear in **Recent Changes** on the
**General** page.

- You can leave the whole address blank.
- Once you fill in any part, **Street**, **City**, **State** and **Zip Code** are required and
  are marked as required. **Street 2** and **Country** stay optional.
- If you save with a required part missing, BarnCRM keeps what was saved before and tells you
  what is missing: "The organization address is incomplete. Add City, Zip Code, or clear every
  part of the address."

Receipts print the address as one line per part, with City, State and Zip Code together on one
line. In a letter's body, the `{{OrganizationAddress}}` token (receipts) and
`{OrganizationAddress}` token (volunteer letters) put the whole address on one line, with the
parts separated by commas.

## You never type an identifier

No setting asks you for a record ID, an API name or a developer name. Where a setting points
at something, you choose it:

- **A record**, such as the default fund or the default appeal with Giving, is chosen with a
  search box. Start typing the record's name and pick it from the list. The box shows the
  name; clearing it leaves the setting empty.
- **Record types**, such as which kinds of Opportunity become gifts with BarnCRM Mirror, are
  a list of checkboxes, one per active record type in your org, by the name you see in Setup.
  Ticking none means every record type.
- **A choice from a fixed list**, such as the month your fiscal year starts, is a dropdown.

The description of each setting is read out by a screen reader together with the control,
so every setting is explained the same way however you use the page.

## When a section needs a change in Setup

BarnCRM avoids Salesforce Setup wherever it can. A few features still depend on something only
Setup can change, usually because Salesforce keeps that switch for itself. When a section has
one, a note at the top of the section says, before any setting:

- **what** to change in Setup,
- **why** BarnCRM needs it, in one sentence,
- **where** it is, as a path in plain words, for example "Setup, Company Settings, Fiscal
  Year".

Where BarnCRM can read the answer without any extra permission, the note also says whether it
is already done: **Done** with a green tick, or **Not done yet** with a warning icon. Otherwise
the note is an instruction only, and it stays there after you make the change, because BarnCRM
cannot tell. Nothing on the note changes your org: you make the change in Setup yourself.

| Section | What to change in Setup | Checked by BarnCRM |
|---|---|---|
| General | Make the Setup fiscal year start in the same month as **Fiscal year start month** (Setup, Company Settings, Fiscal Year) | Yes |
| General | To save Custom Metadata entries in an installed package: turn on **Deploy Metadata from Non-Certified Package Versions via Apex** (Setup, Apex Settings). The **BarnCRM Metadata Admin** permission it also needs is given on the Access page, under Extra Permissions | No |
| Households | To review duplicates: keep the standard duplicate rules active (Setup, Duplicate Rules). The **BarnCRM Duplicate Review** permission is given on the Access page, under Extra Permissions, to people with a Sales Cloud or Service Cloud license | No: the Duplicates panel shows each rule as On or Off |
| Rollups | Create the field a new rollup writes to before you build it (Setup, Object Manager, the object, Fields & Relationships) | No |
| Error Log | Allow the org to send email, or no digest is sent (Setup, Deliverability, Access level: All email) | Yes |
| Access | Giving and Mirror permission sets, such as Giving Staff or Opportunity Mirror, are given on the page itself, under Extra Permissions, alongside the role. Core's own extra permissions (Find and Export, Bulk Update, Bulk Delete, Erase People, Duplicate Review, Metadata Admin) are given on the page itself, under Extra Permissions; see [Erase a person](erase-a-person.md) for who should have Erase People. Creating the user is the **Create a user in Setup** link on the page itself | No |

If the check cannot be read (for example, your Salesforce did not answer), the note shows the
instruction without Done or Not done yet.

A module's own settings page, reached from its section here, carries its notes in the same
form at the top of that page:

| Page | What to change in Setup | Checked by BarnCRM |
|---|---|---|
| Giving, Acknowledgments | Add and verify the shared From address (Setup, Organization-Wide Addresses) | No |
| Giving, Acknowledgments | Allow the org to send email (Setup, Deliverability, Access level: All email) | Yes |
| Giving, Acknowledgments | Write or change the thank you wording in an email template (Setup, Classic Email Templates, folder BarnCRM Acknowledgments) | No |
| Receipts | Assign **Gift Record Page** as the org default for Gift, and **Giving Contact Record Page** and **Giving Account Record Page** to the BarnCRM app (Setup, Lightning App Builder, Activation) | No |
| Receipts | Assign **Giving Staff**, **Giving Admin** or **Giving Read Only** on the **Access** page, under Extra Permissions | No |
| Giving, Campaign sync (BarnCRM Mirror) | **Campaign Sync** for you; **Marketing User** and Campaign create and edit for the people who create appeals | No |
| Giving, Opportunity mirror (BarnCRM Mirror) | **Opportunity Mirror** for you; Opportunity create and edit for fundraising staff, if each gift should get its Opportunity at once | No |
| Giving, Accounting export (Mirror) | **Accounting Export** with a Giving permission set that shows gifts, for the person who runs it | No |

## Common mistakes

- **Trying to change settings without the permission and thinking the page is broken.**
  If the controls are greyed out, read the notice at the top of the page. It names the
  exact permission to ask for: Manage BarnCRM Settings.
- **Editing values and leaving the page without saving.** The console does not save as you
  type. Changed settings are held until you click **Save**, and leaving the page discards
  them. If you are not sure whether a change went in, check **Recent Changes** on **General**.
- **Worrying that two people saving at once undo each other.** They do not. A save writes
  only the settings you changed, compared with what is stored at that moment, so a setting
  someone else saved after you opened the page is kept. If you both changed the same
  setting, the later save wins, and **Recent Changes** (on **General**) shows both, each with the value it
  replaced.
- **Wondering whether a nightly job or another page changed your settings.** A job saves only
  its own run details (when it ran and what it did), and a page such as Accounting Periods
  saves only its own setting. A setting that ships switched on (with Giving, for example,
  printing the logo on receipts) stays on until someone switches it off, even when a job was
  the first thing ever to save your settings.
- **Looking for a setting in Setup because it is not in the section you expected.** Use the
  search box before you go hunting. It searches the setting name, the description, and the
  section name, so `greeting`, `household`, or `pause` all find something.
- **Typing a value in the wrong format.** A date and time setting expects a date and time,
  and a number setting expects a number. If a value cannot be read, nothing on the page is
  saved and a message says which value to fix. Correct it and save again.
- **Typing a number outside its range.** Every number setting has a lowest and a highest
  value. Type a number outside them and the box says so, and Save saves nothing until you
  correct it. The server refuses such a value too, with a message naming the setting and
  its range, so the page never shows a value as saved that BarnCRM would not use.
- **Not finding a record in a picker.** The search box finds records you can see, by name.
  If the fund or appeal you want is missing, check that it exists and that you have access
  to it, then search again.
- **Expecting a settings change to fix records that already exist.** Changing a naming
  pattern changes what happens next. To apply it to households you already have, use the
  recompute action on the household naming settings.

## Fields behind this page, for report builders

Maria does not need these. They are here for someone building a report on settings
changes.

| What you see | Where it is stored |
|---|---|
| A setting's value | The settings record of the module that owns it, one field per setting. Core's is BarnCRM Settings; a module such as Giving brings its own. |
| A row in Recent Changes | Setting Change: setting name, old value, new value, changed by, changed at |
| The list of settings the console shows | Setting Definition, a package-shipped list that upgrades bring you |
| Which features are on | BarnCRM Settings, Features Turned On (a comma-separated list; `None` on a new install until first-run setup; `NoneChosen` when first-run setup was finished with every feature unticked; empty, on an org upgraded from before features existed, means all on) |
| Which modules are off | BarnCRM Settings, Modules Turned Off |
