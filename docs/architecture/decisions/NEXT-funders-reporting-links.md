# ADR-NEXT: Funders reporting: outcomes linked to requirements, a funder report template merged in the browser, a board dashboard that reads Giving when it can

**Status:** Proposed (built for release 0.16, L-06, F-06 and F-07; awaits owner confirmation)
**Date:** 2026-11-02
**Source:** plan Section 5.5 (F-06, F-07), Section 5.7 (L-06: "no hard dependency in either
direction"), Section 9.9 (portability); builds on ADR-0014, ADR-0016, ADR-0129, ADR-0154 and ADR-NEXT
`NEXT-funders-module.md`.

## Context

Three release 0.16 items reach across modules. L-06 links a Logic Models outcome to what a grant
requires, while neither Funders nor Logic Models may need the other. F-06 merges a grant, its
requirements and, where Logic Models is installed, indicator results into a report for the funder.
F-07 shows a board the revenue mix, how concentrated it is and the restricted balances, from Giving
when Giving is there. BarnCRM already has two merge engines (Giving receipts, Volunteers letters),
both Apex, both closed sets of `{Token}` names in an HTML body, both rendering PDF files.

## Decision

1. **The link lives in Funders, by record identifier.** A grant requirement's `Outcome_Id__c`
   (Text(18)) holds the identifier of a Logic Models element of type Outcome or Output, the pattern
   Funders already uses for a program (ADR-NEXT `NEXT-funders-module.md` decision 6, ADR-0014).
   Logic Models stays unaware of Funders. An always-run automation (`Grant_Requirement_Rules`)
   refuses text that is not an identifier, or, where Logic Models is installed, one of another
   object; the card offers only outcomes and outputs.
2. **Funders reads Logic Models by describe.** `GrantOutcomeService` finds `Logic_Model_Element__c`,
   `Indicator__c` and `Indicator_Period__c` with `NamespaceUtil.packagedObjectType`, queries them
   in user mode with dynamic SOQL whose object and field names come from describe, never from the
   user, and returns plain maps. Without Logic Models, or without read access to it, the outcome
   card says so and the report token is empty. This is the program pattern applied to a second
   module, so it adds no new mechanism; the ADR records that an optional module may read another
   optional module's objects only this way.
3. **The report template reuses the token approach, merged in the browser.** A Funder Report
   Template (`Funder_Report_Template__c`) is an HTML body with a closed set of `{Token}` names,
   shipped as `Funder_Report_Template_Default__mdt` rows copied in at install and never changed
   after (the Volunteers letter template pattern, plan Section 4.8). The merge runs in the
   framework-free module `grantReportModel.js`: every value is escaped, the body is the
   organization's own, and the result is a printable HTML file downloaded from the grant's page,
   as the logic model report does (L-04). The Apex controller only returns the grant, its
   requirements, the linked outcomes' indicator results and the active templates as plain JSON.
   No PDF and no saved file: a funder report is edited before it is sent, and an HTML file opens in
   any word processor. This keeps the merge portable (plan 9.9) and costs no file storage.
4. **The board dashboard reads Giving by describe too.** Funders lists Giving as a package
   dependency (ADR-NEXT `NEXT-funders-module.md` decision 1), but release 0.16 still references no
   Giving object, so F-07 reads Giving's totals (`Fund__c` with `Restricted__c` and the year's
   raised amount, and the top accounts by `Giving_This_Year__c`) by describe, and shows the grant
   figures alone where Giving is absent or unreadable. The restricted balance per fund comes from
   the fund ledger (F-03) once it lands; until then the panel shows what each restricted fund
   raised, and the integration point is one method, `FundersBoardController.restrictedFunds`.
5. **Concentration uses fixed, documented thresholds.** The board marks a single source above 25
   percent of the year's revenue, and the five largest above 50 percent, as a risk worth
   discussing. These are board guidance shown as words, not enforced, so they are not settings.

## Alternatives Considered

- **The link in Logic Models (an indicator naming a requirement).** Rejected: an outcome serves
  many grants, and a requirement is the thing a funder asks about; the record that is reported on
  holds the link.
- **A Core junction object between any two modules' records.** Rejected: one optional text field
  does the job, and a Core object would be a new dependency for every org.
- **Merging in Apex and saving a PDF, as receipts and letters do.** Rejected for funder reports:
  they are edited before sending, a PDF cannot be, and the browser merge is portable.
- **Shipped report and dashboard metadata for the board.** Not chosen for the first version: a
  standard dashboard cannot combine grants and Giving totals or compute shares; the in-app panel
  can, and shipped reports can follow.

## Consequences

- A requirement can name an outcome that is later deleted; the card shows it as missing, as the
  Program card does.
- The report's look is the organization's HTML; a template with broken HTML still merges.
- `FundersBoardController.restrictedFunds` reads each restricted grant's balance from F-03's
  Grant fields (`Restricted__c`, `Restricted_Balance__c`) by describe, so the board lists them as
  soon as the ledger is merged, with no change here, and runs without it meanwhile.
