# Corporate Hub

## What It Does

BarnCRM Corporate Hub is an optional module, in either edition, for the paperwork that keeps an
organization in good standing:

- **Library Documents** (CH-01): your policies, procedures, bylaws and other governing documents,
  plans and forms, with their files on Salesforce Files, an owner, a status (Draft, Active,
  Retired), a current version and a next review date.
- **Policy acknowledgments** (CH-02): ask staff to confirm they have read a policy's current
  version, and see who is still outstanding.
- **Compliance calendar** (CH-03): filings, registrations and renewals with due dates, a
  recurrence and an owner. Completing one keeps a record of that cycle, with its evidence, and
  moves the due date on.
- **Templates** (CH-04, CH-06, CH-07): common obligations and starter policies, loaded for you
  and switched off until you adapt them.
- **Agreements** (CH-08): contracts, leases and subscriptions with their end, renewal and notice
  dates.
- **Data protection** (CH-05): a record of processing activities, data subject requests linked
  to Core's Erase a Person, DPIA review dates and a personal data breach log with its 72-hour
  deadline, plus GDPR starter templates.
- **Board governance** (CH-09 to CH-20): boards and committees with seats and terms, meetings
  with attendance, quorum, packets, minutes approval, motions and votes, carried action items, an
  availability poll, yearly conflict-of-interest disclosures, a board self-assessment and a board
  dashboard. Members take part through the board portal template (PB-02).

The owner of each obligation, agreement and document gets a bell notification before it is due.
Files count against your org's file storage. Reports and dashboards are standard Salesforce ones.

> **Not legal advice.** The templates and starter policies are general guidance for US
> nonprofits, written to be adapted. They contain no legal text. Review every obligation and
> policy with your own counsel or accountant before relying on it; rules differ by country,
> state and the kind of organization you are.

## Install and Turn On

Corporate Hub depends on BarnCRM Core only. Install it like any module, then turn it on in
BarnCRM Settings, **Modules** (it installs off). The install, and Finish Setup on the Modules
page, does three things, each safe to run again:

1. Gives you, and every holder of the BarnCRM Admin role, the Corporate Hub Admin permission set.
2. Gives the module's Staff set to Team Member and Fundraising Staff holders, and its Read Only
   set to Read Only holders (see Access below).
3. Loads the shipped templates that your org does not have yet (see Templates).

The **Corporate Hub**, **Library Documents**, **Compliance Obligations**, **Agreements**,
**Boards and Committees** and **Board Meetings** tabs join the BarnCRM and BarnCRM Console apps
before Error Log. Corporate Hub has no app of its own. The **Processing Activities**, **Data
Subject Requests** and **Data Breaches** tabs are not added to the apps' menus (most
organizations open them rarely): find them in the App Launcher, or add them to an app's
navigation yourself.

## Access

| Permission set | Who gets it automatically | What it allows |
|---|---|---|
| Corporate Hub Admin | BarnCRM Admin holders | Everything, every record, including deleting, requesting acknowledgments, publishing versions, recording an acknowledgment for someone else and loading templates (custom permission Manage Corporate Hub) |
| Corporate Hub Staff | Team Member and Fundraising Staff holders | Create and edit documents, obligations, completed cycles and agreements; never delete; answer their own acknowledgments |
| Corporate Hub Read Only | Read Only holders | Read everything above; answer their own acknowledgments |

Sets are given, never taken away. Library Documents and Agreements are readable by everyone and
editable by their owner and admins; Compliance Obligations are editable by every Staff holder;
each acknowledgment is owned by, and visible to, the person asked (and admins). Boards and
Committees and Board Meetings are readable and editable by every holder of a Staff or Admin set;
seats, motions, votes, attendees, action items and assessments follow their board or meeting.
Only admins delete board records, mark minutes approved, request disclosures from the board and
start a self-assessment. Processing Activities are readable by everyone and editable by their
owner and admins. Data Subject Requests and Data Breaches are private: each is visible to its
owner and to admins (Corporate Hub Admin sees and edits every one); Staff create and edit their
own, Read Only reads their own.

## Settings

BarnCRM Settings, **Corporate Hub**:

| Setting | Default | What it does |
|---|---|---|
| Send Corporate Hub reminders | On | Whether the nightly run sends the bell reminders. |
| Days before to remind | 30 | How many days ahead an owner is reminded, for any record that has no Reminder Days of its own (1 to 365). |
| Days to acknowledge | 30 | The due date a new acknowledgment request gets (1 to 365). |
| Show board demographics | Off | Whether the Board panel shows the optional age range and gender of current seats. |

The reminder step is **Corporate Hub reminders** on the Nightly Jobs page, at 6:45 AM, with its
own switch. It runs once a night, but a breach is different: its bell goes the moment the breach
is logged (D-196), and the 6:45 AM run then sends no second bell for the same deadline date. The
**Data Breach: Bell When Logged** row on the Automations page turns the immediate bell off, and
**Send Corporate Hub reminders** turns off both; with either off, the first bell comes with the
6:45 AM run. A breach logged in a bulk load tells its owner at once for the first 50 only; the
6:45 AM run sends the rest.

## Templates

The templates ship in the static resource `BarnCorporateHubTemplates` and are loaded as ordinary
records you can change:

| Template | Loads as | Set |
|---|---|---|
| Corporate or state annual report | Compliance Obligation, Off, yearly | CH-04 |
| Annual tax return (US: IRS Form 990 series) | Compliance Obligation, Off, yearly | CH-04 |
| Charitable solicitation registration | Compliance Obligation, Off, yearly (copy it for each state) | CH-06 |
| Insurance renewals | Compliance Obligation, Off, yearly | CH-06 |
| Annual financial audit or review | Compliance Obligation, Off, yearly | CH-06 |
| Registered agent renewal | Compliance Obligation, Off, yearly | CH-06 |
| Conflict of interest policy | Library Document, Draft, needs acknowledgment | CH-07 |
| Whistleblower policy | Library Document, Draft, needs acknowledgment | CH-07 |
| Document retention and destruction policy | Library Document, Draft | CH-07 |
| Gift acceptance policy | Library Document, Draft | CH-07 |
| Record of processing review | Compliance Obligation, Off, yearly, category Data Protection | CH-05 |
| Data protection impact assessment (DPIA) reviews | Compliance Obligation, Off, yearly, category Data Protection | CH-05 |
| Data protection policy | Library Document, Draft, needs acknowledgment | CH-05 |
| Privacy notice | Library Document, Draft | CH-05 |
| Data subject request procedure | Library Document, Draft | CH-05 |
| Personal data breach response procedure | Library Document, Draft, needs acknowledgment | CH-05 |
| Donor records and fundraising, Email newsletter, Volunteer management, Program participants, Staff and board records | Processing Activity, Draft (one each) | CH-05 |

To use an obligation template: open it, set **Next Due Date**, the owner and the jurisdiction,
adjust the recurrence (for example Every Two Years for a biennial state report), then set
**Status** to Active. To use a starter policy: attach your own policy file, edit the summary,
then publish it (below).

An upgrade adds new templates only; it never changes a record you already have. The **Add
Missing Templates** button on the Corporate Hub page (admins) loads any template your org has no
record for. Set a template you do not need to Off (obligation) or Retired (policy) rather than
deleting it, or the next setup loads it again. Other countries: rename the tax return template
and its instructions, or add your own obligations.

## Library Documents

Create a Library Document, attach its file in the **Files** related list (a newer file is
uploaded as a new version of the same file), and fill in the type, owner, review interval and
next review date. The **Policy** panel on the document page has:

- **Publish New Version**: raises the version by one, sets the effective date to today and the
  status to Active. Open acknowledgment requests for the older version become Superseded, and
  the same people are asked again for the new one.
- **Mark Reviewed**: sets Last Reviewed to today and Next Review to today plus the review
  interval.
- **Retire**: sets the status to Retired and the date. A retired document asks no one.

A document with acknowledgments cannot be deleted; retire it.

## Policy Acknowledgments

On a document with **Needs Acknowledgment** checked and status Active, **Request
Acknowledgments** asks either everyone who holds a BarnCRM role or the active members of one
public group (direct user members). Each person gets a bell notification and a request due in
**Days to acknowledge**. Asking again skips anyone already asked for that version.

People acknowledge on the Corporate Hub page, under **Policies to Acknowledge**. The document's
panel counts acknowledged and outstanding for the current version and lists who is outstanding.
An admin can **Record** an acknowledgment for someone (a signed paper copy, for example), and can
create a request by hand for a person with no login by filling in Person instead of User.

Only the person asked, or a holder of Manage Corporate Hub, can mark a request Acknowledged.

## Compliance Calendar

A Compliance Obligation has a category, jurisdiction, next due date, recurrence, owner, reminder
days, instructions and a reference link. **Days Until Due** is negative when overdue, for reports
and list views. The **Compliance** panel on the obligation page has **Complete This Cycle**:
choose the date done, the outcome (Done, Done Late or Not Required) and notes, then attach the
evidence (the filed return, the confirmation) to the new Compliance Cycle. The due date moves on
by the recurrence; a One Time obligation becomes Done. The Compliance Cycles related list is the
history.

## Agreements

An Agreement records the other party (an organization and a contact), dates, **Auto-Renews** with
its renewal term, **Notice Days** (the **Notice Date** is worked out), value, terms, and the
signed copy in Files. The owner is reminded before the notice date (or the end date when no notice
is set). Each night an Active, auto-renewing agreement past its end date moves on by its term
(an end date on the last day of a month stays on the last day: 31 January, then 28 February,
then 31 March), and any other Active agreement past its end date becomes Expired.

## Data Protection

The data protection set (CH-05) is for organizations under the GDPR or a similar law (UK GDPR,
for example). It records what you do; it decides nothing for you and sends nothing outside
Salesforce.

### Processing Activities

A **Processing Activity** is one line of your record of processing: its purpose, **Lawful
Basis** (Consent, Contract, Legal Obligation, Vital Interests, Public Task or Legitimate
Interests), the data subjects and categories of data, any special category data, recipients,
transfers outside the country, retention and security measures. Status is Draft, Active or
Retired. The five starter activities load as Draft with suggested wording; check each against
what you really do, fill in the lawful basis where it is blank, and set it Active.

Tick **DPIA Required** for an activity that needs a data protection impact assessment, record
**DPIA Reviewed On** and set the **DPIA Review Date**: the owner of an Active activity gets one
bell reminder before that date.

### Data Subject Requests

Log each request a person makes about their data as a **Data Subject Request** (numbered
DSR-00001 on): the **Request Type** (Access, Rectification, Erasure, Restriction, Portability,
Objection or Other), the person (a Contact, when you have one) or the requester's name and email,
the date received (today by default) and the **Due Date** (left blank, it becomes the date
received plus 30 days when you save, and follows the date received if you correct it and never
edited the due date; change it when you extend the deadline and it stays as you set it). The
**Data Subject Request: Due Date** row on the Automations page turns this
off. Tick **Identity Verified** once checked. Status is
Received, In Progress, Completed, Refused or Withdrawn; a closed request needs its **Completed
Date**. The owner gets one bell reminder before the due date.

For an erasure request, run Core's **Erase a Person** on the person and enter the request
number (for example DSR-00001) as its **Request Reference**. That night the request's **Erasure
Record** is filled with the erasure, so the request shows what was done. Its status is not
changed: close it yourself once you have replied.

### Data Breaches

Log every personal data breach as a **Data Breach**, even one you will not report:
**Discovered At** (now by default), when it happened, what data and how many people are affected,
the **Risk** (Not Yet Assessed, Unlikely to Result in Risk, Risk or High Risk), the decision on
notifying and the actions taken. **Authority Deadline** is 72 hours after discovery. Until you
record **Authority Notified At**, the owner of an open breach whose risk is not Unlikely to
Result in Risk gets a bell reminder as soon as the breach is logged (D-196), and the breach
shows on the Corporate Hub page. Record **People Notified At** when you tell the people affected. A breach cannot be
closed while its risk is Not Yet Assessed.

### On the Corporate Hub Page

A **Data Protection** section lists open data subject requests by due date and breaches not
yet reported, for the people who can see them. It does not show when there are none.

Until the org has a board or committee, the page opens with **Set Up Your Board** for anyone who
may create one (D-200 R4). Its **New Board or Committee** button opens the new record form (see
Boards and Committees below). It goes away once the first board is saved.

## Board Governance

Board governance (CH-09 to CH-20) lets staff run the board with no portal; board members act on
it through the [board portal template](portal-builder.md#ready-made-templates) (PB-02). A board
member is a person (Contact) in BarnCRM and needs no Salesforce login.

### Boards and Committees

A **Board or Committee** record is a board of directors, committee, task force, working group,
advisory council or chapter (Type). A committee names its **Parent Board**. Set the usual
**Term Length (Months)**, the **Term Limit** (consecutive terms, blank for none), the **Quorum
(Percent)** of voting members who must be present (51 when blank, a simple majority) and the
**Skills Wanted** for the skills matrix.

### Seats and Terms

Add a **Board Member** for each person's term: person, role (Chair, Vice Chair, Treasurer,
Secretary, Member, Ex Officio), term start and end, term number, and whether the seat votes. A
seat is **Current** while today falls within its term; a new term is a new row, so the related
list is the board's history. **At Term Limit** is checked when the term number reaches the
board's limit. The owner of the board gets a bell reminder once for each current seat whose term
ends within **Days before to remind** (the nightly Corporate Hub step).

The **Board** panel on the board's page shows the current seats, terms ending soon, the skills
matrix with the wanted skills nobody holds, open action items and, when BarnCRM Giving is
installed, the share of current members who gave this fiscal year (read from Giving This Year;
Corporate Hub never requires Giving). Age range and gender are optional on each seat and appear
only with **Show board demographics** on (off by default); collect them only if your board has
agreed to.

### Meetings

A **Board Meeting** has a start, location (or call link, or "held in writing" for a written
consent), status, agenda, **Packet Link** and minutes. Attach the packet and papers as Files on
the meeting; they count against your file storage. Put a link to the packet in Packet Link for
the portal: the portal shows that link and does not serve files itself, so choose where the
packet lives (for example a shared folder or a password-protected public link you create).

On the **Meeting** panel:

- **Invite Board** adds every current seat as an attendee (voting as on the seat), once each.
  Set each attendee's attendance; the panel shows whether quorum is met (voting members present
  against the board's quorum percent).
- **Submit Minutes for Approval** opens the minutes to members in the portal; the panel counts
  the members who approved them and who marked the packet read. An admin (Manage Corporate Hub)
  then uses **Mark Minutes Approved**, after the board approves them by its own procedure.
- **Action Items Carried Forward** lists the board's open action items raised at earlier
  meetings, until each is Done or Dropped.
- **Motions**: add a Board Motion to the meeting. **Open Voting** gives each voting attendee a
  vote to cast in the portal; staff can also fill in votes. **Close Voting** records Passed (more
  For than Against) or Failed and the date. When the meeting has not reached quorum, the outcome
  is recorded the same way, a warning says to check your bylaws before relying on the vote, and
  the motion's **Closed Without Quorum** box is ticked and shown under the motion in the panel
  (D-196). A meeting with no attendance recorded has not reached quorum, so closing voting on it
  always warns and ticks **Closed Without Quorum**: record attendance before closing. A vote
  cannot change once voting closes, except by an admin recording a vote taken by voice.
- **Availability Poll**: before the time is fixed, leave Start blank, fill in up to three Poll
  Times and use **Send Poll** (it invites the board first if needed). Members answer Yes, If
  Needed or No for each time in the portal; **Choose This Time** sets the start and closes the
  poll.

### Disclosures

Make your conflict-of-interest policy a Library Document with **Needs Acknowledgment** and **Ask
Every Year** checked. On the board's panel choose it and use **Request From Board**: each current
seat holder gets a request, which they answer in the portal (writing any interests and whether
they have a conflict) or which an admin records from paper. With Ask Every Year, requesting
again next year asks everyone again for the same version.

### Self-Assessment

**Start Self-Assessment** on the board's panel creates this year's self-assessment with the
shipped questions (`BarnCorporateHubTemplates`, `board-self-assessment`) for every current seat
holder. Members rate each statement 1 to 5 with an optional comment in the portal while it is
Open; set it Closed to stop changes. For results, create a custom report type on Board
Assessments with Assessment Answers and group a summary report by Question with the average
Rating.

### Board Dashboard

The **Board Governance** dashboard (folder BarnCRM Corporate Hub) shows the current roster, terms
ending in the next 90 days, attendance this year and open board disclosures. Giving
participation is on each board's panel, not the dashboard, so the dashboard never depends on
Giving.

## Reports

Build reports on Library Documents with Policy Acknowledgments, Compliance Obligations with
Compliance Cycles, and Agreements, as standard report types allow. Useful filters: Status
Requested and Version equal to the document's version (outstanding), Days Until Due less than 30
(due soon), Notice Date next 90 days.

Corporate Hub also ships the report types **Board Members**, **Board Meeting Attendees** and
**Policy Acknowledgments**, and four reports in the **BarnCRM Corporate Hub** folder: Current
Board Roster, Terms Ending Next 90 Days, Attendance This Year and Open Board Disclosures.

## Removing the Module

Uninstalling deletes every Library Document, acknowledgment, obligation, cycle and agreement
record, every processing activity, data subject request and data breach, and every board, seat, meeting, attendee, motion, vote, action item and assessment. Files stay in Salesforce Files, unlinked. The Module Manager's report counts the records
first.
