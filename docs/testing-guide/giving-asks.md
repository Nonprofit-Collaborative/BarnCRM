# Giving: Asks

Scripts for the Ask Pipeline: stages, the board, moving and closing asks, and the gift or pledge a won ask can produce. Setup detail: [Ask Pipeline](../admin-guide/ask-pipeline.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Giving deployed and sample data loaded. Work in the **Fundraising** app. A default fund must be set (script T-GIFT-01 in [Giving: gifts, funds and batches](giving-gifts-funds-batches.md)). Sample data has no asks, so the board starts empty.

## T-ASK-01: Stages in Settings

**Purpose:** confirm the default stages, a changed list, and that an unlisted stage is refused.
**Prerequisites:** an admin (see [Test users](before-you-test.md#test-users)).
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Giving**, and find **Ask stages**. | It shows the default `Identified;Qualified;Cultivating;Ask Planned;Asked`. |
| 2 | Open the **Ask Pipeline** tab in the **Fundraising** app. | Five columns in that order, each with a count of 0. Page title **Ask Pipeline**. |
| 3 | Set **Ask stages** to `Prospect;Cultivating;Asked` and save. Reload **Ask Pipeline**. | Three columns: **Prospect**, **Cultivating**, **Asked**. |
| 4 | Open the **Asks** tab, click **New**, choose **Donor Contact** `Luis Garcia`, set **Stage** to `Maybe`, save. | Refused: the stage is not in the list. |
| 5 | Set **Ask stages** back to the default (or clear it) and save. | The five default columns return. |

**Cleanup:** none.

## T-ASK-02: Create an Ask From a Person's Page

**Purpose:** confirm an ask saves with its defaults and one-donor rule.
**Prerequisites:** staff.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the person `Luis Garcia`. In the **Asks** related list click **New**. | The form opens with the donor already chosen. |
| 2 | Enter **Ask Amount** `5000`, **Target Date** 30 days out, **Next Step** `Call about the roof`. Leave **Stage** empty. Save. | The ask is saved and numbered like ASK-00000001. |
| 3 | Read the fields. | **Stage** is the first stage, **Outcome** is Open, **Assigned To** is you, **Stage Changed Date** is filled in, **Closed Date** is empty. |
| 4 | Click **New** again. Choose both **Donor Contact** and **Donor Account**. Save. | Refused: an ask needs exactly one donor. |
| 5 | Clear both donors. Save. | Refused for the same reason. |
| 6 | Cancel. Open **Ask Pipeline**. | The first column shows 1 ask. |

**Cleanup:** keep the ask for the next scripts.

## T-ASK-03: Board Totals, Drag and Move To

**Purpose:** confirm totals, the card contents, dragging and the card menu.
**Prerequisites:** staff; the ask from T-ASK-02. Add a second open ask of `2000` for `Harper Garcia`, Assigned To a different user if you can.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **Ask Pipeline**, **Board**. Read the top. | **Open Asks** 2, **Open Ask Total** 7,000.00, **Won This Fiscal Year** 0, **Declined This Fiscal Year** 0. |
| 2 | Read the first column. | Count 2 and total 7,000.00. Each card shows donor, ask amount, target date, next step, assigned to and "0 days in this stage". |
| 3 | Drag the Luis Garcia card to **Cultivating**. | The card moves. **Identified** shows 1 and 2,000.00; **Cultivating** shows 1 and 5,000.00. |
| 4 | Open the Harper Garcia card's menu. | It offers **Move to** each other stage, **Open** and **Close Ask**. |
| 5 | Choose **Move to Ask Planned**. | The card moves to **Ask Planned**. |
| 6 | Click **List**. | A table with **Ask**, **Donor**, **Stage**, **Ask Amount**, **Target Date**, **Next Step**, **Assigned To** and **Days in Stage**, in stage order. Click **Board** to return. |
| 7 | Click **My Asks**, then **Everyone's Asks**. | **My Asks** shows only asks assigned to you; **Everyone's Asks** shows both. |

**Cleanup:** none.

## T-ASK-04: Close an Ask as Won

**Purpose:** confirm each of the four results of a won ask.
**Prerequisites:** staff; four open asks for `Luis Garcia`, each with an **Ask Amount** of `1000` (A, B, C, D). Create a gift of `500` for `Harper Garcia` and a gift of `300` for `Luis Garcia` for the link steps.

| Step | Action | Expected result |
|---|---|---|
| 1 | On card A choose **Close Ask**. **How Did It End?** `Won`. | **What Did It Produce?** shows **Record the Gift Now**, **Record a Pledge**, **Link a Gift or Pledge Already Entered** and **Record It Later**. |
| 2 | Choose **Record the Gift Now**: **Amount** `1000`, **Gift Date** today, a **How It Arrived** value. Save. | The card leaves the board. **Won This Fiscal Year** counts it. |
| 3 | Open ask A. | **Outcome** Won, **Closed Date** today, **Resulting Gift** filled in. Open the gift: donor, fund and appeal match the ask, and the gift is posted as Quick Gift Entry would post it. |
| 4 | On card B choose **Close Ask**, **Won**, **Record a Pledge**: **Pledge Total** `1200`, **First Payment Date** today, **How Often** `Monthly`, **Number of Payments** `12`. Save. | Ask B shows **Resulting Commitment**. The commitment is type Pledge with a 12 row payment schedule of 100.00 each. |
| 5 | On card C choose **Close Ask**, **Won**, **Link a Gift or Pledge Already Entered**, and pick the 300 gift of Luis Garcia. Save. | Ask C shows that gift as **Resulting Gift**. |
| 6 | Repeat on card D but try to pick the gift of Harper Garcia. | Refused: it belongs to a different donor. Nothing is saved and the ask stays open. |
| 7 | On card D choose **Record It Later**. Save. | Ask D is Won with no resulting gift. Edit it and set **Resulting Gift** to a Luis Garcia gift. It saves. |

**Cleanup:** keep the asks for T-ASK-06.

## T-ASK-05: Declined, Withdrawn and Next Ask Date

**Purpose:** confirm the other two outcomes and the optional next ask date.
**Prerequisites:** staff; two more open asks (E, F).

| Step | Action | Expected result |
|---|---|---|
| 1 | On card E choose **Close Ask**, **Declined**, **Next Ask Date** a date six months out. Save. | The card leaves the board. **Declined This Fiscal Year** counts it. |
| 2 | Open ask E. | **Outcome** Declined, **Closed Date** today, **Next Ask Date** as typed. |
| 3 | On card F choose **Close Ask**, **Withdrawn**, no **Next Ask Date**. Save. | The card leaves the board. **Declined This Fiscal Year** does not change. |
| 4 | Open ask F. | **Outcome** Withdrawn, **Closed Date** today. |

**Cleanup:** keep E for T-ASK-06.

## T-ASK-06: Reopen and History

**Purpose:** confirm reopening and the history list.
**Prerequisites:** staff; ask E (Declined).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open ask E, edit it, set **Outcome** to `Open`. Save. | Saved. **Closed Date** is empty. |
| 2 | Open **Ask Pipeline**. | Ask E is on the board again. |
| 3 | Change E's **Ask Amount** to `2500` and **Target Date**. Save. | Saved. |
| 4 | On ask E, read the **Ask History** list. | Rows for the **Outcome** change (Declined to Open), the **Ask Amount** change and the **Target Date** change, each with who and when. |

**Cleanup:** none.

## T-ASK-07: A Read Only User

**Purpose:** confirm Giving Read Only sees the board and cannot change it.
**Prerequisites:** a user with **Giving Read Only** only; open asks exist.

| Step | Action | Expected result |
|---|---|---|
| 1 | Log in as that user. Open **Ask Pipeline**. | The board and totals show. |
| 2 | Look at the top of the page, then try to drag a card and open a card's menu. | A line says you can see asks but not change them. **New Ask** is not shown. Cards do not drag, and the menu offers only **Open**. |
| 3 | Open an ask and try to edit it. | Refused: no edit access. |
