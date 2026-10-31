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

The builder has seven columns: **Inputs**, **Activities**, **Outputs**, **Short Term Outcomes**,
**Intermediate Term Outcomes**, **Long Term Outcomes** and **Impact**.

1. Under a column, click **Add to** and the column's name (for example **Add to Inputs**).
2. Type a short **Name** and click **Save**.

You should see: the part at the bottom of its column.

## To Change, Move or Delete a Part

1. Click the part. Its details open below the columns.
2. Click **Edit** to change its **Name**, **Description** or **Column**, then **Save**. A part with
   indicators can only move to another output or outcome column.
3. Click **Move Up** or **Move Down** to change its place in its column.
4. Click **Delete**, then **Delete** again to confirm. Its arrows, and its indicators with their
   periods, are deleted too.

## To Draw an Arrow

An arrow says one part leads to another, and the assumption says why you believe it does.

1. Click the part the arrow starts from.
2. Under **Leads To**, click **Add Arrow**.
3. Choose the **Part It Leads To**. Only parts in later columns are offered.
4. Type the **Assumption**, for example "Students who attend twice a week read more at home", and
   click **Save**.

To change an assumption, click **Edit** beside the arrow. To remove an arrow, click **Remove**.
Arrows into the part are listed under **Comes From**.

## To Measure an Output or Outcome

1. Click the output or outcome. Its **Indicators** show below its arrows.
2. Click **Add Indicator**. Fill in **Indicator Name**, and if useful **Unit**, **Better When**
   (**Higher** or **Lower**), **Baseline** and **Baseline Date**. Click **Save**.
3. Under the indicator, click **Add Period**. Fill in **Period** (for example "2026 Q1"), **Start
   Date**, **End Date**, **Target** and, once you know it, **Result**. Click **Save**.

You should see: the period in the indicator's table. **Progress** shows **Met** when the result
reaches the target, or how far it got from the baseline, for example 50%.

To record a result later, click **Edit** on the period's row. Each indicator has one row for the
same start and end dates.

## To See What Needs Attention

**Things to Look At**, at the bottom of the builder, lists columns with nothing in them, parts with
no arrow in or out, and outcomes with no indicator. When nothing is listed, every part is linked
and every outcome is measured.

## Related Pages

- [Logic Models admin guide](../admin-guide/logic-models.md): turning the module on and giving
  access.
