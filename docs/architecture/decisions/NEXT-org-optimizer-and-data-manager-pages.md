# ADR-NEXT: Org Optimizer and Data Manager pages

**Status:** Accepted (owner decisions, Brandon, 2026-10-13)
**Date:** 2026-10-13
**Source:** owner request 2026-10-13 (expand Data Hygiene into an Org Optimizer, add a Data
Manager hub for the data tools) and owner decisions of the same day: field utilization lives
only inside Org Optimizer; duplicate review moves to Org Optimizer with a link left in BarnCRM
Settings; Import is reached from Data Manager and keeps the tab label "Import"; Import and Bulk
Update leave the app navigation and Find stays; unused-setup checks are for administrators
only. Builds on ADR-0079 (data hygiene checks), ADR-0047 (data jobs), ADR-0077 and ADR-0091
(bulk update and delete), ADR-0020 (module pages reached by navigation), ADR-NEXT
`NEXT-field-utilization-on-demand.md` and ADR-NEXT `NEXT-barncrm-app-is-a-console-app.md`.
Admin guide `org-optimizer.md`, `data-manager.md`.

## Context

What needs attention in an org was spread over four places: the Data Hygiene tab, the
Duplicates panel in BarnCRM Settings > Households, the field utilization page and Health
Check. The data tools were spread over three tabs (Import, Find, Bulk Update), and their job
history over three components on two tabs (`importHistory`, `bulkUpdateHistory`,
`bulkDeleteHistory`), although every job is one `Import_Batch__c` with an `Operation__c`.

No package version has been released, so tab labels and app navigation can change freely; API
names should not, because links, permission sets and the console's workspace mappings name them.

## Decision

1. **Labels change, API names stay.** The `Data_Hygiene` tab and flexipage read **Org
   Optimizer**; `Import`, `Find`, `Bulk_Update`, `dataHygieneConsole` and the `DataHygiene*`
   classes keep their names. The `Import` tab keeps the label **Import**; the
   `Import_Batch__c` object reads **Data Job**.
2. **Org Optimizer is a shell of lazy sections.** One new component, `orgOptimizer`, on the
   `Data_Hygiene` flexipage, shows a vertical `lightning-tabset`: Overview, Data quality
   (`dataHygieneConsole`), Duplicates (`duplicateReview`), Field utilization
   (`fieldUtilization`) and Health Check (`healthCheckPanel`). A section's component is created
   only when its tab is first opened, and Health Check only on **Run Health Check**, so opening
   the page runs no check (the lesson of ADMIN-7). The embedded components are unchanged.
3. **Section visibility by custom permission, checked in the browser.** Data quality needs
   `Find_And_Export_Records`; Duplicates, Field utilization and Health Check need
   `Manage_BarnCRM_Settings`. Each embedded component keeps its own server-side check, so the
   browser check only hides what the server would refuse. Duplicate review keeps its own
   message for a person without the Duplicate Review permission set (which carries no custom
   permission to test).
4. **Duplicate review leaves the settings console.** The `Duplicate_Review` Setting Definition
   stays, with no component, so the console's existing "navigate away" row opens Org
   Optimizer (ADR-0020's path). `Field_Utilization` keeps its app page and tab for direct
   links, out of the navigation and out of every permission set's tab visibility.
5. **Data Manager is a new tab, not a relabel.** A new app page and tab `Data_Manager` hosts
   `dataManager`: tool cards gated by the same custom permissions as the tools, the import
   mappings, the merged job history and links to Salesforce's own tools. Relabelling
   `Bulk_Update` as Data Manager was rejected: an API name that says the opposite of the page
   invites wrong links. `Data_Manager` is visible in `BarnCRM_Admin`, `BarnCRM_Find_And_Export`,
   `BarnCRM_Bulk_Update` and `BarnCRM_Bulk_Delete`. No new custom permission.
6. **One job history.** `dataJobHistory` replaces the three history components. It reads the
   three existing endpoints (`ImportController.getRecentBatches`, `BulkUpdateController.getPage`,
   `BulkDeleteController.getPage`), each only when the person holds that tool's permission,
   merges them newest first and filters by kind. Undo calls each tool's existing undo, and every
   undo asks the person to type the number it will act on (the import undo now types the total
   its preview counted, as bulk update and bulk delete already did). No new object, field or
   selector.
7. **Navigation.** `Data_Manager` is added to the app's `<tabs>` and `workspaceConfig`;
   `Import` and `Bulk_Update` leave both (metadata and permission set visibility kept, reached
   from Data Manager and from existing links); `Find` and `Data_Hygiene` stay. A tab reached by
   `standard__navItemPage` that is not in the navigation still opens, as a workspace tab in the
   console.

## Alternatives considered

- **One Apex call for the whole history.** Rejected for now: the three endpoints already
  enforce their own permissions and shapes, and a merged server query would duplicate
  `toView` logic in a fourth place. Revisit with FINDB-12's shared job base.
- **Show duplicate review in both places.** Rejected by the owner.
- **Keep Field Utilization as its own tab.** Rejected by the owner.

## Consequences

- Admin guide pages that say "open the Data Hygiene tab", "BarnCRM Settings > Households >
  Duplicates", "the Bulk Update tab" or "Recent imports" change in the branch that changes the
  behavior.
- The Bulk Update flexipage keeps working for bookmarks and shows the merged history filtered
  to bulk jobs; the Import flexipage shows it filtered to imports.
- Further Org Optimizer sections (Errors, Storage and limits, Unused and stale setup, more data
  quality checks) are added as tabs of the same shell, each lazily loaded and gated the same way.
