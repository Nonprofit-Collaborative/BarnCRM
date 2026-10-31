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

Results are typed in by hand for now. Loading them from a file or working them out from other
records (L-03) and a logic model report that compares periods (L-04) come in a later release.

## How to Turn It On

### Before You Install

- Logic Models is offered in the **Nonprofit Edition** only (see [Editions](editions.md)).
- It needs BarnCRM Core and nothing else. With the Programs module installed, a model can be
  chosen for one program; without it, every model is the organization's.

### Installing

Install it from **Module Manager** (see [Module Manager](module-manager.md)). When the install
finishes, BarnCRM does three things on its own:

1. Creates the switch row for the module's automation on the **Automation** page.
2. Gives you, the person who installed it, the **Logic Models Admin** permission set.
3. Gives everyone who already has a BarnCRM role their Logic Models permission set (see below).

Then open the **BarnCRM Logic Models** app from the App Launcher. Its tab is **Logic Models**,
which also joins the BarnCRM apps.

Logic Models has no settings yet, so it adds no section to BarnCRM Settings.

### Roles and Permission Sets

You never assign the Logic Models permission sets by hand. Give people their BarnCRM role on the
[Access](access.md) page as usual, and the module gives each role its set:

| BarnCRM role | Logic Models set they get | What they can do |
|---|---|---|
| Admin (anyone holding BarnCRM Admin) | Logic Models Admin | Everything, including deleting a whole logic model |
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

The builder shows seven columns, in order: **Inputs**, **Activities**, **Outputs**, **Short Term
Outcomes**, **Intermediate Term Outcomes**, **Long Term Outcomes** and **Impact**. On a phone the
columns are stacked.

- Click **Add to** under a column (for example **Add to Inputs**), type a short name (for example "Two tutors" or "Weekly reading
  sessions"), and press **Save**. Add a longer **Description** if it helps.
- Click a part to select it. Its details open below the columns: change its name, description or
  column, or **Delete** it. Deleting a part removes its arrows and its indicators with their
  periods; the builder asks first.
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
arrow's assumption to change it, or **Remove** to delete the arrow.

### Things to Look At

Under the columns, the builder lists what usually needs attention in a model, as you build it:

- a column with nothing in it (activities, outputs, outcomes or impact),
- a part with no arrow in or out (an input needs an arrow out, an impact an arrow in, everything
  else both),
- an outcome with no indicator.

These are reminders, never errors: save as you go and come back.

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

Each period row shows its **Progress**: **Met** when the result reaches the target (for a Lower
indicator, when it is at or below the target), otherwise how far it has come from the baseline
toward the target, as a percent. A row with no result yet shows nothing.

You can add as many periods as you need, and they may overlap (a year and its four quarters).
The same start and end dates twice for one indicator are refused: change the row that is there.

A part with indicators cannot be moved to the Inputs, Activities or Impact column; delete or
move its indicators first.

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

## Common Mistakes

- **Adding indicators to an activity.** Indicators measure outputs and outcomes. Count the
  activity's results as an output (for example "Sessions held") and put the indicator there.
- **Linking backwards.** If the part you want is not in the arrow's list, it is in the same or an
  earlier column. Start the arrow from the earlier part instead.
- **Two models for the organization.** Each choice under **For** holds one model. Open the one
  that is there, or delete it first if it was a test.
- **Deleting a part to rename it.** Deleting removes its indicators and their results. Select the
  part and change its name instead.
- **Looking for the program in the model's fields.** The program is chosen with **Change** in the
  builder. The model's Program field holds an identifier BarnCRM fills in for you.
