# ADR-0002: Second-generation managed packages with one shared namespace

**Status:** Accepted
**Date:** 2026-09-06
**Amended by:** ADR-0046, under which packages are built and piloted as unlocked packages
  under the same namespace, following managed-package rules, and become the 2GP managed packages
  below for the AppExchange listing. Read the Decision below with ADR-0046 beside it.
**Source:** plan Section 12, decision D-02

## Context

BarnCRM ships as several packages (Core plus optional modules, ADR-0003) and must be
listed on the AppExchange, must be upgradable in installed orgs without an administrator
doing anything, and must let its packages call each other's Apex and reference each
other's objects.

NPSP's history is the cautionary case (plan Section 3.1 and 3.3): it grew as five
first-generation packages with five separate namespaces, later unified under a sixth.
The result was overlapping settings, legacy objects nobody could remove, and an install
flow that needed a special installer. The namespace count, not the package count, caused
most of that pain.

Salesforce packaging offers three shapes: first-generation managed packages (1GP),
second-generation managed packages (2GP), and unlocked packages.

## Decision

All BarnCRM packages are **second-generation managed packages sharing a single
namespace**. Package versions are created from the Dev Hub that will own the AppExchange
listing (plan Section 8.1), and promoted versions are the only ones installed anywhere
other than test orgs.

## Alternatives considered

- **Unlocked packages**: no push upgrades and no managed AppExchange listing, and
  subscriber orgs can modify packaged metadata, which breaks the upgrade-safety promise
  in Principle 6. Rejected.
- **First-generation managed packages**: legacy tooling, packaging org rather than source
  of truth in the repository, and no shared namespace across packages. Rejected.
- **A single package containing everything**: rejected separately in ADR-0003 on
  Principle 3 grounds.
- **Multiple namespaces, one per package** (the NPSP shape): rejected outright, because
  it is the specific mistake plan Section 3.3 item 1 names.

## Consequences

- Cross-package Apex calls and object references work as though everything were one
  package, so the module boundary is a packaging boundary and not a coding tax.
- Push upgrades become available, which the release process depends on from v0.6 (plan
  Section 7.5).
- Package IDs are tied to the Dev Hub, so the Dev Hub decision must be made before the
  first package version that will ever be promoted. Creating early versions from a
  throwaway Dev Hub means re-creating the packages with new IDs later.
- Managed packaging means packaged metadata cannot be edited by subscribers, which is
  what makes "nothing an admin configures is overwritten by an upgrade" achievable, and
  which is why shipped defaults are materialized into admin-owned records rather than
  edited in place (ADR-0006).
- Subscribers install several packages rather than one; that friction is paid by the
  Module Manager (plan Section 4.8), not by the administrator.
