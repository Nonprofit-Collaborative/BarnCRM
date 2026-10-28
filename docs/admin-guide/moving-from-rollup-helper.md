# Moving Rollups From Rollup Helper

Rollup Helper (by Passage Technology, managed namespace `rh2`) is a separate rollup tool. When
it is installed, the **Rollup Builder** tab says so under **Other Rollup Tools**, and so do the
Setup Assistant and the **Modules** section of BarnCRM Settings (see
[DLRS and Rollup Helper in the Same Org](rollups.md#dlrs-and-rollup-helper-in-the-same-org)).

BarnCRM does not import Rollup Helper's rollups. Their definitions are kept inside Rollup
Helper in a form BarnCRM cannot read reliably, so a copy could be wrong without anyone
noticing. For the same reason, the check that stops BarnCRM and DLRS filling the same field
cannot see Rollup Helper's rollups: you check that part yourself.

This page is the way to move them by hand, one rollup at a time. Nothing here changes Rollup
Helper until you switch its rollup off yourself.

## Before You Start

- Install BarnCRM Rollup Builder and give yourself the **Rollup Builder Admin** permission set
  and the Manage BarnCRM Settings permission.
- Work in a sandbox first if you can, then move the finished rollups to production with
  **Export to a file** and **Import from a file** (see
  [Moving Rollups to Another Org](rollups.md#moving-rollups-to-another-org)).
- Make a list of your Rollup Helper rollups from Rollup Helper's own screens: for each one, the
  object and field that shows the total, the records counted and the lookup that links them,
  the calculation (sum, count, maximum and so on), the field it reads, any filter, and whether
  it runs in real time or on a schedule.

## Move One Rollup

1. **Build it in the Rollup Builder, switched off.** On the **Rollup Builder** tab, click
   **New rollup** and work through the five steps with the values from your list. In the last
   step, **Check and save**, untick **Active** before you save, so BarnCRM does not write the
   field yet.
2. **Check the values agree.** Before saving, use **See it on a record** in the last step on a
   few records you know: it reads "Calculated: ... On the record now: ...", the total BarnCRM
   would write next to the value Rollup Helper wrote. If they differ, compare the filter and
   the calculation with Rollup
   Helper's and adjust. Common reasons: a filter written differently, blank values counted as
   zero, or records in the Recycle Bin (see **Include deleted and archived records**).
3. **Switch the Rollup Helper rollup off** in Rollup Helper. Do this before the next step, so
   the two tools never fill the field at the same time.
4. **Turn the BarnCRM rollup on.** In the list, switch **Active** on, then click **Recalculate**
   on its row to fill every record now.
5. **Check a few records again** a day later, after the nightly run.

Repeat for each rollup. When the last one is moved, you can remove Rollup Helper's triggers or
uninstall Rollup Helper whenever suits you; BarnCRM does not need it gone.

## What Does Not Move

- **Real time on objects BarnCRM does not own.** A total that counts a standard object or one of
  your own objects is recalculated every night until you turn on instant totals for that object
  (see [Instant Totals on Other Objects](rollups.md#instant-totals-on-other-objects)).
- **Anything the Builder cannot express.** If a Rollup Helper rollup needs something the five
  steps do not offer, keep it in Rollup Helper. The two tools can run side by side as long as
  they never fill the same field.
