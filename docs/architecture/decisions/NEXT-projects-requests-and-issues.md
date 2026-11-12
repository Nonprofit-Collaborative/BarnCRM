# ADR-NEXT: Projects requests and issues: staff triage, a portal template for requesters, an org-to-org intake API and a Mirror Case bridge, each off until turned on

**Status:** Accepted (builder decision, for Brandon to confirm)
**Date:** 2026-11-12
**Source:** D-201 (Brandon, 2026-11-12): "For the Projects/PSA module, please research how internal
org requests are solutions in general and add an option to enable a requests/issues management
feature with internal and optionally (with setting enabled) external via a portal site." And:
"Preferably, that case/request submission feature would also allow for other orgs to submit a
request (via a standard Salesforce Case perhaps) that are logged back to the case management
org." Release 1.21. Builds on ADR-0219 `0219-projects-psa.md` (Projects settings, permission
sets, change requests), ADR-0185 `0185-portal-builder-off-platform-portal-api.md` (the portal
engine and its person-scoped API), ADR-0017 (cross-package mechanisms), ADR-0013 (standard
objects only in Mirror), ADR-0166 (nightly run), ADR-0164 (help text JSON) and ADR-0201 (the
PaymentWebhookRest per-sender hourly cap).

## Context

Organizations running Projects (shared-services nonprofits, fiscal sponsors, an operations or IT
team serving program staff, a consultancy serving nonprofits) take requests: "the report is
wrong", "add a user", "can you build a form". Today these arrive by email and either become
project tasks with no record of who asked, or are lost. D-201 asks for an optional request and
issue feature: staff log and work requests; optionally requesters outside the staff submit and
follow them through a portal; optionally another Salesforce org sends its own Cases in.

## Research: how service desks and PSA tools handle requests

Sources (read 2026-11-12):
[Jira Service Management, working with customers on requests](https://community.atlassian.com/learning/path/get-the-most-out-of-jira-service-management/course/get-started-quickly-with-jira-service-management/lesson/work-with-customers-on-requests-in-jira-service-management),
[Jira Service Management agent guide](https://confluence.atlassian.com/servicemanagementserver/getting-started-for-service-desk-agents-939926229.html),
[ServiceNow incident life cycle](https://www.servicenow.com/docs/r/zurich/it-service-management/incident-management/incident-management-process.html),
[ServiceNow incident FAQ (impact, urgency, priority)](https://www.servicenow.com/community/itsm-articles/fqa-of-incident-management/ta-p/2309617),
[Freshservice SLA policies and due by times](https://support.freshservice.com/en/support/solutions/articles/156455-understanding-due-by-times-and-sla-policies),
[Freshservice escalations](https://support.freshservice.com/support/solutions/articles/156464-manage-ticket-escalations-in-freshservice),
[Freshworks: incident versus service request](https://www.freshworks.com/explore-it/incident-service-request/),
[Salesforce Support agents guide (Case, comments, Web-to-Case, Email-to-Case)](https://resources.docs.salesforce.com/208/latest/en-us/sfdc/pdf/support_agents.pdf),
[Salesforce Support admin guide (assignment, escalation, entitlements)](https://resources.docs.salesforce.com/208/latest/en-us/sfdc/pdf/support_admins.pdf),
[TeamDynamix: converting tickets to project requests](https://solutions.teamdynamix.com/TDClient/1965/Portal/KB/Article/164872/Converting-Tickets-to-Project-Requests),
[Adobe Workfront community: convert a request to a task](https://experienceleaguecommunities.adobe.com/adobe-workfront-23/looking-for-a-way-to-take-one-intake-request-with-multiple-actions-to-split-them-into-multiple-projects-127369),
[Birdview PSA: project intake](https://birdviewpsa.com/blog/project-intake-best-practices/).

The common core, and what this design keeps:

| Element | What the tools do | Kept here |
|---|---|---|
| Intake channels | Staff entry, portal form, email, API, chat | Staff entry, the portal, an org-to-org API. Email-to-request is left out (decision 9). |
| Request types | Incident or problem versus service request versus question versus change; each type its own form and SLA in large tools | One Type picklist (Question, Problem, Service Request, Change) and an open Category picklist the org extends |
| Priority | Impact times urgency gives priority (ServiceNow); a single priority elsewhere | One Priority (Low, Medium, High, Urgent): a matrix is more than a small team triages by |
| Status life cycle | New, In Progress, On Hold or Pending (awaiting the caller), Resolved (reopenable), Closed | New, In Progress, Waiting on Requester, Resolved, Closed, Cancelled; a requester's reply reopens |
| Assignment and queues | Assignment rules, groups, queues | Record owner: a user or a Salesforce queue, so the org's own queues and assignment habits work |
| SLA targets and breach warnings | Response and resolution targets per priority, business hours, escalation levels | A resolution due date from days per priority (weekdays), an Overdue flag that pauses while waiting on the requester, list and report highlighting |
| Comments | Internal notes versus replies the requester sees (Jira: Add internal note versus Reply to customer; Salesforce: Public on a case comment) | Request Comment with Shared With Requester, off by default |
| Linking to work | Convert or link a ticket to a task, project or change request (Workfront, TeamDynamix, PSA intake) | Link to a project; Create Task and Create Change Request; time entries may name a request |
| Requester notifications | Email on reply and on resolve | Email the requester on a shared comment and on Resolved; a bell notice to the owner on assignment and on a requester's reply |
| Satisfaction | A survey after resolution | One Satisfaction field the requester sets in the portal |
| Reporting | Volume, backlog, overdue, time to resolve, satisfaction | Reports on a Requests report type: Open Requests by Owner, Overdue Requests, Requests Resolved This Month |

## Decision

### 1. Settings: two switches, both off at install

`Projects_Settings__c` gains (Setting Definitions in the Projects section, Help Path
`projects-requests.md`):

| Setting (Setting Definition) | Field | Default |
|---|---|---|
| Track requests and issues (`Projects_Requests_Enabled`) | `Requests_Enabled__c` | Off |
| Take requests from outside (`Projects_Requests_External_Enabled`) | `Requests_External_Enabled__c` | Off; works only while Track requests and issues is on |
| Urgent request due days (`Projects_Request_Days_Urgent`) | `Request_Days_Urgent__c` | 1 (1 to 365) |
| High request due days (`Projects_Request_Days_High`) | `Request_Days_High__c` | 2 |
| Medium request due days (`Projects_Request_Days_Medium`) | `Request_Days_Medium__c` | 5 |
| Low request due days (`Projects_Request_Days_Low`) | `Request_Days_Low__c` | 10 |

Requests do not need Track time and budgets: an organization that only plans projects may still
take requests. One external switch covers both the portal and other organizations, since each of
those also needs its own setup (a portal using the template, an active connection) before
anything arrives; two switches would add a second thing to forget without adding control.

### 2. Objects (canonical model 29PM16 to 29PM18)

- **Request (`Project_Request__c`)**, auto number `REQ-{000000}`, sharing Read/Write (Project's
  model; an org that wants requests private sets it to Private), field history on Status
  and Priority. Subject (required), Description, Type, Category, Priority, Status,
  Channel (Staff, Portal, Partner Organization, set by Apex), Requester (Contact), Requesting
  Organization (Account), Project, Project Task (filtered to the project), Change Request, Due
  Date, Resolved Date, Resolution (the requester sees it), Overdue (formula), Satisfaction, and
  Reply (a portal-only inbox field, decision 5). Owner is the assignee: a user or a queue.
- **Request Comment (`Project_Request_Comment__c`)**, master-detail to Request: Body, Shared
  With Requester (default off), From Requester (set by Apex).
- **Request Connection (`Request_Connection__c`)**, the provider side of one partner org (decision
  6): partner name, Requesting Organization (Account), Org Id (unique), Integration User, Active,
  Hourly Limit (default 60).
- **Time Entry** gains a Request lookup (Set Null): time can be logged against a request at no
  other cost, and Projects reports sum it.

### 3. Internal: staff log, triage, assign, resolve, link

- A **Requests** page tab (`Projects_Requests`, Staff_Tabs) lists requests by view: My Open, All
  Open, Unassigned (owned by a queue), Overdue, Recently Closed. Choosing one opens the request
  panel (`projectsRequestPanel`, also placeable on the Request record page): status, priority,
  owner, due date, project, resolution, the comment thread with Shared marked, Add Comment (with a
  Share With Requester box), Create Task (on the linked project, name from the subject) and
  Create Change Request (Draft, needs Track change requests). New Request opens the standard new
  record page. The controller is thin (`ProjectRequestsController`), returns plain DTOs and
  writes in user mode; list filtering and view rules live in the framework-free
  `c/projectsRequestsModel`.
- **Before save** (`ProjectRequestHandler`, registry row `Project_Request_Rules`, Always Runs):
  a blank Channel becomes Staff when the saving user can create requests and Portal otherwise
  (only the portal's integration user, which has no object access, saves one without that right);
  a Portal or Partner Organization request is refused unless both switches are on; a blank Due
  Date becomes today plus the priority's days, counted in weekdays; a blank Requesting
  Organization takes the requester's Account; Resolved or Closed stamps Resolved Date and a
  reopen clears it; a save by a user who cannot edit requests (the portal) keeps Subject,
  Description, Type, Category and Priority as they were, so a requester cannot re-prioritize.
- Validation: `Requests_Turned_On` (no new request while the feature is off), `Resolution_Needed`
  (Resolved needs a Resolution), and on the comment `Body_Needed`.
- **Notifications** use Core's `JobNotifier.ownType` with a packaged type `Projects_Request`:
  the new owner on assignment (not when assigning to oneself or a queue), the owner on a
  requester's reply and on a request arriving from outside. The requester (when they have an
  email) gets an email on a shared comment and on Resolved, with the resolution. No escalation
  emails: the Overdue flag, the Overdue view and report are the breach warning (decision 9).

### 4. Permission sets (ADR-0194: no new set for staff)

| Object | Projects Admin | Projects Staff | Projects Read Only |
|---|---|---|---|
| Request | All | Create, read, edit | Read |
| Request Comment | All | Create, read, edit | Read |
| Request Connection | All | Read | Read |

Plus `Projects_Request_Intake` (decision 6), which grants only the API class, never given
automatically.

### 5. External via the portal: a template, no new site

Portal Builder (ADR-0185) already gives a signed-in, person-scoped, off-platform portal with no
Salesforce license per requester. Projects ships no portal code; it ships a template,
`portal-client/templates/requests.json` (requires module Projects), used by Portal Builder when
both are installed and doing nothing otherwise, so neither package depends on the other:

- **My Requests**, a related page on Request with `personField` Requester: Subject, Type,
  Category, Priority and Description editable on create; Number, Status, Due Date and Resolution
  read only; Reply and Satisfaction editable. Actions `create` and `update`. The before save rule
  above keeps the requester's later edits to the request itself from sticking.
- **Updates**, a related page on Request Comment with `personField` `Request__r.Requester__c` and
  `where` Shared With Requester equals true: the request number and subject, the comment and its
  date. Read only. Internal comments are never on a page.
- **Replying.** The engine cannot create a comment on a parent-hop page, and module actions take
  no text. So the request carries a Reply field the requester fills; the before save rule moves it
  into a new comment marked From Requester and Shared, clears it, and moves a Waiting on
  Requester or Resolved request back to In Progress. No engine change, no Core seam.
- The portal saves in system mode as its integration user; the Channel rule marks those saves
  Portal, and the external switch refuses them while off (the portal answers `save_failed`).

### 6. Other organizations: an authenticated intake API in the provider org

- `ProjectRequestApi`, Apex REST `/services/apexrest/barncrm/requests/v1/requests`:
  `POST` creates a request from `{ orgId, reference, subject, description, type, priority,
  category, requesterName, requesterEmail }` and returns `{ number, status, dueDate }`; the same
  `reference` again returns the existing request (key Connection plus reference, unique field
  `External_Key__c`), so a resend never duplicates. `GET ?refs=a,b` (at most 200) returns the
  status, due date and resolution of this sender's own requests by reference.
- **Who is calling.** Each partner org connects as its own integration user in the provider org
  (OAuth client credentials through an External Client App; a Salesforce Integration license
  where available, ADR-0185 research), given `Projects_Request_Intake` (the API class only, no
  object access). A call is served only when an Active Request Connection names the calling user
  and its Org Id equals the body's `orgId`; anything else is `403 not_allowed`, the same answer
  for every refusal. Requests read and written in system mode, only that connection's rows
  (without sharing register: Projects intake kind).
- **Limits.** Bodies over 32 KB are refused; a connection's creates in the last hour at its Hourly
  Limit answer `429`, as PaymentWebhookRest caps per processor; both switches off answer `403`.
  Errors return a short code, never a stack or record detail.
- **No secret in a custom setting.** The provider stores none; the submitting org's credential is
  its own Named Credential (decision 7).
- Requester name and email are written into the request's description, not matched to a Contact:
  matching people across organizations by email would create or reveal Contacts the provider
  should not have. The submitting org talks to its own requester; the provider's resolution and
  status flow back to it.

### 7. A submitting org with a standard Case: a Mirror bridge

Case is a standard object, so the submitting side is in `packages/mirror` (ADR-0013), off by
default:

- `Mirror_Settings__c.Case_Requests_Enabled__c` (Setting Definition `Mirror_Case_Requests`,
  default off).
- Case gains Send to Service Provider (checkbox), Provider Request Number, Provider Request
  Status, Provider Resolution and Provider Synced.
- A Case trigger through the Core dispatcher (registry row `Case_Provider_Request`) queues the
  send when Send to Service Provider is checked and no number is stored, while the setting is on.
  The queued job posts the Case (reference the Case Number, subject, description, priority
  mapped High, Medium, Low, requester the Case's contact) to `callout:Barn_Request_Provider` and
  writes back the number and status. A failure is written to the Error Log and the Case stays
  unsent, so unchecking and checking again retries.
- Status comes back by pull, never push: a nightly Mirror step (`CaseRequests.step()`, ADR-0166)
  asks for the status of every sent Case not yet Resolved, Closed or Cancelled, 200 per call, and
  writes Status, Resolution and Synced. Pull needs one credential, in one direction.
- **Credential.** The admin creates the External Credential (OAuth 2.0 client credentials to the
  provider's External Client App) and the Named Credential `Barn_Request_Provider` (the provider's
  My Domain) in Setup, and grants its principal to the users who send Cases and to the user the
  nightly run runs as. Nothing is shipped for it: its URL and secret are the org's own, and the
  platform stores the secret.
- Submitting orgs without BarnCRM use the portal (decision 5), or call the API from their own
  integration.

### 8. Tabs, pages, reports, sample data

Requests page tab (Staff_Tabs, after Approvals); Request Connections tab (Admin_Tabs); Request
layout with Comments and Time Entries; report type Requests and three reports in the BarnCRM
Projects folder. No sample data: Projects ships none.

### 9. Left out, on purpose

- **Email-to-request.** Salesforce Email Services need an email service address per org and an
  inbound handler with its own spoofing concerns; the portal already gives a verified requester.
- **Response targets, business hours, escalation levels, impact times urgency.** A small team
  needs one due date and a visible overdue list; each of these is configuration a three-person
  team would not maintain.
- **Pushing status to the submitting org.** It needs credentials to every partner org in the
  provider; nightly pull needs none.

## Implementation split (stacked pull requests, base `landing/batch-k`)

1. This ADR, canonical model, objects, settings, permission sets, layout, report type.
2. Internal Apex (handler, controller, notifications), the Requests tab and LWCs, help, guides.
3. The portal template and its offline check.
4. The org-to-org API, Request Connection, the intake permission set.
5. The Mirror Case bridge.

## Open questions for Brandon

1. **Nightly status pull** (decision 7): enough for partner orgs, or should the submitting org
   also refresh on a schedule during the day? An hourly schedule is a small addition.
2. **Mirror requires Giving.** Mirror depends on Giving and Rollup Builder, so a submitting org
   must install them to use the Case bridge. Moving the bridge to a small package of its own
   would avoid that; this design follows the brief and puts it in Mirror.

## Alternatives considered

- **Reuse Resource Request or Change Request.** Rejected: each has a project master and a
  different life cycle; a request may have no project yet.
- **A Salesforce Site and guest user form for requesters.** Rejected by ADR-0185 and D-187: the
  portal gives a verified requester without a guest user.
- **Forms public form for intake.** Possible for anonymous intake, but a requester could then
  never see their own requests; the portal does both. An org may still map a form to Request.
- **One integration user for every partner org, told apart by `orgId`.** Rejected: the body is
  not authenticated, so one partner could submit as another.

## Consequences

- Three objects and one Time Entry field in Projects (canonical model 29PM16 to 29PM18), six
  settings, one permission set, one notification type, two tabs.
- The portal surface works only where Portal Builder is installed and its plugin set up.
- The Case bridge needs Mirror (and so Giving) in the submitting org and a Named Credential the
  admin sets up.
