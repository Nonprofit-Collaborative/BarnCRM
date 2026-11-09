# Portal Builder

## What It Does

BarnCRM Portal Builder lets people outside your staff, such as volunteers, speakers or donors,
sign in to a portal and see or update their own records, without a Salesforce license each. The
portal runs off Salesforce, for example on your WordPress site, and reaches Salesforce through
**one integration user**. Inside Salesforce, the Portal Builder module checks every request:

- **Sign-in by emailed code.** A person types their email; Salesforce emails them a six-digit
  code and checks it. Codes are stored only as hashes and are never returned to the website.
- **Optional second factor.** A portal can also ask for a code from an authenticator app
  (Google Authenticator, Microsoft Authenticator, 1Password and the like). No text messages, so
  nothing to pay for.
- **Person-scoped pages.** Each portal has a template: its pages, the objects and fields on
  each, and what the person may change. Every request names the signed-in person, and Salesforce
  returns or changes only that person's records, only on those pages.
- **Sessions you control from Salesforce.** Sessions end after a time limit, after sitting idle,
  or the moment you suspend the person, set the portal Inactive or turn Portal Sign-In off.

BarnCRM ships the portal client as source code (in the `portal-client` folder of the BarnCRM
repository, with a small WordPress plugin). BarnCRM does not host portals and offers no
installation service: you, or a developer you choose, put it on your own website.

## Before You Start: The Integration User and Its License

The website signs in to Salesforce as one user. Which license that user needs depends on your
org:

- **Salesforce Integration user license (no extra cost where you have it).** Salesforce
  includes a small number of these API-only licenses in Enterprise, Unlimited, Performance and
  Developer Editions ("one or more", Salesforce Spring '23 release notes; the BarnCRM test org,
  an Enterprise Edition sandbox, shows 5). Check **Setup, Company Information, User Licenses**
  for **Salesforce Integration**. Professional Edition is not listed.
- **A regular user with API access (the fallback).** If you have no Salesforce Integration
  license free, or the check in step 6 below fails, use a Salesforce Platform or Salesforce user
  with **API Enabled**. That costs one license for the whole portal, not one per person.

**Confirm the terms with Salesforce.** Offer the Integration license first where you have one,
and use the regular API-enabled user below if you do not or Salesforce says no; BarnCRM works with
either. Salesforce's Spring '23 release notes
([link](https://help.salesforce.com/s/articleView?id=release-notes.rn_api_integration_license.htm&release=242&type=5))
say the license "may not be used for human users to access Salesforce data or features through
any user interface", and describe it as for system-to-system integrations. A portal shows people their own records through
your website. Whether that use is allowed under your contract is a question for your Salesforce
account executive, not something BarnCRM can answer. Ask before you go live.

**A small board?** If only a handful of people need access, donated or spare internal Salesforce
licenses (where your organization has them) may be simpler than a portal.

## How to Set It Up

1. **Install the module.** Install BarnCRM Portal Builder and turn it on in the Module Manager.
   You get the Portal Builder Admin permission set; every BarnCRM Admin holder gets it within the
   hour.
2. **Create the integration user.** In Setup, Users, create a user such as "Portal Integration",
   with the **Salesforce Integration** license and the **Minimum Access - API Only Integrations**
   profile (or, for the fallback, a Platform or Salesforce license with API Enabled). Give it an
   email address you read.
3. **Assign the Portal Builder Integration permission set to that user, and nothing else from
   BarnCRM.** It lets the user call the portal API and nothing more: it grants no object access,
   so the integration user cannot read your contacts through Salesforce's own API. Assign it in
   Setup, Users, the user, Permission Set Assignments. On a Salesforce Integration user, also
   assign the permission set license **Salesforce API Integration** if Salesforce asks for it.
4. **Create the External Client App (or connected app).** In Setup, External Client App Manager
   (or App Manager, New Connected App in older orgs):
   - Name it "BarnCRM Portal", enable OAuth, and give any callback address (for example
     `https://localhost/callback`; the client credentials flow does not use it).
   - Select the OAuth scope **Manage user data via APIs (api)**.
   - Turn on **Enable Client Credentials Flow**.
   - Save, then in the app's policies set **Run As** (the client credentials user) to the
     integration user from step 2, and limit **Permitted Users** to admin-approved users with
     that user approved.
   - Copy the **Consumer Key** and **Consumer Secret**. Keep them only in the website's server
     settings (step 7), never in an email or a page.
5. **Choose the sender address.** Sign-in codes come from Salesforce. In Setup,
   Organization-Wide Addresses, add and verify an address such as `portal@yourorg.org`. In Setup,
   Deliverability, Access level must be **All email**.
6. **Check that the integration user can call the portal API.** From the website server, or any
   computer with `curl`, get a token and call the API (replace the parts in angle brackets):

   ```
   curl -s https://<your-domain>.my.salesforce.com/services/oauth2/token \
     -d grant_type=client_credentials -d client_id=<key> -d client_secret=<secret>
   curl -s -X POST https://<your-domain>.my.salesforce.com/services/apexrest/barncrm/portal/v1/login/start \
     -H "Authorization: Bearer <access_token>" -H "Content-Type: application/json" \
     -d '{"portal":"none","email":"test@example.org"}'
   ```

   The second call should answer `{"ok":false,"error":"portal_unavailable"}` (no portal yet, or
   Portal Sign-In off). That answer means the user, the permission set and the app work. An
   answer about a missing class or insufficient access means Salesforce would not give this
   license what the API needs: use the fallback user in step 2.
7. **Install the portal client on your website.** For WordPress, run
   `bash portal-client/build-wordpress.sh` from the BarnCRM repository, upload the
   `barncrm-portal.zip` it makes in Plugins, Add New, Upload Plugin, activate **BarnCRM
   Portal**, and in Settings, BarnCRM Portal enter your Salesforce domain, the Consumer Key and
   Consumer Secret (kept on the server, never sent to visitors). Put the shortcode
   `[barncrm_portal key="volunteers"]` on a page. The website must use HTTPS. The plugin's
   small stylesheet puts one field per line and fits a phone, in your theme's own fonts and
   colors. For any other website, the `portal-client/README.md` explains the small server
   piece you need.
8. **Add a portal.** In the **BarnCRM Admin** (or **BarnCRM Admin Console**) app, where Portal
   Builder's **Portals** and **Portal Accesses** tabs sit before **Error Log** (it has no app of
   its own, D-188), Portals, New: a name people see, a
   **Key** matching the shortcode, **Access Mode**, **Second Factor**, **Session Hours**,
   **Sender Address**, and the **Template** (below). Set **Status** to Active.
9. **Let people in.** For an Invited portal, add a Portal Access for each person (Portal
   Accesses, New, or the Portal Accesses list on the portal). For Any Matching Person, anyone
   whose email matches exactly one person in BarnCRM can sign in.
10. **Turn Portal Sign-In on** in BarnCRM Settings, Portals.

## Templates

A template is JSON in the portal's Template field. The sample in
`portal-client/templates/sample.json` is a good start:

```json
{
  "schemaVersion": 1,
  "key": "sample",
  "title": "My Account",
  "pages": [
    {
      "key": "profile",
      "title": "My Details",
      "kind": "person",
      "fields": [
        { "field": "FirstName" },
        { "field": "LastName" },
        { "field": "MobilePhone", "label": "Mobile", "edit": true },
        { "field": "Description", "edit": true }
      ],
      "actions": ["update"]
    }
  ]
}
```

- **kind** `person` shows the signed-in person's own record. `related` lists records of a custom
  object whose `personField` (a lookup to the person) is them; `catalog` lists records anyone
  signed in may see (such as open shifts), read only, narrowed by `where` tests.
- **fields** name API fields; `label` changes the label; `edit: true` lets the person change it;
  `required: true` keeps it filled. A field of a parent record can be shown, never edited, as
  `Parent__r.Name`. Lookups, formulas and system fields are never editable.
- **where** tests are `{ "field": ..., "op": ..., "value": ... }` with `equals`, `notEquals`,
  `greaterOrEqual`, `lessOrEqual`, `isBlank`, `isNotBlank`; `TODAY` and `NOW` are allowed values.
- **actions**: `update`, `create` (related pages: the person field is set for them), or a module's
  action such as `{ "extension": "Volunteers.SignUp", "label": "Sign Up" }` where that module offers
  it.
- **requiresModules** lists module keys the portal needs; while one is not installed and on, the
  portal is unavailable.

- A `related` page's `personField` may be `Parent__r.Contact__c`, a parent that itself looks up
  to the person (such as a speaker's session assignments). A page like that is read only: it
  shows records, never edits or adds them.

### Ready-Made Templates

Three templates ship in `portal-client/templates/`. Paste one into a portal's Template field. Each
needs its module: while the module is turned off the portal is unavailable, and where the module
is not installed its pages fail and the Error Log says which field is missing, so install and turn
on the module first. Every page shows only the signed-in person's own records, and only the fields
marked `edit` can be changed. The portal's API user needs no access to any of these objects.

| Template | File and module | Pages |
|---|---|---|
| Volunteer Portal | `volunteer.json`, Volunteers | Open Shifts (Sign Up), My Shifts (Cancel Sign-Up), My Hours (view and log), My Profile |
| Speaker Portal | `speaker.json`, Event Management | Events Open for Proposals (Propose a Talk), Open Proposals (edit, Withdraw), All My Proposals, My Sessions, My Speaker Details, My Details |
| Donor Portal | `donor.json`, Giving | My Giving, Gift History, Pledges and Recurring Gifts, Receipts, My Contact Details |

**Volunteer.** Sign Up adds the person to an open shift that has room and has not started, once
per shift (a cancelled sign-up is reopened). Cancel Sign-Up works until the shift starts. A new
hours entry takes a date, hours and notes; it starts Submitted, or Approved when Volunteers'
**Hours Require Approval** setting is off, as any entry does, and the person cannot edit it
afterwards. Coordinators approve hours as usual.

**Speaker.** Propose a Talk starts a Submitted proposal named for the event, one per event at a
time; the person then writes its title and abstract on Open Proposals, and can withdraw it until
it is Accepted or Declined. Reviewers see it on the event's Applications tab like any other. An
event is listed while its Status is Open and it has not ended. There is no call-for-speakers
deadline in BarnCRM, so the portal shows event and session dates only. A speaker is shown each
session staff assign them to, including its time and room, so assign a speaker only once the
session's time can be public.

**Donor.** Read only, except phone and mailing address on My Contact Details. Email is shown but
not editable, because it is the person's sign-in. Receipts shows the list of issued receipts
(number, date, amount); it does not send the document. There are no payments: BarnCRM takes no
money. Cancelled gifts, pledges and recurring gifts are hidden.

If your org has state and country picklists turned on, a changed State or Country must be a value
in those lists.

Salesforce checks the template on every request. If anything is wrong, the portal shows people
"unavailable" and the reason is in the Error Log (for example "Page roles: Contact__c cannot be
edited in a portal").

## Settings

BarnCRM Settings, Portals (every change saves for the whole org):

| Setting | Default | What it does |
|---|---|---|
| Portal Sign-In | Off | Whether any portal accepts sign-ins and requests |
| Code Minutes | 10 | How long an emailed code works |
| Code Requests per Hour | 5 | Codes one person may ask for per hour |
| Emails per Portal per Hour | 200 | Codes one portal sends per hour |
| Attempts per Code | 5 | Wrong tries before a code stops working |
| Failures Before Lockout | 10 | Wrong codes in a row before a lockout |
| Lockout Minutes | 30 | How long a lockout lasts |
| Idle Minutes | 30 | How long a session may sit unused |

A limit reached when someone asks for a code sends nothing and looks the same to them, so the
portal never reveals who is in your database. The WordPress plugin also limits requests per
visitor address.

## Ending Sessions and Unlocking People

- **Sign one session out:** open the person's Portal Access, then the session, and set Stage to
  Ended.
- **Stop a person:** set their Portal Access Status to Suspended.
- **Unlock a person:** clear Locked Until on their Portal Access.
- **Reset their authenticator:** clear Second Factor Enrolled; they enrol again next time.
- **Stop a portal or all portals:** set the portal Inactive, or turn Portal Sign-In off.
- **Stop the website entirely:** revoke the External Client App's tokens or deactivate the
  integration user.

## Common Mistakes

**Nobody gets a code.** Check Deliverability is All email, the Sender Address is a verified
organization-wide address, the person has an active Portal Access (Invited portals), their email
matches exactly one person, and they are not locked. Email limits of your org apply.

**The portal says it is unavailable.** Portal Sign-In is off, the portal is Inactive, the module
is turned off, a required module is missing, or the template has a mistake (see the Error Log).

**The test call in step 6 is refused.** The integration user lacks the Portal Builder
Integration permission set, or this license cannot hold it: use the fallback user.
