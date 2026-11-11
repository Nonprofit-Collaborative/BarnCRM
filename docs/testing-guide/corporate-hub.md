# Corporate Hub

Scripts for the optional BarnCRM Corporate Hub module: templates, Library Documents and versions,
policy acknowledgments, the compliance calendar, agreements and reminders. Setup detail:
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
| 2 | Open Setup, the staff user's permission set assignments. | Corporate Hub Staff is assigned (within the hour, or after Finish Setup). |
| 3 | Open the Compliance Obligations tab, All. | Six template obligations, each Status Off, including Annual tax return (US: IRS Form 990 series). |
| 4 | Open the Library Documents tab, All. | Four Draft policies: conflict of interest, whistleblower, document retention and destruction, gift acceptance. Each summary says it is not legal advice. |
| 5 | Edit the annual tax return obligation's Instructions; on the Corporate Hub page press **Add Missing Templates**. | A message that nothing was missing; your edit is unchanged; still six obligations. |
| 6 | Delete the Registered agent renewal obligation, then press **Add Missing Templates** again. | One template added; it is back, Off. |

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
