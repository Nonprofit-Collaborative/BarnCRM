# Project Management: Requests and Issues

## What It Does

Requests and issues (release 1.21, D-201) give your team one place for the things people ask of
it: "the report is wrong", "please add a user", "can you build a form". Staff log a request,
set its priority, assign it, talk it through in comments and resolve it, and turn it into a
project task or a change request when it becomes real work. Optionally, requesters outside your
staff send and follow their own requests through a BarnCRM portal, and another organization's
Salesforce can send its own Cases to you as requests.

It suits a shared-services nonprofit, a fiscal sponsor serving its projects, an operations or IT
team serving program staff, or a consultant serving client nonprofits. It is off until you turn
it on, and it does not need Track time and budgets.

| Part | Needs |
|---|---|
| Staff requests: the Requests tab, triage, comments, Create Task and Create Change Request | Track requests and issues |
| Requesters in the portal | Take requests from outside, BarnCRM Portal Builder, a portal using the Requests template |
| Requests from another organization | Take requests from outside, a request connection for that organization |
| Sending your own Cases to a service provider | BarnCRM Mirror in your org (see below) |

## Settings

BarnCRM Settings, **Projects** (org-wide):

| Setting | Default | What it does |
|---|---|---|
| Track requests and issues | Off | The Requests tab and request records. New requests are refused while it is off; saved ones can still be worked. |
| Take requests from outside | Off | Requests from the portal and from other organizations. Works only while Track requests and issues is on. |
| Urgent request due days | 1 | Weekdays from creation to the due date of an Urgent request (1 to 365). |
| High request due days | 2 | The same for High. |
| Medium request due days | 5 | The same for Medium. |
| Low request due days | 10 | The same for Low. |

The due date is filled in only when it is blank, so staff can always set their own.

## Who Does What

| Permission set | Requests and comments | Request connections |
|---|---|---|
| Projects Admin | Create, edit, delete | Create, edit, delete |
| Projects Staff | Create and edit | Read |
| Projects Read Only | Read | Read |

Requests are visible to everyone with Projects access (sharing Read/Write, like projects). If
your requests hold private matters, set the Request object's org-wide default to Private in
Setup, Sharing Settings, and share by owner or queue.

**Assigning.** A request's owner is who works it: a person or a Salesforce queue. To give your
team a shared inbox, create a queue in Setup, Queues, add Request to its objects and add the
team. The Unassigned view of the Requests tab lists requests a queue owns.

## A Request's Life

| Status | Meaning |
|---|---|
| New | Not yet looked at. |
| In Progress | Someone is working on it. |
| Waiting on Requester | You asked the requester something. The due date clock pauses: it is not counted Overdue. |
| Resolved | Done, with a resolution the requester sees. Needs a Resolution. |
| Closed | Finished; no more work. |
| Cancelled | Withdrawn or not going ahead. |

A requester's reply from the portal moves a Waiting on Requester or Resolved request back to In
Progress. **Overdue** is checked while a New or In Progress request is past its due date.

**Comments.** A comment is internal unless **Shared With Requester** is checked. Shared comments
are emailed to the requester (when the request has a requester with an email address) and shown
in the portal; internal ones never leave your staff.

**Linking to work.** On the request panel: **Create Task** adds a task, named from the subject, to
the request's project and links it; **Create Change Request** adds a Draft change request to the
project (needs Track change requests). Time entries have a **Request** field, so time spent on a
request is counted and reported.

**Notifications.** The new owner gets a bell notice when a request is assigned to them by
someone else, and the owner gets one when a requester replies or a request arrives from outside.
The requester gets an email when staff share a comment and when the request is Resolved.

## Requesters in the Portal

With **BarnCRM Portal Builder** installed and set up (see [Portal Builder](portal-builder.md)):

1. Turn on **Take requests from outside**.
2. Create a portal with the **Requests** template (`portal-client/templates/requests.json`), and
   give your requesters access (Invited) or let any person on file sign in (Any Matching Person).
3. Requesters sign in with a code sent to their email. **My Requests** lists their own requests and
   lets them send a new one (subject, type, category, priority, description), reply, and say
   whether they are satisfied once it is resolved. **Updates** shows the comments you shared on
   their requests. Internal comments and other people's requests are never shown.

A requester cannot change a request's subject, description, type, category or priority after
sending it; only their reply and satisfaction are saved. Portal requests are refused while Take
requests from outside is off.

## Requests From Another Organization

Another Salesforce org (a partner nonprofit, a client) can send requests straight into yours
and get the status back. In **your** org (the provider):

1. Turn on **Take requests from outside**.
2. For each sending organization, create an integration user (a Salesforce Integration license
   where you have one; see [Portal Builder](portal-builder.md) for that license's terms) and give
   it the permission set **Projects Request Intake**, which reaches only the request API.
3. Create an **External Client App** (or connected app) with the OAuth client credentials flow,
   run as that integration user, and give its consumer key and secret to the sending
   organization's admin by a secure route.
4. On the **Request Connections** tab, add a connection: the organization's name, its Account,
   its **Org Id** (the 18 character Salesforce organization id they give you), the integration
   user, Active, and the **Hourly Limit** (new requests an hour, default 60).

Requests arrive with Channel **Partner Organization**, the connection's Account as Requesting
Organization, and the sender's own reference. The requester's name and email are written in the
description; no Contact is created. Turning a connection off stops it at once.

The API: `POST /services/apexrest/barncrm/requests/v1/requests` with JSON `orgId`, `reference`,
`subject`, `description`, `type`, `priority`, `category`, `requesterName`, `requesterEmail`;
answers `number`, `status` and `dueDate`. Sending the same `reference` again returns the same
request. `GET /services/apexrest/barncrm/requests/v1/requests?refs=A,B` (up to 200) answers the
status, due date and resolution of that organization's own requests. Any refusal answers `403`,
too many new requests in an hour `429`.

## Sending Your Cases to a Service Provider (BarnCRM Mirror)

An org that uses Salesforce Cases and has **BarnCRM Mirror** installed can send a Case to a
provider org running BarnCRM Projects.

## Reports

In the BarnCRM Projects folder, on the **Requests** report type: **Open Requests**, **Overdue
Requests** and **Requests Resolved This Month** (with satisfaction).

## Common Mistakes

- **Requests tab says requests are off.** Turn on Track requests and issues.
- **Portal requests fail with "save failed".** Turn on Take requests from outside; check the Error
  Log for the reason.
- **Resolved will not save.** Enter a Resolution first: the requester sees it.
- **A partner org gets 403.** The connection must be Active, name the integration user the call
  runs as, and its Org Id must match the org sending.

## Removing the Module

Uninstalling Projects deletes requests and comments with the rest of the module's records.
