# User Guide

Applies to: BarnCRM landing/batch-c-review ef74bfa4 (v1.0 and Batch C with its whole-solution review, releases 0.12 to 1.3). Pre-release: no package version exists yet; this tracks the newest code on main.

## Who This Is For

This guide is for staff who use BarnCRM every day: you look people up, keep households and addresses current, enter gifts, sign volunteers up for shifts and log their hours. You are not the person who installs or configures BarnCRM (installing is on [Installing BarnCRM](../admin-guide/installing.md) in the Admin Guide).

Each page is a set of short recipes ("To do X: 1. 2. 3.") using the names you see on screen. Where a task needs an admin (a setting, a permission, a template), the page says so and links to the [Admin Guide](../admin-guide/README.md) instead of explaining it.

What you can do depends on the role your admin gave you on the Access page (for example Fundraising Staff, Team Member or Read Only) and on which modules your organization uses. If a tab, button or panel in this guide is missing for you, ask your admin.

## Pages

### Getting Started

- [Getting around BarnCRM](getting-around.md): the apps, tabs, Home, What's new, in-app tips and notifications.
- [Read only access](read-only-access.md): what a person with the Read Only role can and cannot do.
- Moving from another app: when your organization moves records from another app in the same org (for example DLRS rollups, NPSP relationships, affiliations and addresses, or Volunteers for Salesforce jobs, shifts and hours), your admin runs the [Migration Assistant](../admin-guide/migration-assistant.md). Nothing changes in your daily work until they finish; ask them when the old app's screens stop being updated.

### People and Households

- [Finding people and records](find.md): search, list views and the Find tab.
- [Changing many records at once](super-transform.md): Super Transformer, with a preview and an undo, saved lists and a phone format.
- [Field history](field-history.md): who changed a field on a record, when, and what it was before.
- [People and households](people-and-households.md): adding people, household members, names and greetings, merge and split, interaction notes.
- [Addresses, email and phone](addresses-email-phone.md): several addresses, seasonal addresses, the preferred email and phone, and their Contact Point copies where Contact Point Sync is installed.
- [Relationships and affiliations](relationships-affiliations.md): how people are connected to each other and to organizations.
- [Reviewing duplicates](duplicates.md): checking likely duplicate pairs and merging them.

### Gifts (Nonprofit Edition)

- [Entering gifts](gifts.md): Quick Gift Entry, the Enter a Gift action, funds, soft credits, tributes, in-kind, stock, planned, donor-advised fund and matching gifts.
- [Gift batches](gift-batches.md): typing a stack of checks against a deposit total.
- [Pledges and recurring gifts](commitments.md): commitments, installments and paying them.
- [The Ask Pipeline](ask-pipeline.md): tracking asks by step on a board, and closing them as won, declined or withdrawn.
- [Refunds and write-offs](refunds.md): recording money that went back, and cancelling a pending gift.
- [Receipts and acknowledgments](receipts-and-acknowledgments.md): receipts, thank-yous and stewardship plans.
- [Ask reminders](ask-reminders.md): a next ask date on a donor, the task that reminds you, and the Who Is Due list.

### Volunteers (Nonprofit Edition)

- [Volunteer jobs, shifts and sign-ups](volunteer-shifts.md): finding and creating shifts, recurring shifts, signing people up and marking attendance.
- [Volunteer hours, profiles and letters](volunteer-hours.md): logging and approving hours, a volunteer's profile and readiness, hour letters.

### Programs (Nonprofit Edition)

- [Programs, services and enrollments](programs.md): creating programs and services, enrolling people and moving them through the stages, taking attendance, counting drop-in visitors without names, recording referrals, screening for eligibility, keeping a participant's service plan, and putting people in cohorts with scheduled sessions and attendance.

### Logic Models (Nonprofit Edition)

- [Logic models](logic-models.md): building a logic model with arrows and assumptions, and measuring outputs and outcomes with indicators, targets and results, filled in by hand, from a spreadsheet or worked out from your records, and comparing periods in a report for funders.

### Funders (Nonprofit Edition)

- [Grants and funders](funders.md): adding grants, moving them through the stages on the Grant Pipeline, the deadlines coming up and the Grant Calendar, the program a grant pays for, an award's payments, a restricted grant's ledger and Giving fund, government award fields, the answer library, linking a requirement to the outcome it reports on, funder reports and the Board Dashboard.

### Forms

- [Forms](forms.md): filling in a form a step at a time, seeing a submission and the records it wrote, and finishing one held for review.

### Event Management

- [Events](events.md): finding, creating and repeating events, setting up tickets, building the agenda, reading the event dashboard, offering appointments, planning volunteers, adding speakers, managing sponsors, reviewing speaker applications, registering people and their reminder and follow-up emails, and checking people in.

### Portal Builder

- [Portals](portal-builder.md): who can sign in to a portal, ending someone's portal sessions, what a person sees when they sign in, and what the volunteer, speaker and donor portals show and let them do.

### Corporate Hub

- [Corporate Hub](corporate-hub.md): acknowledging policies, what is due on the Corporate Hub page, Library Documents and their versions, completing a compliance obligation with its evidence, agreements and reminders.

### Payments

- [Payments](payments.md): finding a payment taken online, what its status means, and how refunds are made.

### Reports

- [Reports and dashboards](reports-and-dashboards.md): the reports and dashboards BarnCRM ships, and the totals on records.
- [Donor segments](donor-segments.md): lists of donors by their giving, exported for Mailchimp or Constant Contact.
- [Donor scores](donor-scores.md): how recently, how often and how much each donor gives, as a score and a segment on their record, and any wealth screening loaded for them.

## Report a Bug or Give Feedback

If something in BarnCRM or in this guide is wrong or unclear, open an issue on GitHub: [github.com/Nonprofit-Collaborative/BarnCRM/issues/new/choose](https://github.com/Nonprofit-Collaborative/BarnCRM/issues/new/choose). Pick **Bug report** for something that does not work as described, or **Feature request** for an idea.

- See [SUPPORT.md](../../SUPPORT.md) for what to include: what you did, what you expected, what you saw, and the exact message on screen.
- Never include donor or personal data (names, emails, addresses, gift amounts). Describe the record instead, or use sample data.
- Report a security problem privately as [SECURITY.md](../../SECURITY.md) describes, never in a public issue.

BarnCRM is self-service open source software: issues are read by the project, but no response or fix time is promised.

## Related Guides

- [Overview](../overview.md): what BarnCRM is and what is built now.
- [Admin Guide](../admin-guide/README.md): setting up and running BarnCRM.
- [Feature catalog](../barncrm-features.md): every feature and its status.
