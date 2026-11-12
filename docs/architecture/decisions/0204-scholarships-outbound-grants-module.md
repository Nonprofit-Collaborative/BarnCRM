# ADR-0204: The BarnCRM Scholarships and Outbound Grants module: its own package on Core, applications on the Forms engine, reviews with rubrics and panels, awards, conditional disbursements recorded only, recipient reports and an applicant portal template

**Status:** Accepted (builder decision, for Brandon to confirm)
**Date:** 2026-11-11
**Source:** plan Section 5.11 (SG-01 to SG-08), Section 6.0a release 1.12 (SG-01 to SG-06, SG-08,
SG-09, PB-06) and release 1.10 (SG-10), D-122, D-156, D-178, Section 1.5 (BarnCRM moves no
money, no services); builds on ADR-0013, ADR-0017, ADR-0131, ADR-0164 (help text JSON),
ADR-0166 (nightly dispatcher), ADR-0175 (Forms and its attachment seam), ADR-0185 (portal
action seam), ADR-0191 (portal templates) and ADR-0192 (module tabs in the BarnCRM apps).

## Context

D-122 reverses the non-goal "grantmaking as a funder": organizations that give scholarships,
fellowships and small grants need programs, applications, review, decisions, payments and
recipient reports. NPC Grantmaking and Outbound Funds orgs keep their tools and are detected
only; migration from Outbound Funds is MIG-11, later. Funders (F-) already tracks grants the
organization receives and owns `Grant__c`, `Grant_Payment__c` and `Grant_Requirement__c`, so
this module must not reuse those names or that meaning.

## Decision

1. **Its own package, Core only, Nonprofit Edition.** `packages/scholarships`, package
   `BarnCRM Scholarships and Outbound Grants`, module key `Scholarships`. Core ships the catalog
   row `BarnCRM_Module.Scholarships` (edition `Nonprofit`, Sort Order 42, no probe object: its
   Setting Definition rows name the module, #1053). No app of its own (ADR-0192): its tabs join
   BarnCRM and BarnCRM Console before Error Log. Install leaves the module off, as every module.
   Giving and Funders are not referenced.
2. **Seven objects, named Award.** Award Program (`Award_Program__c`), Award Cycle
   (`Award_Cycle__c`, master-detail to program), Award Application (`Award_Application__c`,
   master-detail to cycle), Application Review (`Application_Review__c`, master-detail to
   application), Award (`Award__c`, master-detail to cycle, lookup to application), Disbursement
   (`Award_Payment__c`, master-detail to award) and Award Requirement (`Award_Requirement__c`,
   master-detail to award; conditions and recipient reports in one object). Master-detail gives
   the roll-ups (applications, awarded amount, scores, paid amount, open requirements) without
   Apex. Programs are Public Read/Write so reviewers can save reviews on every cycle; an admin
   can tighten it and share programs to teams.
3. **The applicant is a Core person or organization.** Applications and awards look up Contact
   and Account, which Core owns. No Person Account, no new person object.
4. **Applications come through Forms (C-42), not a second form engine.** A cycle names its
   application form by record ID as text (`Application_Form_Key__c`), as events do (ADR-0175
   decision 9). `ScholarshipFormAttachment` implements Core's `FormAttachmentExtension`: a
   submission filled from a cycle creates an application for the person and organization Forms
   matched, keeps the answers as JSON and links the submission's files to the application
   (Salesforce Files, no copies). A submission filled from an applicant's own Draft application
   or from a requirement (a recipient report) needs a signed claim (EV-18). Without Forms, staff
   enter applications on the tab.
5. **Eligibility rules are JSON on the cycle.** A list of `{answer, op, value}` with the ops
   `equals`, `notEquals`, `atLeast`, `atMost`, `isTrue` and `contains`, checked against the form's
   answers at intake: all met is Eligible, any not met is Ineligible with the reasons in
   Eligibility Notes; no rules is Submitted. Staff can override the status.
6. **Rubrics are JSON on the cycle.** A list of `{key, label, max, weight}`; blank means one
   overall score from 0 to 10. A review keeps each criterion's score as JSON and Apex writes the
   weighted total to Score, so the roll-ups and reports read one number. Ranking is by Average
   Score, shown on the cycle's review board and in the shipped reports; it is not stored.
7. **Recusal, blind review and panels (SG-03, SG-10).** A reviewer recuses on their own review
   (conflict of interest) with a reason. Blind Review hides the applicant on the review screen:
   a display rule, not a security control, stated in the guides. A cycle names a public group as
   its reviewer panel and how many reviewers each application gets; **Assign Reviewers** fills
   each open application up to that number from the panel, giving each next review to the
   member with the fewest open reviews in the cycle and never to someone who recused on it. Only
   the reviewer or a holder of Manage Scholarships changes a review (validation rule).
8. **Awards and letters (SG-04).** **Decide** on the review board turns an application into an
   Offered award (or Declined). **Make Letter** renders the program's letter template (merge
   tags, HTML-escaped) as a PDF with `Blob.toPdf()`, filed on the award, the technique of
   Volunteers' letters (V-08). Acceptance is recorded by staff or by the recipient in the
   portal.
9. **Disbursements are records only (SG-05, Section 1.5).** BarnCRM never moves money and
   calls no payment service. A schedule splits the award into equal payments; a payment is
   Scheduled, Paid (with the date, method and reference from the accounting system) or
   Cancelled. **Export Disbursements** builds a CSV in the browser (framework-free JS) of the
   payments due or paid in a date range and stamps their Exported Date.
10. **Conditional disbursements (SG-09).** A Condition requirement names the disbursement it
    holds back, or none to hold back all of the award's. `AwardPaymentRulesHandler` (a trigger handler
    that always runs) refuses Paid while a holding condition is Open or Submitted, and refuses
    Paid to anyone without Manage Scholarships.
11. **Recipient reports and renewal (SG-06).** Progress and final reports are requirements with
    due dates; the 6:50 AM nightly step reminds the program owner by bell (an award has no owner of its own), once per date, and,
    when the admin turns it on, emails the recipient their own signed report link. The same step
    opens Planned cycles on their open date and moves Open cycles to Reviewing after the close
    date. **Start Renewal** on a renewable award creates a Draft application in the program's
    next Planned or Open cycle, linked by Renewal Of.
12. **Applicant portal template (PB-06, SG-07).** `portal-client/templates/applicant.json`:
    open cycles (catalog) with **Apply**, my applications with their signed form link, my awards
    with **Accept Award**, and my reports with their signed report link. The actions are
    `ScholarshipsPortalExtension` through Core's `PortalActionExtension` seam; Portal Builder does
    not depend on this module. Files are uploaded on the Forms pages the links open, so the
    portal API gains no upload endpoint. The portal client shows an `https` URL field as a link.
13. **Access (ADR-0131, D-191).** Scholarships Admin (with Manage Scholarships) goes to BarnCRM
    Admin holders, Scholarships Staff to Team Member and Fundraising Staff, Scholarships Read
    Only to Read Only, by `ScholarshipsAccessSync`; it only gives. Reviewers who are not staff
    need Scholarships Staff assigned by hand.
14. **Dashboard (SG-08).** Standard report types, reports and one dashboard in a BarnCRM
    Scholarships folder. No CRM Analytics.

## Consequences

- The module adds seven objects, one settings object, three permission sets, one custom
  permission, one notification type, one trigger, one nightly step and no external endpoint.
- Applications and reports with file uploads need Forms and an active Forms public site; without
  Forms the module still works staff-side.
- Blind review is not enforced by sharing: a reviewer who opens the applicant's Contact can see
  it. A separate reviewer permission set without the applicant fields is the stronger option if
  an organization needs it.
- The `Award_*` names stay distinct from Funders' `Grant_*` objects, which track money received.

## Alternatives considered

- Folding outbound grants into Funders: rejected by D-122 (different customer and meaning).
- A rubric criterion object instead of JSON: more records and Apex for no reporting gain, since
  reports read the weighted total.
- A portal upload endpoint: more attack surface; the signed Forms link already takes files.
