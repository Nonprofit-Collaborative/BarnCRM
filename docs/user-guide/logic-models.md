# Logic Models

This page covers building a logic model in BarnCRM: the parts of your program from what you put
in to the change you hope for, the arrows between them, and the indicators that measure your
outputs and outcomes, with a target and a result for each period.

**Before you start:** open the **BarnCRM Logic Models** app from the App Launcher. Program Staff
and Coordinators build models and can delete parts, but not a whole model. Admins can also delete
a whole model. Read Only users can look but change nothing. If you need more access, ask your
admin (see the [Logic Models admin guide](../admin-guide/logic-models.md#roles-and-permission-sets)).

Your organization has one logic model for the whole organization, and at most one for each
program.

## To Start a Logic Model

1. Click the **Logic Models** tab, then **New**.
2. Type a **Name**, for example "Reading Program Model", and click **Save**.

You should see: the model's page with the **Logic Model Builder** panel. **For** shows **The whole
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
4. Click **Delete**, then **Delete** again in the dialog to confirm. Its arrows, and its
   indicators with their periods, are deleted too.

## To Draw an Arrow

An arrow says one part leads to another, and the assumption says why you believe it does.

1. Click the part the arrow starts from.
2. Under **Leads To**, click **Add Arrow**.
3. Choose the **Part It Leads To**. Only parts in later columns are offered.
4. Type the **Assumption**, for example "Students who attend twice a week read more at home", and
   click **Save**.

To change an assumption, click **Edit** beside the arrow. To remove an arrow, click **Remove**,
then **Remove** in the dialog.
Arrows into the part are listed under **Comes From**.

## To Measure an Output or Outcome

1. Click the output or outcome. Its **Indicators** show below its arrows.
2. Click **Add Indicator**. Fill in **Indicator Name**, and if useful **Unit**, **Better When**
   (**Higher** or **Lower**), **Baseline** and **Baseline Date**. Click **Save**.
3. Under the indicator, click **Add Period**. Fill in **Period** (for example "2026 Q1"), **Start
   Date**, **End Date**, **Target** and, once you know it, **Result**. Click **Save**.

You should see: the period in the indicator's table. **Progress** is a bar with **Met** when the
result reaches the target, or how far it got from the baseline, for example 50%.

To record a result later, click **Edit** on the period's row. Each indicator has one row for the
same start and end dates.

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
out. Only an admin can change what an
indicator counts (its **Source**).

## To Compare Periods for a Funder

1. Scroll to **Logic Model Report** at the bottom of the builder.
2. Under **Periods to Compare**, tick the periods you want side by side. The latest four are
   ticked when the page opens.
3. Click **Download CSV** for a spreadsheet, or **Download Printable Report** for a page to open
   in your browser and print, or save as a PDF.

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
