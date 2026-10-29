# BarnCRM Settings

## What It Does

BarnCRM Settings is the one page where
everything about how BarnCRM behaves is changed: how households are named, which
automations run, who has access, and how this org fits alongside anything you already had.
Settings are grouped into sections on the left, and on each section's page into boxes, each
with its own heading (see "Sections and their boxes" below). The section list is grouped under
short headings (Organization, People, Data, Fundraising, Programs, System), and each section
has its own icon. Every setting has a plain-language description: click the info icon under
the setting to read it, and **Learn More** beside the icon opens this guide's page for it in a
new tab. There is a search box for when you remember the word but not the section.

Every setting applies to the whole organization, never to one person.

You never need Salesforce Setup for a normal day. When something genuinely can only be
done in Setup, the setup checklist on the Hub home page sends you there with instructions,
and the section of this page that depends on it says so at the top (see "When a section
needs a change in Setup" below).

No module has a settings tab of its own: a module's settings are a section of this page, for
example **Rollups** and **Volunteers**. The **Rollups** section holds **Default rollup
mode**, **When instant totals are calculated** and **Time of the nightly run**. Saving a new
**Time of the nightly run** moves the scheduled nightly rollup run at once (see
[Rollups](rollups.md#how-the-nightly-run-works)).

The footer of the page has a **Report a Problem or Give Feedback** link. It opens the
BarnCRM support page on GitHub in a new tab.

## How to Turn It On

There is nothing to turn on, but there is one permission to give out.

1. Open the **BarnCRM Admin** app and click the **BarnCRM Settings** tab.
2. If you can change values, you already have the **Manage BarnCRM Settings**
   permission. If you see a notice at the top of the page saying you can read but not
   change settings, you do not.
3. To give someone the permission, add them to the **BarnCRM Admin** role on the Access
   page. That role carries Manage BarnCRM Settings. Staff and read-only roles do not, on
   purpose: settings change how the whole org behaves.

Everyone can open the page and read it. That is deliberate: David should be able to see
how greetings are configured before he asks Maria to change them.

## First-Run Setup

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
feature that is off has a **Turn On** button, which asks you to confirm before it does
anything; a feature that is on just says **On**. Only people with Manage BarnCRM Settings see
the Turn on buttons.

While a feature is off its tabs are hidden for everyone, its rows in this page are hidden (a
section left empty disappears), and its automations do not run. Turning it on shows its tabs
to the people who should see them, shows its settings, and starts its automations.

| Feature | What it covers | Hidden or stopped while off |
|---|---|---|
| Data Manager | Data Manager, Import, Find and Bulk Update | Those four tabs and the Import section |
| Duplicate Matching | Duplicate suggestions, review and matching logic | The Duplicate Matching tab and the Duplicate Matching section |
| Org Optimizer and Health Check | The Org Optimizer tab and Health Check | The Org Optimizer tab, the Health section and the Org Optimizer section (its three thresholds) |
| Household upkeep | Creating, naming and tidying households | Its three automations and the household naming and tidy-up rows |
| Addresses | Address capture and the primary address | Its three automations and the Addresses section |
| Relationships | Keeping both sides of a relationship in step | Its automation and the Relationships box on People and Households |
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
Export for Find, Data Manager and Org Optimizer, Bulk Update or Bulk Delete for Bulk Update and
Data Manager). BarnCRM keeps these in step when a feature is turned on, when a role or extra
permission is given or removed on the Access page, after every upgrade, and every night (for
roles given in Setup or by user access policies). A large org may take a few minutes to catch
up. Do not assign the BarnCRM Tab permission sets by hand: the nightly run removes them from
anyone who should not have them.

The Households tab works the same way. **Household Upkeep** carries the **BarnCRM Households**
permission set, which shows the Households tab and nothing else (it gives no record type). Once
the feature is on, BarnCRM gives it to everyone with a BarnCRM Admin, Staff or Read Only role.

## Modules

Modules are separate packages, not installed with Core. The **Modules** section lists the
modules your edition offers (see [Editions](editions.md)), plus any module already installed:

- A module that is not installed shows **Not installed** with **Install**, which opens
  Salesforce's installer, and **What this module does**.
- An installed module shows **Installed** and a link to its own app, where it has one.
  No module app has a Settings tab: the Rollup Builder's settings are in the **Rollups**
  section and Volunteers' in the **Volunteers** section of BarnCRM Settings; Giving's Fundraising app has no Settings tab, and Mirror has no app. (Some module
  sections still show in BarnCRM Settings for now; they move to the module's app in a later
  release.)

The modules are BarnCRM Rollup Builder (both editions), and BarnCRM Giving, BarnCRM
Volunteers, BarnCRM Programs, BarnCRM Funders and BarnCRM Mirror (Nonprofit Edition). The
Standard Edition lists no Nonprofit Edition module that is not installed. BarnCRM Rollup
Builder ships as its own package, installed from this section like the others. See the
[Module Manager](module-manager.md) for what else you can do with an installed module.

## A Five-Minute Walkthrough

Start with the sample data loaded. Steps 1 to 6 are Maria. Step 7 is David.

1. Open the app launcher, type `BarnCRM`, and choose **BarnCRM Admin** (or **BarnCRM Admin
   Console**). It opens on the **BarnCRM Settings** tab.
2. The console opens with the section list on the
   left and the first section showing on the right. The page name shows once, in the page
   header. The sections are listed in groups: **Organization** (General, Organization),
   **People** (People and Households, Addresses), **Data** (Import, Duplicate Matching, Org
   Optimizer), **Fundraising** (Giving, Receipts, Rollups), **Programs** (Volunteers) and
   **System** (Modules, Access, Automation, Integrations, Health, Error Log). A section a
   module adds that is not in these groups is listed under **More**, before System, so Error
   Log is always last. Each section's settings sit in bordered boxes with a heading, such as **People** and
   **Households** on People and Households. You only see
   the ones that have something in them, and a feature that is off hides its sections: Giving and
   Receipts come with the Giving module, and Giving also adds the receipt details to the
   Organization section, so BarnCRM Core on its own shows fewer. General starts with
   **Edition**, shown read-only: it is chosen once in first-run setup, and the
   **Change Edition** link under it is the way to change it later (see
   [Editions](editions.md)).
3. Click in the **Search settings** box and type `greeting`. Results appear as you type. If
   the search cannot run, the box says so and asks you to try again, instead of saying nothing
   matches.
   Every setting whose name, description, or section mentions greeting is listed, which
   includes the household formal and informal greeting settings.
4. Click the result **Formal greeting pattern**. The console jumps to the People and
   Households section and to the **Preview and Recompute** panel, in the **Household Names
   and Greetings** box. The three household naming
   patterns (household name, formal greeting, informal greeting) are edited only in that
   panel, not as separate rows, so the panel is where the search result takes you. The
   panel's own text explains the patterns; the household naming page of this admin guide
   gives the longer explanation.
5. Change the value in the panel. For example, put `{Salutation} {FirstName} {LastName}` in
   the formal greeting pattern, watch the preview update, then click the panel's **Save**.
   A confirmation appears saying the patterns are saved. The new value is in effect
   immediately: the next contact you add gets the new greeting, with no waiting and no
   cache to clear. The settings console's own save bar is for the other settings in
   the section, such as whether people who have died stay in the household name (see
   "Saving Your Changes" below).
6. Open the **General** section and scroll to **Recent Changes** at the bottom of the page.
   It shows on **General** only, whichever section the change was made in. Your change is the first row,
   showing the setting by the name you see on this page, the old value, the new value, your
   name, and the time. A setting with a list of choices shows each value as the choice reads
   on this page (the edition, for example, reads "Nonprofit Edition"), and a setting that holds
  one record, such as the default fund, shows the record's name. If that record has been deleted
  or you cannot open it, the stored Id shows instead. Nothing is ever changed silently: one row is written per setting you
   actually changed, and saving a page without changing anything writes nothing. Ticking or
   skipping a step in the setup checklist is not a settings change, so it is not listed.
7. Now sign in as David, who has the Team Member role and not Manage BarnCRM
   Settings. He opens the same tab and sees the same sections and the same values, with a
   notice across the top: "You can read these settings but not change them. Ask your
   administrator for the Manage BarnCRM Settings permission." Every control is greyed
   out and no save bar appears. He can still open every description from its info icon and
   follow every Learn More link.

## Saving Your Changes

Changes are not saved as you make them. As soon as you change a setting, a bar docks to the
bottom of the screen saying how many changes are not saved yet, with **Discard** and
**Save**. **Save** saves every changed setting, including changes made in another section
before you moved on; **Discard** puts them all back. The bar goes away once nothing is
unsaved. While anything is unsaved, closing or reloading the browser tab asks you first;
moving to another tab inside Salesforce does not ask, so save before you leave the page.

Panels with their own **Save** button (such as household naming or the organization address)
save on their own and do not count in the bar. The **Integrations** section has nothing to
save, so it has no save bar.

## Sections and Their Boxes

Each section's page groups its settings into boxes. A box shows only when it has a setting
to show, and a setting added later that no box names goes in the box marked "(the rest)"
below, so nothing is ever hidden by the grouping. A section not listed here, such as Modules,
Duplicate Matching, Automation, Access, Integrations or Health, shows one box headed with the
section's name.

| Section | Boxes, in order |
|---|---|
| General | Edition and Features; Preferences (the rest); Tools |
| Organization | Organization Details (the rest); Organization Address; Receipt Logo and Signature |
| People and Households | People; Households (the rest); Household Names and Greetings; Relationships |
| Addresses | Address Updates (the rest); Address Card; Seasonal Addresses |
| Giving | Gift Defaults (the rest); Commitments and Installments; Donor Levels; Acknowledgments and Stewardship; Nightly Jobs and Accounting Periods; BarnCRM Mirror |
| Receipts | Receipt Details (the rest); Receipt Printing; Receipt Letters and Year End Statements |
| Rollups | Rollup Processing (the rest); Rollup Builder |
| Volunteers | Hours and Shifts |
| Error Log | Error Digest (the rest); Error Log Retention |
| Import | Importing (the rest); Gift Matching on Import; Find, Bulk Update and Bulk Delete |

### People and Households

People and Households is one section for the settings that used to be on two, Households and
Relationships. No setting changed: each keeps its value, its default and its name. Duplicates
are not here: they have their own **Duplicate Matching** section, right after this one.

| Box | Settings |
|---|---|
| People | How people belong to a household; Create a household automatically |
| Households | Delete a household once it is empty; Keep the households of deleted people |
| Household Names and Greetings | The **Preview and Recompute** naming panel (the three patterns); Include people who have died in names |
| Relationships | Keep both sides of relationships in step |

A link that opens the old **Households** or **Relationships** section, such as a bookmark, a
job notification or a Health Check fix, opens People and Households scrolled to the
**Households** or **Relationships** box. The Setup Assistant's naming step opens the
**Household Names and Greetings** box, and Health Check's fix for people hidden from their
households opens the **People** box.

## Your Organization's Address

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

### Record Type for Organizations

**General** always shows **Record type for organizations**, whether or not Household Upkeep is
on, because import, addresses and Giving use organizations either way. Accounts of the record
type chosen here are your organizations: they appear on the **Organizations** tab, get the
organization parts of the record page, are matched as organizations by import, and an import
creates new organizations with it. Choose **No record type** when your org has no Account
record types; then every account without one is an organization.

BarnCRM never adds an Organization record type. On install it picks one you already have and
saves it, so the row is never blank:

1. A record type your accounts already use comes first.
2. Among those (or among all, when none is used), **Organization**, then **Business
   Account**, then **Business**, then **Default**, by the name in Setup; otherwise the first
   by name.
3. A household or person account record type is never offered or picked.
4. With none left, **No record type**.

Change it if the guess is wrong. Saving a person account record type or one named Household
is refused. Accounts already saved keep their record type; only which accounts count as
organizations changes.

## You Never Type an Identifier

No setting asks you for a record ID, an API name or a developer name. Where a setting points
at something, you choose it:

- **A record**, such as the default fund or the default appeal with Giving, is chosen with a
  search box. Start typing the record's name and pick it from the list. The box shows the
  name; clearing it leaves the setting empty.
- **Record types**, such as which kinds of Opportunity become gifts with BarnCRM Mirror, are
  a list of checkboxes, one per active record type in your org, by the name you see in Setup.
  Ticking none means every record type.
- **One record type**, such as **Record type for organizations**, is a dropdown of your active
  record types by the name you see in Setup, plus **No record type**.
- **A choice from a fixed list**, such as **Coexistence mode**, is a dropdown.

Every setting shows its default until you change it. A dropdown, a number or a text setting
that has not been saved yet shows the value BarnCRM is already using (for example **Default
rollup mode** shows **Both (recommended)** on a new org, and **Household name pattern** shows
the shipped pattern), not an empty box. Opening the page saves nothing. **Coexistence mode**
shows the mode BarnCRM detects as right for your org, and stays unconfirmed until you choose
one and save. Settings that point at a record (such as a default fund), a list of record
types, or a date have no default to show and stay empty until you choose.

A setting showing a default nobody has saved carries a **Default** badge under it. When a
section has any such setting, a banner at the top of the section says **These Are Defaults**
and that you can keep them all or change any. **Keep All Defaults** in that banner saves every
default the section shows at once, in one save, each exactly as shown and each with its own
**Recent Changes** row. It skips any setting you have already changed on the page and any
setting with no button (see below). To keep just one, click **Keep This Setting** beside its
badge: it saves exactly the
value shown, as if you had chosen it yourself, with the same permission, checks and **Recent
Changes** row, and anything choosing it by hand sets off (keeping **Coexistence mode**, for
example, confirms that mode and completes its Setup Assistant step). Changes you have not saved
yet stay on the page. A setting already saved shows no badge, and people without Manage
BarnCRM Settings see the badge and the banner but no buttons. **How people belong to a household** has no button when
BarnCRM would choose differently for your org (with Person Accounts or Nonprofit Cloud it
moves a household choice nobody made to the flexible way): the badge stays, and you choose the
way you want from the list and save.

Each setting's info icon is a button: a screen reader names it with the setting and reads the
description when it is opened, and each setting is a labelled group, so the Learn More link
beside it is read with the setting's name.

## Values That Come From Setup

A few things BarnCRM needs are already held by Salesforce Setup. BarnCRM shows them on this
page, read only, and keeps no copy that could drift from Setup. Under each one, **Open in
Setup** opens the Setup page that changes it in a new tab; after you change it there, reload
this page to see the new value.

| Section | Shown | Open in Setup opens |
|---|---|---|
| General | **Fiscal year start month**: the month your fiscal year starts. Totals for this year, last year and two years ago, and every report by fiscal year, follow it. After changing it, click **Recalculate all** on the Rollups page | Company Settings, Fiscal Year |
| Organization | **Organization name**, at the top of the section, directly above **Organization legal name** | Company Settings, Company Information |

BarnCRM follows the standard fiscal year: each year starts on the first day of the start month.
If your org uses a custom fiscal year, Health Check says so, because reports then follow your
custom periods while BarnCRM totals stay in whole years (see
[Health Check](health-check.md#what-health-check-looks-at)).

## When a Section Needs a Change in Setup

BarnCRM avoids Salesforce Setup wherever it can. A few features still depend on something only
Setup can change, usually because Salesforce keeps that switch for itself. When a section has
one, a short note at the top of the section says, before any setting:

- **what** to change in Setup, in one line under the heading **Needs a Change in Setup**,
- an **Open in Setup** button that opens that Setup page in a new tab, so this page stays open,
- **Show Steps**, which opens **why** BarnCRM needs it, in one sentence, and the **steps**, 2
  to 4 numbered clicks once you are on the Setup page. The steps start closed so the
  settings stay near the top.

Where BarnCRM can read the answer without any extra permission, the note also says whether it
is already done: **Done** with a green tick, or **Not done yet** with a warning icon, and a
**Check Again** button reads it again once you have made the change. Otherwise the note is an
instruction only, and it stays there after you make the change, because BarnCRM cannot tell.
Nothing on the note changes your org: you make the change in Setup yourself.

Salesforce has no stable link to a single object, permission set or Lightning page, so for
those the button opens the list and the first step says which one to click.

| Section | What to change in Setup | Open in Setup opens | Checked by BarnCRM |
|---|---|---|---|
| General | To save Custom Metadata entries in an installed package: turn on **Deploy Metadata from Non-Certified Package Versions via Apex**. The **BarnCRM Metadata Admin** permission it also needs is given on the Access page, under Extra Permissions | Apex Settings | No |
| Duplicate Matching | To review duplicates: keep the standard duplicate rules active. The **BarnCRM Duplicate Review** permission is given on the Access page, under Extra Permissions, to people with a Sales Cloud or Service Cloud license | Duplicate Rules | No: the Duplicates panel shows each rule as On or Off |
| Rollups | Create the field a new rollup writes to before you build it | Object Manager (click the object, then Fields & Relationships, New) | No |
| Error Log | Allow the org to send email, or no digest is sent (Access level: All email) | Deliverability | Yes, with Check Again |
| Access | Assign a module permission set this page does not list under Extra Permissions. Giving and Mirror permission sets, such as Giving Staff or Opportunity Mirror, and Core's own extra permissions (Find and Export, Bulk Update, Bulk Delete, Erase People, Duplicate Review, Metadata Admin) are given on the page itself; see [Erase a person](erase-a-person.md) for who should have Erase People. Creating the user is the **Create a User in Setup** link on the page itself | Permission Sets (click the set, then Manage Assignments) | No |

If the check cannot be read (for example, your Salesforce did not answer), the note shows the
instruction without Done or Not done yet.

A module's own settings page, reached from its section here, carries its notes in the same
form at the top of that page:

| Page | What to change in Setup | Open in Setup opens | Checked by BarnCRM |
|---|---|---|---|
| Giving, Acknowledgments | Add and verify the shared From address | Organization-Wide Addresses | No |
| Giving, Acknowledgments | Allow the org to send email (Access level: All email) | Deliverability | Yes, with Check Again |
| Giving, Acknowledgments | Write or change the thank you wording in an email template, folder BarnCRM Acknowledgments | Classic Email Templates | No |
| Receipts | Assign **Gift Record Page** as the org default for Gift, and **Giving Contact Record Page** and **Giving Account Record Page** to the BarnCRM app | Lightning App Builder (click Edit next to the page, then Activation) | No |
| Giving, Campaign Sync (BarnCRM Mirror) | Campaign create and edit for the people who create appeals | Permission Sets (click the set, then Object Settings, Campaigns) | No |
| Giving, Campaign Sync (BarnCRM Mirror) | **Marketing User** ticked on the user of each person who creates appeals | Users | No |
| Giving, Opportunity Mirror (BarnCRM Mirror) | Opportunity create and edit for fundraising staff, if each gift should get its Opportunity at once | Permission Sets (click the set, then Object Settings, Opportunities) | No |

Giving Staff, Giving Admin and Giving Read Only, and Mirror's Campaign Sync, Opportunity Mirror
and Accounting Export, are given on the **Access** page, under Extra Permissions, so they need
no note. Accounting Export has no Setup note.

## Common Mistakes

- **Trying to change settings without the permission and thinking the page is broken.**
  If the controls are greyed out, read the notice at the top of the page. It names the
  exact permission to ask for: Manage BarnCRM Settings.
- **Editing values and leaving the page without saving.** The console does not save as you
  type. Changed settings are held until you click **Save** in the bar docked at the bottom of
  the screen, which counts them, and leaving the page discards them. If you are not sure whether a change went in, check **Recent Changes** on **General**.
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

## Fields Behind This Page, for Report Builders

Maria does not need these. They are here for someone building a report on settings
changes.

| What you see | Where it is stored |
|---|---|
| A setting's value | The settings record of the module that owns it, one field per setting. Core's is BarnCRM Settings; a module such as Giving brings its own. |
| A row in Recent Changes | Setting Change: setting name, old value, new value, changed by, changed at |
| The list of settings the console shows | Setting Definition, a package-shipped list that upgrades bring you |
| Which features are on | BarnCRM Settings, Features Turned On (a comma-separated list; `None` on a new install until first-run setup; `NoneChosen` when first-run setup was finished with every feature unticked; empty, on an org upgraded from before features existed, means all on) |
| Which modules are off | BarnCRM Settings, Modules Turned Off |
