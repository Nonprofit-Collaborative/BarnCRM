# Scholarships and Outbound Grants

Scripts for the optional BarnCRM Scholarships and Outbound Grants module. Setup detail:
[Scholarships and Outbound Grants](../admin-guide/scholarships.md).

Before you start: an org from [Before you test](before-you-test.md), with Core, Forms and
Scholarships and Outbound Grants deployed (Portal Builder too for T-SG-08), the module turned on in
BarnCRM Settings, **Modules**, and the Forms public site set up. You need an admin (BarnCRM Admin),
two users with the Team Member role (reviewer A and reviewer B), and a public group
`Scholarship_Panel` holding both reviewers.

## T-SG-01: Install and Access

**Purpose:** confirm the tabs, sets and settings.
**Prerequisites:** admin.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the BarnCRM app. | Scholarships and Grants, Award Programs, Award Applications and Awards tabs, before Error Log. |
| 2 | Open Setup, reviewer A's permission set assignments. | Scholarships Staff is assigned (within the hour, or after Finish Setup). |
| 3 | Open BarnCRM Settings, Scholarships and Grants. | Send Scholarships reminders on, Days before to remind 14, Email recipients about reports off. |

**Cleanup:** None.

## T-SG-02: Application From a Form, Eligibility and Files

**Purpose:** confirm a public submission becomes an application with its status and files.
**Prerequisites:** admin; a published public form with questions `gpa` (number) and `transcript`
(file).

| Step | Action | Expected result |
|---|---|---|
| 1 | Create an Award Program "Test Scholarship" and a cycle "2027" with Status Open, Application Form the form's record ID and Eligibility Rules `[{"answer":"gpa","op":"atLeast","value":3}]`. | The cycle page shows the public application link. |
| 2 | Open the link in a private window; submit as a new person with gpa 3.5 and a small PDF. | Thank-you page. |
| 3 | Open the cycle's Applications. | One application, Status Eligible, Applicant the new person, Submitted Date today, the PDF in Files, the answers in Form Answers. |
| 4 | Submit again with another new person and gpa 2.0. | A second application, Status Ineligible; Eligibility Notes names the gpa rule. |

**Cleanup:** None (used by T-SG-03).

## T-SG-03: Panel Assignment, Recusal and Scoring

**Purpose:** confirm load-balanced assignment, recusal and the weighted score.
**Prerequisites:** T-SG-02; the cycle's Reviewer Panel `Scholarship_Panel`, Reviewers per Application 1, Rubric `[{"key":"need","label":"Need","max":10,"weight":2},{"key":"essay","label":"Essay","max":10,"weight":1}]`.

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, on the cycle press **Assign Reviewers**. | Each application gets one review; the two go to different reviewers; the Eligible one is In Review. |
| 2 | As the reviewer of the Eligible application, open it from My Reviews; score Need 8, Essay 6; **Submit Review**. | Score 22; the application's Reviews Submitted 1, Average Score 22. |
| 3 | As the other reviewer, open the Ineligible application, press **Recuse** with a reason. | Review Recused. |
| 4 | As admin press **Assign Reviewers** again. | The Ineligible application gets a review for the first reviewer, never again for the one who recused. |
| 5 | As reviewer A, try to edit reviewer B's review score on the record. | Refused: only the reviewer or Manage Scholarships. |

**Cleanup:** None.

## T-SG-04: Review Board, Decision and Letter

**Purpose:** confirm ranking, the award and its PDF.
**Prerequisites:** T-SG-03.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the cycle's Review Board; check Blind Review on the cycle and reload as a reviewer. | Ranked by Average Score; with blind review the applicant column shows only the application number. |
| 2 | As admin press **Award** on the top application, amount 1000. | An Offered award; the application Awarded; the cycle's Awarded Amount 1000 and Remaining Budget less 1000. |
| 3 | On the award press **Make Letter**. | A PDF in Files naming the recipient, program, cycle and amount; Letter Date today. |
| 4 | Press **Accepted**. | Status Accepted, Accepted Date today. |

**Cleanup:** None.

## T-SG-05: Schedule, Conditional Disbursement and Paid

**Purpose:** confirm a condition holds back a payment and only managers mark Paid.
**Prerequisites:** T-SG-04.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the award press **Build Schedule**: 2 payments, 6 months apart, starting next month. | Two Scheduled disbursements of 500, six months apart, Payee the recipient. |
| 2 | Add an Award Requirement "Proof of enrollment", Type Condition, Blocks Disbursement the first payment. | The first payment shows as held back. |
| 3 | As reviewer A (Staff), try to set the second payment to Paid. | Refused: Manage Scholarships needed. |
| 4 | As admin, **Mark Paid** on the first payment. | Refused: the condition is open. |
| 5 | Press **Met** on the condition, then **Mark Paid** (Check, reference 1001). | Paid, Paid Date today; the award's Paid Amount 500. |

**Cleanup:** None.

## T-SG-06: Disbursement Export

**Purpose:** confirm the CSV and the Exported Date.
**Prerequisites:** T-SG-05.

| Step | Action | Expected result |
|---|---|---|
| 1 | On the Scholarships and Grants tab, **Export Disbursements** for this year. | A CSV downloads with both payments, their payee, amount, status, dates, method and reference. |
| 2 | Open the paid disbursement. | Exported Date today. |

**Cleanup:** None.

## T-SG-07: Recipient Reports, Reminders and Renewal

**Purpose:** confirm a report link, the reminder once per date and renewal.
**Prerequisites:** T-SG-04; a public report form set as the cycle's Report Form; the award Renewable; a second cycle "2028" of the program, Planned.

| Step | Action | Expected result |
|---|---|---|
| 1 | Add a Progress Report requirement due in 5 days. | The requirement Open; Report Form Link blank until the nightly run. |
| 2 | Run the nightly job (Nightly Jobs page, Run Now) twice. | Report Form Link filled; one bell notification to the program's owner, not two; Reminded For the due date. |
| 3 | Open the report link and submit. | The requirement Submitted, Report or Evidence filled, Submitted Date today. |
| 4 | On the award press **Start Renewal**. | A Draft application in "2028" for the same recipient, Renewal Of this award. |

**Cleanup:** None.

## T-SG-08: Applicant Portal

**Purpose:** confirm the applicant template's actions.
**Prerequisites:** Portal Builder set up with a portal on the `applicant` template; the T-SG-02 applicant has portal access.

| Step | Action | Expected result |
|---|---|---|
| 1 | Sign in to the portal as the applicant. | Open Cycles, My Applications, My Awards and My Reports pages. |
| 2 | On Open Cycles press **Apply** on another open cycle. | A message that a draft was started; My Applications shows it with its form link. |
| 3 | Open the form link and submit. | The same application, now Submitted with the answers. |
| 4 | On My Awards press **Accept Award** on an Offered award. | It shows Accepted. |
| 5 | As admin set an application of the applicant to Ineligible. As the applicant press **Withdraw** on it. | "This application has been decided and cannot be withdrawn." Its status stays Ineligible. |
| 6 | Delete a cycle after the applicant has its page open, then press **Apply** on it. | "This cycle is not taking applications." and no error page. |

**Cleanup:** None.

## T-SG-09: Moving From Outbound Funds

**Purpose:** confirm the Outbound Funds kit copies programs, requests, awards, disbursements and requirements with their links, and never changes Outbound Funds.
**Prerequisites:** a test org (never production) with the Outbound Funds Module installed and this module on; admin user with Manage Scholarships; **Send Scholarships reminders** off. In Outbound Funds: a funding program "Community Grants" (In progress, total 50,000); a funding request "Garden Project" from a contact and organization for 5,000, Awarded 4,000, with one Paid disbursement of 2,000 by EFT, one Scheduled disbursement of 2,000, and a requirement "Final Report" (type Report) due next month on the second disbursement; a second request "Library Hours", Declined, with no awarded amount.

| Step | Action | Expected result |
|---|---|---|
| 1 | Open **BarnCRM Settings**, **Integrations**, Outbound Funds Module. | **Start Migration: Outbound Funds Programs and Awards**. Click it: six steps, Programs first, the rest Waiting. |
| 2 | Run and load **Programs**, then **Cycles**. | An award program Community Grants, type Grant, active, with one cycle Community Grants (Open, budget 50,000). Each **Verified**. |
| 3 | Run and load **Applications**. | Two applications in that cycle: Garden Project (Awarded, 5,000 requested) and Library Hours (Declined). **Verified**. |
| 4 | Run and load **Awards**. | One award of 4,000, Active, on the Garden Project application, for the same contact and organization. **Verified** (1 in the other app). |
| 5 | Run and load **Disbursements**, then **Requirements**. | Two disbursements on the award (Paid by Bank Transfer, and Scheduled); one requirement, Open, due next month, linked to the Scheduled disbursement. Each **Verified**. |
| 6 | Open the Outbound Funds records. | Nothing changed. |

**Cleanup:** undo the six steps in reverse order; switch reminders back on if they were on.
