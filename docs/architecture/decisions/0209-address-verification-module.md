# ADR-0209: BarnCRM Address Verification: the org's own Smarty or Google key, verified on save and nightly, writing only the two R-AD6 fields unless corrections are switched on

**Status:** Accepted (builder decision)
**Date:** 2026-11-11
**Source:** plan Section 6.0a release 1.15 (C-46, "ADR first"), D-112 (verification is an optional
module, the admin brings their own provider key set in the BarnCRM Settings console, no provider
bundled, no paid service), D-177, D-178, Section 4.7 (addresses), Section 4.13 (security), Section
9.9 (portability). Builds on ADR-0013 (Core runs alone), ADR-0017 (cross-package mechanisms by
name), ADR-0057 (Health Check extensions), ADR-0131 (module access by role), ADR-0166 (the nightly
run) and the Payments ADR-0201 `0201-payments-module.md` (write-only keys entered in the app).

## Context

Core's `Address__c` carries `Verification_Status__c` (Unverified, Verified, Failed; default
Unverified) and `Latest_Verified_Date__c`, which Core's code never writes (canonical model R-AD6)
so that a verification app can. D-112 makes BarnCRM's own verification an optional module: the
organization brings an account with an address service and enters its key in the app. Address
services charge per lookup beyond a free allowance, so the module must never make lookups the
admin did not expect.

## Decision

1. **A new optional module, BarnCRM Address Verification** (`packages/addressverification`,
   module key `AddressVerification`), depending on Core only, both editions, not installed by
   default. It ships its catalog row with no probe object and Setting Definition rows naming it
   (#1053). It has no object of its own and no app; its one page is an admin tab.
2. **Two providers, the org's own account.** The admin chooses one in BarnCRM Settings,
   Addresses (`Address_Verification_Settings__c.Provider__c`, default Smarty):
   - **Smarty US Street Address API** (`GET https://us-street.api.smarty.com/street-address`,
     `auth-id` and `auth-token`, one candidate). United States addresses only: an address whose
     country is not blank, US, USA or United States is left Unverified. Verified when the
     candidate's DPV match code is `Y` (or `S` or `D`: confirmed with a missing or extra
     secondary number, still deliverable); Failed when there is no candidate or the code is `N`.
   - **Google Address Validation API** (`POST https://addressvalidation.googleapis.com/v1:validateAddress`,
     an API key), any country Google covers. Verified when the verdict's
     `validationGranularity` is `PREMISE` or `SUB_PREMISE` and `hasUnconfirmedComponents` is not
     true; otherwise Failed.
   Both endpoints ship as Remote Site Settings. A provider error (an HTTP status other than 200,
   or no answer) changes nothing: the address stays Unverified and the error is logged once per
   run. No provider is bundled: without a key the module looks nothing up.
3. **Keys are the org's own, entered in the app, never shown again** (the Payments decision 7
   pattern): `Address_Verification_Keys__c`, a protected hierarchy custom setting granted to no
   permission set, holding the Smarty Auth ID and Auth Token and the Google API key. The Address
   Verification Setup page writes them and shows only whether each is set and its last four
   characters; it needs Manage BarnCRM Settings to save.
4. **What is written.** Only the two R-AD6 fields: Verified sets Verification Status and Latest
   Verified Date (today); Failed sets the status and leaves the date (the last success). With
   **Apply Corrections** on (default off), a Verified address also takes the provider's
   standardized street, city, state and postal code; the country is never changed. Every write
   is in user mode as the person whose save or job it is; a refused write is logged, never
   raised. Former addresses are never looked up.
5. **When it looks up, bounded by the admin.**
   - **On save** (`Verify_On_Save__c`, default on): a registry handler on `Address__c`
     (`Address_Verification`, a switch on the Automation page that Pause All covers) sets
     Verification Status back to Unverified before a change to the street, city, state, postal
     code or country is saved, and after the save queues one job for the changed Current
     addresses (up to 50 per job, the rest left for the nightly step). A save inside a batch or a
     queued job, or with no queueable left, is left for the nightly step. Saves the module itself
     makes are skipped, so a correction never verifies twice.
   - **Nightly** (`AddressVerification`, a step of the one nightly run, switch shipped on, active
     only while the module is on and the chosen provider's keys are set): Current addresses that
     are Unverified, or Verified longer ago than **Re-Check After (Months)** (default 12; 0 never
     re-checks), oldest first, at most **Nightly Limit** a night (default 200), 50 per batch
     transaction, so a free allowance is not spent by surprise.
   - **Now**: the setup page's Verify Waiting Addresses starts the same batch at once.
6. **Core stays unchanged in behavior.** Core's code still never writes the two fields (R-AD6
   now reads "never written by Core's code; the Address Verification module writes them"), so
   another verification app can keep using them while the module is not installed or its
   handler is switched off. Core only lists the module's class names where it lists every
   module's (Health Check extensions, nightly step providers, the help catalog, Module Manager).
7. **Health Check** reports, while the module is on: the chosen provider's keys not set
   (warning), and addresses Unverified for over 30 days while the nightly step is on (info, with
   their count), which a too-low Nightly Limit or a non-US address on Smarty explains.
8. **Access.** `Address_Verification_Admin` (BarnCRM Admin holders): the setup page and its
   controller. `Address_Verification_Staff` (Team Member): nothing beyond Core's own Address
   access, so the on-save job runs for staff who can edit addresses; it exists so the role sync
   and the Module Manager treat the module like every other. There is no Read Only set: the
   module has no record of its own to read, and a Read Only user cannot save an address.

## Alternatives considered

- **A bundled or BarnCRM-held provider account.** Rejected by D-112: BarnCRM sells no service and
  holds no key.
- **Keys in Named Credentials.** Rejected for the Payments reason: edited in Setup, not in the
  app; moving the keys to an External Credential later changes one class.
- **Verifying in the trigger.** Impossible: no callout during a save.
- **Verifying every address at install or every night.** Rejected: an org with 50,000 addresses
  would spend a paid allowance overnight; the nightly limit makes the cost the admin's choice.
- **One provider only.** Smarty covers only the United States and Google costs more per lookup;
  two cover the common cases with one adapter each.

## Consequences

- Addresses saved during an import are verified by the nightly step over several nights at the
  default limit; an admin raises the limit or uses Verify Waiting Addresses.
- With Smarty, non-US addresses stay Unverified; Health Check's count makes that visible.
- Until the packages have a namespace, an administrator with View All Custom Settings can read
  the keys in Setup; with the namespace the setting is protected.
