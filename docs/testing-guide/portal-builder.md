# Portal Builder

Scripts for the optional BarnCRM Portal Builder module: signing in by emailed code, the second factor, lockout, template pages scoped to the person, and staff ending sessions. Setup detail: [Portal Builder](../admin-guide/portal-builder.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Portal Builder deployed and sample data loaded, the integration user and External Client App set up as the Admin Guide describes, and **Portal sign-in** turned on in BarnCRM Settings, **Portals**. Calls are made with `curl` against `/services/apexrest/barncrm/portal/v1/`, using an access token from the client credentials flow, or through the WordPress plugin. Use a test inbox you can read.

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
| 3 | Start a sign-in for Pat, wait past **Code Minutes**, and send a wrong code. | 400 `code_invalid`, the same as step 2. |
| 4 | Start another sign-in for Pat, wait past **Code Minutes**, and send the right code. | 400 `code_expired`: only the inbox holder learns the code expired. |

**Cleanup:** None.

## T-PB-03: Wrong Codes Lock the Person

**Purpose:** confirm lockout and unlocking.
**Prerequisites:** admin; set **Wrong codes before lockout** to 3 in Settings, **Portals**.

| Step | Action | Expected result |
|---|---|---|
| 1 | Start two sign-ins (A and B). On B, send a wrong code three times. | 400 `code_invalid` each time. Pat's Portal Access shows Locked Until. |
| 2 | On B, send its right code. | 400 `code_invalid`: B ended at the lockout. |
| 3 | On A, send a wrong code, then A's right code. | 400 `code_invalid`, then 403 `locked`: the lockout is told only after the right code. |
| 4 | Clear Locked Until and sign in again. | Signed in. |

**Cleanup:** set Wrong codes before lockout back to 10.

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
| 2 | POST `login/second-factor` with the authenticator code. | `signedIn`; Second Factor Enrolled is ticked and Second Factor Last Step is filled in. |
| 3 | Sign in again at once and send the same authenticator code before the app shows a new one. | 400 `code_invalid`: a code is used once. With the next code the app shows, `signedIn`. |
| 4 | Set Pat's Portal Access Status to Suspended, then GET `me` with that session. | 401 `not_signed_in`. That session now shows Stage Ended. |
| 5 | Turn **Portal sign-in** off and POST `login/start`. | 503 `portal_unavailable`. |

**Cleanup:** set Status Active, Second Factor Off, and Portal sign-in back on if needed.

## T-PB-06: Volunteer Portal Template

**Purpose:** confirm a volunteer signs up, cancels and logs hours for themselves only.
**Prerequisites:** admin; Volunteers installed with sample data; a portal with key `volunteer`, Active, Invited, the template `portal-client/templates/volunteer.json`; two people `Pat Tester` (signed in as in T-PB-01) and `Lee Other`; an Open shift starting tomorrow with room, a full Open shift, and a shift that started yesterday.

| Step | Action | Expected result |
|---|---|---|
| 1 | GET `me`, then GET `page?key=shifts`. | Four pages. Only Open shifts that start now or later, with Job, Starts, Ends, Where and Spots Left. |
| 2 | POST `page/action` on the open shift with action `Volunteers.SignUp`. | 200 with "You are signed up for this shift." A Volunteer Signup for Pat, status Signed up, exists. |
| 3 | Repeat step 2. | 200 with "You are already signed up for this shift."; still one sign-up. |
| 4 | Sign up for the full shift. | 200 with "This shift is full."; no sign-up. |
| 5 | GET `page?key=signups`, then POST `page/action` `Volunteers.CancelSignup` on Pat's sign-up. | The list shows only Pat's sign-ups. The cancel answers "Your sign-up was cancelled."; status Cancelled. |
| 6 | Cancel a sign-up that belongs to Lee (use its Id). | 404 `not_found`; Lee's sign-up is unchanged. |
| 7 | POST `page/save` on `hours` with no record, `Date_Worked__c` and `Hours__c` 2. | 200 with an Id. Pat has a Volunteer Hours entry, status Submitted (Approved if Hours Require Approval is off). |
| 8 | POST `page/save` on `hours` naming that record. | 403 `not_allowed`: hours cannot be edited after saving. |
| 9 | POST `page/save` on `hours` with `Status__c` set to Approved. | 403 `not_allowed`. |

**Cleanup:** delete Pat's test sign-up and hours entry.

## T-PB-07: Speaker Portal Template

**Purpose:** confirm a speaker proposes, edits and withdraws only their own proposals and sees their sessions.
**Prerequisites:** admin; Event Management installed; a portal with key `speaker`, Active, Invited, the template `portal-client/templates/speaker.json`; Pat Tester signed in; an Open event that has not ended, a Draft event, and a session at the Open event assigned to a speaker record for Pat.

| Step | Action | Expected result |
|---|---|---|
| 1 | GET `page?key=events`. | Only the Open event that has not ended. |
| 2 | POST `page/action` `Events.ApplyToSpeak` on it. | 200 with "Your proposal was started." A Speaker Application for Pat, Submitted, titled "New proposal for" the event. |
| 3 | Repeat step 2. | 200 with "You already have a proposal for this event."; still one. |
| 4 | POST `page/save` on `proposals` with a new `Name` and `Abstract__c`. | 200; the application shows them. |
| 5 | POST `page/save` on `proposals` changing `Status__c`. | 403 `not_allowed`. |
| 6 | Set the application to Accepted in Salesforce and GET `page?key=proposals`. | It is no longer listed; `decisions` still shows it as Accepted. POST `Events.WithdrawProposal` on it answers "This proposal has been decided or withdrawn, so it cannot be withdrawn." |
| 7 | GET `page?key=sessions`. | Only Pat's session with its start, end, room and role; a save on that page is `not_allowed`. |
| 8 | Propose for the Open event again and withdraw the new proposal. | Withdrawn; a second proposal can then be started. |

**Cleanup:** delete the test applications.

## T-PB-08: Donor Portal Template

**Purpose:** confirm a donor sees only their own giving, with no payments and no edits beyond contact details.
**Prerequisites:** admin; Giving installed with sample data; a portal with key `donor`, Active, Invited, the template `portal-client/templates/donor.json`; Pat Tester signed in with two gifts (one Cancelled), a pledge and an issued receipt; another donor with gifts.

| Step | Action | Expected result |
|---|---|---|
| 1 | GET `page?key=summary`. | Pat's totals and Pledge Balance only. |
| 2 | GET `page?key=gifts`. | Pat's gifts except the Cancelled one, newest first; none of the other donor's. |
| 3 | GET `page?key=pledges` and `page?key=receipts`. | Pat's pledge with Paid to Date and Balance; Pat's issued receipt. No other donor's records. |
| 4 | POST `page/save` on `contact` changing `MobilePhone` and `MailingCity`. | 200; changed in BarnCRM. |
| 5 | POST `page/save` on `contact` changing `Email`. | 403 `not_allowed`. |
| 6 | POST `page/save` on `gifts` with no record, or on a gift's Id. | 403 `not_allowed`. |

**Cleanup:** restore Pat's phone and city.

## T-PB-09: The Portal on a WordPress Page

**Purpose:** confirm the portal is usable on a phone and with a keyboard or screen reader.
**Prerequisites:** the WordPress plugin installed as the Admin Guide describes; the `sample` portal from T-PB-01 on a page with `[barncrm_portal key="sample"]`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the page on a phone, or narrow the browser window to phone width. | Each label sits above its box; boxes fit the screen; no sideways scrolling. Fonts and colors match the theme. |
| 2 | Sign in with the emailed code, using only the keyboard. | Each screen starts in its first box. After sign-in, focus is on the **My Details** heading. |
| 3 | Choose **Edit**. | Focus moves to the first box of the edit form. |
| 4 | Enter a wrong code on a fresh sign-in. | The message is read out as an alert and marked by a bar on its left. |

**Cleanup:** sign out.

## T-PB-10: Board Portal Template

**Purpose:** confirm a board member sees and acts on only their own meetings, votes and requests (PB-02, CH-18, CH-19, CH-20).
**Prerequisites:** admin; Corporate Hub on; the board, meetings and requests from the Corporate Hub tests T-CH-09 to T-CH-13, with Ade and Bea invited; a portal with key `board`, Active, Invited, the template `portal-client/templates/board.json`; Ade signed in.

| Step | Action | Expected result |
|---|---|---|
| 1 | GET `page?key=meetings`. | Ade's meetings only, with agenda and Packet Link; none of Bea's rows. |
| 2 | POST `page/action` `CorporateHub.MarkPacketRead` on one row. | "Thank you. Your reading of the packet is recorded."; the meeting panel counts 1 packet read. |
| 3 | With minutes Draft, GET `page?key=minutes`. Submit them as staff and GET again; run `CorporateHub.ApproveMinutes`. | Empty while Draft; then listed; the approval is recorded and counted on the meeting panel. |
| 4 | Open voting on a motion; GET `page?key=votes`; run `CorporateHub.VoteFor`. Close voting; run `CorporateHub.VoteAgainst`. | Ade's blank vote listed; then For with Voted; after closing, "Voting on this motion is closed." and the vote stays For. |
| 5 | GET `page?key=disclosures`; POST `page/save` with Interests Disclosed text and the conflict box; run `CorporateHub.Acknowledge`. | Ade's open request; saved; Acknowledged with Answered in Portal checked; it leaves the page. |
| 6 | GET `page?key=assessment`; save a Rating of 4 and of 7. | 4 saves; 7 is refused (`save_failed`, the Error Log names the 1 to 5 rule). |
| 7 | With the poll open, save Ade's Available for Time 1 as Yes; close the poll and try again. | Saved and counted; once closed the page is empty and the save is refused. |
| 8 | POST any action with Bea's row Id. | 404 `not_found`; Bea's row is unchanged. |

**Cleanup:** None.

## T-PB-11: Member Portal Template

**Purpose:** confirm a member sees their own membership, controls their own listing, and finds only members who opted in (PB-09).
**Prerequisites:** admin; Memberships on; Pat and Sam each with a Current membership and an email; a portal with key `member`, Active, Invited, the template `portal-client/templates/member.json`; Pat signed in.

| Step | Action | Expected result |
|---|---|---|
| 1 | GET `page?key=membership`. | Pat's membership with level, dates and dues; none of Sam's. |
| 2 | GET `page?key=directory`. | Empty: nobody has opted in. |
| 3 | POST `page/save` on `listing` with Show Me to Other Members on and a location; GET `page?key=directory`. | Pat listed with name, level, location and bio only. |
| 4 | Open the portal page in a browser on Member Directory and type part of Pat's location. | A search box above the list; only matching members stay shown. |
| 5 | With Payments not ready, POST `page/action` `Memberships.PayDues` on Pat's membership. | Refused; no payment link is queued and the membership is unchanged. |
| 6 | POST `page/action` `Memberships.PayDues` with Sam's membership Id. | 404 `not_found`. |

**Cleanup:** turn Pat's listing off.
