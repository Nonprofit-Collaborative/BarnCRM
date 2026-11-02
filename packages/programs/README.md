# BarnCRM Programs

## Purpose

Programs, the services they offer, and the people enrolled in them (P-01), attendance and
service delivery (P-02), private case notes (P-04), intake and eligibility fields with the
Programs Settings page (P-07), the participant privacy preset (P-08), and the program dashboard
with a person's last service (P-05), the program roster import template (P-06), counts of people
served without names (P-12), referrals in and out (P-13) and eligibility screening rules (P-14).
with a person's last service (P-05), the program roster import template (P-06), and participant
service plans with goals and steps (P-10), and cohorts, scheduled sessions, mass enrollment
and attendance per session (P-11).

## Design

- ADR-0151 `docs/architecture/decisions/0151-programs-module.md`
- ADR-0160 `docs/architecture/decisions/0160-programs-service-plans-cohorts-sessions.md`
- Canonical model Sections 29Y (Program), 29Z (Service), 29ZA (Enrollment), 29ZA1 (Case Note),
  29ZA3 (Goal), 29ZA4 (Goal Step), 29ZA5 (Cohort), 29ZA6 (Session) and 29ZB (Service Delivery)
- Admin guide `docs/admin-guide/programs.md`

## First ships in

Release **0.12**.

## Depends on

- BarnCRM Core

Nonprofit Edition only (ADR-0124).
