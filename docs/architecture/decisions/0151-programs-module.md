# ADR-0151: The BarnCRM Programs module: Core only, three objects, enrollment kept apart from its program for privacy

**Status:** Proposed (built as recommended for release 0.12, P-01; awaits owner confirmation)
**Date:** 2026-10-31
**Source:** plan Section 5.4 (P-01), Section 6.0a release 0.12 (D-155), Section 6.1.4 item 9
(PMM-mappable now); builds on ADR-0003, ADR-0005, ADR-0013, ADR-0017, ADR-0018, ADR-0024,
ADR-0059, ADR-0124, ADR-0127 and ADR-0131.

## Context

Programs (P-01 to P-09, plan Section 5.4) is the second nonprofit module after Volunteers. On
main `packages/programs` holds a README, `sfdx-project.json` lists Core as its only dependency,
and Core ships the catalog row `BarnCRM_Module.Programs` (`Editions__c` `Nonprofit`, Sort Order
30) and the Integrations row for the Program Management Module (PMM), shown only where PMM is
installed. Release 0.12 builds P-01 (Program, Service, Enrollment); attendance and service
delivery (P-02), case notes (P-04), the dashboard (P-05), the roster import (P-06), intake fields
(P-07) and the privacy preset (P-08) follow in 0.13 and 0.14. Plan Section 6.0a asks for an ADR
before each new module.

## Decision

1. **Core only.** Programs depends on Core alone (install order Core, Programs) and ships no
   totals: the roster panel counts a program's enrollments when it opens, and P-05's reports
   count the rest. Rollup Builder stays optional for an org that wants stored counts.
2. **Three objects, PMM-mappable.** Program (`Program__c`; Status Planned, Active, Completed),
   Service (`Service__c`, a detail of its program; unit of measure, Active) and Enrollment
   (`Enrollment__c`; a person, a program, Stage Applied, Enrolled, Completed or Withdrawn, start
   and end dates). Each maps onto PMM's Program, Service and Program Engagement field by field
   (canonical model Section 29Y), so the PMM migration (MIG-09) needs no new field. The PMM
   field names are taken from its public repository; they are checked against an org with PMM
   installed when MIG-09 is built, not before.
3. **Enrollment is a lookup to its program, not a detail.** Its sharing is its own, so P-08 can
   make participants private without hiding programs. The lookup is required with delete
   Restrict: a program with enrollments cannot be deleted, enforced by the platform with no code.
   Enrollment ships Public Read/Write until P-08, which lands in the same batch (A) before any
   client deploy.
4. **The person is the Contact and Account pair** (Section 4), exactly one set, as Volunteers.
5. **One open enrollment per person per program.** Applied or Enrolled is open; a second open one
   is refused, in Apex, by an automation that always runs (ADR-0024). A person may enroll again
   once the first has ended (Completed or Withdrawn).
6. **Stage dates are stamped.** Moving to Enrolled fills an empty Start Date with today; moving
   to Completed or Withdrawn fills an empty End Date. A switchable automation, since it does work
   for the user rather than enforcing a rule.
7. **Three permission sets.** `Programs_Admin` (everything, including delete) to holders of
   `BarnCRM_Admin`; `Programs_Staff` (create and edit programs, services and enrollments, never
   delete) to the Team Member (`Program_Staff`) and Coordinator (`Volunteer_Coordinator`) roles;
   `Programs_Read_Only` to the Read Only role. Given by `ProgramsAccessSync` on the Volunteers
   pattern (ADR-0127 decision 3, ADR-0131), never taken away. No custom permission yet:
   `Manage_Programs` (plan Section 7) is reserved for the first rule that needs one (P-04, P-08).
8. **No settings yet.** P-01 has no choice an organization needs to make, so it ships no
   settings object and no Programs section in BarnCRM Settings; the first setting (P-07 or P-08)
   adds both.
9. **Erasure and merge need no module code.** Enrollments carry no typed text, so erasing a
   person keeps them, credited to the anonymous record; deleting a person empties the person on
   them (SetNull) and keeps the counts; a merge moves them to the record kept.

## Alternatives considered

- **Totals through Rollup Builder, as Volunteers.** Rejected for P-01: nothing in P-01 needs a
  stored count, and the dependency would make every Programs org install a second module.
- **Enrollment as a detail of Program.** Rejected: participant privacy (P-08) would then follow
  the program's sharing.
- **Refusing new enrollments into a Completed program.** Rejected: migrating history (PMM, a
  spreadsheet) enrolls people into programs that have ended.
- **A fourth, Coordinator, permission set.** Rejected until a rule tells the two roles apart.

## Consequences

- The Lightning Platform Starter object count (ADR-0121) grows by three for a program user.
- A merge, or an enrollment undeleted from the Recycle Bin, can leave two open enrollments for
  one person in one program; the next edit of either is refused until one is ended.
- Programs can never be offered in the Standard Edition (ADR-0124).
- No Opportunity, Campaign or Case is used (ADR-0013); PMM's own objects are never referenced.
