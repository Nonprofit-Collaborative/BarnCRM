# Automation Control

## What It Does

BarnCRM does small pieces of work for you in the background: it creates a household
for a new person, keeps household names and greetings up to date, and so on. Automation
control is the page where you can see every one of those pieces of work, read what it
does, and switch it off if it is getting in your way.

It also gives you one big switch: pause everything for a couple of hours while you load a
spreadsheet, then let it turn itself back on. You never have to call anyone to get
unstuck.

A small number of automations are not switches at all. They enforce a rule rather than
doing something for you, and BarnCRM runs them whatever this page says. Today they all
come with the Giving module (the receipt lock on gifts is the first of them). They are still
listed here, so you can find them and
read what they do, but their switch is off, greyed out, and carries a line explaining that
the automation always runs. See "Automations that always run" below.

## How to Turn It On

Automation control is on as soon as BarnCRM is installed. There is nothing to enable
and nothing to install: installing or upgrading each package creates the switch for every
automation it ships, and leaves every switch you already have as you set it. If a switch is
ever missing, the automation still runs, and Health Check names it and offers to restore it.

You will find it in these places:

- **The Automation tab** in **BarnCRM Admin** and **BarnCRM Admin Console** (BarnCRM Admin
  only, D-184). This is the full page: the list of every automation with its on and off
  switch, the pause button, **Catch Up Now**, the people and profiles that pause or bypass
  automation, and your own flows.
- **BarnCRM Settings, then Automation.** The same panel, kept where admins already look for it.
- **The BarnCRM home page.** While automation is paused, a banner appears at the top
  of the home page telling you what is paused and when it will come back on.

Changing anything on this page requires the Manage BarnCRM Settings permission, which
comes with the BarnCRM Admin role. If you do not have it, the page still opens and you
can read everything, but the switches are greyed out and a message names the permission
you need to ask for.

## A Five-Minute Walkthrough

Maria is about to load a spreadsheet of 400 people from a partner organization. She wants
the records in first and the automatic housekeeping to happen afterwards, so nothing runs
400 times while she is watching.

1. Open the **BarnCRM Admin** app and click **BarnCRM Settings**.
2. In the left navigation, click **Automation**. You see a list of every piece of
   automation BarnCRM ships, each with a plain-language description and a switch.
3. At the top of the page, choose **2 hours** in the **How long** list, then click
   **Pause All Automation**. The page now shows a yellow bar: "Automation is paused until
   3:40 PM. Paused by Maria Lopez. It turns itself back on then." with a **Resume
   Automation** button inside it. **How long** and **Pause All Automation** are hidden while
   automation is paused, and **Resume Automation** shows only in that bar, so only the button
   that does something is ever offered. Every switch in the list is still where you left it:
   pausing does not change anything you have chosen.
4. Click **Home**. The same banner appears at the top of the Hub, so anyone else working
   today can see why records are not updating themselves.
5. Load your spreadsheet. Nothing runs automatically while you do.
6. Come back to **BarnCRM Settings**, then **Automation**, and click **Resume
   Automation** in the yellow bar. The banner disappears, **Pause All Automation** is back, and the automation starts running again on the next
   record anyone saves. If you forget this step, nothing breaks: automation turns itself
   back on at the two hour mark, and the change is recorded like any other (see "How long
   a pause lasts" below).
7. Now switch off a single automation instead. Find **Household upkeep when a person
   changes** in the list and click its switch to **Off**. Only that one stops running. For a
   few seconds a line next to the switch says "Household upkeep when a person changes is
   off. Turn it back on here." (a screen reader announces it).
   Everything else carries on.
8. Switch it back **On**. Every change you make here is recorded with your name, the time,
   and what the value was before, so you can always see who changed what.

That is the whole feature: one switch per automation, one switch for all of them, and it
expires by itself.

## How Long a Pause Lasts

You choose the length when you pause: 1, 2, 4, 8 or 24 hours. Two hours is already
selected, because most spreadsheet loads are done in less. There is no longer choice and no
"until I say so": a pause always ends by itself.

When the time is up, automation starts again at that moment, whether or not anybody has the
page open. BarnCRM also writes the end of the pause into the list of recent changes at the
bottom of BarnCRM Settings, with the time it ended and the name of the person who paused, as
if they had clicked **Resume Automation** themselves. So the list always shows every pause
with its start and its end.

Clicking **Resume Automation** early, or pausing again to get more time, replaces the
scheduled end: the new length counts from the moment you click.

If Health Check says **Automation Is Paused with No Automatic Resume**, a pause is in effect
that nothing is set to end: usually one started before this version of BarnCRM, or one
set somewhere other than this page. Open this page, click **Resume Automation**, and pause
again for a set time if you still need to.

## Automations That Always Run

Pause stops BarnCRM filling things in for you. It never stops BarnCRM refusing
something. An automation whose job is to refuse a change, rather than to save you typing,
is marked as always running, and neither the pause nor its own switch turns it off.

In the list you can tell one at a glance: its switch sits at **Off** and is greyed out even
when you hold the Manage BarnCRM Settings permission, and underneath the description is
the line "This automation enforces a rule, so it always runs. It cannot be switched off
here and a pause does not suspend it." Clicking the switch does nothing, and if a change
somehow reaches the server it is refused with the same explanation.

Three ship today, all with the Giving module, so an org with Core alone has none:

- **Gift: receipt lock** refuses a change to the amount, the date, the donor or the receipt
  number of a gift that carries a receipt number, and refuses to delete such a gift. That
  rule is what a receipt in a donor's hands means: see the [Gifts page](gifts.md).
- **Gift: posting lock** and **Gift Allocation: posting lock** refuse a change to a gift that
  is posted to accounting or dated in a closed period, and to its funds, and refuse a new gift
  in a closed period. See [Posting and Closed Periods](posting-and-closed-periods.md); that
  lock has its own override, Override Posting Lock.

With Giving, if you genuinely have to change a receipted gift, there is a way, and it is deliberately
not on this page. It is the Override Receipt Lock permission, described under "Lifting the
receipt lock" on the [Gifts page](gifts.md). Every change made with it is written to the
[Error Log](error-log.md).

## When Automation Fails on One Record

If BarnCRM's automation fails on one record of a larger save, only that record is refused. The
rest of the save goes ahead. This matters most for the Data Loader, the BarnCRM importer and
integrations, which save 200 records at a time: one record BarnCRM cannot handle no longer costs
the other 199 their save.

- The refused record carries the message "Something went wrong while BarnCRM was updating this
  record, so it was not saved." In the Data Loader it is in the error file; in the importer it
  is on the row.
- The [Error Log](error-log.md) has one entry for the failure itself, with the technical
  detail, and one entry per refused record naming its row in the save. Fix the value it names
  and save that record again.
- To find the record, BarnCRM undoes the failed attempt and runs its automation again over
  smaller and smaller parts of the save. That takes a little longer than a clean save. If the
  save has too little room left in Salesforce's limits to do it, the records not yet cleared are
  refused together, still with the message and the log entries.
- A rule that always runs (see above) is the exception: if it fails, every record in front of
  it is refused, because a rule that could not be checked lets nothing through.

## Pausing or Bypassing for Some People

The timed pause stops automation for everyone. When only some people's saves should skip it,
use the **BarnCRM Automation Control** setting. It has two boxes, and each can be set for the
whole organization, for a profile, or for one user. The value that applies to a save is the
saving person's own, else their profile's, else the organization's.

- **Bypass**: for an integration user (or its profile) and a migration consultant. Their saves
  skip BarnCRM automation, while everyone else's run as normal.
- **Pause All**: the long pause. Set for the whole organization, it stops automation for
  everyone until you turn it off, for a migration that takes longer than the 24-hour pause.
  Set for a profile or a user, BarnCRM treats it like Bypass.

Rules that always run (see above) still run, whatever the setting says. The timed pause, the
switches on this page and this setting all apply together: automation runs only when none of
them stops it.

You set it on this page, in **Pause or Bypass for Some People**; there is nothing to do in
Setup. The section lists:

- **Whole Organization** first, always, with both boxes off until you change them. Ticking
  **Pause All** here pauses automation for everyone until you untick it. While it is on, a
  yellow bar at the top of the page says so, with a **Turn Off** button.
- then each profile and each user that has its own row, with their **Pause All** and
  **Bypass** boxes and a **Remove** button.

To add one, choose **Profile** or **User** under **Add a Profile or User**, pick the profile or
the person, and select **Add**. The new row starts with **Bypass** ticked, the usual reason to
add one; change either box at any time. Each box saves as soon as you click it, and every
change is recorded with your name and the value before, like the switches below (the
organization's row is recorded as "Automation Control: Whole Organization"). **Remove**
deletes the row, so that profile or person follows the organization's row again.

A profile or user row replaces the organization's row for those people, both boxes together.
So a row with both boxes off keeps automation running for them even while **Pause All** is on
for the whole organization: use that to keep, say, your own admin profile running during a
long pause.

### Using It in Your Own Flows, Triggers and Validation Rules

Your own automation can follow the same setting, so one place pauses or bypasses everything
your organization has:

- **A validation rule or formula:** add `NOT($Setup.BarnCRM_Automation_Control__c.Bypass__c) &&`
  in front of the condition, or check `Pause_All__c` the same way.
- **A flow:** start it with a **Decision** on
  `{!$Setup.BarnCRM_Automation_Control__c.Pause_All__c}` or `Bypass__c` equals true, ending the
  flow on that outcome, as every BarnCRM flow template does. To follow the timed pause and a
  switch on this page as well, start it with the **Check BarnCRM Automation** action instead
  and end the flow when **Run** is false.
- **An Apex trigger:** read `BarnCRM_Automation_Control__c.getInstance()` and return early when
  `Pause_All__c` or `Bypass__c` is true.

### Listing Your Own Flows on This Page

In **Your Own Flows**, pick one of your organization's active flows and select **Add**. It joins
the list of automations with its own switch, named `Flow:` and the flow's API name (for example
`Flow:My_Gift_Flow`), and its description says the same. **Remove** takes it off the list
again. Listing or removing a flow never activates, deactivates or changes the flow itself.

The switch works when your flow starts with the **Check BarnCRM Automation** action, with
**Automation Name** set to that same name, and ends when **Run** is false. Then switching it
off here stops the flow, and so do the timed pause and the BarnCRM Automation Control setting.
A listed flow that does not call the action is on the list for the record only: its switch
does nothing.

### Catching Up After a Pause or a Bypassed Load

BarnCRM does not record each save it skipped, so nothing is replayed record by record. When
the timed pause ends, by itself or with **Resume Automation**, BarnCRM gives a household to
every person added without one and works the rollup totals that waited. After a long Pause All
or a bypassed load, select **Catch Up Now** on this page once automation runs again: it does
the same, and also recomputes every household's name and greetings (a household marked as a
custom name keeps its wording). It runs in the background, and the page says it has started.
Selecting it again while a catch-up is still waiting or running does nothing but say "A
catch-up is already running", so two runs never overlap.
Anything else that was skipped (a preferred email or phone copied to the
standard field, an address copied to its household, the other side of a relationship) is caught
up by saving those records again, for example with **Bulk Update** changing nothing but a
harmless field.

## Every Automation in This Org

Below the Automation panel, the **Automation** tab has an **Automation Inventory** card: one
table of every automation in the org (C-60, D-184).

- **What is listed:** BarnCRM's automations with their switch (On, Off or Always Runs), every
  record-triggered, scheduled and platform event flow and every Process Builder process, active
  or inactive, and every Apex trigger, active or inactive.
- **Owner:** BarnCRM, **This Org** (your own), or a managed package's namespace.
- **Covered by Pause All:** **Yes** when the BarnCRM Automation Control setting (Pause All and
  Bypass) stops it: BarnCRM's automations and flow templates, and your own triggers whose code
  checks the setting. **No** for automations that always run, BarnCRM's error recording, a
  managed package's flows and your triggers that do not check it. **Not Checked** for your own
  flows until a scan (below) has read whether they call Check BarnCRM Automation.
- **How to Make This Respect Pause All:** the row menu of your own automation that is not
  covered shows what to add, ready to copy: the Check BarnCRM Automation action and Decision for
  a flow, the Apex lines for a trigger, the wrapped formula for a validation or workflow rule.
- **Object** and **Owner** filter the table; **Download CSV** saves what is shown;
  **Refresh** reads it again.

It is read as you, with the same queries the Data Dictionary uses, and needs the Manage BarnCRM
Settings permission. A very large org is capped at 2,000 flows and 500 triggers, and the card
says so.

### Scan Org Automation

Validation rules, workflow rules and whether your own flows call Check BarnCRM Automation can
only be read through Salesforce's Tooling API. **Scan Org Automation** reads them through the
org connection, the same one-time connection Super Importer uses to create a field (see
[Creating a New Field From an Import](import-new-fields.md): Set Up Connection, then
Enabled for Callouts in Setup). Until it is set
up, the card shows the connection's status and **Set Up Connection** to anyone who may use it.

Using the connection needs the **BarnCRM Metadata Admin** permission set, Customize Application
and Modify Metadata. The scan runs in the background; the card says it is scanning and updates
when it finishes, then shows when it last scanned. After a scan:

- Your validation rules and workflow rules join the table (a workflow rule's active state is
  not read). A rule whose formula reads the BarnCRM Automation Control setting is **Yes**.
- Each of your own flows is **Yes** when it uses Check BarnCRM Automation or reads the setting,
  otherwise **No**.

Only the newest scan is kept. Scan again after you change your automation.

## Running Your Own Version Instead

If an automation does almost what you want, do not change ours: an upgrade would undo your
change. Switch ours off here and run your own copy. For most of the automations a flow can
do, BarnCRM ships a flow template you copy and change: see
[Your own version of an automation](flow-templates.md). That page also lists the automations
with no template, and why.

## Common Mistakes

- **Expecting the pause to last longer than 24 hours.** It cannot. For a load that runs
  over several days, pause again each morning, or switch off only the automation that is
  in your way: a switch stays where you put it.
- **Pausing and forgetting, then wondering why names are wrong.** While automation is
  paused, new people do not get households and names are not recomputed. The records are
  fine, they are just not finished. Resume automation and then re-save the records, or run
  the recompute action on the People and Households page.
- **Expecting the pause to suspend everything.** It does not, and it never did what its
  name suggests for the rules that refuse a change. The pause stops the housekeeping:
  households, names, greetings (and, with Giving, default allocations). An automation marked
  as always running keeps running through the pause: with Giving, a receipted gift stays
  locked while everything else is paused for your import.
- **Expecting pause to undo work already done.** Pause stops future automation. It does
  not roll back anything that already ran. If something ran that you did not want, fix the
  records themselves.
- **Switching an automation off to stop an error, and never switching it back on.** An
  automation that is off is a piece of your setup that has quietly stopped working. Look at
  the Error Log first: it usually tells you what to fix in the data, and then you can leave
  the automation on. See the [Error Log page](error-log.md).
- **Assuming a pause covers other people's work.** The pause is for the whole organization,
  not for you alone. Anyone saving a record during the pause gets the same behavior, so say
  something in your team channel before you pause during working hours.
- **Looking for the switches with the wrong role.** If the switches are greyed out, you are
  signed in as a user without the Manage BarnCRM Settings permission. Ask whoever
  administers your Salesforce to give you the BarnCRM Admin role.
