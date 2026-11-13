# ADR-0222: Packaged dashboards run as a specified user, not the logged-in user

**Status:** Accepted (owner decision)
**Date:** 2026-11-13
**Source:** D-202 (Brandon, 2026-11-13): "The logged-in-user dashboards need to be converted to
non-logged-in-user Salesforce dashboards but they can be reproduced in the Advanced Reporting
module's dashboards." Amends ADR-0018 `0018-module-tabs-and-apps.md` (its `LoggedInUser`
dashboard decision). Advanced Reporting is plan Section 6.1 item 22, planned and not built.

## Context

ADR-0018 shipped `Giving_Overview` with `dashboardType` set to `LoggedInUser` so it read as
whoever opened it. Salesforce caps these dynamic dashboards per edition: 3 in Developer Edition
and 5 in Enterprise Edition. A full install ships four (Giving, Volunteers, Scholarships and
Grants, Board Governance) and failed on a Developer Edition org.

## Decision

All four packaged dashboards ship with `dashboardType` set to `SpecifiedUser` and no
`runningUser` element. A deploy with no `runningUser` succeeds; the running user becomes the
admin who installs or deploys the package. The admin can change it in the dashboard's properties
(**Edit**, then **View dashboard as**). Viewer-aware dashboards are reproduced in the Advanced
Reporting module (plan Section 6.1 item 22, D-202), not here.

## Consequences

- Every viewer sees what the running user can see, whatever their own record access. Access is
  therefore controlled by the dashboard folder's sharing. The four shipped folders are public
  and read only (`accessType` Public, `publicFolderAccess` ReadOnly), so every internal user
  can open the dashboards. The admin guides tell admins to share the folders only with people
  allowed to see that data and to change the running user if needed.
- If the running user is deactivated or loses report or object access, the dashboards show a
  running user error until an admin chooses another user.
- The four dashboards no longer count against the dynamic dashboard allowance, so a full
  install works in Developer Edition.
- Docs that said the dashboards read as the viewer are corrected: the Giving, Volunteers,
  Scholarships and Corporate Hub admin guides, the user guide, the testing guide (T-GRD-06),
  the feature catalog and the G-03 to G-06 permissions note.
