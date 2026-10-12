# Open Impact Settings

## What it does

Open Impact Settings (called Nonprofit Settings before version 0.6) is the one page where
everything about how Open Impact behaves is changed: how households are named, which
automations run, who has access, and how this org fits alongside anything you already had.
Settings are grouped into sections on the left, every setting has a plain-language
description under it, and there is a search box for when you
remember the word but not the section.

You never need Salesforce Setup for a normal day. When something genuinely can only be
done in Setup, the setup checklist on the Hub home page sends you there with instructions.

## How to turn it on

There is nothing to turn on, but there is one permission to give out.

1. Open the **Open Impact** app and click the **Open Impact Settings** tab.
2. If you can change values, you already have the **Manage Open Impact Settings**
   permission. If you see a notice at the top of the page saying you can read but not
   change settings, you do not.
3. To give someone the permission, add them to the **Open Impact Admin** role on the Access
   page. That role carries Manage Open Impact Settings. Staff and read-only roles do not, on
   purpose: settings change how the whole org behaves.

Everyone can open the page and read it. That is deliberate: David should be able to see
how greetings are configured before he asks Maria to change them.

## A five-minute walkthrough

Start with the sample data loaded. Steps 1 to 6 are Maria. Step 7 is David.

1. Open the app launcher, type `Open Impact`, and choose **Open Impact**. The home page
   opens with the **Setup checklist**.
2. Click the **Open Impact Settings** tab. The console opens with the section list on the
   left and the first section showing on the right. The sections are General, Organization,
   Households, Relationships, Addresses, Giving, Receipts, Rollups, Automation, Error Log,
   Access, Import, and Health. You only see the ones that have something in them: Giving and
   Receipts come with the Giving module, and Giving also adds the receipt details to the
   Organization section, so Open Impact Core on its own shows fewer.
3. Click in the **Search settings** box and type `greeting`. Results appear as you type.
   Every setting whose name, description, or section mentions greeting is listed, which
   includes the household formal and informal greeting settings.
4. Click the result **Formal greeting pattern**. The console jumps to the Households
   section with that setting in view. Read the description under it and, if you want the
   longer explanation, click **Learn more** to open this admin guide at the household
   naming page.
5. Change the value. For example, put `{Salutation} {FirstName} {LastName}` in the formal
   greeting pattern, then click **Save**. A green confirmation appears saying your settings
   are saved. The new value is in effect immediately: the next contact you add gets the new
   greeting, with no waiting and no cache to clear.
6. Scroll to **Recent changes** at the bottom of the page. Your change is the first row,
   showing the setting, the old value, the new value, your name, and the time. Nothing is
   ever changed silently: one row is written per setting you actually changed, and saving a
   page without changing anything writes nothing.
7. Now sign in as David, who has the Fundraising Staff role and not Manage Open Impact
   Settings. He opens the same tab and sees the same sections and the same values, with a
   notice across the top: "You can read these settings but not change them. Ask your
   administrator for the Manage Open Impact Settings permission." Every control is greyed
   out and there is no Save button. He can still read every description and follow every
   Learn more link.

## Common mistakes

- **Trying to change settings without the permission and thinking the page is broken.**
  If the controls are greyed out, read the notice at the top of the page. It names the
  exact permission to ask for: Manage Open Impact Settings.
- **Editing values and leaving the page without saving.** The console does not save as you
  type. Changed settings are held until you click **Save**, and leaving the page discards
  them. If you are not sure whether a change went in, check **Recent changes**.
- **Looking for a setting in Setup because it is not in the section you expected.** Use the
  search box before you go hunting. It searches the setting name, the description, and the
  section name, so `greeting`, `household`, or `pause` all find something.
- **Typing a value in the wrong format.** A date and time setting expects a date and time,
  and a number setting expects a number. If a value cannot be read, nothing on the page is
  saved and a message says which value to fix. Correct it and save again.
- **Expecting a settings change to fix records that already exist.** Changing a naming
  pattern changes what happens next. To apply it to households you already have, use the
  recompute action on the household naming settings.

## Fields behind this page, for report builders

Maria does not need these. They are here for someone building a report on settings
changes.

| What you see | Where it is stored |
|---|---|
| A setting's value | The settings record of the module that owns it, one field per setting. Core's is Open Impact Settings; a module such as Giving brings its own. |
| A row in Recent changes | Setting Change: setting name, old value, new value, changed by, changed at |
| The list of settings the console shows | Setting Definition, a package-shipped list that upgrades bring you |
