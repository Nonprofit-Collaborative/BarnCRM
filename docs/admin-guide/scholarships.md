# Scholarships and Outbound Grants

## What It Does

BarnCRM Scholarships and Outbound Grants is an optional Nonprofit Edition module for
organizations that give money: scholarships, fellowships, mini-grants and other outbound grants.

- **Programs and cycles** (SG-01): a program (a scholarship fund, a mini-grant program) runs in
  cycles, each with open and close dates, eligibility in words and as rules, a budget and a planned
  number of awards.
- **Applications** (SG-02): each from a BarnCRM person or organization, with the answers and files
  from a BarnCRM Forms application form, or entered by staff.
- **Reviews** (SG-03, SG-10): scoring rubrics, a reviewer panel, Assign Reviewers that spreads the
  work evenly, conflict-of-interest recusal, optional blind review, total and average scores and
  a ranked review board.
- **Awards** (SG-04): the decision, an award letter as a PDF, acceptance and terms.
- **Disbursements** (SG-05, SG-09): a payment schedule, the payee, Paid with its date and
  reference, conditions that hold a payment back until met, and a CSV export for your accounting
  system. **BarnCRM moves no money**: it records payments you make elsewhere.
- **Recipient reports** (SG-06): progress and final reports with due dates, reminders and renewal
  of multi-year awards.
- **Applicant portal** (PB-06): with Portal Builder, applicants apply, follow their applications,
  accept awards and send reports (see [Portal Builder](portal-builder.md)).
- **Reports and dashboard** (SG-08): standard Salesforce reports and one dashboard.

Organizations on Nonprofit Cloud Grantmaking or Outbound Funds keep those tools; BarnCRM never
changes them. An organization moving from Outbound Funds can copy its records in with the
Migration Assistant (see [Moving From Outbound Funds](#moving-from-outbound-funds)).

## Install and Turn On

1. Deploy or install the `BarnCRM Scholarships and Outbound Grants` package after Core.
2. In BarnCRM Settings, **Modules**, turn on **Scholarships and Outbound Grants**. It ships off.
3. The Scholarships and Grants, Award Programs, Award Applications and Awards tabs appear in the
   BarnCRM and BarnCRM Console apps, before Error Log. There is no separate app.

For applications with files, also install BarnCRM Forms and set up its public site (see
[Forms](forms.md)). For the applicant portal, install Portal Builder.

## Access

| Permission set | Who gets it | What it allows |
|---|---|---|
| Scholarships Admin | BarnCRM Admin holders | Everything, delete, and Manage Scholarships |
| Scholarships Staff | Team Member and Fundraising Staff roles | Create and edit everything, no delete |
| Scholarships Read Only | Read Only role | Read everything |

BarnCRM gives these sets when a role is given on the Access page, at Turn on and with the hourly
access check; it never takes them away. **Manage Scholarships** (in Scholarships Admin) is needed
to assign reviewers, decide awards, waive conditions and mark disbursements Paid. A reviewer who is
not on staff (a volunteer committee member with a Salesforce login) needs Scholarships Staff
assigned by hand.

Award Programs are shared Public Read/Write so every reviewer can save a review; cycles,
applications, reviews, awards, disbursements and requirements follow their program. To limit a
program to a team, set the Award Program default to Private in Sharing Settings and share it.

## Settings

BarnCRM Settings, **Scholarships and Grants**. Every setting is org-wide.

| Setting | Default | What it does |
|---|---|---|
| Send Scholarships reminders | On | The 6:50 AM run sends the owner of the award's program a bell notification before a report or condition is due, once per date. |
| Days before to remind | 14 | How far ahead, 1 to 365. |
| Email recipients about reports | Off | The same run also emails the award's Recipient their own report link. Uses your org's daily email limit. |

The nightly step is **Scholarships reminders** on the Nightly Jobs page. It also opens a Planned
cycle on its Open Date and moves an Open cycle to Reviewing after its Close Date.

## Programs and Cycles

1. On **Award Programs**, press **New**: a name, a Type (Scholarship, Grant, Fellowship, Other),
   a public description and, if you like, an award letter template (see Award Letters).
2. On the program, add an **Award Cycle**: name (for example "2027 Spring"), Open Date, Close
   Date, Budget, Planned Awards, and Eligibility in words.
3. Optional fields:
   - **Application Form**: the record ID of a published BarnCRM Forms form. The cycle page then
     shows the public application link to put on your website.
   - **Report Form**: the record ID of the form recipients use for progress and final reports.
   - **Eligibility Rules**, **Rubric**, **Reviewer Panel**, **Reviewers per Application** and
     **Blind Review**, below.

### Eligibility Rules

A JSON list, each rule naming a form answer by its field key:

```json
[
  { "answer": "gpa", "op": "atLeast", "value": 3.0 },
  { "answer": "county", "op": "equals", "value": "Marion" },
  { "answer": "enrolled", "op": "isTrue" }
]
```

Ops: `equals`, `notEquals`, `atLeast`, `atMost`, `isTrue`, `contains`. When an application
arrives, all rules met makes it Eligible; any not met makes it Ineligible and lists the unmet rules
in Eligibility Notes. With no rules it is Submitted. Staff can change the status by hand. Rules
that cannot be read are ignored and written to the Error Log.

### Rubric

A JSON list of criteria. Each has a key, a label, the highest score and a weight:

```json
[
  { "key": "need", "label": "Financial need", "max": 10, "weight": 2 },
  { "key": "essay", "label": "Essay", "max": 10, "weight": 1 }
]
```

A review's Score is each criterion's score times its weight, added together. With no rubric,
reviewers give one overall score from 0 to 10.

### Reviewer Panel

Create a public group (Setup, Public Groups) with the reviewers as members and put its API name in
**Reviewer Panel**. On the cycle page, **Assign Reviewers** gives each Submitted, Eligible or In
Review application reviews up to **Reviewers per Application** (default 2): each next review goes
to the panel member with the fewest open reviews in the cycle, never to someone who already has a
review of that application, including one they recused from. Press it again after a recusal to
fill the gap. Reviewers get a bell notification.

### Blind Review

With **Blind Review** checked, the review screen and the review board hide the applicant's name and
organization from reviewers. This is a display rule, not a security control: a reviewer who opens
the application record or the person can still see who it is. If your program needs more, give
reviewers a custom permission set without access to the applicant fields.

## Applications

With an Application Form set, each submission from the form's public link (or from the applicant
portal) creates an Award Application with the matched person and organization, the answers in Form
Answers, and the uploaded files linked to the application. A person who applies twice to the same
cycle updates their Draft or Submitted application rather than creating a second one.

Staff can also add an application on the cycle's Applications related list.

## Reviews and Decisions

- A reviewer opens an application from the Scholarships and Grants tab (**My Reviews**). The
  review panel shows the rubric; **Save** keeps a draft, **Submit Review** counts it, **Recuse**
  steps aside with a reason. Only the reviewer, or a holder of Manage Scholarships, can change a
  review.
- The cycle page shows the **Review Board**: applications ranked by Average Score, with reviews
  submitted, the amount requested and the budget remaining. A holder of Manage Scholarships
  presses **Award** (with an amount) or **Decline** on each row. Award creates an Offered award
  and marks the application Awarded.

## Award Letters

On the award, **Make Letter** creates a PDF from the program's Award Letter Template and files it
on the award (Files). Merge tags: `{Recipient}`, `{Program}`, `{Cycle}`, `{Amount}`,
`{Conditions}`, `{Organization}` (your organization's name from BarnCRM Settings) and `{Date}`.
With no template, the shipped letter is used. Send the PDF yourself; BarnCRM does not email it.

Record the answer with **Accepted** or **Declined** on the award, or let the recipient press
**Accept Award** in the applicant portal.

## Disbursements and Conditions

- **Build Schedule** on the award splits the amount not yet scheduled into equal payments, a chosen
  number of months apart. Edit any payment's Payee (for example the school), date or amount.
- Add a **Condition** requirement (Award Requirements related list) for anything that must happen
  first, such as proof of enrollment. Name a disbursement in **Blocks Disbursement** to hold back
  that one payment, or leave it blank to hold back every payment of the award.
- **Mark Paid** records the date, method and reference after you pay in your accounting system. It
  is refused while a holding condition is Open or Submitted, and for anyone without Manage
  Scholarships. **Met** and **Waive** on a condition release it.
- **Export Disbursements** on the Scholarships and Grants tab downloads a CSV of the payments
  scheduled or paid in a date range (number, award, recipient, payee, amount, dates, method,
  reference, program, cycle) and stamps their Exported Date. Import it into your accounting
  system.

## Recipient Reports and Renewals

Add **Progress Report** and **Final Report** requirements with due dates. With a Report Form on the
cycle, each requirement carries the recipient's own signed report link; a submission from that
link fills Report or Evidence, links the files and marks the requirement Submitted. Staff then mark
it **Met**.

On a Renewable award, **Start Renewal** creates a Draft application in the program's next Planned
or Open cycle, linked to the award by Renewal Of.

## Reports

The **BarnCRM Scholarships** folder holds Applications by Cycle and Status, Applications Ranked by
Score, Awards by Program, Disbursements Due Next 30 Days and Recipient Reports Due, and the
**Scholarships and Grants** dashboard. Copy them to change them.

## Moving From Outbound Funds

When the Outbound Funds Module (the free Salesforce.org package for grants you give) is installed
in the same org, the [Migration Assistant](migration-assistant.md) copies its records into this
module, with a preview, a check that the numbers match and undo for each step. Open **BarnCRM
Settings**, **Integrations**, find **Outbound Funds Module** and click **Start Migration: Outbound
Funds Programs and Awards**. You need Manage BarnCRM Settings and Manage Scholarships, and you
should see every Outbound Funds record.

| Step | What it does |
|---|---|
| Programs | Copies each funding program as an award program of type **Grant**, with its description; a Completed or Closed program is inactive. |
| Cycles | Outbound Funds has no cycles, so each copied program gets one cycle named after the funding program, with its start and end dates as open and close dates, its total amount as the budget, and its status (In progress becomes Open, Completed becomes Closed). |
| Applications | Copies each funding request as an application in that cycle: its name as the title, applying contact and organization, requested amount, application date, what it is for as the summary, and status (In progress becomes Draft, Under Review becomes In Review, Rejected becomes Declined). |
| Awards | Copies each funding request with an awarded amount as an award on its application: recipient, amount, award date as the decision date, and status (Awarded becomes Active, Closed becomes Completed, Withdrawn becomes Cancelled). |
| Disbursements | Copies each disbursement of an awarded request onto its award: amount, scheduled and paid dates, status (Pending and Approved become Scheduled) and method (EFT, ACH and wire become Bank Transfer; any other becomes Other). A Paid disbursement is only saved by someone with Manage Scholarships, so run this step as that person. |
| Requirements | Copies each requirement of an awarded request onto its award, linked to its disbursement: its name as the instructions, due date, type (a report becomes Progress Report or Final Report, anything else Condition) and status (Complete and Accepted become Met). |

Before you load requirements, switch **Send Scholarships reminders** off (BarnCRM Settings,
**Scholarships and Grants**) if you do not want reminders for old requirements, and switch it back
on afterwards. The retire checklist reminds you
to point applicants at BarnCRM, deactivate your own flows on Outbound Funds objects, and rebuild
your reports. Review scores, the review board and award letters start fresh in BarnCRM: Outbound
Funds' reviews, notes and files are not copied.

The Outbound Funds names the kit reads come from its public repository, not from a current
package version: if your version differs, the step stops before reading anything and names the
field it could not find.

## Removing the Module

Turn it off in BarnCRM Settings, **Modules**; the records stay. Uninstalling deletes the seven
objects and their records; the Module Manager's uninstall report counts them first.
