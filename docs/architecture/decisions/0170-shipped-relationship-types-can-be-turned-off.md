# ADR-0170: Shipped relationship types can be turned off

**Status:** Accepted (owner request, Brandon, 2026-11-05)
**Date:** 2026-11-05
**Source:** owner QA request 2026-11-05 ("Default relationships, if relationships are enabled,
should be able to be disabled"); amends ADR-0085 decision 2 and plan decision D-25

## Context

Core ships eleven Relationship Type rows. ADR-0085 made every shipped row read only on the
Custom Metadata page, so an organization that does not use a shipped type (Grandparent, Partner)
cannot stop it being offered without going to Setup, which Principle 1 rules out.

ADR-0133 lets a shipped Match Source be archived by deploying the row with `Active__c` cleared,
relying on the field being subscriber controlled. That holds only in a managed package. In a
source deployed org and in an unlocked package, the next deploy or upgrade writes the shipped
row again and turns the type back on. A subscriber also cannot change a protected packaged
record, and the Apex deployment needs an org setting and finishes asynchronously.

## Decision

1. **A shipped relationship type is turned off by listing it, never by changing the row.**
   `BarnCRM_Settings__c.Relationship_Types_Turned_Off__c` holds the comma separated
   DeveloperNames of the shipped rows turned off. It is organization data, so no deploy or
   upgrade touches it, and the package still updates the row's label and reciprocal.
2. **Turned off and on on the Custom Metadata page.** Relationship Type is registered as
   shipped-archivable with that setting (`shippedOffSetting`): a shipped row's menu offers Turn
   Off or Turn On, the change is saved at once and audited (`SettingsService.saveSystemValue`),
   and the row shows Off. Only holders of Manage BarnCRM Metadata can do it, as for every
   action on the page. Editing a shipped row stays refused.
3. **What turned off means.** A new relationship, or a change of type, to a turned-off type is
   refused with a message naming where to turn it back on; the relationship card does not offer
   it; sample data skips it. Existing relationships keep the type, display it and stay in step,
   because the turned-off row's reciprocal mapping still applies. BarnCRM still writes the
   other side of a pair even when that side's type is off (Grandchild for a new Grandparent).
4. **The organization's own row wins.** An active row that is not turned off for the same Type
   replaces the turned-off shipped mapping, and the type is offered again. Turning the shipped
   row back on is refused while such a row is active, as restoring any row is.
5. **Shown only while Relationships is on.** The Relationship Types list on the page is hidden,
   and its actions refused, while the Relationships feature is off (ADR-0124).

## Alternatives considered

- **Deploy `Active__c` on the shipped row (ADR-0133's way).** Not upgrade safe outside a managed
  package, asynchronous, and needs the Apex deploy org setting.
- **An org-owned override row of the same key.** Upgrade safe, but still a metadata deployment,
  and a second row per type that the uniqueness rule and the page would have to explain.
- **A custom object for relationship types.** The larger change ADR-0085 left open; not needed
  for this request.

## Consequences

- One new settings field. The 255 characters hold every shipped DeveloperName several times.
- The relationship card picks Type with its own picker (`RelationshipController`), because a
  record form field cannot leave values out. Salesforce's standard edit page still lists every
  value; saving a turned-off one there is refused.
- Match Source keeps ADR-0133's deployment. Moving it to a setting the same way is open.
