# The BarnCRM app

## What it does

The BarnCRM app is the app you work in every day, whatever kind of organization you are.
It gives you one home page that tells
you what to do next, a setup checklist that remembers how far you got, and a short list of
the places you go most: your households, your people, your organizations, and your
settings.

If you have ever installed something in Salesforce and then wondered where to start, this
is the answer to that question. You start here.

## How to turn it on

There is nothing to turn on. The app is installed with BarnCRM Core. A module can add its
own app, and the home page lists it under **Modules** once that module is installed (with
Giving, that is the **Fundraising** app).

1. Click the app launcher (the grid of dots at the top left of Salesforce).
2. Type `BarnCRM` and choose **BarnCRM**.
3. Click the star next to the app name if you want it to open by default.

Everyone who has been given a BarnCRM role can open the app. The home page shows each
person what they can act on:

| Part of the home page | Who sees it |
|---|---|
| **What's new in BarnCRM**: what changed in the latest release, until you click **Dismiss** | Everyone, each person once per release |
| **Welcome to BarnCRM**, the **New household** button, and the paused automation banner | Everyone |
| **Setup checklist** (or the **Setup complete** tile once it is finished) | Administrators |
| **Health Check** | Administrators |
| **Errors to review** | Administrators |
| **Rollups last completed** | Administrators |
| **Seasonal addresses last swapped** | Administrators |
| **Modules** | Administrators |
| **Files that arrive regularly** | Anyone who can read import templates, and only when a file is marked as arriving regularly |
| **Quick links** | Everyone |

"Administrators" means anyone with the **Manage BarnCRM Settings** permission, which the
**BarnCRM Admin** role carries. Staff without it see a shorter page: the welcome, the
**New household** button, and the quick links. They are not shown a checklist they cannot
finish or an error count for a log they cannot open. The page does not work those numbers
out for staff at all, so it loads faster for them; if you edit the page to show an
administrator tile to staff, it shows nothing to count.

## A five-minute walkthrough

Maria has just installed BarnCRM and has the sample data loaded. She has the BarnCRM
Admin role.

1. Open the app launcher, type `BarnCRM`, and choose **BarnCRM**. The home page
   opens with the heading **Welcome to BarnCRM** and the sentence "Start with the setup
   checklist below."
2. Read the **Setup checklist**. It opens on the first step you have not finished, with
   one sentence saying what that step is for and the count of how far you have got, for
   example "3 of 8" (eight steps with Core alone, nine with Giving). The steps are guided:
   each one is done here, on the home page, not somewhere else.
3. The first step, **Choose your edition**, asks whether you want the Community Suite or
   the Nonprofit Edition. Choose **Community Suite** and click **Confirm and continue**.
4. The next step, **Confirm how BarnCRM fits your existing org**, says what it found in
   your org and recommends a fit. On a fresh org it says "This looks like a fresh org, with
   no other household model and no Person Accounts. BarnCRM can run on its own." and
   recommends **Standalone**. If your org uses Person Accounts, it says so plainly, and
   household membership uses one record per person so that what you already have keeps
   working. Click **Confirm and continue**.
5. Use **Next**, **Back**, and **Skip for now** to move around. Skipping does not mark a
   step done: it moves the step out of the way and offers it to you again next time. The
   full walkthrough of every step is in [setup-assistant.md](setup-assistant.md).
6. Below the checklist, the **Health Check** lists anything BarnCRM found in your org that
   needs attention, with a button to fix it where it can. The full guide is
   [health-check.md](health-check.md).
7. Look at the **Errors to review** tile. On a fresh org it says `0`. If it ever shows a
   number, click **Open the Error Log** and read the plain-language message on each row.
   The tile counts up to 999; past that it says `999+`, so a flooded Error Log never slows
   the home page down.
8. Look at **Rollups last completed** and **Seasonal addresses last swapped**. Each says
   when that nightly job last finished. If one is more than 36 hours late, the tile says so
   in words, next to a warning icon, and its link opens the settings page where you can run
   it.
9. If someone has paused automation (for example during a large import), a banner under
   the welcome says BarnCRM automation is paused. It disappears by itself when the pause
   expires.
10. Look at **Modules**. It lists BarnCRM Core and each module installed in your org (with
    Giving, that is Giving), and says for each whether it is on or installed and off. Click
    **Open the Module Manager** to turn a module on or off.
11. Use **Quick links** to open Households, Organizations, or BarnCRM Settings without
    going back to the app launcher.

That is the whole home page. Five minutes, and you know what is done, what is next, and
whether anything went wrong.

When every step is done, the checklist collapses to a small **Setup complete** tile, and
the welcome sentence points at the tabs instead of the checklist.

## Rearranging the home page

The home page is a standard Lightning page, and each tile on it is its own component, so
you can move, remove, or add tiles in the Lightning App Builder without any code.

1. Open the home page, click the gear icon, then **Edit Page**.
2. Drag a tile to another region, or select it and click the delete icon to remove it.
   The BarnCRM tiles are listed under **Custom** with names that start with
   **BarnCRM Home**, plus **Health Check**.
3. To add something of your own, drag in a standard component: **List View** (for example
   your households), **Report Chart**, or **Rich Text** for a note to your team.
4. To show a tile only to some people, select it and use **Set Component Visibility**. The
   administrator tiles use the filter **Permissions, Custom Permission, Manage BarnCRM
   Settings, equals true**. Use the same filter to hide your own tiles from staff.
5. Click **Save**. If the App Builder says the page cannot be edited because it came with
   the package, click **Save As** to make your own copy, then **Activation** to make the
   copy the home page of the BarnCRM app.

A copy you made does not receive changes from later BarnCRM versions. After an upgrade,
compare it with the page that came with the package.

## Common mistakes

- **Looking for the app in Setup.** BarnCRM is an app, not a Setup page. Use the app
  launcher, not the gear icon. If `BarnCRM` does not appear in the app launcher, you
  have not been assigned a BarnCRM role: ask whoever installed the package to add you
  on the Access page.
- **Wondering where the checklist went for a staff member.** The checklist, the Health
  Check and the status tiles show only to people with the Manage BarnCRM Settings
  permission. A staff member sees the welcome and the quick links, on purpose.
- **Treating Skip for now as done.** Skipping moves you on without finishing the step, on
  purpose, so that a step waiting for a module you have not installed does not block you. A
  skipped step is still waiting for you next time.
- **Reading the checklist as a one-time task.** When every step is done the checklist
  collapses to a small **Setup complete** tile with a **Reopen setup** button. Re-run it
  whenever your organization changes: a new fiscal year, a new staff member, a new address.
- **Assuming an empty Errors tile means nothing failed.** The tile counts errors with the
  status **New**. If someone has already marked an error Acknowledged or Resolved, it
  stops counting. Open the Error Log tab to see everything.
