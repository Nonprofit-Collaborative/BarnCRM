# ADR-0203: The BarnCRM LWC Builder module: component definitions as JSON records, one packaged renderer reading in user mode, nothing deployed at run time

**Status:** Accepted (builder decision; LB-01 to LB-06 built as recommended, for Brandon to confirm)
**Date:** 2026-11-11
**Source:** plan Section 5.10 (LB-01 to LB-06), Section 6.0a releases 1.14 and 1.16, D-120,
Section 6.1.2 item 19, Section 1.5 (self-service, nothing paid), Section 9.9 (portability);
builds on ADR-0013, ADR-0017, ADR-0131, ADR-0164 (help text JSON), ADR-0192 (module tabs in the
BarnCRM apps) and ADR-0196 `0196-corporate-hub-module.md` (module skeleton).

## Context

Owner request (D-120): "a drag and drop grid builder based interface so people can create their
own LWCs declaratively." Section 5.10 recommends one packaged runtime renderer that shows a saved
definition and leaves to this record where a definition is stored. The recorded alternative,
generating LWC source and deploying it through the Metadata API, is not for v1: it needs a
callout to the org's own API, deploy permissions and, for an unlocked package, the "Deploy
Metadata from Non-Certified Package Versions via Apex" org setting.

## Decision

1. **Its own package, Core only, both editions.** `packages/lwcbuilder`, package
   `BarnCRM LWC Builder`, module key `LwcBuilder`. Core ships the catalog row
   `BarnCRM_Module.LwcBuilder` (editions `Standard;Nonprofit`, Sort Order 52, no probe object:
   its Setting Definition rows name the module, #1053). No app of its own (ADR-0192): one tab,
   **LWC Builder** (Lightning page tab, `Custom34: Insect`, the only motif still free), joins
   BarnCRM and BarnCRM Console before Error Log, for admins only (catalog Admin Tabs). Install
   leaves the module off, as every module.
2. **A definition is a record, not metadata.** `Built_Component__c` (canonical model 29LB1): a
   name, a unique key (the stable name a Lightning page stores, so a page keeps working after a
   definition is moved between orgs), a description, the object it is built for (optional),
   Active, a version number raised on each save, and the definition itself as JSON in a long
   text field (`Definition__c`, 131,072 characters). Custom metadata was rejected: saving it from
   a page needs a Metadata API deploy, the very thing this design avoids, and a record is
   ordinary data that can be exported, imported, reported on and restored. Sharing Public Read
   Only: everyone who may see built components reads them; only LWC Builder Admin holders
   create, edit and delete (object permissions, decision 9).
3. **The definition document (schema version 1).** `{schemaVersion, sections:[{id, title,
   rows:[{id, columns:[{id, width, blocks:[block]}]}]}]}`. Widths are twelfths (a row's columns
   add up to 12, presets 12, 6+6, 4+4+4, 3+3+3+3, 8+4, 4+8). A block is `{id, type, title,
   visibility, ...type properties}`. The framework-free JavaScript module `lwcBuilderModel`
   owns the format: create, add, move, remove, validate, normalize, the visibility rules and
   the source export, so the same logic serves Salesforce and, later, WordPress (plan 9.9).
   Apex only checks that a saved definition is a JSON object with a known schema version and
   fits the field.
4. **One runtime renderer (LB-02).** `lwcBuilderRenderer`, exposed for record, app and home
   pages in Lightning App Builder, with one property, the component (a picklist of active
   definitions, `LwcBuilderComponentPicklist`). It reads the definition through
   `LwcBuilderController.loadComponent` in user mode and lays it out on the SLDS grid; on a
   phone every column is full width. Nothing is generated or deployed: no Metadata API callout,
   no Named Credential, no deploy permission, and Lightning Web Security, CSP and the org's
   CRUD, FLS and sharing apply to every block as to any packaged component. A definition the
   user cannot read, an inactive one, or the setting Show Built Components turned off renders
   nothing (an admin sees why in the builder's preview).
5. **Building blocks (LB-03).** Each block reads its own data, as the viewing user:
   - **Record Fields**: the page record's fields through Lightning Data Service
     (`lightning-record-view-form`), so field-level security hides what the user may not see;
   - **Related List**: child records of the page record by a lookup field the admin names;
   - **Record List**: records of any object, with one optional filter (field equals, or does
     not equal, a value), a sort and a row limit;
   - **Report Chart**: the first grouping and first summary of a standard summary or matrix
     report, by its API name, run through the Reports API as the user and drawn as plain bars
     (no CRM Analytics, no chart library);
   - **Text**: rich text shown through `lightning-formatted-rich-text`, which strips scripts;
   - **Image**: a Salesforce-relative address (a static resource or a file) or an `https`
     address the org's CSP Trusted Sites allow, with alternative text.
   Related List and Record List queries are built in Apex from names checked against the
   schema (object, fields, filter and sort fields must exist; the filter value is a bind
   variable, never spliced) and run `WITH USER_MODE`, capped by the setting Rows per List (10,
   at most 200) and six columns.
6. **Buttons (LB-04).** An Action block shows a button that opens a quick action (a page
   reference of type `standard__quickAction`, with the page record as context on a record page)
   or runs a screen flow inline (`lightning-flow`), optionally passing the page record's Id as
   the flow's `recordId` input. The platform decides whether the user may run either: the
   builder grants nothing.
7. **Conditional visibility (LB-05).** Each block may carry one rule: Always; the page record's
   field equals, does not equal, contains, is blank or is not blank; or the user holds, or does
   not hold, a named custom permission (checked in Apex with `FeatureManagement`). Field values
   come from Lightning Data Service as optional fields, so a field the user cannot read counts
   as blank. A rule is a display choice, never a security control: what a block shows is still
   limited by the user's access, and the help says so.
8. **Export as LWC source (LB-06).** The builder's Export panel turns a definition into an LWC
   bundle (HTML, JavaScript, `js-meta.xml`) in the browser (`lwcBuilderModel.exportSource`),
   offered as three files to download or copy. Record Fields, Text, Image and Action blocks
   export working markup; Related List, Record List and Report Chart blocks export a card with
   a comment naming what to wire, because their data comes from this module's Apex, which an
   exported bundle must not depend on. Visibility rules export as comments. The bundle is the
   developer's to deploy and maintain (Section 5.10); nothing is deployed for them. The setting
   Allow Source Export (on) hides the panel.
9. **Access (ADR-0131, D-191).** `LWC_Builder_Admin` (create, edit and delete built components,
   the builder tab, every Apex class) to BarnCRM Admin holders; `LWC_Builder_Staff` and
   `LWC_Builder_Read_Only` (read built components and the renderer's Apex, no tab) to Team
   Member and Fundraising Staff, and to Read Only. Given by `LwcBuilderAccessSync`, never taken
   away. Someone with no LWC Builder set sees nothing where a built component is placed.
10. **Settings.** `LWC_Builder_Settings__c` (ADR-0017), section LWC Builder: Show Built
    Components (on), Rows per List (10), Allow Source Export (on). Installing the module changes
    no existing page: a built component shows only where an admin places it.
11. **Pages are thin.** UI text comes from the module's help catalog `BarnHelp_LwcBuilder`
    (ADR-0164), no custom labels; Apex returns plain shapes.

## Alternatives Considered

- **Generate and deploy real LWC bundles through the Metadata API.** Recorded in D-120 and not
  for v1: a callout to the org's own API, deploy rights for the person building, and an org
  setting an admin must turn on for unlocked packages. LB-06 gives developers the source
  without any of that.
- **Definitions as custom metadata.** Deployable between orgs as metadata, but every save from
  the builder would be a Metadata API deploy (decision 2).
- **A chart library.** Bars drawn with plain markup cover a summary report's first grouping,
  need no static resource and stay readable to screen readers as a list.
- **Free-form SOQL in a Record List block.** More flexible, but a text query is hard to check
  and easy to get wrong; named fields with one bound filter cover the common lists.

## Consequences

- An admin can build and place a component without code or a deploy, and move it between orgs
  as a record (Data Loader or the Import page).
- Every block honours the viewer's CRUD, FLS and sharing, because every read is user mode or
  Lightning Data Service; a built component can never show more than a user could open.
- A renamed or deleted field leaves the block showing an error message, not a broken page.
- A quick action that a page layout does not offer, or a flow the user may not run, fails with
  the platform's own message.
