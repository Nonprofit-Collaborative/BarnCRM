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

The **Corporate Hub**, **Library Documents**, **Compliance Obligations** and **Agreements** tabs
join the BarnCRM and BarnCRM Console apps before Error Log. Corporate Hub has no app of its own.

## Access

| Permission set | Who gets it automatically | What it allows |
|---|---|---|
| Corporate Hub Admin | BarnCRM Admin holders | Everything, every record, including deleting, requesting acknowledgments, publishing versions, recording an acknowledgment for someone else and loading templates (custom permission Manage Corporate Hub) |
| Corporate Hub Staff | Team Member and Fundraising Staff holders | Create and edit documents, obligations, completed cycles and agreements; never delete; answer their own acknowledgments |
| Corporate Hub Read Only | Read Only holders | Read everything above; answer their own acknowledgments |

Sets are given, never taken away. Library Documents and Agreements are readable by everyone and
editable by their owner and admins; Compliance Obligations are editable by every Staff holder;
each acknowledgment is owned by, and visible to, the person asked (and admins).

## Settings

BarnCRM Settings, **Corporate Hub**:

| Setting | Default | What it does |
|---|---|---|
| Send Corporate Hub reminders | On | Whether the nightly run sends the bell reminders. |
| Days before to remind | 30 | How many days ahead an owner is reminded, for any record that has no Reminder Days of its own (1 to 365). |
| Days to acknowledge | 30 | The due date a new acknowledgment request gets (1 to 365). |

The reminder step is **Corporate Hub reminders** on the Nightly Jobs page, at 6:45 AM, with its
own switch.

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
is set). Each night an Active, auto-renewing agreement past its end date moves on by its term,
and any other Active agreement past its end date becomes Expired.

## Reports

Build reports on Library Documents with Policy Acknowledgments, Compliance Obligations with
Compliance Cycles, and Agreements, as standard report types allow. Useful filters: Status
Requested and Version equal to the document's version (outstanding), Days Until Due less than 30
(due soon), Notice Date next 90 days.

## Removing the Module

Uninstalling deletes every Library Document, acknowledgment, obligation, cycle and agreement
record. Files stay in Salesforce Files, unlinked. The Module Manager's report counts the records
first.
