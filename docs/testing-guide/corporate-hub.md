# Corporate Hub

Scripts for the optional BarnCRM Corporate Hub module: templates, Library Documents and versions,
policy acknowledgments, the compliance calendar, agreements, reminders and board governance.
Setup detail:
[Corporate Hub](../admin-guide/corporate-hub.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Corporate Hub
deployed and the module turned on in BarnCRM Settings, **Modules**. You need an admin (BarnCRM
Admin) and a second user with the Team Member role, called the staff user below.

## T-CH-01: Install, Access and Templates

**Purpose:** confirm setup gives access and loads each template once.
**Prerequisites:** admin.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the BarnCRM app. | Corporate Hub, Library Documents, Compliance Obligations and Agreements tabs, before Error Log. |
| 1a | Before any board or committee exists, open the **Corporate Hub** page as admin. | **Set Up Your Board** shows. **New Board or Committee** opens the new record form. After the first board is saved and the page reloaded, the panel is gone. |
| 2 | Open Setup, the staff user's permission set assignments. | Corporate Hub Staff is assigned (within the hour, or after Finish Setup). |
| 3 | Open the Compliance Obligations tab, All. | Eight template obligations, each Status Off, including Annual tax return (US: IRS Form 990 series) and the two Data Protection ones. |
| 4 | Open the Library Documents tab, All. | Eight Draft policies: conflict of interest, whistleblower, document retention and destruction, gift acceptance, data protection, privacy notice, data subject request procedure, personal data breach response procedure. Each summary says it is not legal advice. |
| 5 | In the App Launcher, open **Processing Activities**, All. | Five Draft activities, from Donor records and fundraising to Staff and board records. |
| 6 | Edit the annual tax return obligation's Instructions; on the Corporate Hub page press **Add Missing Templates**. | A message that nothing was missing; your edit is unchanged; still eight obligations. |
| 7 | Delete the Registered agent renewal obligation, then press **Add Missing Templates** again. | One template added; it is back, Off. |

**Cleanup:** None.

## T-CH-02: Publish, Review and Retire a Document

**Purpose:** confirm versions, review dates and retire.
**Prerequisites:** admin; the conflict of interest policy from T-CH-01 with a PDF uploaded to its Files.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the Policy panel press **Publish New Version**. | Version 2, Status Active, Effective Date today. |
| 2 | Set Review Every (Months) to 12 and press **Mark Reviewed**. | Last Reviewed today; Next Review a year from today. |
| 3 | Upload a newer PDF to the same file with **Upload New Version** in Files. | The file shows version 2; the document's Version is unchanged until you publish. |

**Cleanup:** None (T-CH-03 uses the document).

## T-CH-03: Request and Answer Acknowledgments

**Purpose:** confirm requests, the staff user's answer and who is outstanding.
**Prerequisites:** admin and staff user; the document from T-CH-02, Needs Acknowledgment checked.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, **Request Acknowledgments**, audience Everyone with a BarnCRM role. | A count of people asked. The panel shows 0 acknowledged and that many outstanding, the staff user among them. |
| 2 | Press it again. | 0 people asked: nobody is asked twice for one version. |
| 3 | As the staff user, check the bell. | A notification naming the policy; it opens the document. |
| 4 | Open the Corporate Hub page. | The policy under Policies to Acknowledge, with its due date (today plus 30 days). |
| 5 | Press **I Have Read This**. | It leaves the list. As admin, the panel shows 1 acknowledged; the staff user is not outstanding. |
| 6 | As admin, **Publish New Version**. | Open requests for the old version show Superseded; the same people are asked for version 3; the staff user is outstanding again. |

**Cleanup:** None.

## T-CH-04: Only the Person Attests

**Purpose:** confirm one person cannot acknowledge for another.
**Prerequisites:** after T-CH-03; a third user with Team Member who has an open request.

| Step | Action | Expected result |
|---|---|---|
| 1 | As the staff user, open the third user's acknowledgment by its URL. | Not visible (insufficient privileges). |
| 2 | As admin, on the Policy panel press **Record** beside the third user. | The request becomes Acknowledged; Acknowledged On is now. |
| 3 | As admin, create a Policy Acknowledgment with both User and Person filled. | Refused: fill in User or Person, not both. |

**Cleanup:** None.

## T-CH-05: Complete a Compliance Cycle

**Purpose:** confirm the cycle, its evidence and the next due date.
**Prerequisites:** staff user; the annual tax return obligation set to Status Active with Next Due Date 2026-05-15.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Set Status Active with Next Due Date blank and save. | Refused: an Active obligation needs a Next Due Date. Set it back to 2026-05-15. |
| 2 | On the Compliance panel press **Complete This Cycle**, Outcome Done, notes `Filed online`, and save. | The panel asks for evidence; upload a PDF. |
| 3 | Look at the obligation. | Next Due Date 2027-05-15, Last Completed today; Compliance Cycles lists one cycle due 2026-05-15 with the PDF in its Files. |
| 4 | Make a One Time obligation Active and complete it. | Its Status becomes Done. |
| 5 | Set a Monthly obligation due 2026-01-31 and complete it. | Next Due Date 2026-02-28. |

**Cleanup:** None.

## T-CH-06: Agreements Renew and Expire

**Purpose:** confirm notice dates and the nightly renewal.
**Prerequisites:** admin; Nightly Jobs page.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create an Agreement: Status Active, End Date 2026-12-31, Notice Days 60. | Notice Date 2026-11-01. |
| 2 | Try End Date before Start Date. | Refused. |
| 3 | Create two Active agreements ending yesterday, one Auto-Renews with term 12, one not. Run **Corporate Hub reminders** now on the Nightly Jobs page. | The auto-renewing one ends a year after yesterday, still Active; the other is Expired. |

**Cleanup:** Delete the agreements.

## T-CH-07: Reminders Once per Date

**Purpose:** confirm bell reminders and their switches.
**Prerequisites:** admin owning an Active obligation due in 10 days, an Active agreement with Notice Date in 5 days and an Active document with Next Review in 20 days.

| Step | Action | Expected result |
|---|---|---|
| 1 | Run **Corporate Hub reminders** now. | Three bell notifications, each opening its record. Each record's Reminded For is its date. |
| 2 | Run it again. | No new notification. |
| 3 | Move the obligation's due date by a day and run it again. | One notification for the obligation. |
| 4 | Turn off **Send Corporate Hub reminders** in Settings, **Corporate Hub**, move a date and run again. | No notification. Turn it back on. |

**Cleanup:** None.

## T-CH-08: The Corporate Hub Page

**Purpose:** confirm the page lists, at phone width and by keyboard.
**Prerequisites:** staff user with an open request; an overdue obligation; an agreement with a notice date in 30 days.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the Corporate Hub tab. | Policies to Acknowledge, Compliance Due (the overdue one first, marked Overdue) and Agreements to Act On. No Add Missing Templates button for the staff user. |
| 2 | Tab through the page. | Every link and button is reachable with a visible focus ring, in reading order. |
| 3 | Open it in the Salesforce mobile app. | The lists stack in one column with no sideways scrolling. |

**Cleanup:** None.

## T-CH-09: Board Roster, Terms and Skills

**Purpose:** confirm seats, the term limit flag, expiring-term reminders and the skills matrix (CH-09, CH-13, CH-15, CH-17).
**Prerequisites:** admin; three people (Ade, Bea, Cy).

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a Board or Committee "Board of Directors" (Type Board, Term Limit 2, Skills Wanted Finance and Legal) and a second, "Finance Committee", Type Committee, Parent Board the first. | Both saved; the committee shows under the board's Committees list. |
| 2 | On the board add seats: Ade Chair, term 2, started a year ago, ends in 20 days, Skills Finance; Bea Member, term 1, ends in two years; Cy Member, ended last month. | The Board panel lists Ade and Bea only; Ade shows **At Term Limit**; a warning says one term ends within the reminder window. |
| 3 | Read the skills matrix. | Finance 1, Legal 0; "Skills wanted that no current member holds: Legal." |
| 4 | Run **Corporate Hub reminders** now on the Nightly Jobs page, then again. | One bell notification to the board's owner naming Ade; none the second time. |
| 5 | With Giving installed, give Ade a gift dated this fiscal year. Reload. | "50% of current members gave this fiscal year." Without Giving the line is absent. |
| 6 | Give Bea an age range, then turn on **Show board demographics** in Settings, **Corporate Hub**. | Bea's age range shows on the panel; turned off again, it is hidden. |

**Cleanup:** None.

## T-CH-10: Meetings, Quorum, Minutes and Action Items

**Purpose:** confirm Invite Board, quorum, the minutes step and carried action items (CH-10, CH-16).
**Prerequisites:** the board from T-CH-09 with Ade and Bea current and voting; the staff user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a Board Meeting last month and add an Action Item on the board, Raised At that meeting, Open. | Saved. |
| 2 | Create a meeting next week. Press **Invite Board** twice. | Two attendees the first time, none the second. "No quorum yet: 0 voting members present, 2 needed." |
| 3 | Set Ade and Bea Present. | "Quorum met: 2 voting members present, 2 needed." |
| 4 | Read **Action Items Carried Forward**. | The open item from last month is listed; mark it Done and it disappears. |
| 5 | As the staff user press **Submit Minutes for Approval**. | Minutes Submitted for Approval; no Mark Minutes Approved button for staff. |
| 6 | As the admin press **Mark Minutes Approved**. | Approved, with today as Minutes Approved On. |

**Cleanup:** None.

## T-CH-11: Motions and Votes

**Purpose:** confirm voting opens, counts and closes, and closed votes stay closed (CH-11).
**Prerequisites:** the meeting from T-CH-10 with two voting attendees; the staff user.

| Step | Action | Expected result |
|---|---|---|
| 1 | Add a Board Motion "Approve the budget". Press **Open Voting**. | "Voting open for 2 members." Two Board Votes, blank. |
| 2 | Set one vote For and one Against; press **Close Voting**. | "Voting closed: Failed." Decided On is today; the motion shows 1 for, 1 against. |
| 3 | As the staff user change a vote. | Refused: "Voting on this motion is closed." As the admin it saves. |
| 4 | Press **Close Voting** again on the closed motion. | Refused: "Voting is not open on this motion, so it cannot be closed." Status and Decided On are unchanged. |
| 5 | On a motion that was never opened, press **Close Voting**. | The same refusal. |
| 6 | Confirm step 2 gave no warning and Closed Without Quorum is unticked on that motion (Ade and Bea were Present). | No warning toast; no "Closed without quorum" under the motion. |
| 7 | On a second meeting where nobody is Present, add a motion, press **Open Voting**, cast one vote For, press **Close Voting** (CH-21, D-196). | "Voting closed: Passed." plus a warning: "This meeting did not reach quorum. Check your bylaws before relying on this vote." The motion shows "Closed without quorum" and its Closed Without Quorum box is ticked. |

**Cleanup:** Delete the second meeting.

## T-CH-12: Disclosures and Self-Assessment

**Purpose:** confirm yearly board disclosures and the self-assessment (CH-12, CH-19).
**Prerequisites:** the board from T-CH-09; an Active Library Document "Conflict of Interest" with Needs Acknowledgment and Ask Every Year.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the Board panel choose the policy and press **Request From Board**, then again. | "2 people asked.", then "0 people asked." Each request names the person, not a user. |
| 2 | Press **Start Self-Assessment**. | A Board Self-Assessment opens with one answer per question for Ade and Bea. |
| 3 | Set the assessment Closed and change an answer's Rating. | Refused: "This self-assessment is closed." |

**Cleanup:** None.

## T-CH-13: Availability Poll and Board Dashboard

**Purpose:** confirm the poll and the dashboard (CH-14, CH-20).
**Prerequisites:** the board from T-CH-09.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create a meeting with no start and press **Send Poll**. | Refused: fill in Poll Time 1 first. |
| 2 | Fill in two Poll Times and press **Send Poll**. | The board is invited; Poll Open is checked; each time shows "0 available". |
| 3 | Set Ade's Available at Time 2 to Yes; press **Choose This Time** on time 2. | Start is time 2; Poll Open is cleared. |
| 4 | Open Dashboards, folder **BarnCRM Corporate Hub**, **Board Governance**. | Current roster, terms ending in 90 days (Ade), attendance this year and open disclosures, each opening its report. |

**Cleanup:** None.

## T-CH-14: Data Subject Requests and the Erasure Link

**Purpose:** confirm a data subject request is reminded once, shows on the Corporate Hub page and is linked to Core's erasure (CH-05).
**Prerequisites:** admin; a staff user; a test Contact you may erase. **Send Corporate Hub reminders** on.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open **Data Subject Requests** from the App Launcher and create one: Request Type **Erasure**, Person the test Contact. | It is numbered DSR-nnnnn, Status Received, Received Date today, Due Date 30 days from today. |
| 1a | Create another request with Received Date 10 days ago and Due Date blank. Then change its Received Date to 20 days ago. | Due Date is 20 days from today after the first save, then 10 days from today after the change. A request whose Due Date you typed keeps it when the Received Date changes. |
| 2 | Set Due Date before Received Date and save. | Refused: the due date cannot be before the date received. |
| 3 | Set Status to Completed with no Completed Date and save. | Refused until Completed Date is filled in. Set Status back to Received. |
| 4 | Open the Corporate Hub tab. | A **Data Protection** section lists "Data subject request: DSR-nnnnn" with its due date and type. |
| 5 | As another staff user, open the Data Subject Requests tab, All. | The request is not listed (requests are private). |
| 6 | As admin, run Core's **Erase a Person** on the test Contact with Request Reference the request number. | The erasure completes. |
| 7 | Run **Corporate Hub reminders** now. | The request's **Erasure Record** is the erasure; Status is still Received. The owner gets one bell notification "Data subject request DSR-nnnnn is due ...". |
| 8 | Run it again. | No new notification. |
| 9 | Set the request Completed with today's Completed Date. | It leaves the Data Protection section, which disappears when nothing else is listed. |

**Cleanup:** Delete the request.

## T-CH-15: Breaches and DPIA Reviews

**Purpose:** confirm the breach log's 72-hour deadline and reminders, and DPIA review reminders (CH-05).
**Prerequisites:** admin. **Send Corporate Hub reminders** on.

| Step | Action | Expected result |
|---|---|---|
| 1 | From the App Launcher, open **Data Breaches** and create one: Breach Title "Lost laptop". | Status Open, Risk Not Yet Assessed, Discovered At now, Authority Deadline 72 hours later. The owner gets a bell at once ("Breach Lost laptop: report to the authority by ...") and Reminded For is the deadline date (CH-22, D-196). |
| 2 | Set Status Closed and save. | Refused while the risk is Not Yet Assessed. Set Status back to Open. |
| 3 | Open the Corporate Hub page. | Data Protection lists "Breach not yet reported: Lost laptop". |
| 4 | Create a second breach with Risk **Unlikely to Result in Risk**. | It is not listed on the Corporate Hub page, and no bell is sent. |
| 5 | Open the Processing Activity "Donor records and fundraising": tick DPIA Required, DPIA Review Date in 10 days, Status Active. | Saved. |
| 6 | Run **Corporate Hub reminders** now. | One bell notification: the DPIA review. None for the first breach (already told in step 1) or the low-risk breach. |
| 7 | Run it again. | No new notification. |
| 8 | Fill in Authority Notified At on the first breach. | It leaves the Corporate Hub page. |
| 9 | On the Automations page turn off **Data Breach: Bell When Logged**, then create a breach "Phishing email" with Risk **Risk**. | No bell on saving. Run **Corporate Hub reminders**: one bell for "Phishing email". Turn the row back on. |

**Cleanup:** Delete the three breaches; set the activity back to Draft and untick DPIA Required.

## T-CH-16: Sample Data

**Purpose:** confirm the Corporate Hub sample data loads for the sample people and takes away only
itself.
**Prerequisites:** admin; Core's sample data not yet loaded; a Library Document of your own.
**Smoke:** no

| Step | Action | Expected result |
|---|---|---|
| 1 | **BarnCRM Settings**, **Load Sample Data**, wait for it to finish. | The Sample Data card shows a **Documents** count of `5`. |
| 2 | Open **Library Documents** and **Compliance Obligations**. | Five sample documents and five obligations beside your own. |
| 3 | Open the Conflict of Interest Policy. | One acknowledgment Acknowledged and one Requested. |
| 4 | Open **Boards**, then the Board of Directors. | Five seats (Chair, Treasurer, Secretary, two Members) and a Finance Committee under it. |
| 5 | Open the past Quarterly Board Meeting. | Four Present, one Excused, quorum met, minutes Approved; the budget motion Passed with three For and one Abstain. |
| 6 | **Remove Sample Data**. | Every sample record above is gone; your own document stays. |

**Cleanup:** None.
