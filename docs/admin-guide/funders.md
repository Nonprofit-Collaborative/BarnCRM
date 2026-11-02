# Funders

## What It Does

The BarnCRM Funders module tracks the grants your organization asks for and wins. Each **grant**
is one request to one **funder** (a foundation, company or government body, stored as an
organization): how much you asked for, its **stage** from first idea to the decision, the
application deadline, the decision date, how much was awarded and the award period. The **Grant
Pipeline** tab shows every open request by stage with the totals, lets you move a request on, and
lists the deadlines coming up.

If you also use the Programs module, a grant can name the program it pays for.

An award's **requirements** (the reports and deliverables the funder expects) each have a due
date and the staff member doing them, and BarnCRM reminds that person with a task and an email
before each is due. Restricted fund tracking (F-03), government award fields, multi-year award
schedules, a funder report template, a board dashboard and a deadline calendar come in later
releases.

## Before You Install

- Funders is offered in the **Nonprofit Edition** only (see [Editions](editions.md)).
- It needs BarnCRM Core, the Rollup Builder module and Giving installed first. Release 0.16 uses
  nothing in Giving yet; restricted fund tracking (F-03) and award schedules (F-05) will.
- It does not need the Programs module. With Programs installed, a grant can name a program.

## Installing

Install it from **Module Manager** (see [Module Manager](module-manager.md)). When the install
finishes, BarnCRM does three things on its own:

1. Creates the switch rows for the module's automations on the **Automation** page.
2. Gives you, the person who installed it, the **Funders Admin** permission set.
3. Gives everyone who already has a BarnCRM role their Funders permission set (see below).

Then open the **BarnCRM Funders** app from the App Launcher. Its tabs are **Grant Pipeline**,
**Grants**, **Grant Requirements**, **Reports** and **Error Log**; Grant Pipeline and Grants also
join the BarnCRM apps. Run Health Check's **Schedule all nightly jobs** fix once to start the
morning reminder job (see [Reminders](#reminders)).

## Roles and Permission Sets

You never assign the Funders permission sets by hand. Give people their BarnCRM role on the
[Access](access.md) page as usual, and the module gives each role its set:

| BarnCRM role | Funders set they get | What they can do |
|---|---|---|
| Admin (anyone holding BarnCRM Admin) | Funders Admin | Everything, including deleting a grant |
| Fundraising Staff (Giving) | Funders Staff | Create and edit grants and move them through the stages; never delete a grant |
| Team Member | Funders Staff | The same as Fundraising Staff |
| Coordinator | Funders Staff | The same as Fundraising Staff |
| Read Only | Funders Read Only | Look at grants and the pipeline |

The sets are given at install, when you give a role on the Access page (within a minute), when
you turn the module back on, and every hour with BarnCRM's access check, for roles given in
Setup. The module only ever gives a set; if someone leaves a role, remove their Funders set in
Setup under **Users**, **Permission Set Assignments**.

Grants are shared with everyone who has a Funders set (Public Read/Write), because a small team
works one pipeline together. To keep each person's grants to themselves, set **Grant** to
Private in Setup, **Sharing Settings**; the board's **Everyone** view then shows only the grants
each person can see.

## Grants

On the **Grants** tab click **New** and fill in:

| Field | What to put |
|---|---|
| Grant Name | What you call it, for example "2027 Literacy Grant". |
| Funder | The organization you are asking. Required. Use the organization's own record, the one its gifts are on. |
| Funder Contact | The program officer, if you know one. |
| Stage | Where it stands (see below). Starts at Prospect. |
| Amount Requested, Amount Awarded | What you asked for, and what they gave. |
| Application Deadline | When the application or letter of inquiry is due. |
| Submitted Date, Decision Date | Filled in for you as the stage moves, or type them. |
| Award Start Date, Award End Date | The award period, once awarded. |
| Purpose | What the money is for, in words you can reuse in a report. |
| Next Step | The next thing to do. |
| Owner | The staff member responsible. |

### Stages

| Stage | Means | Open or closed |
|---|---|---|
| Prospect | A funder worth asking; nothing sent yet | Open |
| Letter of Inquiry | A letter of inquiry is being written or has been sent | Open |
| Invited to Apply | The funder asked for a full application | Open |
| Applied | The application went in; waiting for the decision | Open |
| Awarded | The funder said yes | Closed |
| Declined | The funder said no | Closed |
| Withdrawn | You stopped pursuing it | Closed |

The stages are the same in every organization, so they are not a setting. Moving a grant to
**Applied** fills an empty **Submitted Date** with today; moving it to **Awarded**, **Declined**
or **Withdrawn** fills an empty **Decision Date**. A date you typed is kept. To load past grants
with their own dates, switch **Grant: fill in the stage dates** off on the **Automation** page
while you import, then on again.

Changes to Stage, Amount Requested and Amount Awarded are kept in the grant's history.

### A Funder With Grants Is Kept

Salesforce refuses to delete an organization that has grants, and lists them. Merging two
organizations moves the grants to the one you keep.

### The Program a Grant Pays For

With the Programs module installed, the grant's page has a **Program** card. Choose the program
from the list and click **Save**; choose **No program** to clear it. Without Programs the card
says that programs are not installed and there is nothing to choose. The grant stores the
program's record ID, so Funders works without Programs; if the program is later deleted, the card
says the program cannot be found and you can choose another.

## The Grant Pipeline Tab

The **Grant Pipeline** tab is where most people work:

- **Totals** at the top: open requests and the amount requested, and grants awarded this fiscal
  year with the amount awarded.
- **Board**: one column per open stage, each with its count and amount, and a card per grant
  showing the funder, the amount requested, the deadline and the owner. Click a card's menu to
  open the grant or move it to another stage. Moving to **Awarded** asks for the amount awarded
  (the amount requested is filled in for you).
- **Everyone** or **Mine**: all open grants, or only those you own.
- **Upcoming Deadlines**: every open grant whose application deadline is past or within the next
  60 days, and every open requirement due in that time or overdue, soonest first, with overdue
  ones marked. A requirement row has a **Mark Submitted** button.

Moving and the menu's stage choices are offered only to people who can edit grants, and **Mark
Submitted** only to people who can change requirements.

## Grant Requirements

An award usually comes with things to send back: an interim and a final report, a financial
report, a deliverable, a site visit. Record each one as a **grant requirement**: on the grant's
page, in the **Requirements** list, click **New**:

| Field | What to put |
|---|---|
| Requirement Name | What is due, for example "Year 1 interim report". |
| Type | Narrative Report (the default), Financial Report, Deliverable, Site Visit or Other. |
| Due Date | When the funder expects it. Required. |
| Status | Not Started (the default), In Progress, Submitted, Accepted or Waived. |
| Assigned To | The staff member doing it. Reminders go to them. |
| Instructions | What the funder asks for: the template, the portal, the questions. |
| Submitted Date | Filled in with today when the status becomes Submitted or Accepted, unless you typed a date. |
| Reminder Sent For | Set by BarnCRM: the due date the last reminder was made for. |

Not Started and In Progress are open; Submitted, Accepted and Waived are done. The automation
**Requirement: fill in the submitted date** on the [Automation](automation-control.md) page fills in the
Submitted Date; switch it off while you load past requirements with their own dates.

A requirement belongs to its grant: whoever can see the grant sees its requirements, and deleting
the grant deletes them. Funders Staff can create, edit and delete requirements.

## Reminders

Every morning at 6:00 AM in your org time zone, BarnCRM reminds each open requirement due within
the next 14 days (you can change this), or up to 30 days overdue, that has not been reminded for
its current due date:

- **A task** for the person in **Assigned To**, or the grant's owner when nobody is assigned or
  the person assigned is inactive. The task is on the grant, due on the requirement's due date.
- **An email**, once you turn **Email Reminders** on, to the same person, with a link to the grant. It goes to their Salesforce user, so
  it does not count against your org's daily limit for outside addresses.

Each due date is reminded once. If the funder moves the date and you change **Due Date**, the new
date is reminded again. When nobody active can be reminded, nothing is sent, and Health Check
still lists the requirement once it is overdue.

The job is called **BarnCRM Grant Reminders**. Health Check's **Schedule all nightly jobs** fix
schedules it with BarnCRM's other nightly jobs; it shows on the nightly jobs list as **Grant
Requirement Reminders, 6:00 AM**. It does nothing while Funders is turned off or both reminder
settings are off.

## Settings

Open **BarnCRM Settings**, **Funders** (under Fundraising). Each setting saves for the whole
organization.

| Setting | Default | What it does |
|---|---|---|
| Create Reminder Tasks | On | Makes the reminder task. |
| Email Reminders | Off | Also sends the reminder email. |
| Days Before a Deadline to Remind | 14 | How many days before a requirement is due its reminder goes out, from 1 to 90. |

Tasks ship on, because a missed funder report can cost the next award and a task goes only to the
person doing the work. Emails ship off, like shift and pledge reminders: BarnCRM sends no email
until you turn it on.

## Health Check

With Funders installed, [Health Check](health-check.md) asks two more questions, shown only to
people who can manage BarnCRM Settings and not while Funders is turned off:

| Finding | Severity | What it means | What to do |
|---|---|---|---|
| **Grant applications are past their deadline** | Information | Open grants at Prospect, Letter of Inquiry or Invited to Apply whose Application Deadline has passed. | Open each linked grant: move it to Applied if it went in, set Withdrawn if you did not apply, or move the deadline if the funder extended it. |
| **Grant requirements are overdue** | Information | Requirements still Not Started or In Progress whose Due Date has passed. | Open each linked requirement: mark it Submitted if it went in, Waived if the funder excused it, or move the due date if the funder agreed a new one. |

## Sample Data

**Load Sample Data** in BarnCRM Settings also loads three sample grants to Core's sample
organizations (one Applied, one Awarded, one Prospect) and three requirements on the award, and
**Remove Sample Data** takes them away again. See [Sample data](sample-data.md).

## Turning It Off

Turning Funders off in Module Manager stops its automations, its reminders and its Health Check
questions; the records stay. No Funders set is given while it is off.

## A Five-Minute Walkthrough

Do this as Maria, who holds the Admin role, with a second user, Dana, who has none yet.

1. On the [Access](access.md) page, give Dana the **Fundraising Staff** role.
2. In Setup, open Dana's user record and look at **Permission Set Assignments**. Within a minute
   she holds **Funders Staff**.
3. Open the **BarnCRM Funders** app. On **Grants**, create "2027 Literacy Grant" for any
   organization, **Amount Requested** 25,000, **Application Deadline** two weeks from today.
4. Open **Grant Pipeline**. The grant is in the **Prospect** column, and in **Upcoming
   Deadlines**.
5. From the card's menu choose **Move to Applied**. Open the grant: **Submitted Date** is today.
6. Back on the board, choose **Move to Awarded** and accept 25,000. The grant leaves the board and
   **Awarded This Fiscal Year** shows 25,000; its **Decision Date** is today.
7. Try to delete the organization. Salesforce refuses and names the grant.
8. On the grant's **Requirements** list click **New**: "Year 1 report", due in 5 days, **Assigned
   To** Dana. On **Grant Pipeline** it shows under **Upcoming Deadlines** with **Mark Submitted**.
9. The next morning Dana has a task "Year 1 report due for 2027 Literacy Grant" (and an
   email, if you turned **Email Reminders** on).
   Click **Mark Submitted**: the row leaves the list and the requirement's **Submitted Date** is
   today.

## Common Mistakes

- **Making a funder a household or a person.** A funder is an organization; record the family
  foundation as an organization, with the family members as its contacts.
- **Deleting a declined request.** Set Declined instead: the history is what tells you whom to ask
  again and when.
