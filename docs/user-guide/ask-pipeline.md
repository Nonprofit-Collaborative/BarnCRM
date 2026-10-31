# The Ask Pipeline

An ask is a request you plan to make, or have made, to a donor. The Ask Pipeline shows every open ask by step, so you can see where each one stands and what to do next.

Before you start: open the **BarnCRM Fundraising** app, **Ask Pipeline** tab. You need the **Fundraising Staff** role (the **Giving Staff** permission set) to add or change asks. A Giving Read Only user can look but not change.

## To Add an Ask

1. Open **Ask Pipeline** and click **New Ask**. Or open a person, household or organization and click **New** in its **Asks** list.
2. Choose the donor: **Donor Contact** for a person, or **Donor Account** for an organization or household. Fill in one, never both.
3. Type the **Ask Amount** and **Target Date**. Add a **Next Step**, **Fund** and **Appeal** if they apply.
4. Leave **Stage** empty to start at the first stage. **Assigned To** is the record owner.
5. Click **Save**.

You should see: the ask on the board, in its stage column.

## To Read the Board

The numbers at the top are **Open Asks**, **Open Ask Total**, **Won This Fiscal Year** and **Declined This Fiscal Year**. Each column shows its stage with a count and a total. Each card shows the donor, ask amount, target date, next step, who it is assigned to and "N days in this stage". Only open asks are on the board.

Click **Everyone's Asks** or **My Asks** to filter by who an ask is assigned to. Click **List** for a table of the same open asks, in stage order, and **Board** to go back.

If a column is called **Not in Your Stage List**, your admin renamed or removed a stage. Move those cards to a current stage.

## To Move an Ask

Drag the card to another column. Or open the card's menu and choose **Move to** and the stage.

You should see: the card in its new column, the counts and totals updated, and "0 days in this stage".

## To Close an Ask

1. On the card's menu choose **Close Ask**.
2. Under **How Did It End?** choose **Won**, **Declined** or **Withdrawn**.
3. For **Won**, choose **What Did It Produce?**:
   - **Record the Gift Now**: type the **Amount**, **Gift Date** and **How It Arrived**. The gift is saved the same way Quick Gift Entry saves one, with the ask's donor, fund and appeal.
   - **Record a Pledge**: type the **Pledge Total**, **First Payment Date**, **How Often** and **Number of Payments**. BarnCRM creates a pledge in equal payments (the last payment takes up any rounding) and lays out its payment schedule.
   - **Link a Gift or Pledge Already Entered**: pick one that belongs to the same donor. Another donor's is refused.
   - **Record It Later**: close the ask now and link a gift or pledge afterward, by editing the ask's **Resulting Gift** or **Resulting Commitment**.
4. Optionally type a **Next Ask Date**, the day to ask this donor again.
5. Click **Save**.

You should see: the card leaves the board and the totals change. The gift or pledge, the link and the outcome save together, or none of them does.

The reminder follows the donor's own **Next Ask Date**: while a donor has open asks, it is the earliest **Target Date** among them. When you close the donor's last open ask, fill in the ask's **Next Ask Date** as you close it, and the donor's date becomes that date (if it is after today). Without one, the donor's date is cleared. A date someone changed by hand on the donor is always kept ([Ask reminders](ask-reminders.md)).

## To Reopen an Ask

Open the ask, edit it and set **Outcome** back to **Open**. **Closed Date** clears and the ask returns to the board.

## To See What Changed

Open the ask. The **Ask History** list shows changes to **Stage**, **Outcome**, **Ask Amount** and **Target Date**.

## Common Problems

- **"The stage is not in the list."** Choose one of the stages shown in the board columns. Your admin sets them.
- **An ask has no donor after a donor was deleted.** That is expected. You can still close it.
- **You cannot change an ask.** You may have the read-only role. Ask your admin.
- **You see only your own asks.** Your admin may have made asks private, so each fundraiser sees only their own.

## Related

- [Entering gifts](gifts.md)
- [Pledges and recurring gifts](commitments.md)
- [Admin page: Ask Pipeline](../admin-guide/ask-pipeline.md)
