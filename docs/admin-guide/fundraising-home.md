# Fundraising Home

## What It Does

**Fundraising Home** is the first tab of the **BarnCRM Fundraising** app. It answers "what needs
me today" in one look, so a fundraiser no longer starts on a menu of twenty tabs:

- Five figures, each a link to the list behind it:
  - **Gifts** with **To acknowledge**: received gifts waiting for a thank you. Opens the
    **Thank-Yous** page.
  - **Installments** with **Overdue**: pledge payments past due. Opens the Installments list
    view **Overdue**.
  - **My Asks Due This Month**: your own open asks whose Target Date falls this month. Opens the
    Asks list view of the same name.
  - **Gift Batches** with **Open**: batches still being keyed. Opens the list view **Open
    Batches**.
  - **Stewardship Plans** with **Running**: plans still under way. Opens the list view
    **Running Plans**.
- **Enter a Gift**, which opens Quick Gift Entry.
- **Fundraising Setup**: a tile for each setup page that left the app's menu (**Donor Level
  Ladder**, **Stewardship Plan Setup**, **Pledge Reminders**, **Receipt Letters**). All four
  are also tabs in **BarnCRM Admin** and **BarnCRM Admin Console**, before **Error Log**.
- Two report charts: **Giving by Month** and **Open Asks by Stage**.

Each figure's name is the object's own label and its status word is the picklist value's label,
so a renamed object or status shows its new name here with nothing else to change. The asks
figure is named by its list view. A badge turns to its color only when its count is above zero.
A figure counts at most 2,000 records and shows "2,000+" past that.

Each figure, tile and button shows only to someone who can read the records behind it:
**Enter a Gift** needs create access to gifts, the **Donor Level Ladder** and **Stewardship
Plan Setup** tiles need the **Manage BarnCRM Settings** permission, and the other two setup
tiles need read access to pledge reminders or receipt runs.

## How to Turn It On

Nothing to turn on. The page and its tab come with the Giving module, and the **Giving Admin**,
**Giving Staff** and **Giving Read Only** permission sets show the tab.

## What Changed in the App's Menu

The app's navigation now opens on **Fundraising Home** and adds **Installments** after
**Commitments**. Four setup pages left the default menu: **Donor Level Ladder**, **Stewardship
Plan Setup**, **Pledge Reminders** and **Receipt Letters**. Nothing was removed: each is a tile
under **Fundraising Setup** on Fundraising Home, is still in the App Launcher, and the first two
are also in the BarnCRM Admin apps. Anyone can add one back to their own menu with the pencil
icon at the end of the navigation bar.

## The Charts

The charts are standard Salesforce report charts placed on the page, drawn by Salesforce in its
own colors, theme and dark mode. They read packaged reports in the **BarnCRM Giving** report
folder:

- **Giving by Month**: received gifts in each of the last twelve months (the same report the
  Giving dashboard uses).
- **Open Asks by Stage**: open asks by stage, with the amount asked. It uses the **Asks** report
  type, which ships with the module.

A chart shows to anyone who may run reports and read the records. It refreshes about once a day,
or at once with its refresh button. Every report reads BarnCRM's own objects only.

The BarnCRM home page also carries an admin-only chart, **Errors by Day**, from the **BarnCRM
Admin** report folder: the Error Log entries of severity Error or Critical in the last 30 days.

## Changing the Page

The page is an ordinary Lightning page. In the App Builder an administrator can move the
charts, remove one, or add another report chart (Edit Page, then drag **Report Chart** onto a
region and pick a report). The figures and setup tiles are one component, **Fundraising Home**.

## A Five-Minute Walkthrough

1. Open **BarnCRM Fundraising**. It opens on **Fundraising Home**.
2. Read the five figures. Click **Installments** with **Overdue**: the Overdue list view opens.
3. Go back and click **Enter a Gift**: Quick Gift Entry opens.
4. As an administrator, open **Donor Level Ladder** from **Fundraising Setup**.
5. Scroll to the charts and click one to open its report.

## Common Mistakes

- **Expecting the setup pages in the menu.** They are tiles under **Fundraising Setup** now.
- **A chart says it has no data.** The person may lack the Run Reports permission or read access
  to the records; the Giving permission sets give the second, a profile or role gives the first.

## What This Does Not Do Yet

- The figures do not refresh on their own; reload the page.
