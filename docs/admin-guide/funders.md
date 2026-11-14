# Grants

## What It Does

The BarnCRM Grants module (its app is also named **BarnCRM Grants**) tracks the grants your organization asks for and wins. Each **grant**
is one request to one **funder** (a foundation, company or government body, stored as an
organization): how much you asked for, its **stage** from first idea to the decision, the
application deadline, the decision date, how much was awarded and the award period. The **Grant
Pipeline** tab shows every open request by stage with the totals, lets you move a request on, and
lists the deadlines coming up.

If you also use the Programs module, a grant can name the program it pays for.

An award's **requirements** (the reports and deliverables the funder expects) each have a due
date and the staff member doing them, and BarnCRM reminds that person with a task (and, if you
turn it on, an email) before each is due.

A multi-year award's **payments** form its schedule, built in one step and marked received as the
money comes in. A **restricted** grant keeps a simple ledger of the money received, spent and
released, with its balance; received payments enter it on their own. The **Grant Calendar** tab
shows every deadline and expected payment on a month calendar. A grant also carries the fields a
government award needs (see [Government Awards](#government-awards)), and the [Answer
Library](#answer-library) keeps the application answers you reuse. A [funder report
template](#funder-report-templates) turns a grant into a printable report, and the [Board
Dashboard](#the-board-dashboard-tab) shows your board the year's revenue mix, how concentrated it
is and the restricted balances.

To find and manage grants, the [Grant Finder](#the-grant-finder-tab) searches open federal
opportunities on Grants.gov and saves one as a prospect, [application
checklists](#application-checklists) add the same steps to every grant at each stage, the
[Documents](#grant-documents) card keeps letters of inquiry, applications and reports with their
files, the [Budget](#budget-lines) card compares the budget asked for with the award and the
spending, and [Renewals](#renewals) remind you before a renewable award ends and start next
year's application from it.

## Before You Install

- Grants is offered in the **Nonprofit Edition** only (see [Editions](editions.md)).
- It needs only BarnCRM Core installed first.
- It does not need the Programs, Giving or Logic Models modules. With Programs installed, a grant
  can name a program; with Giving installed, it can name the Giving fund its money is booked to,
  and the Board Dashboard reads Giving's totals.

## Installing

Install it from **Module Manager** (see [Module Manager](module-manager.md)). When the install
finishes, BarnCRM does three things on its own:

1. Creates the switch rows for the module's automations on the **Automation** page.
2. Gives you, the person who installed it, the **Grants Admin** permission set.
3. Gives everyone who already has a BarnCRM role their Grants permission set (see below).

Then open the **BarnCRM Grants** app from the App Launcher. It opens on the **Board Dashboard**,
the module's home. Its tabs are **Board Dashboard**, **Grant Pipeline**, **Grant Calendar**,
**Grant Finder**, **Grants**, **Grant Requirements**, **Grant Answers**,
**Funder Report Templates** (admins only), **Grant Checklist**, **Reports** and **Error Log**; Grant Pipeline and
Grants also join the BarnCRM apps. The morning reminder job is a step of
[BarnCRM Nightly Jobs](nightly-jobs.md), which a new install schedules; if Health Check says
the nightly run is not scheduled, run its **Schedule all nightly jobs** fix once (see
[Reminders](#reminders)).

## Roles and Permission Sets

You never assign the Grants permission sets by hand. Give people their BarnCRM role on the
[Access](access.md) page as usual, and the module gives each role its set:

| BarnCRM role | Grants set they get | What they can do |
|---|---|---|
| Admin (anyone holding BarnCRM Admin) | Grants Admin | Everything, including deleting a grant |
| Fundraising Staff (Giving) | Grants Staff | Create and edit grants and move them through the stages; add, change and remove requirements, payments and restricted fund entries; never delete a grant |
| Team Member | Grants Staff | The same as Fundraising Staff |
| Read Only | Grants Read Only | Look at grants, the pipeline and the calendar |

The sets are given at install, when you give a role on the Access page (within a minute), when
you turn the module back on, and every hour with BarnCRM's access check, for roles given in
Setup. The module only ever gives a set; if someone leaves a role, remove their Grants set in
Setup under **Users**, **Permission Set Assignments**.

Grants are shared with everyone who has a Grants set (Public Read/Write), because a small team
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
| Funding Source | What kind of funder: Foundation, Corporate, Federal, Federal Pass-Through, State, Local Government or Other. The board dashboard groups awards by it. |

### The Grant Page

A grant's page groups its panels into tabs, on a phone too:

| Tab | What is on it |
|---|---|
| Overview | The grant's details, and the Program and Giving Fund cards (each only with its module). |
| Money | The Award Schedule card, the Payments list and the Restricted Fund Entries list. |
| Reporting | The Requirements list, the Logic Model Outcomes card (with Logic Models) and the Funder Report card. |
| Writing | The Answer Library card. |
| Related | Every related list, including any your organization adds. |

To change the page, edit **Grant Record Page** in Lightning App Builder.

### Government Awards

A grant's **Government Award** section holds what a government award (or any award that asks for
it) carries. Every field is optional:

| Field | What to put |
|---|---|
| Assistance Listing Number | The federal Assistance Listing number (formerly CFDA), for example 84.287: two digits, a point and three digits or capital letters. |
| Award Number | The funder's number for the award: the FAIN on a direct federal award, the subaward number from a pass-through. |
| Federal Agency | The federal agency the money comes from, also when it reaches you through a state or another pass-through. |
| Indirect Cost Rate | The indirect (overhead) rate the award allows, from 0 to 100 percent. |
| Match Required | The match or cost share you must put in. Leave it blank when there is none. |

For federal money passed on by a state agency or another body, set **Funding Source** to
**Federal Pass-Through**, make that body the **Funder**, and name the federal agency in **Federal
Agency**. The period of performance is the award period (**Award Start Date** and **Award End
Date**). Drawdowns are recorded as money received in the fund ledger (restricted fund tracking).

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
is not shown at all (staff cannot install a module, so the page does not ask them to). The
Giving Fund and Logic Model Outcomes cards do the same without their module. The grant stores the
program's record ID, so Grants works without Programs; if the program is later deleted, the card
says the program cannot be found and you can choose another.

### Outcomes a Requirement Reports On

With the Logic Models module installed as well, the grant's page has a **Logic Model Outcomes**
card. It lists the grant's requirements; for each one you can choose the outcome or output from
your logic models that it reports on (a deliverable such as "200 students tutored", or the final
narrative report on "Students read at grade level"), and click **Save**. Under each linked
outcome the card shows its indicators with the target and result of each period that overlaps
the grant's award period (every period when the grant has no award period yet), so you see at a
glance what you will report.

Any requirement type can name an outcome; Deliverable and Narrative Report are the usual ones. The
requirement stores the outcome's record ID in **Logic Model Outcome**, so Grants and Logic Models
never need each other: without Logic Models the card is not shown, and if the outcome
is later deleted the card says it cannot be found. The automation **Requirement: outcome is an
outcome** always runs and refuses anything in that field that is not one. Choosing an
outcome needs edit access to requirements (Grants Staff or Admin) and read access to Logic
Models; the outcomes and results shown follow each person's own Logic Models access.

## The Grant Pipeline Tab

The **Grant Pipeline** tab is where most people work:

- **Totals** at the top as tiles: open requests and the amount requested, and the amount awarded
  this fiscal year, with the number of grants awarded under them.
- **Board**: one column per open stage, each with its count and amount, and a card per grant
  showing its name (a link that opens the grant), the amount requested, the funder, the deadline
  and the owner. A deadline within 14 days shows a **Due in** badge (amber), a past one an
  **Overdue** badge (red). Click a card's menu to open the grant or move it to another stage,
  or drag the card by its handle into another column, or onto the **Awarded**, **Declined** and
  **Withdrawn** zones after the last column. Dragging works with a mouse, by touch (press and
  hold first) and by keyboard (Space, the arrow keys, Space; Escape cancels), and a screen
  reader hears each step. The menu stays for every move.
- **Record the Award**: moving a grant to **Awarded** opens a dialog that also asks **Amount
  Awarded** (the amount requested is filled in), **Award Start Date**, **Award End Date** and
  **Restricted**, all optional. On save a message links to the grant, where the Award Schedule
  card builds the payments.
- **Everyone** or **Mine**: all open grants, or only those you own.
- **Upcoming Deadlines**: every open grant whose application deadline is past or within the next
  60 days, and every open requirement due in that time or overdue, soonest first, with due soon
  and overdue ones badged. A requirement row has a **Mark Submitted** button; after it, an
  **Undo** link puts the requirement's status and Submitted Date back while the tab stays open.

Moving, dragging and the menu's stage choices are offered only to people who can edit grants, and **Mark
Submitted** only to people who can change requirements.

## The Board Dashboard Tab

The **Board Dashboard** tab is the Grants app's home and answers the questions a board asks
about money, for the current fiscal year. Everyone with a Grants set sees it; it only reads, and
it stores nothing. At the top, tiles show **Revenue This Fiscal Year**, **Awarded This Fiscal
Year**, with Giving **Gifts to funds**, and, with restricted fund tracking, **Restricted Grants:
Balance**. Under them, a tile for each Grants tab the person can open (Grant Pipeline, Grant
Calendar, Grants, Grant Requirements, Grant Answers and, for admins, Funder Report Templates).

- **Revenue Mix**: grants awarded this fiscal year (stage Awarded, decision date this fiscal year)
  totaled by **Funding Source**, and, with Giving, one more line for gifts designated to funds
  this fiscal year. Each line shows its amount and share as a bar. Grants with no funding source show as
  "Not set"; fill it in so the mix is right.
- **Concentration**: the organizations giving the most, each with its share of that revenue (its
  grants awarded plus, with Giving, its Giving This Year). The dashboard flags a single source
  above 25 percent, or the five largest together above 50 percent, as a risk to discuss: losing
  one funder would hurt. These thresholds are common board guidance and are fixed, not settings.
- **Restricted Balances**: with Giving, each active restricted fund and what it raised this
  fiscal year. Once restricted fund tracking (F-03) is installed, each restricted grant's balance
  (received less spent and released) is listed too.

Without Giving, or for someone without access to it, the dashboard shows the grant figures alone.
Each person sees totals of the records they can read. For a board packet, click **Print**: the
browser's print dialog opens with the app's header and navigation left off.

**A grant also recorded as a Giving gift is counted twice.** The dashboard adds grants and gifts
side by side and does not match one to the other, so a grant whose payment you also enter as a
gift designated to a fund appears in the grant lines and again in the gifts line, and its funder's
share in **Concentration** includes both. Record each award in one place (the grant, or the gift),
or read the two lines knowing they overlap.

If grant money is recorded both on the grant and as a gift in Giving, it counts in both lines;
record each payment in one place.

## Grant Requirements

An award usually comes with things to send back: an interim and a final report, a financial
report, a deliverable, a site visit. Record each one as a **grant requirement**: on the grant's
page, in the **Requirements** list, click **New**:

| Field | What to put |
|---|---|
| Requirement Name | What is due, for example "Year 1 interim report". |
| Type | Narrative Report (the default), Financial Report, Deliverable, Site Visit, Letter of Inquiry, Application, Task (a checklist step), Renewal or Other. |
| Due Date | When the funder expects it. Required. |
| Status | Not Started (the default), In Progress, Submitted, Accepted, Waived or Done. |
| Assigned To | The staff member doing it. Reminders go to them. |
| Instructions | What the funder asks for: the template, the portal, the questions. |
| Submitted Date | Filled in with today when the status becomes Submitted or Accepted, unless you typed a date. |
| Reminder Sent For | Set by BarnCRM: the due date the last reminder was made for. |

Not Started and In Progress are open; Submitted, Accepted, Waived and Done are done. The automation
**Requirement: fill in the submitted date** on the [Automation](automation-control.md) page fills in the
Submitted Date; switch it off while you load past requirements with their own dates.

A requirement belongs to its grant: whoever can see the grant sees its requirements, and deleting
the grant deletes them. Grants Staff can create, edit and delete requirements.

## Reminders

Every morning at 6:00 AM in your org time zone, BarnCRM reminds each open requirement due within
the next 14 days (you can change this), or up to 30 days overdue, that has not been reminded for
its current due date:

- **A task** for the person in **Assigned To**, or the grant's owner when nobody is assigned or
  the person assigned is inactive. The task is on the grant, due on the requirement's due date.
- **An email**, once you turn **Email reminders** on, to the same person, with a link to the grant. It goes to their Salesforce user, so
  it does not count against your org's daily limit for outside addresses.

Each due date is reminded once. If the funder moves the date and you change **Due Date**, the new
date is reminded again. When nobody active can be reminded, nothing is sent, and Health Check
still lists the requirement once it is overdue.

The job is a step of [BarnCRM Nightly Jobs](nightly-jobs.md), the one nightly run, and shows on
the Nightly Jobs panel as **Grant Requirement Reminders** (6:00 AM). It has no switch of its own;
Health Check's **Schedule all nightly jobs** fix schedules the run if it is not. It does nothing while Grants is turned off or both reminder
settings are off.

## Answer Library

Most applications ask the same questions: the mission, the need, the people served, how results
are measured, the budget. Keep your best answers once, as **grant answers**, and copy them into
each application instead of hunting through old proposals.

On the **Grant Answers** tab click **New**:

| Field | What to put |
|---|---|
| Answer Title | What it is and how long, for example "Mission statement (100 words)". |
| Answer | The text, exactly as you would paste it into an application. Required. |
| Topics | The topics it answers, separated by commas, for example "Mission, Need". Use the same words each time; capital letters do not matter. |
| Last Used Date | Set by BarnCRM when someone copies the answer from the library. |

Each grant's page has an **Answer Library** card: a search box, a **Topic** list built from the
topics you typed, and each answer with its topics, word count and last used date. **Copy** puts
the answer on the clipboard and sets its **Last Used Date** to today, so answers nobody has used
for a year stand out for a refresh. The card lists up to 500 answers, by title.

Grants Admin and Grants Staff add, edit and delete answers; Grants Read Only can search and
copy them (their copies do not change the last used date). Answers are shared with everyone who
has a Grants set. Topics are typed, not a picklist, so there is nothing to set up in Setup.

## Funder Report Templates

Each grant's page has a **Funder Report** card: choose a template and click **Download
Printable** to get the report as an HTML file, filled in with the grant, its requirements and,
with Logic Models installed, the results of the outcomes its requirements report on. Open the file
in a browser to print it or save it as a PDF, or in a word processor to edit it before you send
it. Nothing is saved in BarnCRM.

BarnCRM ships one template, **Grant report**, copied in at install. To change it or add your own,
open the **Funder Report Templates** tab (Grants Admin only):

| Field | What to put |
|---|---|
| Template Name | What staff choose, for example "Interim report". |
| Body | The report's HTML, with the tokens below. |
| Active | Only active templates are offered. Clear it to retire one without deleting it. |
| Template Key | Set by BarnCRM on the shipped template. Leave it blank on your own. |

| Token | Becomes |
|---|---|
| `{OrganizationName}` | Your organization's legal name from BarnCRM Settings (or the org name) |
| `{Today}` | Today's date |
| `{GrantName}`, `{FunderName}`, `{FunderContactName}`, `{OwnerName}`, `{Stage}`, `{FundingSource}` | The grant's fields |
| `{AmountRequested}`, `{AmountAwarded}` | The amounts, in your currency |
| `{ApplicationDeadline}`, `{AwardStartDate}`, `{AwardEndDate}` | The dates |
| `{Purpose}` | The grant's Purpose, line breaks kept |
| `{ProgramName}` | The program it pays for (Programs installed) |
| `{AssistanceListingNumber}`, `{AwardNumber}`, `{FederalAgency}` | The government award fields |
| `{RequirementTable}` | A table of the grant's requirements: name, type, due date, status and submitted date |
| `{OutcomeResults}` | Each outcome a requirement reports on, with its indicators' targets and results for the award period (Logic Models installed; empty otherwise) |

Every value is written as text, so a grant name with `<` or `&` cannot break the HTML. A token
with no value becomes empty, and anything else in braces stays as you typed it. An upgrade never
changes a template you already have; delete the shipped one and run Finish Setup to get it back.

## The Grant Finder Tab

The **Grant Finder** tab searches open federal funding opportunities on
[Grants.gov](https://www.grants.gov), a free public service that needs no account or key. Type
words (for example "literacy" or "after school"), choose **Posted** (open now), **Forecasted**
(announced, not open yet) or both, and click **Search**. Each result shows its title, agency,
opportunity number, open and close dates and assistance listing number, with a link to its
Grants.gov page.

**Save to Pipeline** makes a grant at **Prospect** with the title as its name, the close date as
**Application Deadline**, **Funding Source** Federal, the agency as **Federal Agency** and the
first assistance listing number. The funder is the organization with the agency's exact name, or
a new organization when you have none. A result already saved shows **Saved** with a link to its
grant. Saving needs permission to create grants (Grants Admin or Staff).

Only the words you search leave your org. BarnCRM installs the Remote Site Setting
**BarnCRM_Grants_Gov** (`https://api.grants.gov`) so the search works without a Setup step; keep
it active in Setup, **Remote Site Settings**. To hide the search, turn **Grant Finder** off in
[Settings](#settings). Paid grant directories are not built in: BarnCRM adds no paid service.

## Application Checklists

A **Grant Checklist Item** is one step you take on every application at a stage, for example
"Ask the program officer about fit" at Prospect or "Attach the board list" at Applied. Admins
keep them on the **Grant Checklist** tab:

| Field | What to put |
|---|---|
| Task | The step, as it appears on each grant. |
| Stage | Prospect, Letter of Inquiry, Invited to Apply, Applied or Awarded. |
| Days Before Deadline | How many days before the grant's Application Deadline it is due; blank is the deadline itself. |
| Assigned To | Who does it on every grant; blank leaves it to the grant's owner. |
| Instructions | Copied to each task. |
| Active | Only active items are added. |

When a grant is created at, or moves to, a stage, BarnCRM adds each active item of that stage as
a requirement of type **Task**, once per grant. A task is never due before today, and a grant
with no deadline gets it due in 14 days. Tasks are reminded like any requirement. The automation
**Grant: add checklist tasks** on the [Automation](automation-control.md) page does this; switch
it off while you import grants. **Add Checklist Tasks** on a grant's **Checklist** card adds any
missing ones for its current stage. Changing or deleting an item leaves tasks already made alone.

## Grant Documents

Letters of inquiry, applications and reports are requirements of type **Letter of Inquiry**,
**Application**, **Narrative Report** or **Financial Report**. Their files are Salesforce Files on
the requirement. The **Documents** card on a grant's **Writing** tab lists them with their status,
due and submitted dates and latest file, with the file's version number; **Upload** adds a file.
For a new draft, open the file and use **Upload New Version**, so the version number goes up and
the history stays on the file. Files count against your org's file storage. Uploading needs edit
access to the requirement.

## Budget Lines

On a grant's **Money** tab, add the budget's lines in the **Budget Lines** list (for example
Personnel, Supplies), each with **Amount Requested** and, once awarded, **Amount Awarded**. A
**Spent** restricted fund entry can name its **Budget Line**. The **Budget** card shows each
line's requested, awarded, spent and remaining amounts, the line totals against the grant's
Amount Requested and Amount Awarded (flagged when they differ), and spending not on a line.
Grants Admin and Staff add and change lines; Read Only sees them.

## Renewals

Tick **Renewable** on an award the funder may renew. Once the grant is **Awarded** and has an
**Award End Date**, BarnCRM adds one **Renewal** requirement due 90 days before the end date (the
**Days before an award ends to renew** setting; never before today), so it is reminded
like any requirement; moving the end date moves it. The automation is **Grant: add the renewal
requirement** on the Automation page.

**Start Renewal** on the grant's **Renewals** card makes next cycle's grant at Prospect: the same
funder, contact, purpose, program, Giving fund, funding source, restricted flag, payment frequency
and government award fields, the amount awarded as the new request, a copy of the budget lines,
and **Renewal Of** naming this grant. The Renewal requirement becomes Done. The card lists every
grant in the chain, earlier and later, with its award period and amounts.

## Settings

Open **BarnCRM Settings**, **Grants** (under Fundraising). Each setting saves for the whole
organization.

| Setting | Default | What it does |
|---|---|---|
| Create reminder tasks | On | Makes the reminder task. |
| Email reminders | Off | Also sends the reminder email. |
| Days before a deadline to remind | 14 | How many days before a requirement is due its reminder goes out, from 1 to 90. |
| Grant Finder | On | Whether the Grant Finder tab searches Grants.gov. |
| Days before an award ends to renew | 90 | When a renewable award's Renewal requirement is due, from 1 to 365 days before the award ends. |

Tasks ship on, because a missed funder report can cost the next award and a task goes only to the
person doing the work. Emails ship off, like shift and pledge reminders: BarnCRM sends no email
until you turn it on.

## Health Check

With Grants installed, [Health Check](health-check.md) asks two more questions, shown only to
people who can manage BarnCRM Settings and not while Grants is turned off:

| Finding | Severity | What it means | What to do |
|---|---|---|---|
| **Grant applications are past their deadline** | Information | Open grants at Prospect, Letter of Inquiry or Invited to Apply whose Application Deadline has passed. | Open each linked grant: move it to Applied if it went in, set Withdrawn if you did not apply, or move the deadline if the funder extended it. |
| **Grant requirements are overdue** | Information | Requirements still Not Started or In Progress whose Due Date has passed. | Open each linked requirement: mark it Submitted if it went in, Waived if the funder excused it, or move the due date if the funder agreed a new one. |

## Award Schedules

An award paid over several years, or in parts, has **payments**: each with a **Due Date**, an
**Amount**, a **Status** (Expected, Received or Cancelled) and a **Received Date**. The grant
shows **Amount Scheduled** (every payment not Cancelled) and **Amount Received**.

The grant's page has an **Award Schedule** card. Once the grant is **Awarded** with an **Amount
Awarded**, an **Award Start Date** and an **Award End Date**, and has no expected or received
payment yet, the card offers **Build Schedule**. Until then it names only what is missing: the
Awarded stage, one of those fields, or award dates in the wrong order. The card shows Amount
Awarded, Amount Scheduled and Amount Received as tiles, with a bar for the share received.

1. Choose the **Payment Frequency**: **Once**, **Annual**, **Semiannual**, **Quarterly** or
   **Monthly**.
2. The card shows the payments it will make: the amount awarded split evenly, the first on the
   award start date and each later one a period apart, up to the award end date. The last payment
   takes any cents left by rounding.
3. Click **Build Schedule**. The payments are saved, and the frequency is kept in the grant's
   **Payment Frequency**.

After that, change a payment's date or amount, add one, or cancel one in the grant's **Payments**
list. **Mark Received** on the card sets a payment Received; its **Received Date** fills in with
today unless you typed one, and the card offers **Undo** while it is open: the payment goes back
to Expected with its earlier Received Date, and the Received ledger entry it wrote is removed,
unless the payment was changed since. That is the automation **Grant payment received** on the
**Automation** page; switch it off while you import past payments.

## Restricted Funds

Money a funder limits to a purpose or a period is **restricted**, and you answer to the funder for
it. Tick **Restricted** on the grant to keep its restricted ledger. Each **restricted fund entry**
has a **Type**, an **Amount** (always above zero), an **Entry Date** and a **Description**:

| Type | Use it for |
|---|---|
| Received | Restricted money that came in. |
| Spent | Money spent on the purpose, for example "Q1 tutor salaries". |
| Released | Restriction the funder lifted, or that lapsed, without the money being spent on it. |

The grant shows **Restricted Received**, **Restricted Spent**, **Restricted Released** and the
**Restricted Balance** (received minus spent minus released). The balance can go below zero: a
reimbursement grant is spent before the funder pays. This is a ledger for reporting to the
funder, not accounting; your books stay in your accounting system.

On a restricted grant, marking a payment **Received** adds its **Received** entry for you, and the
entry follows the payment: a changed amount or date changes it, and setting the payment back to
Expected or Cancelled, or deleting it, removes it. Entries you type yourself are never changed.
Ticking **Restricted** after payments came in adds no entries for them: add those yourself. The
automation is **Grant payment received** on the **Automation** page; switch it off while you
import past payments and entries.

### The Giving Fund a Grant Is Booked To

With the Giving module installed, the grant's page has a **Giving Fund** card. Choose the fund the
organization books this money to in Giving and click **Save**. Like the program, the grant stores
the fund's record ID, so Grants works without Giving; without Giving the card is not shown. Grants
reads only the fund's name: Giving's own fund totals count the gifts you record in Giving, and the
grant's restricted ledger counts its entries, so nothing is counted twice.

## The Grant Calendar Tab

The **Grant Calendar** tab shows a month at a time: application deadlines of open grants not yet
submitted, due dates of open requirements, and expected payments, each on its day and linked to
its grant. An overdue item shows a warning icon, the word Overdue (in its hover text and for screen readers) and bold text, not red alone. A key under the month heading names the border colours: Application (blue), Grant Requirement (orange), Grant Payment (green), plus the Overdue mark. Use **Previous**, **Next** and **Today** to move between
months, and **Everyone** or **Mine** as on the Grant Pipeline (Mine: grants you own and
requirements assigned to you). It shows the same deadlines as the pipeline's **Upcoming
Deadlines**, plus payments with their amounts in your currency. **Print** prints the month
without the app's header and navigation.

## Sample Data

**Load Sample Data** in BarnCRM Settings also loads eight sample grants to Core's sample
organizations across the pipeline (two Prospect, one Letter of Inquiry, one Invited to Apply, one
Applied, two Awarded, one Declined), with an application or report requirement on most of them
(so the Grant Pipeline and Grant Calendar tabs and the Board Dashboard all show data), three
requirements on the main award, a
two-payment schedule with the first payment received, and a restricted ledger with that payment's
Received entry and one Spent entry, and two budget lines on the award (the Spent entry is on
the first). **Remove Sample Data** takes them away again. See
[Sample data](sample-data.md).

## Turning It Off

Turning Grants off in Module Manager stops its automations, its reminders and its Health Check
questions; the records stay. No Grants set is given while it is off.

## A Five-Minute Walkthrough

Do this as Maria, who holds the Admin role, with a second user, Dana, who has none yet.

1. On the [Access](access.md) page, give Dana the **Fundraising Staff** role.
2. In Setup, open Dana's user record and look at **Permission Set Assignments**. Within a minute
   she holds **Grants Staff**.
3. Open the **BarnCRM Grants** app. On **Grants**, create "2027 Literacy Grant" for any
   organization, **Amount Requested** 25,000, **Application Deadline** two weeks from today.
4. Open **Grant Pipeline**. The grant is in the **Prospect** column, and in **Upcoming
   Deadlines**.
5. From the card's menu choose **Move to Applied**. Open the grant: **Submitted Date** is today.
6. Back on the board, choose **Move to Awarded**. In **Record the Award** accept 25,000, set
   **Award Start Date** to January 1 next year and **Award End Date** to December 31 the year
   after, tick **Restricted** and click **Save**. The grant leaves the board, **Awarded This
   Fiscal Year** shows 25,000 and its **Decision Date** is today.
7. Try to delete the organization. Salesforce refuses and names the grant.
8. On the grant's **Requirements** list click **New**: "Year 1 report", due in 5 days, **Assigned
   To** Dana. On **Grant Pipeline** it shows under **Upcoming Deadlines** with **Mark Submitted**.
9. The next morning Dana has a task "Year 1 report due for 2027 Literacy Grant" (and an
   email, if you turned **Email reminders** on).
   Click **Mark Submitted**: the row leaves the list and the requirement's **Submitted Date** is
   today. Click **Undo**: it is back, not submitted; mark it again.
10. Open the grant. On the **Award Schedule** card choose **Annual**: two payments of 12,500, a
    year apart. Click **Build Schedule**.
11. Open **Grant Calendar** and move to January next year: the first payment is on January 1.
12. Back on the grant, click **Mark Received** on the first payment. **Amount Received** and
    **Restricted Received** show 12,500, and the **Restricted Fund Entries** list has its Received
    entry. Add a Spent entry of 2,000: **Restricted Balance** shows 10,500.
13. On **Grant Checklist**, add "Ask the program officer about fit", Stage **Prospect**, Days
    Before Deadline 7. Open **Grant Finder**, search "literacy" and click **Save to Pipeline** on
    a result: the new grant is at Prospect and its **Checklist** card shows the task.
14. On the 2027 Literacy Grant, add a budget line "Tutors", requested and awarded 20,000, and set
    the Spent entry's **Budget Line** to it: the **Budget** card shows 2,000 spent of 20,000.
15. Tick **Renewable**: a **Renewal** requirement appears, due 90 days before the award ends.
    Click **Start Renewal** on the **Renewals** card: the new grant is at Prospect, asks 25,000
    and both grants are listed on its Renewals card.

## Common Mistakes

- **Making a funder a household or a person.** A funder is an organization; record the family
  foundation as an organization, with the family members as its contacts.
- **Deleting a declined request.** Set Declined instead: the history is what tells you whom to ask
  again and when.
- **Uploading each draft as a new file.** Use **Upload New Version** on the file instead, so the
  Documents card shows one file with its version number.
- **Creating next year's grant by hand.** Use **Start Renewal**, so the grants stay linked and the
  Renewals card shows the history.
