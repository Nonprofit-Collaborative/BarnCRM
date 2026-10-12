# The Open Impact app

## What it does

The Open Impact app is the app you work in every day, whatever kind of organization you are.
Before version 0.6 it was called the Nonprofit Hub. It gives you one home page that tells
you what to do next, a setup checklist that remembers how far you got, and a short list of
the places you go most: your households, your people, your organizations, and your
settings.

If you have ever installed something in Salesforce and then wondered where to start, this
is the answer to that question. You start here.

## How to turn it on

There is nothing to turn on. The app is installed with Open Impact Core. The Giving module
adds its own app, **Fundraising**, for entering gifts and reading the giving numbers; the
home page lists it under **Modules** once Giving is installed.

1. Click the app launcher (the grid of dots at the top left of Salesforce).
2. Type `Open Impact` and choose **Open Impact**.
3. Click the star next to the app name if you want it to open by default.

Everyone who has been given an Open Impact role can open the Hub. Two things on the home
page are for administrators only:

- The **Errors to review** tile counts only errors you are allowed to see, and the Error
  Log tab itself is on the administrator role.
- The **Setup checklist** can be read by anyone, but only a person with the **Manage
  Open Impact Settings** permission can finish a step or change a setting.

## A five-minute walkthrough

Maria has just installed Open Impact and has the sample data loaded.

1. Open the app launcher, type `Open Impact`, and choose **Open Impact**. The home page
   opens with the heading **Welcome to Open Impact**.
2. Read the **Setup checklist**. It opens on the first of eight steps you have not
   finished, with one sentence saying what that step is for and the count of how far you
   have got, for example "3 of 8" (seven steps with Core alone, eight with Giving). The steps are guided: each one is done here, on the home
   page, not somewhere else.
3. The first step, **Confirm how Open Impact fits your existing org**, says what it found in
   your org. If your org uses Person Accounts, as Nonprofit Cloud orgs do, it says so
   plainly, recommends Agentforce Nonprofit coexistence, and household membership uses the
   junction model so that what you already have keeps working. Click **Confirm and
   continue**.
4. Use **Next**, **Back**, and **Skip for now** to move around. Skipping does not mark a
   step done: it moves the step out of the way and offers it to you again next time. The
   full walkthrough of every step is in [setup-assistant.md](setup-assistant.md).
5. Look at the **Errors to review** tile. On a fresh org it says `0`. If it ever shows a
   number, click **Open the Error Log** and read the plain-language message on each row.
6. If someone has paused automation (for example during a large import), a banner sits
   above the checklist saying Open Impact automation is paused. It disappears by itself
   when the pause expires.
7. Use **Quick links** to open Households, Organizations, or Open Impact Settings without
   going back to the app launcher.

That is the whole home page. Five minutes, and you know what is done, what is next, and
whether anything went wrong.

## Common mistakes

- **Looking for the app in Setup.** Open Impact is an app, not a Setup page. Use the app
  launcher, not the gear icon. If `Open Impact` does not appear in the app launcher, you
  have not been assigned an Open Impact role: ask whoever installed the package to add you
  on the Access page.
- **Treating Skip for now as done.** Skipping moves you on without finishing the step, on
  purpose, so that a step waiting for a module you have not installed does not block you. A
  skipped step is still waiting for you next time.
- **Reading the checklist as a one-time task.** When every step is done the checklist
  collapses to a small **Setup complete** tile with a **Reopen setup** button. Re-run it
  whenever your organization changes: a new fiscal year, a new staff member, a new address.
- **Assuming an empty Errors tile means nothing failed.** The tile counts errors with the
  status **New**. If someone has already marked an error Acknowledged or Resolved, it
  stops counting. Open the Error Log tab to see everything.
