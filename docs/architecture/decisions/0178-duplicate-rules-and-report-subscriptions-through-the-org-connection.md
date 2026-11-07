# ADR-0178: Duplicate Rules Starter and report subscriptions through the org connection

**Status:** Accepted (builder decision)
**Date:** 2026-11-06
**Source:** C-61 Duplicate Rules Starter and C-63 Report subscription setup (plan D-156,
release 1.1); reuses the org connection of ADR-0148; narrows ADR-0050 ("BarnCRM ships no
matching rule and no duplicate rule")

## Context

Both features need a call Apex cannot make from a Lightning session: creating matching and
duplicate rules (Metadata API) and creating a report subscription (Analytics Notification
REST API). ADR-0148 already gives BarnCRM one admin-created connection, the Named Credential
`Barn_Org_Connection`, that a queued job calls with its own session; ADR-0174 added Tooling API
reads and writes through it. No second connection is added.

ADR-0050 rejected shipping BarnCRM rules: a packaged matching rule deploys inactive, needs Setup
steps, and an upgrade may clash with an admin's edits. C-61 does not ship rules. It creates
them in the org on an admin's click, as ordinary org metadata, so an upgrade never touches them.

### C-63 feasibility check (2026-11-06)

- The Analytics Notification API (`/services/data/vXX.0/analytics/notifications`, source
  `lightningReportSubscribe`) creates, lists and deletes the calling user's own report
  subscriptions: POST with the report Id, a schedule (daily, weekly on chosen days, or monthly
  on a day, at an hour) and a "send email" action with no extra recipients.
- Read on oi-test through the CLI (GET only, nothing changed): `analytics/notifications/limits`
  answered `{"userLimit":{"max":7,"remaining":7}}`, and the list of the user's subscriptions
  answered `[]`. So the API is on in the org, and each user may hold 7 report subscriptions.
- A queued job's session is the running user's, so a subscription created through
  `Barn_Org_Connection` belongs to the person who clicked Subscribe. That is the only owner the
  API allows without the Add Recipients permission, and it is what the feature needs.
- Limits: 7 per user (read at run time, not hard coded); one schedule per report per user;
  the user needs the Subscribe to Reports permission and access to the report's folder; the
  schedule hour is in the user's time zone. The run is native, so the email is sent by Salesforce
  and counts against nothing of BarnCRM's.
- Unproven until QA on a test org: the POST accepted with the job's session (as the SOAP and
  Tooling calls were in ADR-0148 A1 and ADR-0174). If it is refused, the page keeps the
  per-report **Open Report** link, where Subscribe is one click (the recommended alternative).

Verdict: feasible. The page is built.

## Decision

1. **One connection, two more uses.** `OrgMetadataApi` sends Metadata API SOAP calls
   (`upsertMetadata`) and `OrgToolingApi` gains a plain REST call for the Analytics API; both
   go through `Barn_Org_Connection` from a queued job only. Who may: the connection's own rule
   (ADR-0148 decision 2) for C-61. For C-63 the person needs Manage BarnCRM Metadata (BarnCRM
   Metadata Admin carries the credential's principal, so only its holders can call through the
   connection) and Salesforce's Subscribe to Reports; the subscription is their own. Everyone
   else sees the same list with **Open Report**, where Salesforce's Subscribe button is.
2. **C-61: create or repair only BarnCRM's own rules.** Two recommended sets, each a matching
   rule and a duplicate rule named `BarnCRM_...`:
   - People (Contact): first and last name, plus the same email, or the same street and postal
     code, or the same phone.
   - Households (Account, Household record type only): the same street with the same city or
     postal code, the same phone, or the same name with the same postal code (the evidence of
     ADR-0168).
   Both duplicate rules allow the save, alert, and report the pair, so imports and the scan
   keep working. The page shows the org's own rules on each object (left unchanged), what would
   be created or repaired and the rule in words, then acts on a confirm. Repair means: a
   BarnCRM matching rule that is not active is rewritten to the recommendation and activated;
   a BarnCRM duplicate rule that is missing or inactive is written and activated. An active
   BarnCRM matching rule is never edited (Salesforce refuses edits to an active rule). Nothing
   else in the org is changed, deleted or deactivated.
3. **Order.** A matching rule activates asynchronously, so the job writes the matching rules,
   then a delayed job checks each one every minute (up to 15 tries) and writes the duplicate
   rule once its matching rule is active. Each run ends with one Error Log entry in words; the
   page polls while the job runs.
4. **C-63: subscribe the running user.** Org Optimizer's Report Subscriptions section lists the
   reports in BarnCRM's report folders, each linked, with **Subscribe** and a frequency, day and
   hour. The job reads the person's subscription to that report and updates it, or checks the
   per-user limit and creates one; it logs only a failure, in words, which the page polls for.
   A Lightning call cannot read subscriptions (no API session), so the page does not list them
   or unsubscribe; the report's own Subscribe button changes or removes one.
5. **No connection.** Both pages explain the connection and show its setup panel; C-61 also
   links to Duplicate Rules in Setup, and C-63 keeps Open Report.

## Alternatives considered

- **Ship the rules in the package** (ADR-0050's rejected draft): inactive on install, Setup
  steps, upgrade clashes. Rejected again.
- **Edit or deactivate the org's standard rules.** Never: the org's own rules are its
  administrator's, and this tool only adds BarnCRM's beside them.
- **Tooling API create for rules.** Matching and duplicate rules are Metadata API types; the
  SOAP path ADR-0148 proved is used.
- **C-63 without the connection.** Apex has no report subscription API and
  `ReportNotification` style objects are not writable; the alternative is the Open Report
  link to Salesforce's own Subscribe button, kept as the fallback.

## Consequences

- Security review scope grows inside the ADR-0148 connection: Metadata API `upsertMetadata` for
  two named rule pairs, and the Analytics Notification API for the running user's own
  subscriptions. Admin click for rules; self-only for subscriptions.
- Two active rules on an object (the org's and BarnCRM's) can both alert on a save; the page
  says so and leaves the choice to turn one off in Setup to the admin.
- In an org with person accounts the people rule covers people stored as contacts only.
- No new BarnCRM object or field; canonical model unchanged.
- Unproven on an org until QA: `upsertMetadata` of `MatchingRule` and `DuplicateRule` with the
  job's session, the record type filter item, and the notification POST.
