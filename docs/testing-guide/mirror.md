# Mirror

Scripts for Campaign sync, the Opportunity mirror, the accounting export, the Inbound Gift API and the Record Inbound Gift action. Setup detail: [Campaign Sync](../admin-guide/campaign-sync.md), [Opportunity Mirror](../admin-guide/opportunity-mirror.md), [Accounting Export](../admin-guide/accounting-export.md), [Inbound Gift API](../admin-guide/inbound-gift-api.md).

Before you start: an org from [Before you test](before-you-test.md), with Core, Giving and Mirror deployed and sample data loaded unless a script says otherwise. Campaign sync and the Opportunity mirror need Opportunity and Campaign, so use the Person Accounts (or `sales-cloud`) shape, not platform-only: see [Create a test org](before-you-test.md#create-a-test-org). Each Mirror feature has its own permission set (**Campaign Sync**, **Opportunity Mirror**, **Accounting Export**, **Inbound Gift API**, **Record Inbound Gift Action**). No role includes them, and the admin user does not have them until a script gives them: open **BarnCRM Settings**, **Access**, find the person, and use **Extra permissions**, **Give permission**.

## T-MIR-01: Switch on Campaign sync and sync all appeals

**Purpose:** confirm the switch, the counts and Sync all appeals give every sample appeal a Campaign.
**Prerequisites:** admin, with the **Campaign Sync** permission set and **Marketing User** ticked on your user (Setup, Users, your user, Edit). Sample data (7 appeals).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Giving**, and open **Campaign sync**. | The **Campaign sync** card says `Campaign sync is off. Switch on Copy appeals to Campaigns in the Giving section of BarnCRM Settings, then come back to sync your appeals.` No **Sync all appeals** button shows. |
| 2 | In **Giving**, tick **Copy appeals to Campaigns** and save. | The setting saves. |
| 3 | Open **Campaign sync** again. | `Campaign sync is on. Saving an appeal creates or updates its Campaign.` and `0 of 7 appeals have a Campaign.` **Sync all appeals** is enabled. |
| 4 | Click **Sync all appeals**. | `Sync all appeals is running in the background. Reload this page in a minute to see the new counts. Anything that could not be copied is in the Error Log.` |
| 5 | Wait a minute and reload the page. | `7 of 7 appeals have a Campaign.` |
| 6 | Open the App Launcher, search **Campaigns**, and open the list. | Seven Campaigns named after the appeals. **Spring Appeal** shows **Annual Fund** as its Parent Campaign. |
| 7 | Open the **Appeals** tab and choose the **Appeals and Their Campaigns** list view. | Every appeal has a **Campaign ID** starting `701`. |

**Cleanup:** None (later scripts use these Campaigns).

## T-MIR-02: Appeal changes reach the Campaign, one way only

**Purpose:** confirm saving an appeal creates and updates its Campaign, nothing comes back, and a bad Campaign ID is refused.
**Prerequisites:** admin, as in T-MIR-01, with Campaign sync on.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the **Appeals** tab, click **New**. Name `Giving Tuesday`, **Goal** 5,000, a start date of today. Save. | The appeal saves. |
| 2 | Open the Campaigns list and open `Giving Tuesday`. | Expected Revenue 5,000, start date today. |
| 3 | On the appeal, change **Goal** to 7,500 and save. Reload the Campaign. | Expected Revenue is 7,500. |
| 4 | Create appeal `Giving Tuesday: matching challenge` with **Parent Appeal** `Giving Tuesday`. Open its Campaign. | Parent Campaign is `Giving Tuesday`. |
| 5 | On the `Giving Tuesday` Campaign, change its Description and save. Open the appeal. | The appeal's description is unchanged. |
| 6 | In **Appeals and Their Campaigns**, double-click the **Campaign ID** cell of `Giving Tuesday: matching challenge`, enter `abc`, and save. | The save is refused with `Campaign ID must be the record ID of a Campaign (18 characters, starting 701), or empty.` |
| 7 | Paste the **Campaign ID** of `Giving Tuesday` into the same cell and save. | The save fails with a duplicate value error. Both appeals keep their own Campaign ID. |

**Cleanup:** None. Campaign sync never deletes a Campaign; delete the two Campaigns and appeals by hand if you want them gone.

## T-MIR-03: Campaign sync access and switching off

**Purpose:** confirm who cannot sync, and that switching off stops copying and deletes nothing.
**Prerequisites:** staff given the **Campaign Sync** permission set (Marketing User not ticked); read-only; admin. Campaign sync on.

| Step | Action | Expected result |
|---|---|---|
| 1 | As read-only, open the App Launcher and search `Campaign Sync`. | No **Campaign Sync** item is found. |
| 2 | As staff, open the **Campaign Sync** tab from the App Launcher. | The card shows `You cannot create and edit Campaigns, so appeals you save get no Campaign...` and `Only someone with the Manage BarnCRM Settings permission can sync all appeals.` **Sync all appeals** is disabled. |
| 3 | As admin, in **BarnCRM Settings**, **Giving**, untick **Copy appeals to Campaigns** and save. | The setting saves. |
| 4 | Change the **Goal** of `Giving Tuesday` to 9,000 and save. Reload its Campaign. | Expected Revenue is still 7,500. Every Campaign is still there. |
| 5 | Tick **Copy appeals to Campaigns** again and save `Giving Tuesday` once more. | The Campaign's Expected Revenue is 9,000. |

**Cleanup:** remove the **Campaign Sync** permission set from staff.

## T-MIR-04: Opportunity mirror, Gifts to Opportunities

**Purpose:** confirm a run gives every gift in the totals an Opportunity and the reconciliation agrees.
**Prerequisites:** admin, with the **Opportunity Mirror** permission set. Sample data, with rollups recalculated.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the App Launcher and the **Opportunity Mirror** tab. | `The Opportunity mirror is off. Choose a direction in BarnCRM Settings, Giving, Opportunity mirror direction.` |
| 2 | In **BarnCRM Settings**, **Giving**, set **Opportunity mirror direction** to **Gifts to Opportunities** and save. | The setting saves. |
| 3 | Reopen **Opportunity Mirror**. | `Direction: Gifts to Opportunities. Every gift in the totals gets a matching Opportunity.`, `The nightly run is not scheduled.` and `No run has completed yet.` |
| 4 | Click **Run now**. | `The run has started. Its summary is written to the Error Log when it ends.` |
| 5 | Wait a minute and reload. | The last run line reads `Last completed run: started <time>. Opportunity mirror run, Gifts to Opportunities: <n> Opportunities created, 0 updated, ...` |
| 6 | Under **Reconciliation**, set **From** to 1 January of this year and **To** to today. Click **Compare**. | `Gifts: <n>, total <amount>` and `Won Opportunities: <n>, total <amount>` show the same count and total, and `No differences.` |
| 7 | Record a gift of 100 from Luis Garcia on the **Quick Gift Entry** tab. Open the newest Opportunity from the App Launcher. | Amount 100, Stage Closed Won, Close Date today, Luis Garcia as primary contact. |
| 8 | Change the gift's amount to 150 and save. Reload the Opportunity. | Amount 150. |

**Cleanup:** None (T-MIR-05 continues from here).

## T-MIR-05: Reconciliation differences and repair

**Purpose:** confirm a hand-changed Opportunity is listed and **Copy these gifts again** repairs it; a bad Opportunity ID is refused.
**Prerequisites:** admin, after T-MIR-04.

| Step | Action | Expected result |
|---|---|---|
| 1 | On Luis Garcia's 150 Opportunity, change Amount to 175 and save. | Saved. |
| 2 | On **Opportunity Mirror**, click **Compare** for this year. | `Differences found: 1. All are listed.` The table row shows **Gift amount** 150, **Opportunity amount** 175, **Difference** `Amount differs`. **Copy these gifts again** shows. |
| 3 | Click **Copy these gifts again**, wait, and click **Compare**. | `No differences.` The Opportunity's Amount is 150. |
| 4 | Clear both dates and click **Compare**. | `Choose a start date and an end date.` |
| 5 | Set **From** after **To** and click **Compare**. | `The start date must be on or before the end date.` |
| 6 | On the **Gifts** tab, choose **Gifts and Their Opportunities**. Double-click a gift's **Opportunity ID**, enter `abc`, and save. | Refused with `Opportunity ID must be the record ID of an Opportunity (18 characters, starting 006), or empty.` |

**Cleanup:** None.

## T-MIR-06: Opportunities to Gifts, start date and the nightly run

**Purpose:** confirm a won Opportunity becomes a gift only after the start date, and the nightly run can be scheduled and stopped.
**Prerequisites:** admin, with the **Opportunity Mirror** permission set.

| Step | Action | Expected result |
|---|---|---|
| 1 | In **Giving**, set **Opportunity mirror direction** to **Opportunities to Gifts**, leave **Opportunity mirror start date** empty, save, and open **Opportunity Mirror**. | `Direction: Opportunities to Gifts, but no start date is set, so no Opportunity becomes a gift. Set Opportunity mirror start date in BarnCRM Settings.` |
| 2 | Set **Opportunity mirror start date** to today and save. Reopen the page. | `Direction: Opportunities to Gifts. Won Opportunities closed on or after <today> become gifts.` |
| 3 | Create a won Opportunity of 60, closed today, with Luis Garcia's account and Luis as primary contact. Click **Run now** and wait a minute. | A gift of 60 appears on Luis Garcia's record. In **Gifts and Their Opportunities** its **Opportunity ID** names that Opportunity. |
| 4 | Create a won Opportunity of 80 closed last month and click **Run now**. | No gift of 80 is made. |
| 5 | Click **Schedule nightly run**. | `Next nightly run: <date> 1:30 AM`. The button changes to **Stop nightly run**. |
| 6 | Click **Stop nightly run** (undo). | `The nightly run is not scheduled.` The button changes back to **Schedule nightly run**. |

**Cleanup:** set **Opportunity mirror direction** to **Off**; delete the 60 gift and the two Opportunities.

## T-MIR-07: Opportunity mirror access

**Purpose:** confirm the page and run buttons are closed to people without the permission set or Manage BarnCRM Settings.
**Prerequisites:** read-only; staff given the **Opportunity Mirror** permission set. Direction **Gifts to Opportunities**.

| Step | Action | Expected result |
|---|---|---|
| 1 | As read-only, search the App Launcher for `Opportunity Mirror`. | No **Opportunity Mirror** item is found. |
| 2 | As staff, open the **Opportunity Mirror** tab. | `Starting or scheduling the mirror needs the Manage BarnCRM Settings permission.` **Run now** and **Schedule nightly run** are disabled. |
| 3 | As staff, run **Compare** for this year. | The comparison shows, limited to what staff can see. |

**Cleanup:** remove the **Opportunity Mirror** permission set from staff; set the direction to **Off**.

## T-MIR-08: Download the accounting export

**Purpose:** confirm the CSV downloads with the fixed columns, filters by fund and method, and an empty range gives no file.
**Prerequisites:** admin, with the **Accounting Export** permission set. Sample data.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the App Launcher and the **Accounting Export** tab. | **Accounting export** card with **From**, **To**, **Fund** (placeholder **All funds**), **Payment method** (**All payment methods**), **Only gifts not yet posted** and **Download file**. |
| 2 | Set **From** and **To** to the first and last day of last month. Click **Download file**. | `accounting-export-<from>-to-<to>.csv` downloads. The page says `<rows> rows from <gifts> gifts. Net total <amount>.` |
| 3 | Open the file. | Header row: `Date,Gift Number,Original Gift,Donor,Fund,Accounting Code,Payment Method,Reference,Amount`. Every date is in the range, and Amount adds up to the net total. |
| 4 | Choose **Building Fund** in **Fund** and download. | Every row says Building Fund, accounting code 4100. |
| 5 | Also choose **Check** in **Payment method** and download. | Only Check rows to Building Fund remain (or `No gifts in this range.`). |
| 6 | Set a week next year and download. | No file. `No gifts in this range.` |
| 7 | Clear **From** and click **Download file**. | `Choose a From date and a To date.` |
| 8 | Set **To** before **From** and download. | `The To date is before the From date.` |

**Cleanup:** None.

## T-MIR-09: Mark gifts posted, and unpost one

**Purpose:** confirm marking posted locks the gifts, Only gifts not yet posted leaves them out, and Unpost reverses one.
**Prerequisites:** admin, with the **Accounting Export** permission set. Last month's range from T-MIR-08.

| Step | Action | Expected result |
|---|---|---|
| 1 | Choose **Building Fund** and download last month. | `To mark gifts posted, download the export for all funds: a gift split across funds would be locked when only part of it is in this file.` No **Mark these gifts posted** button. |
| 2 | Clear **Fund** and download again. | **Mark these gifts posted** shows, with `Once this file is in your accounting system, mark its gifts posted. A posted gift cannot be changed or deleted.` |
| 3 | Click **Mark these gifts posted**. | `Marked <n> gifts posted. Gifts already posted were left as they were.` The button goes away. |
| 4 | Open one gift from the file and change its amount. | Refused: `This gift has been posted to accounting, so its date, amount, donor, payment method, reference and funds cannot change and it cannot be deleted...` |
| 5 | Tick **Only gifts not yet posted** and download last month. | `No gifts in this range.` |
| 6 | On that gift's **Posting** card, enter a reason in **Why is this gift being unposted?** and click **Unpost** (undo). | `Unposted. The reason is in the Error Log. Mark it posted again after your next export.` |
| 7 | Download last month again with **Only gifts not yet posted** ticked. | The file holds that one gift's rows. |

**Cleanup:** None (posted flags are harmless to later scripts; unpost more gifts the same way if needed).

## T-MIR-10: Accounting export access

**Purpose:** confirm only holders of the permission set reach the export.
**Prerequisites:** read-only; staff.

| Step | Action | Expected result |
|---|---|---|
| 1 | As read-only, search the App Launcher for `Accounting Export`. | No **Accounting Export** item is found. |
| 2 | As staff, do the same. | No **Accounting Export** item is found. |
| 3 | As admin, give staff **Accounting Export**. As staff, open the tab and download last month. | A file downloads, holding only the gifts staff can see. **Mark these gifts posted** shows, because the set includes Post Gifts. |

**Cleanup:** remove **Accounting Export** from staff.

## T-MIR-11: Inbound Gift API, record and resend

**Purpose:** confirm the REST endpoint records a gift once and refuses a changed resend.
**Prerequisites:** an API user: `sf org create user --target-org <alias> --set-alias <alias>-api profileName="Standard User" LastName="API Tester" Username="api@<alias>.barncrm.test" Email="api@<alias>.barncrm.test"`, then `sf org assign permset --target-org <alias> --on-behalf-of api@<alias>.barncrm.test --name Inbound_Gift_API`. Sample data. Endpoint in a test org: `/services/apexrest/v1/gifts`.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Run `sf api request rest /services/apexrest/v1/gifts --method POST --include --target-org <alias>-api --body '{"externalId":"test:api-1","amount":25,"paymentMethod":"Card","donorEmail":"luis.garcia2@example.org","fundCode":"4100"}'` | HTTP 201. Body `"outcome":"created"`, a `giftId`, `"message":"Gift recorded."` |
| 2 | Run the same command again. | HTTP 200. `"outcome":"existing"`, the same `giftId`, `"message":"This gift was already recorded. Nothing was changed."` |
| 3 | Run it again with `"amount":30`. | HTTP 409. `"errorCode":"external_id_conflict"`, `"message":"A gift with this externalId is already recorded with a different amount. Nothing was changed."` |
| 4 | As admin, open the gift by its `giftId`. | Luis Garcia, 25.00, type Card, today, one allocation to Building Fund. |

If step 1 answers `donor_not_found`, the API user cannot see contacts: see [Inbound Gift API](../admin-guide/inbound-gift-api.md).

**Cleanup:** delete the gift as admin.

## T-MIR-12: Inbound Gift API refusals

**Purpose:** confirm bad requests are refused with the documented code and message, logged, and that a user without the set is turned away.
**Prerequisites:** the API user from T-MIR-11; read-only. Use the step 1 command of T-MIR-11 with the body shown.

| Step | Body or action | Expected result |
|---|---|---|
| 1 | `{"externalId":"test:api-2","amount":-5,"paymentMethod":"Card","donorEmail":"luis.garcia2@example.org"}` | HTTP 400. `invalid_field`, `amount must be greater than zero, with at most two decimal places.` |
| 2 | `{"externalId":"test:api-3","amount":5,"paymentMethod":"Card"}` | HTTP 400. `invalid_field`, `Name the donor with donorId or donorEmail.` |
| 3 | `{"externalId":"test:api-4","amount":5,"paymentMethod":"Card","donorEmail":"nobody@example.org"}` | HTTP 422. `donor_not_found`, `No person has this donorEmail. Add the donor first, then send the gift again.` |
| 4 | `{"externalId":"test:api-5","amount":5,"paymentMethod":"Bitcoin","donorEmail":"luis.garcia2@example.org"}` | HTTP 400. `invalid_field`, message starts `paymentMethod must be one of:` |
| 5 | `{"externalId":"test:api-6","amount":5,"paymentMethod":"Card","donorEmail":"luis.garcia2@example.org","fundCode":"9999"}` | HTTP 422. `fund_not_found`, `No active fund matches fundId or fundCode.` |
| 6 | `not json` | HTTP 400. `invalid_request`, message starts `The request body is not a gift this API reads:` |
| 7 | As admin, open the **Error Log** tab. | Warnings such as `Inbound gift test:api-4 was refused (donor_not_found)...`, one per refusal. |
| 8 | Send the T-MIR-11 body with `--target-org <alias>-ro`. | HTTP 403 from Salesforce. No gift is recorded. |

**Cleanup:** None (nothing was recorded).

## T-MIR-13: Record Inbound Gift action in Flow

**Purpose:** confirm the Flow action records, recognizes a resend and refuses an unknown donor.
**Prerequisites:** admin, with the **Record Inbound Gift Action** permission set. Sample data.

| Step | Action | Expected result |
|---|---|---|
| 1 | Setup, **Flows**, **New Flow**, **Autolaunched Flow (No Trigger)**. Add an **Action**, search `Record Inbound Gift`, pick it. | The action shows inputs **External Id**, **Amount**, **Payment Method**, **Gift Date**, **Payment Reference**, **Donor Id**, **Donor Email**, **Fund Accounting Code**, **Fund Id**, **Appeal Id**. |
| 2 | Set **External Id** `test:flow-1`, **Amount** 25, **Payment Method** `Card`, **Donor Email** `luis.garcia2@example.org`, **Fund Accounting Code** `4100`. **Debug**, **Run**. | Result: **Outcome** `created`, a **Gift Id**, **Message** `Gift recorded.` |
| 3 | **Debug**, **Run** again. | **Outcome** `existing`, same **Gift Id**. |
| 4 | Change **Donor Email** to `nobody@example.org` and **External Id** to `test:flow-2`. Run. | **Outcome** `rejected`, **Error Code** `donor_not_found`. |

**Cleanup:** close the flow without activating it; delete the `test:flow-1` gift.
