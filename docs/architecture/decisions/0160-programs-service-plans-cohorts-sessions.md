# ADR-0160: Programs depth: goals on the enrollment, cohorts through the enrollment, sessions under a service with attendance on Service Delivery

**Status:** Proposed (built as recommended for release 0.15, P-10 and P-11; awaits owner confirmation)
**Date:** 2026-11-02
**Source:** plan Section 5.4, Section 6.0a release 0.15 (P-10, P-11, D-156), competitive research
items M-06 and M-07 (plan Section 6.1.5), Section 9.9 (portability); builds on ADR-0014,
ADR-0024, ADR-0151 and ADR-0154.

## Context

ADR-0151 set up Programs with three objects (Program, Service, Enrollment); batch A added Service
Delivery (attendance and service in one record), Case Note and the Participant Privacy preset.
Programs is still thinner than the Program Management Module (PMM) and Nonprofit Cloud Program
Management on two points the research named: per-participant service plans with goals (case
management lite, P-10) and cohorts with scheduled sessions, mass enrollment and attendance per
session (P-11). Both add objects, so the module's design changes and needs this record.

The settled rules that bound the design: participant records follow the Participant Privacy preset
(R-EN7); a case note is private to its author (R-CN2); Programs and Logic Models never reference
each other (plan Section 5.7, ADR-0154 decision 5); attendance has one model, Service Delivery
(29ZB), which maps onto PMM's Service Delivery.

## Decision

### Service plans and goals (P-10)

1. **A plan is the enrollment's goals; no plan object.** A goal (`Goal__c`) and its steps
   (`Goal_Step__c`) hang off the enrollment. Everything a plan record would hold (owner, dates,
   status, review) is per goal in practice, and the enrollment already says who and which
   program. A plan object would add a level, a record to create first and a sharing question,
   and nothing would break without it.
2. **Master-detail, so privacy follows the enrollment with no code.** Goal is a detail of
   Enrollment and Goal Step a detail of Goal (sharing Controlled by Parent): whoever sees the
   enrollment under the Participant Privacy preset sees its plan, and editing a goal needs edit
   access to the enrollment. No sharing reason, trigger share or batch is added. Deleting an
   enrollment (Programs Admin only) deletes its goals and steps.
3. **Goal fields.** The goal (name), Description, Status (Not Started, In Progress, Achieved, Not
   Achieved; Achieved and Not Achieved are closed), Target Date, Assigned To (a User), Last
   Reviewed and Next Review dates, Closed Date and Outcome Id. **Step fields:** the step (name),
   Status (Not Started, In Progress, Done), Assigned To, Target Date and Completed Date.
4. **Closed and Completed dates are stamped.** Closing a goal fills an empty Closed Date with
   today and reopening it empties it; the same for a step and Done. Switchable automations
   (registry rows `Goal_Dates` and `Goal_Step_Dates`), as R-EN3: they do work for the user, and an
   import of history turns them off.
5. **Reviews are dates on the goal.** The Service Plan panel's Mark Reviewed sets Last Reviewed to
   today and Next Review to a date the user confirms, offered three months on (a default in the
   panel's framework-free module, not a setting: the user sees and changes it every time). A goal
   whose Next Review has passed is flagged in the panel and listed by the Reviews Due list view.
6. **Linked to case notes by a lookup on the note.** Case Note gains an optional Goal lookup
   (SetNull), checked by a validation rule to be a goal on the note's own enrollment. The note
   stays private to its author (R-CN2); the panel lists, under each goal, the notes the user may
   see. New Note on a goal opens the standard new case note with the enrollment and goal filled
   in.
7. **Linked to a Logic Models outcome by record identifier, never a lookup.** `Outcome_Id__c`
   holds the Id of a Logic Model Element of type Outcome as text, the ADR-0014 pattern ADR-0154
   decision 5 uses for the reverse direction. The panel offers an outcome picker only where an
   object named `Logic_Model_Element__c` exists and the user can read it (describe, dynamic SOQL
   in user mode): the outcomes of the logic model for the enrollment's program, then those of the
   organization's model. Without Logic Models the field is hidden from the panel and nothing
   else changes; an outcome deleted later shows as missing. Neither package references the
   other's schema, so both still install alone.
8. **Who.** Programs Admin: everything, including delete. Programs Staff: create and edit goals
   and steps, never delete (close a goal as Not Achieved instead), as ADR-0151 decision 7.
   Programs Read Only: read.
9. **Erasure deletes goals.** A goal is typed text about the person, so erasing a person deletes
   the goals (and with them the steps) on their enrollments, as R-CN4 does for case notes; the
   enrollment is kept (R-EN5).

### Cohorts, sessions and mass enrollment (P-11)

10. **A cohort is a group within one program; membership is the enrollment.** Cohort
    (`Cohort__c`: program, status, start and end dates) and a Cohort lookup on Enrollment
    (SetNull), checked by a validation rule to be a cohort of the enrollment's program. No
    junction object: one open enrollment per person per program (R-EN2) already means one cohort
    per person per program at a time, and the enrollment carries privacy, stage and dates.
11. **A session is one scheduled occurrence of a service.** Session (`Session__c`: service,
    optional cohort of the same program, date, start time, status Scheduled, Held or
    Cancelled). A lookup to the service with delete Restrict, not a detail, so a service keeps
    its sessions' history; Cohort and Session hold no participant data and are shared like
    Program (Public Read/Write).
12. **Attendance per session is Service Delivery, not a parallel record.** Service Delivery gains
    an optional Session lookup (delete Restrict), checked to be a session of the delivery's
    service. Taking attendance on a session writes the same deliveries as the Service Delivery
    Log, so the dashboard, the person card, privacy (R-SD6), the absence rule (R-SD2) and the PMM
    mapping need no change. The log's one row per person per service per day (R-SD4) becomes one
    row per person per session when a session is named; a delivery for the same service and day
    with no session is adopted by the session rather than duplicated.
13. **One log, two places.** The Service Delivery Log panel also sits on the session page: the
    service and day come from the session, the roster is the cohort's open enrollments (the
    program's when the session has no cohort), and saving marks a Scheduled session Held. A
    Cancelled session takes no attendance.
14. **Recurring sessions are generated, not a rule.** The Schedule Sessions panel (on a cohort,
    and on a program for sessions with no cohort) creates one session per chosen weekday between
    two dates, at most 200 at a time; the dates are computed in a framework-free module (plan
    9.9) and the server re-checks the service, the cohort and the count. No recurrence record is
    kept: a session is edited or cancelled one by one, and scheduling again adds sessions.
15. **Mass enrollment on the cohort.** The Cohort Members panel adds many people in one action:
    people picked one by one into a list, and the program's open enrollments not yet in a
    cohort, ticked. A person with an open enrollment in the program is moved into the cohort; one
    without is enrolled (stage Enrolled) through the enrollment rules. Each person succeeds or
    fails alone, and the panel lists who failed and why.

## Alternatives considered

- **A Service Plan object above the goals.** Rejected (decision 1): nothing breaks without it.
- **Goals as lookups with Apex managed sharing, as Enrollment.** Rejected: master-detail gives the
  same visibility with no code and no batch.
- **A lookup from Goal to the Logic Model Element.** Rejected: it would make Logic Models a
  dependency of Programs (plan Section 5.7).
- **A Cohort Member junction object.** Rejected (decision 10): the enrollment already is the
  membership.
- **A Session Attendance object.** Rejected (decision 12): a second attendance model would split
  every count PMM, the dashboard and the person card rely on.
- **A stored recurrence (schedule) record.** Rejected for now (decision 14): nothing edits a
  series as a whole yet.

## Consequences

- Four more custom objects for a program user (Goal, Goal Step, Cohort, Session; the Lightning
  Platform Starter object count, ADR-0121) and four Module Manager uninstall counts.
- PMM mapping grows: Cohort maps to PMM's Program Cohort and Enrollment's Cohort to the Program
  Engagement's cohort; Session maps to PMM's Service Session; goals have no PMM equivalent.
- Two sessions of one service on one day are told apart only on the session page; the program's
  Service Delivery Log still keeps one row per person per service per day.
- An outcome's Id survives the outcome's deletion; the panel shows it as missing and it can be
  cleared or replaced.
