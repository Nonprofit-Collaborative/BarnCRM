# Giving: receipts and acknowledgments

Scripts for gift receipts, year-end statements, the receipt lock, receipt letters, thank-you acknowledgments, donor levels and stewardship plans. Setup detail: [Receipts and year-end statements](../admin-guide/receipts.md), [Acknowledgments](../admin-guide/acknowledgments.md), [Donor levels](../admin-guide/donor-levels.md), [Stewardship plans](../admin-guide/stewardship-plans.md), [Email addresses](../admin-guide/emails.md).

Before you start: an org from [Before you test](before-you-test.md), with Core, BarnCRM Rollup Builder and Giving deployed and sample data loaded unless a script says otherwise.

For every script on this page:

- Open gifts from the **Fundraising** app, so they open on the packaged **Gift Record Page** with its **Receipts** panel. Outside that app, assign the page as the org default for Gift first ([Receipts](../admin-guide/receipts.md), step 2).
- In **BarnCRM Settings**, **Giving**, set **Default fund** to **General Fund** and save.
- "Enter a gift" means: in the **Fundraising** app, open **Quick Gift Entry**, choose **Person**, pick the **Donor**, type the **Amount**, set **Payment method** to **Check** and **Fund** to **General Fund**, then select **Save**. A **Gift saved** toast names the new gift number.
- **Rosa Hall** and **Susan Ortiz** have no gifts in the sample data, so their totals start empty.

## T-RCPT-01: Set receipt numbering and check the shipped letters

**Purpose:** Confirm the Receipts settings save and both shipped letters exist.
**Prerequisites:** admin (see [Test users](before-you-test.md#test-users)). No receipt issued yet in this org.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, then the **Organization** section. | Your legal name and tax ID are filled in. If the legal name is blank, fill it in and select **Save** (receipts need it). |
| 2 | Open the **Receipts** section. Set **Receipt number prefix** to `TEST`, leave **Receipt next counter** at 1, set **Statement year** to last year. Select **Save**. | The toast reads "Your settings are saved." |
| 3 | On the **Receipt letters and year end statements** row, select **Open this page**. | The Receipts page opens on the **Receipt templates** tab. |
| 4 | Open the **Letter** list. | Two letters are listed: the per gift receipt and the consolidated statement. Neither ends in ", not in use". |
| 5 | Read the notes under the editor. | The tax note starts "The tax wording is not in this letter and cannot be edited." and a token list follows "Tokens you can use." |

**Cleanup:** None. Later scripts use the `TEST` prefix.

## T-RCPT-02: Issue a receipt for a gift

**Purpose:** Confirm a staff user can issue a numbered PDF receipt from the gift.
**Prerequisites:** staff. T-RCPT-01 done.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Enter a gift from **Rosa Hall** for 125. Open the gift. | The **Receipts** panel reads "No receipt has been issued for this gift yet." and shows **Issue receipt**. |
| 2 | Select **Issue receipt**. | Toast **Receipt issued**: "Receipt TEST-<this year>-000001 has been issued. Click View PDF beside it to open the file." |
| 3 | Read the panel row. | **Number** TEST-<this year>-000001, **Status** Issued, **Amount** 125.00, **Issued** today, and a **View PDF** link. **Issue receipt** is gone; a **Why is this receipt being voided?** box and **Void and reissue** button show instead. |
| 4 | Refresh the page and read **Receipt Number** on the gift. | It holds the same number. |
| 5 | Select **View PDF**. | The file preview opens. The PDF shows the organization's name and address at the top, the amount 125.00, the gift date, the tax ID, and the sentence "No goods or services were provided in exchange for this contribution." |

**Cleanup:** None. T-RCPT-03 and T-RCPT-04 use this gift.

## T-RCPT-03: The receipt lock refuses changes to a receipted gift

**Purpose:** Confirm amount, date and donor cannot change once a gift carries a receipt number.
**Prerequisites:** staff, then admin for step 5. The receipted gift from T-RCPT-02.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the gift, select **Edit**, change **Amount** to 150, select **Save**. | The save is refused: "This gift has a receipt number, so its amount, date, donor and in-kind description cannot change. Void the receipt and reissue it, or record a refund." |
| 2 | Cancel. Edit again, change **Gift Date** to yesterday, select **Save**. | The same message. |
| 3 | Cancel. Edit again, set **Payment Reference** to `Check 9001`, select **Save**. | It saves: fields not printed on the receipt stay editable. |
| 4 | Edit again. Look at **Receipt Number**. | It is read only. |
| 5 | As admin, open the same gift and select **Delete**, then confirm. | The delete is refused: "This gift has a receipt number, so it cannot be deleted: a donor is holding the receipt. Record a refund or a write-off instead." |

**Cleanup:** None.

## T-RCPT-04: Void and reissue a receipt

**Purpose:** Confirm a void needs a reason, keeps the original, and issues the next number.
**Prerequisites:** staff, then admin for steps 5 to 6. The receipted gift from T-RCPT-02.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | On the gift, leave **Why is this receipt being voided?** empty and select **Void and reissue**. | Toast **Reason needed**: "Say why this receipt is being voided. A void needs a reason and a date." Nothing changes in the panel. |
| 2 | Type `Amount was entered wrongly` and select **Void and reissue**. | Toast **Receipt reissued**: "Receipt TEST-<this year>-000001 has been voided and reissued as TEST-<this year>-000002. The original file is unchanged." |
| 3 | Read the panel. | Two rows: 000001 with **Status** Void and **Void reason** "Amount was entered wrongly"; 000002 with **Status** Issued. Each row has **View PDF**. |
| 4 | Open **View PDF** on each row. | Both files open; the first is the original PDF, unchanged. |
| 5 | As admin, open the **Receipts** tab in the Fundraising app and choose the list view **Voided Receipts**. Open 000001. | **Replaced By** points at 000002, **Voided On** is today. Opening 000002 shows **Replaces** pointing back at 000001. |
| 6 | On 000002 select **Edit**, change **Issue Date** to yesterday, select **Save**. | The save is refused: "A receipt cannot be changed once it exists. Void it and issue a new one instead." |
| 7 | Open the gift's donor from its **Donor Contact** link. | The **Receipts** list shows 000001 (Void) and 000002 (Issued). |

**Cleanup:** None.

## T-RCPT-05: Generate year-end statements

**Purpose:** Confirm a statement run issues one consolidated statement per donor and skips donors on a rerun.
**Prerequisites:** admin. T-RCPT-01 done (statement year is last year). Sample data loaded at least a few weeks ago, or in a month after January, so last year holds gifts.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Receipts**, on **Receipt letters and year end statements** select **Open this page**, then the **Year end statements** tab. | **Statement year** shows last year. The runs table, or "No statement run has been started yet." |
| 2 | Select **Generate**. | Toast **Statements started**: "Year end statements are being generated. Click Refresh to see the run's progress below." |
| 3 | Select **Refresh** until the run's **Status** stops changing. | One row for last year with **Donors** and **Issued** above zero and **Errors** 0. |
| 4 | Open the **Receipts** tab in the Fundraising app, list view **Year End Statements**. Open one record. | **Type** Consolidated statement, **Statement Year** last year, **Status** Issued, a **Total Amount**, and no **Gift**. |
| 5 | Open the record's file. | One line per gift in that year; the total at the bottom equals the sum of the lines. |
| 6 | Back on **Year end statements**, select **Generate** again, then **Refresh** until it finishes. | A second row with **Issued** 0: donors who already hold a statement for the year are skipped. |

**Cleanup:** None. Statements cannot be deleted.

## T-RCPT-06: Edit a receipt letter, and only an admin may

**Purpose:** Confirm the letter editor saves and previews for admins and is read only for others.
**Prerequisites:** admin for steps 1 to 4; staff and read-only for step 5.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Receipts page (**Receipt Letters** tab in the Fundraising app), **Receipt templates** tab. Choose the per gift letter in **Letter**. | The editor **The letter donors read** shows the wording, with tokens such as `{{DonorName}}`. |
| 2 | Add the sentence `Testing the letter editor.` at the end. Select **Preview**. | A **Preview for a sample gift** section shows the letter filled in for a sample donor, with your sentence and the tax sentences BarnCRM adds. |
| 3 | Select **Save**. | Toast **Letter saved**: "Your receipt letter has been saved." |
| 4 | Remove the test sentence and select **Save**. | **Letter saved** again. |
| 5 | Log in as staff, then as read-only, and open the same tab. | Each sees "You do not have permission to change the receipt letters. Ask your administrator for the BarnCRM Admin role, which carries Manage BarnCRM Settings." The editor and **Save** are disabled. |

**Cleanup:** Step 4 restores the wording.

## T-RCPT-07: Who can issue and who can open receipt files

**Purpose:** Confirm read-only users cannot issue, and users without a Giving permission set cannot open receipt files.
**Prerequisites:** read-only, admin and staff. The gift from T-RCPT-02 (with two receipts).

| Step | Action | Expected result |
|---|---|---|
| 1 | As read-only, open the gift. | The **Receipts** panel lists both receipts with **View PDF**, and shows no **Issue receipt**, no void reason box and no **Void and reissue**. |
| 2 | Select **View PDF** on 000002. | The PDF opens: Giving Read Only may read receipts. |
| 3 | As admin, open receipt 000002 from **Receipts** and copy its browser address. Open **Rosa Hall**'s household and look at its **Files**. | The receipt PDF is not in the household's files. |
| 4 | As admin, in Setup, **Users**, open the staff user, **Permission Set Assignments**, and remove **Giving Staff**. | The staff user now holds BarnCRM Staff only. |
| 5 | As staff, open **Rosa Hall**. | The contact opens. |
| 6 | As staff, paste the receipt address from step 3. | Salesforce says you do not have access to the record; the receipt and its file do not open. |

**Cleanup:** Give the staff user **Giving Staff** again.

## T-RCPT-08: Acknowledgment rules and an emailed thank you

**Purpose:** Confirm rules queue a gift, an email send records the thank you, and it goes to the preferred email.
**Prerequisites:** admin for steps 1 to 4, staff for steps 5 to 8. Setup, **Deliverability**, **Access level** set to **All email**. A scratch org sends only a few emails a day, so the rules below match only the test amounts.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Giving**, turn on **Acknowledge gifts** and select **Save**. On the **Acknowledgments** row select **Open this page**. | The **Acknowledgments** page opens, with **Waiting to go** and **Your rules, in the order they are considered**. |
| 2 | Select **New rule**. **Rule Name**: `Test email`, **Order** 10, **Active** on, **Channel** Email, **Email template** **BarnCRM: thank you for your gift**, **Minimum Amount** 7777, **Maximum Amount** 7777. Select **Save**. | Toast "The rule has been saved." The rule is listed with **Matches** "7777 and up, up to 7777". |
| 3 | Select **New rule**, **Channel** Email, leave **Email template** at **Choose a template**, select **Save**. | Refused: "An email rule needs an email template. Choose one from the list." Select **Cancel**. |
| 4 | Open **Susan Ortiz**. Set **Work Email** to `susan.work@example.org`, **Preferred Email** to **Work**, select **Save**. | The ordinary **Email** now reads `susan.work@example.org` ([Email addresses](../admin-guide/emails.md)). |
| 5 | As staff, enter a gift from **Susan Ortiz** for 7777. Open the gift. | **Acknowledgment Status** is **To acknowledge**. |
| 6 | Open the **Acknowledgments** page (**Acknowledgment Queue** tab in the Fundraising app). | **Emails ready to send** is at least 1. |
| 7 | Select **Send emails now**. | "The email send has started. The run below shows how it goes." After a refresh, a run under **Recent runs** with **Sent** 1 and **Did not go** 0. |
| 8 | Open the gift again, then the newest row in its **Acknowledgments** list. | The gift's **Acknowledgment Status** is **Acknowledged** with today's **Acknowledgment Date**. The acknowledgment has **Status** Sent, **Recipient Email** `susan.work@example.org`. |

**Cleanup:** On the rules list, **Edit** `Test email` and clear **Active**. Leave the gift (T-RCPT-10 uses Susan Ortiz).

## T-RCPT-09: Letter thank yous, no double thanks, and who may send

**Purpose:** Confirm the letter file and Mark as sent, that a sent gift is never queued again, and the permission split.
**Prerequisites:** admin for step 1; staff for steps 2 to 6; read-only for step 7. T-RCPT-08 done.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the Acknowledgments page select **New rule**: `Test letter`, **Order** 5, **Channel** Letter, **Minimum Amount** 8888, **Maximum Amount** 8888. **Save**. | The rule is listed first (lowest order). |
| 2 | As staff, enter a gift from **Rosa Hall** for 8888. Open the Acknowledgments page. | **Letters ready to merge** is at least 1. No **New rule** and no **Edit** buttons show for staff. |
| 3 | Select **Download letters to merge**. | "The letter file is ready on the run below. Merge it, print it, and then choose Mark as sent." The run shows **Download the file** and **Mark as sent**. |
| 4 | Select **Download the file**. | A CSV with a row for the 8888 gift: donor name, greeting, address, amount, gift date, appeal, fund. |
| 5 | Select **Mark as sent**. | "Those letters are recorded as sent." The 8888 gift's **Acknowledgment Status** is **Acknowledged**. |
| 6 | Select **Download letters to merge** again (or note it is disabled). | The 8888 gift is not in a new file: a thanked gift never returns to the queue by itself. |
| 7 | As read-only, open the Acknowledgments page. | The queue counts show. **Send emails now**, **Download letters to merge** and **Send emails nightly** are disabled; no **New rule** or **Edit**. |

**Cleanup:** As admin, **Edit** `Test letter` and clear **Active**.

## T-RCPT-10: Donor levels place a donor and follow a refund down

**Purpose:** Confirm the ladder assigns levels from total giving and moves a donor down after a refund.
**Prerequisites:** admin. **Susan Ortiz** holds only the 7777 gift from T-RCPT-08 (or enter it now).

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Giving**, on the **Donor levels** row select **Open this page**. | The **Donor levels** page. With no rungs: "You have not created any levels yet. Choose New level to add the first rung of your ladder." |
| 2 | Select **New level**: **Level Name** `Friend`, **Minimum Amount** 100, **Maximum Amount** 1000, **Active** on. Save. Repeat for `Sustainer` 1000 to 5000 and `Leadership Circle` 5000 with no maximum. | The page lists three rungs, lowest first; the top one reads "and above". |
| 3 | Try a fourth level with **Minimum Amount** 500 and **Maximum Amount** 200. | Refused: "The maximum amount has to be greater than the minimum amount. Leave the maximum empty for the top level of your ladder." Cancel. |
| 4 | In **BarnCRM Settings**, **Giving**, turn on **Donor levels**, leave **Donor level source** at total giving, **Save**. Back on the page select **Recalculate now**. | "Placing every donor on the ladder. This runs in the background and the counts below update when it finishes." After a refresh, **Donors** counts appear and **Donors last placed** shows a time. |
| 5 | Open Susan Ortiz's household. | **Donor Level** reads `Leadership Circle` (total giving 7777). |
| 6 | Open the 7777 gift and select **Refund or Write Off**. Refund 5000 with reason `Level test`. Open the household again after a few seconds. | **Total Giving** 2777, **Donor Level** `Sustainer`. |
| 7 | On the **Households** list, choose to display **Previous Donor Level** and **Donor Level Changed** and find the household. | **Previous Donor Level** `Leadership Circle`, **Donor Level Changed** today. |
| 8 | As read-only, open the Donor levels page. | The ladder shows; **Recalculate now** is disabled. |

**Cleanup:** In **BarnCRM Settings**, **Giving**, turn **Donor levels** off. Clear **Active** on the three test levels.

## T-RCPT-11: A stewardship plan lays out tasks on a first gift

**Purpose:** Confirm a First gift plan creates its tasks once, and the save checks on plans and steps.
**Prerequisites:** admin. A donor with no gifts (for example **Valentina Singh**).

| Step | Action | Expected result |
|---|---|---|
| 1 | In **BarnCRM Settings**, **Giving**, on **Stewardship plans** select **Open this page**. Select **New plan**: **Plan name** `First gift welcome`, **What starts it** Manual, **Smallest gift that starts it** 100. **Save**. | Refused: "A minimum amount applies only to the First gift and Gift received events. Clear it, or choose one of those events." |
| 2 | Change **What starts it** to **First gift**, clear the minimum, leave **On** off. **Save**. | "Saved." The plan is listed with **On** Off, **Steps** 0, **Running now** 0. |
| 3 | Select the plan, then **Add step**: **Subject** `Call to say thank you`, **Days after start** 1, **Assign to** Specific user, no **Assigned user**. **Save**. | Refused: "Choose the person this task goes to, or change Assign To." |
| 4 | Change **Assign to** to **Record owner**, **Save**. Add `Send the welcome packet`, 7 days, Record owner. | Two steps listed in order; **Move up** and **Move down** reorder them. |
| 5 | Select **Turn on** in the plan's row. | **On** reads On. |
| 6 | Enter a gift from **Valentina Singh** for 50. | **Gift saved**. |
| 7 | Open **Stewardship Plans** in the Fundraising app, list view **Running Plans**. Open the new plan. | **Plan Template** `First gift welcome`, **Status** Running, **Started Date** today, **Contact** Valentina Singh. Its activity shows two open tasks due tomorrow and in 7 days, assigned to the contact's owner. |
| 8 | Enter a second gift from Valentina Singh for 50. Reopen **Running Plans**. | Still one plan for her: the same plan does not start twice while running. |
| 9 | Open Valentina Singh in the Fundraising app. | Her **Stewardship Plans** list shows the one running plan. |
| 10 | As read-only, open the Stewardship plans page. | "You can read the plans here. Changing them needs the Manage BarnCRM Settings permission." **New plan** is disabled. |

**Cleanup:** Set the plan's **Status** to Cancelled (its tasks stay). Select **Turn off** on `First gift welcome`.
