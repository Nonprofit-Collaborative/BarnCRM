# ADR-0123: Core roles have neutral names that fit any organization

**Status:** Accepted (owner decision, Brandon, 2026-10-14)
**Date:** 2026-10-14
**Source:** Owner decision 2026-10-14 reversing plan decision D-92 for the Core roles; plan
D-96 (edition names: the Standard Edition and the Nonprofit Edition share Core); D-54 (the two
groups get their module permission sets when those modules ship)

## Context

Core ships four permission set groups, shown to admins as roles on the Access page, in the
Setup Assistant and in Setup. Two carried nonprofit job titles: **Program Staff**
(`Program_Staff`) and **Volunteer Coordinator** (`Volunteer_Coordinator`). D-92 kept the
existing names.

D-96 makes Core the whole of the Standard Edition, for any Salesforce org: clubs,
associations and businesses as well as nonprofits. In those orgs "Program Staff" describes no
one, and "Volunteer Coordinator" only fits where the people being scheduled are volunteers.
Both groups hold only `BarnCRM_Staff` today: day to day work with people, households and
organizations. D-54 adds the Programs module's sets to the first and the Volunteers module's
sets (shifts and hours) to the second when those modules ship.

## Decision

1. The two labels become **Team Member** (was Program Staff) and **Coordinator** (was
   Volunteer Coordinator). Descriptions are reworded to match: Team Member is for anyone on
   the team who does the day to day work; Coordinator is for whoever schedules people and
   tracks their time.
2. **API names do not change.** `Program_Staff` and `Volunteer_Coordinator` stay as the
   DeveloperName, so upgrades, Apex references (`AccessService`, `HealthCheckService`),
   existing assignments and admins' user access policies keep working. The admin guide names
   the API names wherever an admin needs them.
3. **BarnCRM Admin** and **Read Only** keep their names (already neutral). **Fundraising
   Staff** keeps its name: it ships only in Giving, so only in the Nonprofit Edition.
4. This reverses D-92 for the Core roles. D-92's other names (BarnCRM Admin, Read Only,
   Duplicate Review, BarnCRM Settings) are unaffected.

## Alternatives considered

- **Keep the nonprofit names (D-92).** Rejected: Core is the whole Standard Edition, and a role
  name that describes no one in the org makes the Access page harder to use.
- **"Staff" for Program Staff.** Rejected: it reads as paid employees only (a club's work is
  often done by members or volunteers) and is easily confused with the `BarnCRM_Staff`
  permission set inside every role.
- **"Volunteer Lead" for Volunteer Coordinator.** Rejected: still assumes volunteers. The
  role's distinct grant, once the module ships, is shifts and hours, which any organization
  that schedules people uses.
- **Rename the API names too.** Rejected: a packaged permission set group cannot be renamed
  across an upgrade; it would mean a new group, a migration of every assignment and policy,
  and a deprecated group left in every org.

## Consequences

- Admins see Team Member and Coordinator on the Access page, in the Setup Assistant and in
  Setup; Setup and user access policies still show the API names `Program_Staff` and
  `Volunteer_Coordinator`. The admin guide's Access and Automatic access pages say so.
- An org upgrading from a version with the old labels sees the new labels after the upgrade;
  assignments are untouched.
- When the Programs and Volunteers modules ship (D-54), their sets attach to these groups
  under the new labels; their descriptions already name what each module adds.
- Release notes and ADRs written before this decision keep the old names as history.
