# ADR-0226: Memberships and Scholarships Ship Their Own Apps

**Status:** Accepted (owner decision, 2026-11-14)
**Date:** 2026-11-14
**Source:** Brandon, 2026-11-14 (plan D-208, release 1.27, N-02): Memberships and Scholarships and
Outbound Grants get their own Lightning console app, as Events, Forms, Portal Builder, Corporate
Hub and Projects did. Amends ADR-0223 (module apps), decisions 1 and 4, which name those five
apps as a closed list.

## Context

ADR-0223 gave five big modules a console app of their own and kept their tabs in the BarnCRM
apps. Memberships and Scholarships and Outbound Grants reach staff only through the BarnCRM apps.
Both have enough pages to work in on their own, and Patch logos for both already exist among the
brand masters (ADR-0224). A capped org (scratch or Developer Edition) receives at most
`CAPPED_ORG_APP_BUDGET` (9) suite apps and already receives 8, so two more cannot both fit.

## Decision

1. **Two more module apps**, each a console app in its own package with the Barn Navy header, its
   Patch logo (`scripts/brand/make-logos.py`), its tabs, standard Reports and Error Log last
   (D-135), exactly as ADR-0223 decision 1:
   - BarnCRM Memberships (`BarnCRM_Memberships`, logo `BarnCRM_Patch_Memberships_Logo`):
     Memberships, Member Certifications, Membership Levels, Certifications, Reports, Error Log.
   - BarnCRM Scholarships (`BarnCRM_Scholarships`, logo `BarnCRM_Patch_Scholarships_Logo`):
     Scholarships and Grants, Award Programs, Award Applications, Awards, Reports, Dashboards
     (the module ships a dashboard), Error Log. The label is the short form of the module name,
     as BarnCRM Events and BarnCRM Projects are.
   Each catalog row's `App_Name__c` names the app, so the Home hub offers Open the App. App
   visibility is in the module's Staff set, so the generated Admin and Read Only sets carry it.
2. **Tabs stay in the BarnCRM apps** (ADR-0223 decision 2, unchanged).
3. **Capped orgs leave both apps out.** `memberships` and `scholarships` join `LEFT_OUT` in
   `scripts/org/capped-org-apps.py`, so a capped org still receives 8 apps and the budget stays 9.
   The suite now ships 15 apps.

## Alternatives Considered

- **Raise the budget to 10 and leave one app in.** A scratch org refuses a custom app past about
  10, so the budget would sit at the limit with no room, and the two modules would behave
  differently on test orgs for no reason.
- **No app (today).** The owner asked for the apps.

## Consequences

- Real orgs and the packages get 15 apps; scratch and Developer Edition orgs keep 8.
- On a capped org the Home hub's Open the App link for Memberships and Scholarships points at an
  app the org does not have, as for the other five; test both apps on a real org (`mwdbdevsb`).
