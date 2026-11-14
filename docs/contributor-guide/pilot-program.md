# Pilot program notes

How the BarnCRM pilot is run (QA review Q10). Pilot organizations follow the
[Pilot Checklist](../admin-guide/pilot-checklist.md); this page is the project's side.

## Shape

- 3 to 5 pilot orgs, one per org shape, so every supported shape has a real user:
  - Platform only (ADR-0013: Core must run without standard objects);
  - Sales or Service Cloud;
  - NPSP installed (coexistence and household adoption);
  - Nonprofit Cloud with Person Accounts;
  - a Standard Edition org, if one volunteers (the edition's limits differ).
- Sandboxes, Developer Edition or scratch orgs only. Never a production org while BarnCRM is in
  pilot.
- Self-service only. The project offers no install help, support, services or response time;
  the checklist, the guides and GitHub issues are the whole program. Do not promise more in
  any message to a pilot org.

## What a pilot org gives back

- Bug reports through **Copy for Bug Report** (redacted: codes, exception names and stack
  lines, never the message or record data), plus steps, expected and actual.
- One end-of-trial **Feedback or question** issue: org shape, modules tried, what worked, what
  stopped them.
- Anything that needed Salesforce Setup during normal use (a definition-of-done gap, plan
  Section 7.4).

## Triage

- Each issue is reviewed and recommended to Brandon as a decision; nothing is built without his
  approval.
- A bug from a pilot org gets a Jest or Apex test that reproduces it before the fix lands.
- An issue that shows record data is edited to remove it and the reporter is asked to use
  **Copy for Bug Report**.

## When a version goes to the pilot

- Only after its release gate has passed on every org in `RELEASE_ORGS`
  (`scripts/org/release-gate.sh`), and the namespace decision is made before the first
  production pilot (architect review, 2026-11-04).
- The release notes in `docs/release-notes/` say what changed for pilot orgs.
