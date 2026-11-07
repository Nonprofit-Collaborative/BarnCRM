# Portal Builder

Scripts for the optional BarnCRM Portal Builder module: signing in by emailed code, the second factor, lockout, template pages scoped to the person, and staff ending sessions. Setup detail: [Portal Builder](../admin-guide/portal-builder.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Portal Builder deployed and sample data loaded, the integration user and External Client App set up as the Admin Guide describes, and **Portal Sign-In** turned on in BarnCRM Settings, **Portals**. Calls are made with `curl` against `/services/apexrest/barncrm/portal/v1/`, using an access token from the client credentials flow, or through the WordPress plugin. Use a test inbox you can read.

## T-PB-01: Sign In With the Emailed Code

**Purpose:** confirm the code is sent, works once, and only hashes are stored.
**Prerequisites:** admin; a portal with key `sample`, Status Active, Access Mode Invited, Second Factor Off, the template from `portal-client/templates/sample.json`; a person `Pat Tester` with your test email and a Portal Access for the portal.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | POST `login/start` with `{"portal": "sample", "email": "<your email>"}`. | 200 with a `challenge`. An email `Your sign-in code for` the portal arrives with a six-digit code. |
| 2 | POST `login/verify` with the challenge and the code. | 200, `status` `signedIn` and a `session`. |
| 3 | Open the Portal Access, then its session. | Stage Active. Token Hash is 64 characters and is not the session value; Code Hash is blank. |
| 4 | Repeat step 2 with the same code. | 400 `code_invalid`. |

**Cleanup:** None (T-PB-04 uses the session).

## T-PB-02: Nobody Learns Who Is on File

**Purpose:** confirm an unknown or uninvited email looks the same and sends nothing.
**Prerequisites:** admin, after T-PB-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | POST `login/start` with `nobody@example.org`. | 200 with a challenge of the same length as in T-PB-01. No email, no new session. |
| 2 | POST `login/verify` with that challenge and `123456`. | 400 `code_invalid`. |

**Cleanup:** None.

## T-PB-03: Wrong Codes Lock the Person

**Purpose:** confirm lockout and unlocking.
**Prerequisites:** admin; set **Failures Before Lockout** to 3 in Settings, **Portals**.

| Step | Action | Expected result |
|---|---|---|
| 1 | Start a sign-in and send a wrong code three times. | 400 `code_invalid` each time. Pat's Portal Access shows Locked Until. |
| 2 | Send the right code. | 400 `code_invalid`. |
| 3 | Clear Locked Until and sign in again. | Signed in. |

**Cleanup:** set Failures Before Lockout back to 10.

## T-PB-04: Pages Show and Change Only the Person's Own Records

**Purpose:** confirm template scoping.
**Prerequisites:** admin, a session from T-PB-01; Pat has a Current and a Former affiliation, and another person has a Current one.

| Step | Action | Expected result |
|---|---|---|
| 1 | GET `me` with header `X-Barn-Portal-Session`. | The template title, Pat's first name and two pages. |
| 2 | GET `page?key=roles`. | Only Pat's Current affiliation, with the organization name. |
| 3 | POST `page/save` on the profile page changing **MobilePhone**. | 200; Pat's mobile is changed in BarnCRM. |
| 4 | POST `page/save` on the profile page changing **FirstName**. | 403 `not_allowed`. |
| 5 | POST `page/save` on the roles page with the other person's affiliation Id. | 404 `not_found`; their record is unchanged. |

**Cleanup:** None.

## T-PB-05: Second Factor and Ending Sessions

**Purpose:** confirm enrolment, the second factor, and that staff can end access.
**Prerequisites:** admin; an authenticator app; set the portal's Second Factor to Required.

| Step | Action | Expected result |
|---|---|---|
| 1 | Sign in with the emailed code. | `status` `enroll` with a `secret` and an `otpauth://totp/` uri. Add it to the authenticator. |
| 2 | POST `login/second-factor` with the authenticator code. | `signedIn`; Second Factor Enrolled is ticked. |
| 3 | Set Pat's Portal Access Status to Suspended, then GET `me` with that session. | 401 `not_signed_in`. That session now shows Stage Ended. |
| 4 | Turn **Portal Sign-In** off and POST `login/start`. | 503 `portal_unavailable`. |

**Cleanup:** set Status Active, Second Factor Off, and Portal Sign-In back on if needed.
