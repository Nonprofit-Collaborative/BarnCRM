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

## A five-minute walkthrough

Start with the sample data loaded. Steps 1 to 6 are Maria. Step 7 is David.

1. Open the app launcher, type `BarnCRM`, and choose **BarnCRM**. The home page
   opens with the **Setup checklist**.
2. Click the **BarnCRM Settings** tab. The console opens with the section list on the
   left and the first section showing on the right. The sections are General, Organization,
   Households, Relationships, Addresses, Giving, Receipts, Rollups, Automation, Error Log,
   Access, Import, and Health. You only see the ones that have something in them: Giving and
   Receipts come with the Giving module, and Giving also adds the receipt details to the
   Organization section, so BarnCRM Core on its own shows fewer. General starts with
   **Edition**, shown read-only: it is chosen once in the Setup Assistant, and the
   **Change edition** link under it is the way to change it later (see
   [Editions](editions.md)).
3. Click in the **Search settings** box and type `greeting`. Results appear as you type. If
   the search cannot run, the box says so and asks you to try again, instead of saying nothing
   matches.
   Every setting whose name, description, or section mentions greeting is listed, which
   includes the household formal and informal greeting settings.
4. Click the result **Formal greeting pattern**. The console jumps to the Households
   section and to the **Preview and recompute** panel. The three household naming
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
6. Scroll to **Recent changes** at the bottom of the page. Your change is the first row,
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

## You never type an identifier

No setting asks you for a record ID, an API name or a developer name. Where a setting points
at something, you choose it:

- **A record**, such as the default fund or the default appeal with Giving, is chosen with a
  search box. Start typing the record's name and pick it from the list. The box shows the
  name; clearing it leaves the setting empty.
- **Record types**, such as which kinds of Opportunity become gifts with BarnCRM Connect, are
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
| General | To save Custom Metadata entries in an installed package: turn on **Deploy Metadata from Non-Certified Package Versions via Apex** (Setup, Apex Settings). The **BarnCRM Metadata Admin** permission it also needs is given on the Access page, under Extra permissions | No |
| Households | To review duplicates: keep the standard duplicate rules active (Setup, Duplicate Rules). The **BarnCRM Duplicate Review** permission is given on the Access page, under Extra permissions, to people with a Sales Cloud or Service Cloud license | No: the Duplicates panel shows each rule as On or Off |
| Rollups | Create the field a new rollup writes to before you build it (Setup, Object Manager, the object, Fields & Relationships) | No |
| Error Log | Allow the org to send email, or no digest is sent (Setup, Deliverability, Access level: All email) | Yes |
| Access | Assign a module's own permission set, such as Giving Staff, alongside the role (Setup, Users, Permission Set Assignments). Core's own extra permissions (Find and Export, Bulk Update, Bulk Delete, Erase People, Duplicate Review, Metadata Admin) are given on the page itself, under Extra permissions; see [Erase a person](erase-a-person.md) for who should have Erase People. Creating the user is the **Create a user in Setup** link on the page itself | No |

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
| Receipts | Assign **Giving Staff**, **Giving Admin** or **Giving Read Only** (Setup, Users, Permission Set Assignments) | No |
| Giving, Campaign sync (Connect) | **Campaign Sync** for you; **Marketing User** and Campaign create and edit for the people who create appeals | No |
| Giving, Opportunity mirror (Connect) | **Opportunity Mirror** for you; Opportunity create and edit for fundraising staff, if each gift should get its Opportunity at once | No |
| Giving, Accounting export (Connect) | **Accounting Export** with a Giving permission set that shows gifts, for the person who runs it | No |

## Common mistakes

- **Trying to change settings without the permission and thinking the page is broken.**
  If the controls are greyed out, read the notice at the top of the page. It names the
  exact permission to ask for: Manage BarnCRM Settings.
- **Editing values and leaving the page without saving.** The console does not save as you
  type. Changed settings are held until you click **Save**, and leaving the page discards
  them. If you are not sure whether a change went in, check **Recent changes**.
- **Worrying that two people saving at once undo each other.** They do not. A save writes
  only the settings you changed, compared with what is stored at that moment, so a setting
  someone else saved after you opened the page is kept. If you both changed the same
  setting, the later save wins, and **Recent changes** shows both, each with the value it
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
| A row in Recent changes | Setting Change: setting name, old value, new value, changed by, changed at |
| The list of settings the console shows | Setting Definition, a package-shipped list that upgrades bring you |
