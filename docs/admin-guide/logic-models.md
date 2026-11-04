# Logic Models

## What It Does

The BarnCRM Logic Models module lets your organization build its **logic model** in BarnCRM: what
you put in (**inputs**), what you do (**activities**), what that produces (**outputs**), what
changes for the people you serve (**outcomes**, short, intermediate and long term) and the
**impact** you work toward. Arrows link each part to the next, each with the **assumption** that
explains why one leads to the other. On every output and outcome you add **indicators**: how you
know it happened, with a unit, a baseline, and a target and a result for each period.

You can build one logic model for the whole organization and, if you like, one for each program.
Logic Models works on its own: you do not need the Programs module, and nothing here is about
program records until you choose a program for a model.

Each indicator's results are typed in by hand, loaded from a spreadsheet with BarnCRM Import, or
worked out every night from other records (for example service deliveries, volunteer hours or
gifts) through a query you save in Find (L-03). The **Logic Model Report** compares periods side by side
and downloads as a spreadsheet or a page to print for a funder (L-04).

## How to Turn It On

### Before You Install

- Logic Models is offered in the **Nonprofit Edition** only (see [Editions](editions.md)).
- It needs BarnCRM Core and nothing else. With the Programs module installed, a model can be
  chosen for one program; without it, every model is the organization's.

### Installing

Install it from **Module Manager** (see [Module Manager](module-manager.md)). When the install
finishes, BarnCRM does four things on its own:

1. Creates the switch row for the module's automation on the **Automation** page.
2. Adds the **Indicator Results** template to **Import** (see [Where Results Come
   From](#where-results-come-from)).
3. Gives you, the person who installed it, the **Logic Models Admin** permission set.
4. Gives everyone who already has a BarnCRM role their Logic Models permission set (see below).

Logic Models also has one nightly job, **Indicator Results** (3:30 AM), which works out computed
indicators. **Health Check** lists it with BarnCRM's other nightly jobs, and its **Schedule all
nightly jobs** fix schedules it.

Then open the **BarnCRM Logic Models** app from the App Launcher. Its tab is **Logic Models**,
which also joins the BarnCRM apps.

Logic Models has no settings yet, so it adds no section to BarnCRM Settings.

### Roles and Permission Sets

You never assign the Logic Models permission sets by hand. Give people their BarnCRM role on the
[Access](access.md) page as usual, and the module gives each role its set:

| BarnCRM role | Logic Models set they get | What they can do |
|---|---|---|
| Admin (anyone holding BarnCRM Admin) | Logic Models Admin | Everything, including deleting a whole logic model and choosing where an indicator's results come from |
| Coordinator | Logic Models Staff | Create logic models and build them: add, change and remove parts, arrows, indicators and periods; never deletes a whole model |
| Team Member | Logic Models Staff | The same as Coordinator |
| Read Only | Logic Models Read Only | Look at logic models, indicators and results |

The sets are given at install, when you give a role on the Access page (within a minute), when
you turn the module back on, and every hour with BarnCRM's access check, for roles given in
Setup. The module only ever gives a set; if someone leaves a role, remove their Logic Models set
in Setup under **Users**, **Permission Set Assignments**.

## Building a Logic Model

On the **Logic Models** tab click **New**, give the model a **Logic Model Name** (for example
"Our Theory of Change") and a **Description**, and save. The model opens with the **Logic Model
Builder** panel.

### Whose Model It Is

At the top of the builder, **For** says whose model this is: **The whole organization**, or a
program. With the Programs module installed, click **Change** and pick a program; pick **The
whole organization** to go back. Without Programs there is nothing to change.

There is one model for the organization and at most one for each program. Saving a second one
for the same choice is refused, with a message naming it, even if you cannot see the other model:
open the one that is there instead, or ask your admin.

### Parts

The builder draws the model left to right as seven columns, in order: **Inputs**, **Activities**,
**Outputs**, **Short Term Outcomes**, **Intermediate Term Outcomes**, **Long Term Outcomes** and
**Impact**, with an arrow between each column and the next. Each column heading shows how many
parts it holds, and each part is a small tile with up to two lines of its name (hover for the
whole name). On a phone the columns are stacked, with a downward arrow between them; on a narrow
desktop panel the diagram scrolls sideways.

- Click **Add to** under a column (for example **Add to Inputs**), type a short name (for example "Two tutors" or "Weekly reading
  sessions"), and press **Save**. Add a longer **Description** if it helps.
- Click a part to select it. Its details open below the columns and the page takes you there
  (focus moves to the details heading); **Back to the Model** at the top of the details takes you
  back to the part's tile. While a part is selected, the parts an arrow joins to it get a blue
  border and the others are dimmed, so its chain from input to impact stands out. In the details,
  change its name, description or column, or **Delete** it. Deleting a part removes its arrows
  and its indicators with their periods; the builder asks first, in a dialog with a red
  **Delete** button. Changing a part's column is refused when any arrow attached
  to it would then point backward (to the same or an earlier column). The message names each
  such arrow as "From to To" and says to delete those arrows first or pick a column that keeps
  every arrow forward. The builder checks before saving, and the server refuses the same move.
- Parts keep the order you add them in. Use **Move Up** and **Move Down** in a part's details to
  change it.

### Arrows and Assumptions

An arrow says that one part leads to another. Select a part, then under **Leads To** click **Add
Arrow**, choose the part it leads to and write the **Assumption**: why you believe it does (for
example "Students who attend twice a week read more at home"). Arrows only go forward, from a
column to a later one: an activity can lead to an output or an outcome, never back to an input,
and two parts in the same column are never linked. The list only offers parts an arrow may reach,
and the same arrow cannot be added twice.

Under **Comes From** the builder lists the arrows that point at the selected part. Click an
arrow's assumption to change it, or **Remove** to delete the arrow (the builder asks first).

### Things to Look At

Under the columns, the builder lists what usually needs attention in a model, as you build it:

- a column with nothing in it (activities, outputs, outcomes or impact),
- a part with no arrow in or out (an input needs an arrow out, an impact an arrow in, everything
  else both),
- an outcome with no indicator.

These are reminders, never errors: save as you go and come back. When nothing needs attention
the list is replaced by a green all-clear note.

When a save fails for a reason the builder cannot name, it says the logic model was not saved
and to try again; if it happens again, ask your BarnCRM admin to check the Error Log (the admin
finds the details there).

## Indicators, Baselines, Targets and Results

Indicators belong to **outputs** and **outcomes** only. Select one, then under **Indicators**
click **Add Indicator**:

- **Indicator Name**: what you measure, for example "Students reading at grade level".
- **Unit**: what a value counts, for example "students", "percent" or "sessions".
- **Better When**: **Higher** or **Lower**. Most indicators are better higher; pick Lower for one
  like "Emergency room visits".
- **Baseline** and **Baseline Date**: the value before the work started, and when it was
  measured.
- **Description**: how it is measured, so the next person measures it the same way.

Under each indicator, **Add Period** records a target and a result for one stretch of time:

- **Period**: the name you use, for example "2026 Q1" or "School year 2026-27".
- **Start Date** and **End Date** (an end before the start is refused).
- **Target** and **Result**, typed in, and **Notes** on what explains the result.

Each period row shows its **Progress** as a bar with the words beside it: **Met** (a full bar)
when the result reaches the target (for a Lower indicator, when it is at or below the target),
otherwise how far it has come from the baseline toward the target, as a percent. A row with no
result yet shows nothing. Targets and results are right-aligned and formatted as numbers. On a
phone each period row is stacked, one labelled value per line. Deleting a period or an indicator
asks first, in a dialog with a red **Delete** button.

You can add as many periods as you need, and they may overlap (a year and its four quarters).
The same start and end dates twice for one indicator are refused: change the row that is there.

A part with indicators cannot be moved to the Inputs, Activities or Impact column; delete or
move its indicators first.

### Reporting Periods

Most models report on the same stretches of time for every indicator (four quarters, a school
year). **Reporting Periods**, under the columns of the builder, keeps that list once for the
model so you do not type it into every indicator:

- **Add Period** adds a period to the list: a name and its start and end dates. The list is kept
  in start date order; a period with the same dates as another, or an end before its start, is
  refused, and a model has at most 60.
- **Add Period to Every Indicator** on a row gives that period (name and dates, no target or
  result) to every indicator in the model that does not already have one with the same dates.
  The note says how many indicators got it.
- **Use the Model's Periods**, under an indicator, gives that one indicator every period on the
  list it does not already have. Use it for an indicator added after the periods were shared.
- **Remove** takes a period off the list after a confirm. Periods already given to indicators
  stay, with their targets and results.

The list is a template, not a link: each indicator gets its own ordinary periods, which you then
fill in, change or delete one by one, and an indicator can still have periods of its own that are
not on the list. Shared dates are what line indicators up in the **Logic Model Report**. A Logic
Models Admin or Staff user changes the list; Read Only users see it.

## Where Results Come From

Each indicator shows its **Source** under its name. There are three, and only a Logic Models
Admin can change one: click **Source** under the indicator.

| Source | Where its results come from | Who fills in the result |
|---|---|---|
| **Typed In** (the default) | Typed into each period in the builder | Anyone who builds the model |
| **Imported** | A spreadsheet loaded with BarnCRM Import | Whoever loads the file (results can also be typed) |
| **Computed** | Worked out from other records, every night and on **Refresh Results** | Nobody: the builder shows the results read only |

### Imported Results

1. Add the indicator's periods (name and dates, and the target if you have one) in the builder.
2. At the top of the builder click **Download Results Sheet**. You get a spreadsheet with one row
   per period of every indicator that is not computed: **Period Id**, the model, part, indicator,
   unit, period and dates, then **Target**, **Result** and **Notes**.
3. Fill in **Result** (and **Notes** if you like). Leave **Period Id** alone: it is how BarnCRM
   finds the row's period. Delete rows you are not updating.
4. Open **Import**, choose the **Indicator Results** template and load the file. The dry run shows
   what will change; nothing is created, only the periods named are updated, and Import's
   results, journal and undo work as for any import. A row whose Period Id is not a period you can
   see is reported, not loaded.

### Computed Results

A computed indicator counts records you already keep. The quickest way is a starter; for anything
else you describe the records in **Find** and tell the indicator how to count them.

**Starters.** Click **Source** under the indicator and choose **Computed**. The **Template** box
offers the starters your org can use, then **Saved Query**:

| Template | Counts | Asks for | Offered when |
|---|---|---|---|
| **People Served by a Service** | Each person once (Count Unique of Contact), by Delivery Date, leaving out absences | The service (required) | Programs is installed |
| **Services Delivered** | Service deliveries, by Delivery Date, leaving out absences | The service (required) | Programs is installed |
| **Approved Volunteer Hours** | The total of Hours on approved volunteer hours, by Date Worked | A volunteer job, or **All** | Volunteers is installed |
| **Grants Awarded** | Grants at the Awarded stage, by Decision Date | A program, or **All** (where Programs is installed) | Funders is installed |

Pick the template and the record it is about, then **Save**. BarnCRM writes the saved query in
**Find** for you, named after the template and the record (for example "Services Delivered:
Tutoring"), as your own private query, then makes the indicator computed from it and works out its
results as below. The query is an ordinary saved query: open it in Find to read, share or change
it. A starter needs you to be able to save queries in Find and read its object and fields; if you
cannot, the builder says so and **Saved Query** still works.

**Your own query.** Choose **Saved Query** under **Template** (it is the only choice where no
starter's module is installed, and the one shown for an indicator already built from a query):

1. In **Find**, build and save a query of the records to count, for example service deliveries of
   the Reading service, or volunteer hours that were approved. Leave dates out of the filter: the
   indicator adds each period's dates itself. Share the query if other admins should be able to
   change it.
2. In the builder, click **Source** under the indicator, choose **Computed**, then **Saved Query**
   under **Template**.
3. Pick the **Saved Query**, then the **Date Field** that places a record in a period (for example
   Delivery Date).
4. Pick what to work out:
   - **Count**: how many records fall in the period.
   - **Sum**: the total of a number field, for example Hours.
   - **Count Unique**: how many different values of a field, for example the person on a service
     delivery, so a person served ten times counts once (an unduplicated count).
5. Save. The results are worked out within a few minutes, then every night at 3:30 AM. Click
   **Refresh Results** to work them out again now. While they are worked out the indicator says
   "Working out results"; the panel looks every ten seconds and shows the new results, with a
   note, as soon as they are in. If they take longer than three minutes it says so and offers
   **Check Again**. No page reload is needed.

Every period that has started gets a result, zero when no record falls in it; a period that has
not started yet is left blank. A record counts in every period that holds its date, so a year and
its quarters each get their own figure. Under the indicator the builder shows when the results
were last worked out, or, in a red notice, what stopped them (for example the saved query was
deleted, or a field in it can no longer be read). An unexpected failure says the results were not
worked out and to try again; the details are in the Error Log.

**Who sees what.** BarnCRM checks the query as the admin who saves the source: they must be able
to open the saved query and read its object and fields. The count itself includes every matching
record in the organization, including records the person who presses **Refresh Results** cannot
see (for example participants hidden by the participant privacy preset), so the result is the
organization's figure rather than one person's share. Only numbers are written, never names or
details, and only a Logic Models Admin can choose what is counted.

**Changing the query.** The indicator uses the saved query as it is when the results are worked
out, so editing the query in Find changes the next results, and deleting it stops them (the
builder says so). Choose another query under **Source**.

## The Logic Model Report

The **Logic Model Report** is at the bottom of the Logic Model Builder, under **Things to Look
At**, and changes as soon as you save in the builder. It shows one
row per indicator, in the builder's column and part order, with its baseline and, for each period
you choose, the target, the result and the progress (**Met** or a percent).

- **Periods to Compare** lists every period of the model's indicators, oldest first. Periods of
  different indicators with the same start and end dates count as one period, so name your
  periods the same way across indicators (for example "2026 Q1"). The latest four are chosen when
  the report opens.
- An indicator without a chosen period shows an empty cell for it. Numbers are right-aligned and
  formatted. The table is wide by design: on a narrow screen it scrolls sideways rather than
  stacking.
- **Download CSV** saves the report as a spreadsheet: Column, Part, Indicator, Unit, Better When,
  Baseline and Baseline Date, then a Target, Result and Progress column for each period.
- **Download Printable Report** saves one web page with the table and the model's name. Open it
  in your browser and print it, or print it to PDF, to send to a funder.

Everyone who can open the model can see and download its report, including Read Only users. The
report shows only what the person can read and stores nothing. Nothing needs setting up.

## With the Funders Module

When the Funders module is installed too, each grant requirement (a report or deliverable a
funder expects) can name the outcome or output it reports on, from a **Logic Model Outcomes** card
on the grant's page; the card shows that outcome's indicators with their targets and results for
the award period. Nothing changes in your logic models: the link is kept on the requirement, by
record ID, so neither module needs the other. See
[Funders](funders.md#outcomes-a-requirement-reports-on).

## A Five-Minute Walkthrough

Do this as Maria, who holds the Admin role.

1. Open the **BarnCRM Logic Models** app. On **Logic Models** click **New**, name it "Reading
   Program Model" and save. **For** shows **The whole organization**.
2. In the builder, add "Two tutors" under **Inputs**, "Weekly reading sessions" under
   **Activities**, "Sessions held" under **Outputs**, "Students read more at home" under **Short
   Term Outcomes** and "Every child reads at grade level" under **Impact**.
3. **Things to Look At** lists the empty columns and the parts with no arrows.
4. Select "Two tutors", click **Add Arrow**, choose "Weekly reading sessions" and type an
   assumption. Link "Weekly reading sessions" to "Sessions held", "Sessions held" to "Students
   read more at home", and that outcome to the impact.
5. Select "Weekly reading sessions" and click **Add Arrow** again: "Two tutors" is not offered,
   because arrows only go forward.
6. Select "Students read more at home", click **Add Indicator**, name it "Students reading 20
   minutes a day", unit "students", baseline 10, and save.
7. Under that indicator click **Add Period**: "2026 Q1", 1 January to 31 March 2026, target 30,
   result 20. **Progress** shows 50%. Change the result to 30: it shows **Met**.
8. On **Logic Models** click **New** again and save a second model without changing **For**. It
   is refused: the organization already has a model.
9. Select "Two tutors" and click **Delete**, then confirm. The part and its arrow are gone.
10. Click **Download Results Sheet**. Type 25 in the 2026 Q1 row's **Result**, save the file,
    and load it in **Import** with the **Indicator Results** template. Back in the builder the
    period shows 25.
11. In **Find**, save a query of Contacts named "All people". Select "Sessions held", add an
    indicator "People in our records", click **Source**, choose **Computed**, pick "All
    people", Date Field **Created Date**, **Count**, and save. Add a period covering this year:
    within a few minutes its result shows how many contacts were created this year, and the
    **Result** box is read only.
12. Scroll to **Logic Model Report**. Each indicator has a row with its baseline, and each chosen
    period its target, result and progress. Untick a period: its columns go. Click **Download
    Printable Report**, open the file and print it.

## Common Mistakes

- **Adding indicators to an activity.** Indicators measure outputs and outcomes. Count the
  activity's results as an output (for example "Sessions held") and put the indicator there.
- **Linking backwards.** If the part you want is not in the arrow's list, it is in the same or an
  earlier column. Start the arrow from the earlier part instead.
- **Two models for the organization.** Each choice under **For** holds one model. Open the one
  that is there, or delete it first if it was a test.
- **Deleting a part to rename it.** Deleting removes its indicators and their results. Select the
  part and change its name instead.
- **Putting dates in a computed indicator's Find query.** The indicator adds each period's dates
  itself; a date filter in the query leaves later periods at zero.
- **Typing a result into a computed indicator.** Its results are worked out every night, so the
  builder does not offer the box. Change the **Source** to **Typed In** first if you mean to
  type them.
- **Editing Period Id in the results sheet.** It is how Import finds the period; a changed or
  missing one is reported, not loaded.
- **Looking for the program in the model's fields.** The program is chosen with **Change** in the
  builder. The model's Program field holds an identifier BarnCRM fills in for you.
