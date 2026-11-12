# Logic Models

This page covers building a logic model in BarnCRM: the parts of your program from what you put
in to the change you hope for, the arrows between them, and the indicators that measure your
outputs and outcomes, with a target and a result for each period.

**Before you start:** open the **BarnCRM Logic Models** app from the App Launcher. Team Members
and Fundraising Staff build models and can delete parts, but not a whole model. Admins can also delete
a whole model. Read Only users can look but change nothing. If you need more access, ask your
admin (see the [Logic Models admin guide](../admin-guide/logic-models.md#roles-and-permission-sets)).

Your organization has one logic model for the whole organization, and at most one for each
program.

## To Start a Logic Model

1. Click the **Logic Models** tab, then **New**.
2. Type a **Name**, for example "Reading Program Model", and click **Save**.

You should see: the model's page with the **Builder** tab (the **Logic Model Builder** panel), a **Details** tab and the related lists in the sidebar. **For** shows **The whole
organization**. If the organization already has a model, the save is refused with `The
organization already has a logic model. Open that one instead of adding another.`

## To Make a Model a Program's

Only when your organization uses Programs.

1. In the builder, click **Change** next to **For**.
2. Choose the program and click **Save**.

You should see: **For** shows the program's name. A program that already has a model is refused.
To make the model the organization's again, choose **The whole organization**.

## To Add a Part

The builder draws seven columns from left to right, with an arrow between each: **Inputs**,
**Activities**, **Outputs**, **Short Term Outcomes**, **Intermediate Term Outcomes**, **Long Term
Outcomes** and **Impact**. Each heading shows how many parts the column holds. On a phone the
columns are stacked.

1. Under a column, click **Add to** and the column's name (for example **Add to Inputs**).
2. Type a short **Name** and click **Save**.

You should see: the part at the bottom of its column.

## To Change, Move or Delete a Part

1. Click the part. Its details open below the columns and the page moves you to them. The parts
   it has arrows to or from get a blue border; the rest are dimmed. **Back to the Model**, at the
   top of the details, takes you back to the part in its column.
2. Click **Edit** to change its **Name**, **Description** or **Column**, then **Save**. A part with
   indicators can only move to another output or outcome column. A part cannot move to a column
   that would make one of its arrows point backward; the message names those arrows ("From to
   To"), so delete them first or pick a column that keeps every arrow forward.
3. Click **Move Up** or **Move Down** to change its place in its column.

   Or drag the part by its handle (the grip at its left) or by the part itself: up or down
   within its column, or into another column to change its column. A blue line shows where it
   will land. A move the arrow rules refuse puts the part back and shows the same message as
   **Edit**. With the keyboard, Tab to the handle, press Space, use the arrow keys (Left and
   Right change column, Up and Down change place), then press Space again; Escape cancels. On a
   phone, where the columns stack, press and hold the handle to reorder within a column; use
   **Edit** to change the column.
4. Click **Delete**, then **Delete** again in the dialog to confirm. Its arrows, and its
   indicators with their periods, are deleted too.

## To Draw an Arrow

An arrow says one part leads to another, and the assumption says why you believe it does.

1. Click the part the arrow starts from.
2. Under **Leads To**, click **Add Arrow**.
3. Choose the **Part It Leads To**. Only parts in later columns are offered.
4. Type the **Assumption**, for example "Students who attend twice a week read more at home", and
   click **Save**.

Or drag the arrow handle at the right of a part onto a part in a later column: the part's
details open with **Add Arrow** filled in with the part you dropped on, so only the assumption
is left to type. Parts the arrow cannot go to (earlier columns, or a part it already leads to)
do not take the drop. With the keyboard, Tab to the arrow handle, press Space, use Left and
Right to pick the part, then press Space again. On a phone, use **Add Arrow**.

To change an assumption, click **Edit** beside the arrow. To remove an arrow, click **Remove**,
then **Remove** in the dialog.
Arrows into the part are listed under **Comes From**.

To record what supports an assumption, click **Assumption Evidence** under the arrow, then
**Add**. Write **What It Shows**, and if you have them the **Source**, a **Source Link** and
the **Date**, and pick a **Strength** (Strong, Moderate, Limited, or Challenges when it points the
other way). Click **Save**. The newest evidence is listed first.

## To Measure an Output or Outcome

1. Click the output or outcome. Its **Indicators** show below its arrows.
2. Click **Add Indicator**. Fill in **Indicator Name**, and if useful **Unit**, **Better When**
   (**Higher** or **Lower**), **Baseline** and **Baseline Date**. Click **Save**.
3. Under the indicator, click **Add Period**. Fill in **Period** (for example "2026 Q1"), **Start
   Date**, **End Date**, **Target** and, once you know it, **Result**. Click **Save**.

You should see: the period in the indicator's table. **Progress** is a bar with **Met** when the
result reaches the target, or how far it got from the baseline, for example 50%.

To record a result later, click **Edit** on the period's row. Each indicator has one row for the
same start and end dates: the form tells you when the dates you pick are already used.

## To Use the Same Periods for Every Indicator

1. Under the columns, in **Reporting Periods**, click **Add Period**. Fill in **Period**, **Start
   Date** and **End Date**, and click **Save**. Repeat for each period (for example four quarters).
2. On a period's row, click **Add Period to Every Indicator**.
3. For an indicator added later, select its part and click **Use the Model's Periods** under the
   indicator.

You should see: a note saying how many indicators or periods were added, and the periods in each
indicator's table, ready for targets and results. An indicator that already had a period with the
same dates keeps its own. Removing a period from **Reporting Periods** leaves the indicators'
periods in place.

## To Fill In Results From a Spreadsheet

Under each indicator a line says where its results come from: **Typed In**, **Imported** or
**Computed**.

1. At the top of the builder click **Download Results Sheet**. It has one row per period of every
   indicator that is not computed.
2. Type each **Result** (and **Notes** if useful). Leave **Period Id** as it is.
3. Open **Import**, choose the **Indicator Results** template and load the file.

You should see: back in the builder, each period shows its new result and progress.

## To Refresh a Computed Indicator

A computed indicator's results are worked out from other records every night, so its **Result**
box cannot be typed in. Under the indicator the builder says when they were last worked out, or
what stopped them.

1. Click **Refresh Results** under the indicator. It says "Working out results".
2. Wait: the panel updates by itself when the results are in, usually within a few minutes. If it
   takes longer, click **Check Again**.

You should see: the periods that have started show new results, and a note that they are worked
out. Only an admin can change what an indicator counts (its **Source**). An admin can start a
computed indicator from a template such as **Services Delivered** or **Approved Volunteer Hours**
and the record it is about; BarnCRM builds the saved query in Find for them.

## To Compare Periods for a Funder

1. Scroll to **Logic Model Report** at the bottom of the builder.
2. Under **Periods to Compare**, tick the periods you want side by side. The latest four are
   ticked when the page opens.
3. Click **Download CSV** for a spreadsheet, **Download Printable Report** for a page to open
   in your browser and print, or **Download PDF** for a PDF file to send.

You should see: one row per indicator with its baseline and, for each period, the target, the
result and the progress. Periods with the same dates count as one, so name them the same way on
every indicator.

## To See What Needs Attention

**Things to Look At**, at the bottom of the builder, lists columns with nothing in them, parts with
no arrow in or out, and outcomes with no indicator. When nothing is listed, every part is linked
and every outcome is measured.

## Related Pages

- [Logic Models admin guide](../admin-guide/logic-models.md): turning the module on and giving
  access.
