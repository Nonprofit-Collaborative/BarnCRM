# ADR-0172: Shipped match sources are turned off by a setting

**Status:** Accepted (owner decision D-184, Brandon, 2026-11-06)
**Date:** 2026-11-06
**Source:** owner decision D-184 D ("Match Sources: turning off a shipped item becomes a saved
setting like relationship types"); amends ADR-0133 (archiving a shipped Match Source) and closes
the question ADR-0170 left open

## Context

ADR-0133 lets an administrator archive a shipped Match Source by deploying the row with
`Active__c` cleared, relying on the field being subscriber controlled. ADR-0170 found that this
holds only in a managed package: in a source deployed org and in an unlocked package the next
deploy or upgrade writes the shipped row again and turns the source back on. The deployment also
needs the Apex deploy org setting and finishes in the background. ADR-0170 moved shipped
relationship types to a setting and left Match Source on the deployment.

## Decision

1. **A shipped match source is turned off by listing it, never by changing the row.**
   `BarnCRM_Settings__c.Match_Sources_Turned_Off__c` holds the comma separated DeveloperNames of
   the shipped rows turned off. It is organization data, so no deploy or upgrade touches it.
   Match Source uses ADR-0170's mechanism unchanged: it is registered with the custom metadata
   manager with that setting (`shippedOffSetting`), the change is saved at once and audited
   (`SettingsService.saveSystemValue`), and only holders of Manage BarnCRM Metadata can make it.
2. **Same switch, no wait.** The Active switch in Duplicate Matching, Matching Logic, is
   unchanged for the person using it; for a shipped source it now saves at once and says so,
   with no deployment to wait on. The organization's own sources are still deployed.
3. **What turned off means.** The duplicate scan and import matching skip a listed source
   (`MatchSourceService.usableSources`), and Matching Logic shows it as not active. Where Used
   still lists it, as it lists every source.
4. **A row archived the old way still reads as off.** A shipped row deployed with `Active__c`
   cleared under ADR-0133 stays off. Turning it on clears it from the setting and deploys the
   row active once, as before.

## Alternatives considered

- **Keep the deployment (ADR-0133).** Not upgrade safe outside a managed package, and BarnCRM
  installs unlocked and from source today.
- **One setting for every shipped list.** A single field shared by relationship types and match
  sources would save a field, but mixes two lists whose names could collide, and each list
  already has its own page.

## Consequences

- One new settings field (Text 255); every shipped source name fits several times.
- `Active__c` on a shipped row is now written only to restore a row archived the old way.
