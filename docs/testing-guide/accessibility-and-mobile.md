# Accessibility and Mobile

Scripts for quick manual checks of keyboard use, screen reader labels, dialog focus, zoom and the Salesforce mobile app. Setup detail: [Record pages](../admin-guide/record-pages.md) and [BarnCRM Settings](../admin-guide/barncrm-settings.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Giving deployed and sample data loaded unless a script says otherwise. Use a desktop browser (Chrome or Edge) at 100 percent zoom for keyboard scripts, and keep the mouse out of reach. The full device checklist for phones is the [Mobile audit](../contributor-guide/scale-and-mobile-test-plan.md#mobile-audit) in the scale and mobile test plan; T-A11Y-09 is the short version.

## T-A11Y-01: Keyboard Only in BarnCRM Settings

**Purpose:** Confirm an admin can search, move between sections and change a setting without a mouse, and that **Discard Changes** undoes it.
**Prerequisites:** admin user (see [Test users](before-you-test.md#test-users)); first-run setup already finished.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **BarnCRM Admin** app and the **BarnCRM Settings** tab. Press Tab until focus reaches the page content. | A visible focus ring sits on the **Search settings** box. |
| 2 | Type `greeting`. | A **Search Results** list appears under the box as you type. |
| 3 | Press Tab until focus is on the result **Formal greeting pattern**, then press Enter. | The **People and Households** section opens on the right, the page scrolls to the **Preview and Recompute** panel and focus is on its heading. |
| 4 | Press Shift+Tab until focus is in the **Sections** list, then press Tab or Shift+Tab to reach **General** and press Enter. | The General section shows. Every section in the list can be reached with Tab and opened with Enter. |
| 5 | Open **Households** again with the keyboard. Tab to the checkbox **Create a household automatically** and press Space. | The checkbox changes state. **Save** and **Discard Changes** become enabled. |
| 6 | Tab to **Discard Changes** and press Enter. | The checkbox returns to its original state and nothing is saved. On **General**, **Recent Changes** has no new row. |
| 7 | Tab to the **Learn More** link under the same setting and press Enter. | The help page opens in a new browser tab. Close it; focus is back on the Settings page. |
| 8 | Press Tab through the rest of the section. | Focus never lands on something invisible, and the order follows the page from top to bottom. |

**Cleanup:** None.

## T-A11Y-02: Keyboard Only in Find

**Purpose:** Confirm a query can be built, run and saved without a mouse, and the result count is announced.
**Prerequisites:** admin user; sample data loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Find** tab in the **BarnCRM** app. Tab to the **Object** box. | Focus ring on **Object**, placeholder **Choose an object**. |
| 2 | Press Enter or Down Arrow, use the arrow keys to reach **Households**, press Enter. | The **Columns** chooser, **Conditions**, **Sort by** and the **Query (read only)** box appear. |
| 3 | Tab into **Columns**. In the available list use the arrow keys to pick a field, then Tab to the move right button and press Enter. | The field moves to the chosen list. |
| 4 | Tab to **Run** and press Enter. | A line **N rows found.** appears above the results table (N is a number), and the results table lists households. |
| 5 | Tab to **Query name** and type `A11y check`. Tab to **Save** and press Enter. | A green notice reads **Saved A11y check.** The **Saved queries** box shows the query. |
| 6 | Tab through the results table. | Focus enters the table and arrow keys move between cells. |

**Cleanup:** Keep the saved query for T-A11Y-03, then delete it there.

## T-A11Y-03: Focus in the Confirm Dialog

**Purpose:** Confirm the shared confirm dialog (used by Find, Access, household merge and others) traps focus, closes on Escape and returns focus.
**Prerequisites:** admin user; the saved query **A11y check** from T-A11Y-02 open in Find.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | In Find, with **A11y check** open, Tab to **Delete** and press Enter. | A dialog opens with the heading **Delete this saved query?**, the text **A11y check will be deleted. This cannot be undone.** and two buttons, **Keep it** and **Delete**. Focus is inside the dialog. |
| 2 | Press Tab repeatedly (at least six times). | Focus cycles only through the dialog's close button, **Keep it** and **Delete**. It never reaches the Find page behind the dialog. |
| 3 | Press Shift+Tab repeatedly. | Focus cycles backwards through the same three controls. |
| 4 | Press Escape. | The dialog closes. The query is not deleted. Focus is back on the **Delete** button. |
| 5 | Press Enter on **Delete** again, Tab to **Keep it**, press Enter. | The dialog closes, the query is kept and focus is back on **Delete**. |
| 6 | Press Enter on **Delete** again, Tab to the dialog's **Delete** button, press Enter. | The dialog closes and a notice reads **Deleted A11y check.** The query is gone from **Saved queries**. |

**Cleanup:** None (the query is deleted in step 6).

## T-A11Y-04: Keyboard Only in the Import Wizard

**Purpose:** Confirm every step of an import up to the preview can be done without a mouse.
**Prerequisites:** admin user; the file `docs/admin-guide/samples/npsp-contacts.csv` saved on your computer.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the app launcher, search `Import`, open the **Import** tab. Tab to the card **People and Organizations** and press Enter. | Card **Import a Spreadsheet** shows, with step heading **What Are You Importing?**. Focus ring on each card as you tab, and a **Template** box shows once a card is chosen. |
| 2 | Tab to the **Template** box, open it with Enter, choose **NPSP: contacts** with the arrow keys, press Enter. Tab to **Next** and press Enter. | The step heading **Upload the file** and an **Upload file** control show. |
| 3 | Press Tab until focus is on **Upload file**, press Enter or Space and pick the sample file in the file dialog. | **Reading your file.** shows briefly, then the step **Check the Columns** with a table of **Column in Your File**, **What It Means** and **First Values**. |
| 4 | Tab into the table. Change one **What It Means** box with Enter and the arrow keys. | The box opens, the choice is applied and focus stays in that row. |
| 5 | Press Tab until focus reaches **Next** and press Enter. | The step **Choose how rows are matched** shows. |
| 6 | Press Tab until focus reaches **Preview** and press Enter. | The preview runs. Counts appear and the buttons **Import These Rows** and **Back** can be reached with Tab. |
| 7 | Tab to **Back** and press Enter. | The previous step shows again. Nothing was imported. |

**Cleanup:** None. Do not press **Import These Rows**.

## T-A11Y-05: Keyboard Only in Quick Gift Entry

**Purpose:** Confirm a gift can be entered without a mouse, that an error moves focus to the field to fix, and that **Save and New** puts focus back on the donor.
**Prerequisites:** staff user with Giving Staff; sample data loaded (donor Harper Garcia).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **Fundraising** app and the **Quick Gift Entry** tab. Tab into the form. | Card **Quick Gift Entry**. **Who gave this gift** shows **Person** selected; **Gift Date** holds today's date. |
| 2 | Leave **Donor** empty. Tab to **Amount**, type `50`. Tab to **Payment Method**, press Enter, choose **Check**, press Enter. | The values show in the fields. |
| 3 | Tab to **Save** and press Enter. | Nothing is saved. Under **Donor** the message **Choose the person or organization who gave this gift.** shows, and focus is in the **Donor** box. |
| 4 | Type `Garc`, press Down Arrow to **Harper Garcia**, press Enter. | Harper Garcia stays in the box and the error under **Donor** is cleared on the next save. |
| 5 | Tab to **Save and New** and press Enter. | A success toast and the message **Gift G-... saved** show. The form clears amount and payment method, keeps the date, and focus is back in the **Donor** box. |
| 6 | With **Donor** empty again, press Shift+Tab. | Focus moves to **Who gave this gift**. Left and Right Arrow switch between **Person** and **Organization**; the donor box label changes to match. |

**Cleanup:** Delete the gift created in step 5 (as admin, from the **Gifts** tab).

## T-A11Y-06: Read-Only User with the Keyboard

**Purpose:** Confirm the read-only notice is announced and disabled controls do not trap the keyboard.
**Prerequisites:** read-only user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **BarnCRM Settings** tab. | A notice at the top reads **You can read these settings but not change them. Ask your administrator for the Manage BarnCRM Settings permission.** A screen reader announces it as a status message. |
| 2 | Press Tab through the **People and Households** section. | Every control is greyed out. There is no **Save** or **Discard Changes** button. Each **Learn More** link is still reachable. |
| 3 | Open the **Import** tab from the app launcher. | The warning **You need the Manage BarnCRM Settings permission to import. Ask whoever set up your org for the BarnCRM Admin role.** shows. No wizard controls can be reached with Tab. |

**Cleanup:** None.

## T-A11Y-07: Screen Reader Labels Spot Check

**Purpose:** Confirm a sample of controls announce a name that makes sense without seeing the screen.
**Prerequisites:** admin user; a screen reader on (VoiceOver on a Mac with Command+F5, or NVDA on Windows); sample data loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **People and Households**, Tab to the **Learn More** link under **Create a household automatically**. | Announced as **Learn more about Create a household automatically (opens a new tab)**, not just "Learn More". |
| 2 | Tab onto the checkbox **Create a household automatically**. | The label and its description text are both read. |
| 3 | Open a Garcia household from the **Households** tab (for example **The Garcia Family**). In the **Members** panel, Tab to the first **Make Primary** button. | Announced as **Make Harper Garcia the primary contact** (the member's own name), not just "Make Primary". |
| 4 | Tab to a **Move to another household** button. | Announced as **Move** plus the member's name plus **to another household**. |
| 5 | In Find, run any Households query. | The screen reader announces the **N rows found.** line without you moving focus to it. |
| 6 | In Quick Gift Entry, press **Save** with **Donor** empty. | The error **Choose the person or organization who gave this gift.** is read together with the **Donor** field. |
| 7 | In the Import wizard on **Check the Columns**, move to the table. | The table is announced as **Check the Columns** with column headers **Column in Your File**, **What It Means**, **First Values**. |

**Cleanup:** None.

## T-A11Y-08: Zoom to 200 Percent

**Purpose:** Confirm the main pages reflow at 200 percent zoom without losing content or needing sideways page scrolling.
**Prerequisites:** admin user; browser window about 1280 pixels wide.

| Step | Action | Expected result |
|---|---|---|
| 1 | Set browser zoom to 200 percent. Open **BarnCRM Settings**. | The **Sections** list stacks above the settings instead of beside them. All text is readable; no setting is cut off. |
| 2 | Open **Find**, choose **Households**, press **Run**. | The **Saved queries** and **Object** boxes stack one per line. The page itself does not scroll sideways; only the results table may scroll inside its own area. |
| 3 | Open **Quick Gift Entry**. | Every field label and the **Save** and **Save and New** buttons are visible. Buttons wrap to a new line rather than overlap. |
| 4 | Open the **Import** tab and go to **Check the Columns** with the sample file. | The columns table scrolls inside its own area; the step heading and **Next** stay readable. |
| 5 | Open a household record page. | The **Members** panel shows each member's name and buttons without overlap. |

**Cleanup:** Set browser zoom back to 100 percent.

## T-A11Y-09: Household and Gift Pages on the Salesforce Mobile App

**Purpose:** Confirm household and gift record pages are readable and editable on a phone.
**Prerequisites:** staff user with Giving Staff, signed in to the Salesforce mobile app on a phone (or a device simulator, and say so in your results); sample data loaded.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open a Garcia household from **Households**. | The **Members** panel lists every member, readable without sideways scrolling. |
| 2 | Scroll the page. | Details, related lists and the **Members** panel open and render; nothing overlaps. |
| 3 | Open a gift from the household's gifts related list. | The gift page shows **Amount**, **Gift Date** and the donor, and the **Soft Credits** panel renders. |
| 4 | Edit **Payment Reference**, type `A11Y1`, save. | The value saves and shows on the page. |
| 5 | Record device, OS and app version as the [Mobile audit](../contributor-guide/scale-and-mobile-test-plan.md#mobile-audit) asks. For the full set of mobile screens, run that audit. | Results recorded per [Record results](before-you-test.md#record-results). |

**Cleanup:** Clear **Payment Reference** on the gift from step 4.
