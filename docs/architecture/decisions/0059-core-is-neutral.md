# ADR-0059: Core is neutral: the nonprofit app, wording, giving and receipt settings and Setup Assistant steps live in Giving

**Status:** Accepted (builder decision, under the owner decision recorded in ADR-0046)
**Date:** 2026-09-25
**Source:** C-29; plan Section 4.1 "Suites and packaging" (owner decision, Brandon, 2026-09-23);
ADR-0046; builds on ADR-0014, ADR-0017, ADR-0020 and ADR-0057 (as amended by ADR-0058)

## Context

ADR-0046 made Core alone the Community Suite, for organizations that are not nonprofits, and
said that the nonprofit app and wording, the giving and receipt settings and the nonprofit
Setup Assistant steps move from Core to Giving (C-29). Four things in Core did not meet that:

1. **Settings.** Seven keys on `Nonprofit_Settings__c` are read only by Giving: the default fund
   and appeal, the tax identification number, and the receipt signer, title, logo and signature.
   Core carried them because the Setup Assistant wrote them (ADR-0014, canonical model Section 12).
2. **Setup Assistant.** Core hard-codes eight steps. Step three picks a fund and an appeal, step
   five asks for receipt fields, step eight enters a first gift, and a Core-only org sees notices
   saying Giving is missing.
3. **Health Check.** Core asks two receipt questions: who holds `Override_Receipt_Lock`, and how
   many receipts failed to generate (`ReceiptGapSelector`, reading `Receipt__c` dynamically).
4. **Wording and the app.** The app is "Nonprofit Hub"; the console, permission, permission sets
   and roles say "Nonprofit"; about seventy Core labels speak of gifts, donors and receipts; the
   Fundraising Staff role ships in Core.

Constraints: a dependent package cannot add fields to a Core object (ADR-0014, ADR-0017); Core
may not import a Giving component (ADR-0020); Core must keep working alone on a Platform-only org
(ADR-0013); and an org with Core and Giving should see the same settings, console, Setup
Assistant flow and labels as before.

## Decision

1. **The seven Giving-only keys move to `Giving_Settings__c` with their API names unchanged:**
   `Default_Fund__c`, `Default_Appeal__c`, `Organization_EIN__c`, `Receipt_Signer_Name__c`,
   `Receipt_Signer_Title__c`, `Receipt_Logo_Document_Id__c`, `Receipt_Signature_Document_Id__c`.
   Their Setting Definition rows ship from Giving with the same labels, sections and order, so
   the console is unchanged. `Organization_Legal_Name__c` and `Organization_Address__c` stay in
   Core: every organization has a name and an address, and Giving reads them from Core. No data
   is migrated: no package version exists (plan Section 4.3, ADR-0029, ADR-0046), so there is no
   subscriber org holding values on the old fields.
2. **The Setup Assistant gains an extension seam, the ADR-0057 shape for a new question.**
   Core defines `SetupAssistantExtension` (one method, `contributions()`) and
   `SetupAssistantExtensions`, which looks up a list of class names with `Type.forName` (today
   `GivingSetupAssistantExtension`). A contribution either adds a step, placed by sort order, or
   adds fields to a Core step and may replace that step's wording. A step's fields are data
   (setting key and settings object, label, type Text, Record, File or Navigate, and limits),
   rendered by one generic Core panel and saved by one Core method that accepts only the keys
   that step declares, through `SettingsService` and the settings object each key names. Core
   ships seven neutral steps; Giving contributes the fund and appeal step (third), the receipt
   fields and wording of the identity step, and the first-gift button and wording of the last
   step. With Giving the flow, the eight steps, their wording and their fields are as before;
   without it there are seven steps and no notice about a missing module. An extension that
   cannot be built or throws is logged and left out, and the assistant still opens.
3. **The two receipt checks move to Giving's Health Check extension** with their finding keys,
   wording, severities and fixes unchanged. Core's `ReceiptGapSelector`, which reached
   `Receipt__c` with dynamic SOQL, is replaced by Giving's `ReceiptGenerationFailureSelector`,
   an ordinary user-mode query on Giving's own object.
   `GivingHealthCheckExtension` asks the receipt generation question of every viewer, as Core
   did, and the receipt lock override question only of a viewer who may manage settings.
4. **Core's app is neutral and Giving's app is the nonprofit one.** Core's app keeps its API
   name and is labelled with the working product title, Open Impact, for both suites; its tabs
   and record page overrides do not change. Giving's nonprofit app is the Fundraising app it
   already ships (ADR-0018). The Fundraising Staff role (`Fundraising_Staff` group, unchanged
   content) moves to Giving; Core's Access page already skips a role that is not in the org.
5. **Core's wording is neutral.** No Core label, help text, description, tab, app, permission,
   permission set or role label speaks of gifts, donors, receipts, fundraising or nonprofits,
   with three named exceptions: the names of Salesforce products Core detects and coexists with
   (NPSP, Nonprofit Cloud, Agentforce Nonprofit, Gift Transaction); import aliases that only
   match column headers in a file (`Donor First Name`); and text shown only when Giving is
   installed that a Core screen cannot yet take from Giving (the import wizard's gift columns,
   control total and donation matching, and the Giving and Receipts section names). The
   "Nonprofit" names become "Open Impact": Open Impact Settings, Manage Open Impact Settings,
   Open Impact Admin, Staff, Read Only and Duplicate Review, renamed with the product later
   (plan Section 8.3).
6. **API names do not change in C-29.** `Nonprofit_Settings__c`, `Manage_Nonprofit_Settings`,
   the `Nonprofit_*` permission sets, and the `Nonprofit_Hub_Home` and `Nonprofit_Settings`
   tabs and pages keep their API names. Only labels change. Renaming them is part of the name
   pass, before the first package version.
7. **Core fields that hold a module's record identifier are labelled neutrally.**
   `Import_Row__c.Gift_Id__c` and `Soft_Credit_Id__c` are on Core's Import Row layout, so a
   Core-only org would see them. They stay on the layout, where an org with Giving still reads
   them, and are relabelled Resulting Record and Second Resulting Record, since a module's
   import can also match a row to an existing record rather than creating one, with their API
   names unchanged under decision 6.

## Alternatives considered

- **Leave the keys in Core and hide them.** Rejected: a Community org would still carry tax and
  receipt fields, which ADR-0046 rules out.
- **Split the identity step into a Core step and a Giving receipt step.** Rejected: it changes
  the flow for Core and Giving (nine steps, receipt fields separated from the name they print
  beside), and the plan asks for the same flow.
- **Giving renders its own step panels, reached by navigation (ADR-0020).** Rejected for the
  steps themselves: the assistant would leave the page mid-setup. Kept for anything bigger than
  a few fields.
- **A registry custom metadata type for steps.** Rejected for the reason ADR-0057 gave: one
  dependent package, and a class name gives what a registry would, with no new object.
- **Giving ships a second copy of the hub, labelled Nonprofit Hub.** Rejected as the default:
  Core's permission sets must make Core's app visible for the Community Suite, and cannot name a
  Giving app, so a nonprofit would see two hubs with the same tabs, and a person holding only a
  Core role would see just the neutral one. Listed as an owner question.
- **Rename the API names now.** Rejected for C-29: several hundred references change for no
  user-visible gain, and the name pass renames the same files.

## Consequences

- Core's neutral labels are seen by nonprofits too: the hub reads Open Impact rather than
  Nonprofit Hub, and the console Open Impact Settings. A Core label cannot differ by which
  packages are installed, so "the same labels" holds for everything that moved to Giving, not
  for Core's own names.
- `dynamic-apex.md` lists `SetupAssistantExtensions` as a fourth resolver of the same shape and
  drops `ReceiptGapSelector` from the Core-reaches-Giving table.
- Health Check lists the two receipt findings after Core's own findings of the same category.
- A later module that wants a Setup Assistant step adds its class name to
  `SetupAssistantExtensions.EXTENSION_CLASSES` and implements the interface.
- A step's field limits are data, so Core's save enforces a Text field's length and pattern
  on the server, as the page does: a save that follows an upload sends the whole step without
  the page's own validation.
- Giving isolates each of its Health Check checks the way Core isolates its own: a check that
  throws becomes its own `check_failed_<key>` finding, through `HealthCheckService.checkFailed`,
  and the other Giving findings still stand. The failed-receipt count is capped, because a
  `COUNT()` past 50,000 rows would fail with a limit exception nothing can catch.
- Giving's other writers (`AccountingPeriodWriter`, `AcknowledgmentController`,
  `CommitmentService`) still make a first save from `Giving_Settings__c.getOrgDefaults()`. That
  predates C-29 and has its own follow-up task; C-29 adds no new writer of that kind.
