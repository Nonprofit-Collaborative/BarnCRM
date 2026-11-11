# ADR-NEXT: The BarnCRM Corporate Hub module: its own package on Core, a document and policy library on Salesforce Files, acknowledgments, a compliance calendar, contracts, and templates shipped as data

**Status:** Accepted (builder decision; CH-06 to CH-08 built as recommended, for Brandon to confirm)
**Date:** 2026-11-11
**Source:** plan Section 5.8 (CH-01 to CH-20), Section 6.0a release 1.7, D-118, D-120, D-178,
Section 1.5 (no Experience Cloud, no services), Section 9.9 (portability); builds on ADR-0006,
ADR-0013, ADR-0017, ADR-0131, ADR-0164 (help text JSON), ADR-0166 (nightly dispatcher),
ADR-0177 and ADR-0192 (module tabs in the BarnCRM apps).

## Context

Corporate Hub (D-118) keeps an organization's documents, policies, compliance obligations and,
later, its board governance, in either edition. Release 1.7 builds CH-01 (library), CH-02
(acknowledgments), CH-03 (compliance calendar), CH-04 (shipped templates), CH-06 (recommended
extra templates), CH-07 (recommended policies) and CH-08 (contracts). Later work adds CH-05 (GDPR
templates and records), CH-09 to CH-14 and CH-15 to CH-20 (board roster, meetings, motions,
conflict-of-interest disclosures, the board dashboard and portal), and C-47 legal entities.
This record fixes the model now so those fit without reshaping it.

## Decision

1. **Its own package, Core only, both editions.** `packages/corporatehub`, package
   `BarnCRM Corporate Hub`. Core ships the catalog row `BarnCRM_Module.CorporateHub` (editions
   `Standard;Nonprofit`, Sort Order 48, no probe object: its Setting Definition rows name the
   module, #1053), so Core finds `CorporateHubAccessSync` and `CorporateHubPostInstall` by name.
   No app of its own (ADR-0192): the Corporate Hub, Library Documents, Compliance Obligations
   and Agreements tabs join BarnCRM and BarnCRM Console before Error Log. Install leaves the
   module off, as every module.
2. **Files are Salesforce Files.** A document, a completed compliance cycle (its evidence) and
   an agreement hold their files as ordinary `ContentDocumentLink`s, through the standard Files
   related list. No parallel store, no file body in a field. Files count against the org's file
   storage. A file's own versions are Salesforce's; the policy version people acknowledge is
   the document's Version field (decision 3).
3. **Library Document (CH-01, canonical model 29CH1).** `Hub_Document__c`: title, type (Policy,
   Procedure, Governing Document, Plan, Form, Other), status (Draft, Active, Retired), owner,
   current version number, effective date, next review date and review interval, whether it
   needs acknowledgment, a summary, and a template key. **Publish New Version** raises the
   version, sets the effective date and marks it Active; **Mark Reviewed** moves the review date
   on; **Retire** sets Retired and the date. Sharing Public Read Only: everyone reads the
   library; owners and Corporate Hub admins edit.
4. **Policy Acknowledgment (CH-02, 29CH2).** `Policy_Acknowledgment__c`: one person asked to
   attest to one version of one document, either a staff user (`User__c`) or a Core person
   (`Person__c`, Contact) with no login, never both. Status Requested, Acknowledged or
   Superseded; a unique key (document, version, person) stops duplicates. **Request
   Acknowledgments** creates rows for everyone holding a BarnCRM role, or for the members of a
   public group, owned by the person asked, so sharing is Private and each person sees and
   answers only their own; Corporate Hub admins see all. Publishing a new version supersedes the
   open requests and asks the same people again. A person acknowledges their own request; only a
   holder of the custom permission Manage Corporate Hub records one for someone else (a paper
   attestation), enforced by a validation rule. Outstanding means Requested for the current
   version, shown on the document and in reports.
5. **Compliance calendar (CH-03, 29CH3, 29CH4).** `Compliance_Obligation__c`: category,
   jurisdiction, status (Off, Active, Done), next due date, recurrence (One Time, Monthly,
   Quarterly, Twice a Year, Yearly, Every Two Years), reminder days, instructions, a reference
   link, owner and a template key. **Complete This Cycle** writes a `Compliance_Cycle__c` (a
   detail: the due date it was for, completed on and by, outcome, notes; evidence as Files on
   it) and moves the due date on by the recurrence, or marks a one-time obligation Done. The
   cycles are the history. Sharing Public Read/Write: obligations are the organization's, not a
   person's. Reports and dashboards are standard ones.
6. **Agreements (CH-08, 29CH5).** `Agreement__c` (labelled Agreement: "Contract" is a standard
   object's label): type, status (Draft, Active, Expired, Ended), the other party (Organization
   account and contact), start and end dates, auto-renew and its term, notice days, the notice
   date (formula), value, terms, owner. The nightly run moves an auto-renewing agreement's end
   date on by its term once it passes, and marks any other Active agreement past its end
   Expired. Sharing Public Read Only.
7. **Reminders on the nightly run.** One step of Core's dispatcher (ADR-0166),
   `CorporateHubNightlyJobProvider`, 6:45 AM: a bell notification (the module's own type
   `Corporate_Hub_Reminder`) to the owner of each Active obligation due, Active agreement at its
   notice date (or end date) and Active document at its review date, within the record's
   reminder days or the setting's (30). Each record keeps the date it was reminded for, so one
   reminder goes per date. Acknowledgment requests notify the person asked when created. The
   step's switch and the setting Send Corporate Hub Reminders (on) turn it off.
8. **Templates ship as data (CH-04, CH-06, CH-07; ADR-0006 decision 3).** The JSON static
   resource `BarnCorporateHubTemplates` holds obligation templates (CH-04: corporate or state
   annual report, annual tax return; CH-06: charitable solicitation registration, insurance
   renewals, annual financial audit or review, registered agent) and starter policies (CH-07:
   conflict of interest, whistleblower, document retention and destruction, gift acceptance).
   The setup step (`CorporateHubPostInstall.runSetup`, and Add Missing Templates on the
   Corporate Hub page) creates a record for each template key the org does not have:
   obligations as Off, policies as Draft with no legal text. The admin sets dates, turns them on
   and edits freely; an upgrade adds new keys only and never touches an existing record. Retire
   a template's record rather than delete it, or the next setup adds it again. Template text is
   generic, country-neutral where it can be (US rows say so), and every template carries "not
   legal advice; review with your counsel".
9. **Settings.** `Corporate_Hub_Settings__c` (ADR-0017), section Corporate Hub: Send Corporate
   Hub Reminders (on), Days Before to Remind (30), Days to Acknowledge (30).
10. **Access (ADR-0131 and the simpler permission sets ADR, D-191).** `Corporate_Hub_Admin`
    (everything, View All and Modify All, Manage Corporate Hub) to BarnCRM Admin holders;
    `Corporate_Hub_Staff` (create and edit documents, obligations, cycles and agreements, no
    delete; answer their own acknowledgments) to Team Member and Fundraising Staff;
    `Corporate_Hub_Read_Only` (read, and answer their own acknowledgments) to Read Only. Given
    by `CorporateHubAccessSync`, never taken away.
11. **Pages are thin.** UI text comes from the module's help catalog `BarnHelp_CorporateHub`
    (ADR-0164), no custom labels; Apex returns plain shapes, user mode; date math for views runs
    in the framework-free `corporateHubModel` module (plan 9.9).

## Extension points (later items)

- **CH-05 GDPR.** New template rows (category Data Protection) in the same JSON, plus its own
  objects (processing records, requests, breach log); a request links to Core's Erase a person.
- **CH-09 to CH-20 board governance.** Board roster, terms, meetings, packets, motions and
  disclosures are new objects in this package. Board packets and minutes are Files on the
  meeting. Board policy acknowledgments (CH-12) are Policy Acknowledgment rows with `Person__c`
  set; annual disclosures reuse Request Acknowledgments with a board audience. Template type
  Governance is reserved for board obligations (annual meeting, elections).
- **PB-02 board portal.** A portal acknowledges a `Person__c` row through Core's
  `PortalActionExtension` seam, as the person.
- **C-47 legal entities.** A `Legal_Entity__c` lookup on obligations, documents and agreements
  when C-47 ships; obligations are then per entity. Nothing assumes one entity.
- **More templates.** A new JSON row with a new key; the setup step adds it on upgrade.

## Alternatives Considered

- **Templates as custom metadata rows (`Match_Source__mdt` style).** Upgrade-safe too, but
  each row is a metadata file with a dozen fields, and the JSON is portable to WordPress (9.9).
- **Turn on a template from a list without creating records first.** Fewer records, but the
  brief and ADR-0006 load shipped defaults into editable records at setup.
- **Acknowledgments as a master-detail of the document.** Would force Controlled by Parent
  sharing, so every reader of a policy could edit everyone's attestation.
- **Task-based reminders.** Task is a standard Activity object outside Core's list; a bell
  notification needs no object.

## Consequences

- An org can run its policy library, attestations, filing calendar and contracts on Files
  and standard reports, with nothing paid and no portal.
- Each completed cycle is a record, so "when did we file the 990 last year, and where is the
  proof" is one related list.
- Deleting a template record and running setup again brings it back (documented).
