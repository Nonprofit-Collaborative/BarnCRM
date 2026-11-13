# ADR-0020: Module settings pages reached by navigation, Core pages by literal import

**Status:** Accepted
**Date:** 2026-09-07
**Source:** platform limitation recorded under plan Section 9.3; refines plan Section 4.8 and
ADR-0017

## Context

Plan Section 4.8 requires one Nonprofit Settings console with a left navigation grouped by
module: every setting a nonprofit has, on one page, whichever package ships it. The console is
data driven from `Setting_Definition__mdt`, and a row whose `Data_Type__c` is `Component`
declares that a whole panel, not a single control, belongs in that section: household naming
with its preview, the automation table, the access page, health check.

The console was built to render those panels with a dynamic import,
`await import('c/' + row.Component__c)`, which would have let any package contribute a panel
by shipping a row. Two platform facts make that impossible.

1. **Lightning Web Components cannot import from a computed specifier.** The platform ruleset
   reports `@lwc/lwc-platform/no-dynamic-import-identifier`, "Dynamic import cannot be invoked
   with a dynamic value". The specifier has to be a literal the compiler can see, because the
   module graph is resolved at compile time. A computed import does not throw a useful error at
   run time: it rejects, and a panel silently never appears.
2. **A package cannot import from a package that depends on it.** Core is installed before
   Giving, Volunteers, Programs and Funders and knows nothing about them (ADR-0003). Even with
   literal specifiers, Core cannot write `import('c/giftEntrySettings')`: the module does not
   exist when Core is compiled.

So the two cases are genuinely different, and one mechanism cannot serve both.

## Decision

**Core panels are imported by name. Module panels are reached by navigation.**

1. `settingsConsole` holds a registry of literal imports, one `import('c/name')` per Core
   component it can render, selected by a switch on the row's `Component__c` value. The Core
   components are `householdNamingSettings`, `automationControl`, `errorLogTile`,
   `accessManager`, `healthCheckPanel` and `sampleDataManager`. A row naming anything else
   renders a short "not installed" message in place of the panel rather than an empty space,
   so an admin sees why a section looks bare.
2. `Setting_Definition__mdt` gains `Navigation_Target__c` (text 80). When a row's
   `Data_Type__c` is `Component` and `Component__c` is blank, the console renders a button that
   navigates to the Lightning tab named in `Navigation_Target__c` using `NavigationMixin` and
   `standard__navItemPage`. A module ships its own settings app page, its own tab, and one
   Setting Definition row naming that tab, and its settings appear in the one Nonprofit Settings
   navigation without Core knowing anything about it at compile time.

Both kinds of row keep their `Section__c`, so the left navigation is still one list grouped the
way an administrator thinks, which is what plan Section 4.8 actually asks for.

## Alternatives considered

- **Keep the computed import.** Rejected: the platform rejects it and the failure is silent,
  which is the worst of both (plan Principle 1: if Maria cannot see why, it is not done).
- **A registry of literal imports in Core covering module components too.** Rejected: Core
  cannot name a component that does not exist when Core is compiled, and adding a module would
  mean a new Core version, which breaks the independent-module rule (ADR-0003).
- **One settings tab per package, no shared console.** Rejected: it is the thing plan Section
  4.8 exists to prevent. An administrator would have to know which package owns a setting
  before she could find it.
- **Render module panels in an iframe or a Visualforce page.** Rejected: heavier, worse
  accessibility, and no better than a tab the platform already knows how to navigate to.

## Consequences

- Adding a Core panel is a two-line change in one registry in `settingsConsole` plus a shipped
  row. Adding a module panel is a page, a tab and a row, with no Core change at all.
- A module's panel is a page away rather than inline. The console shows its section, its label
  and its description, so the path is visible; it is one click, not a search.
- The console needs the module's tab to be visible to the user. A row whose tab is not visible
  navigates to a page the user cannot see, so a module's permission set has to grant its own
  tab alongside its Setting Definition row.
- `Component__c` is now documented as Core-only. A module that puts a component name there gets
  the "not installed" message, which is the correct outcome: Core genuinely cannot render it.

## Amendment A1, 2026-11-13: a page with one component is a component tab (release 1.23, S12)

A module's page "and its own tab" (Decision 2) no longer needs an app page when the page holds
one component and needs no record. The component declares `lightning__Tab`, and its CustomTab
names it with `<lwcComponent>` instead of `<flexiPage>`. The tab keeps its API name, so
`Navigation_Target__c` rows and every `standard__navItemPage` link reach it unchanged.

1. **Converted.** 41 single-component app pages across Core and the modules became component
   tabs, and their FlexiPages were removed.
2. **Kept as app pages.** A page that sets component properties (Households, Organizations) or
   holds more than one component (Bulk Update, Import), and every record page.
3. **The title.** An app page printed its name above the component, so page components passed
   `title-hidden` to `c-barn-page-shell`. A component tab prints no header, so those components
   now show the shell's title.
4. **Reachability.** `check-components-reachable.py` counts a component a tab names as reached.

Consequence: one fewer metadata file per page, and no page layout an admin can edit separately
from the component. An org that already has a converted tab as an app-page tab may need the
tab redeployed and the old FlexiPage removed through the destructive manifest.
