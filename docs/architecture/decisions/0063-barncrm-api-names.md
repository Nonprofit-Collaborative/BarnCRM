# ADR-0063: The `Nonprofit_*` API names become BarnCRM names before the first package version

**Status:** Accepted
**Date:** 2026-10-12
**Source:** product owner decision (Brandon, 2026-10-12); supersedes ADR-0059 decision 6; builds
on ADR-0046, ADR-0060 and ADR-0062

## Context

ADR-0059 decision 6 kept Core's `Nonprofit_*` API names through C-29 and left their rename to
the name pass, before the first package version. Core is the whole product for the Community
Suite (ADR-0046), and an API name shows wherever an administrator meets the metadata: Setup,
report builder, the custom settings page, the permission set list, URLs and stored values. No
package version exists yet (ADR-0046), so a rename costs only the references in the
repository and a reset of the test orgs. After the first version, API names are permanent.

## Decision

Rename these API names in one pass, on three stacked branches, before any package version:

| Old | New | What it is |
|---|---|---|
| `Nonprofit_Settings__c` | `BarnCRM_Settings__c` | Core's hierarchy custom setting, with every field reference, `Setting_Definition` `Settings_Object__c` value and the field's default |
| `Manage_Nonprofit_Settings` | `Manage_BarnCRM_Settings` | custom permission, with LWC `@salesforce/customPermission/` imports and `$Permission` references |
| `NonprofitSettings` | `BarnCRMSettings` | the optional Platform Cache partition an administrator creates |
| `Nonprofit_Admin`, `Nonprofit_Staff`, `Nonprofit_Read_Only`, `Nonprofit_Duplicate_Review` | `BarnCRM_Admin`, `BarnCRM_Staff`, `BarnCRM_Read_Only`, `BarnCRM_Duplicate_Review` | permission sets |
| `Nonprofit_Admin_Group` | `BarnCRM_Admin_Group` | permission set group (the BarnCRM Admin role) |
| `Nonprofit_Hub` | `BarnCRM` | Lightning app |
| `Nonprofit_Hub_Home` | `BarnCRM_Home` | tab and flexipage |
| `Nonprofit_Settings` | `BarnCRM_Settings` | tab and flexipage, and every `/lightning/n/` URL |
| `AgentforceNonprofit` | `NonprofitCloud` | stored value of `Coexistence_Mode__c` |
| `Core_CoexistenceMode_AgentforceNonprofit` | `Core_CoexistenceMode_NonprofitCloud` | custom label |
| `Core_SetupAssistant_ModeAgentforce` | `Core_SetupAssistant_ModeNonprofitCloud` | custom label of the same mode in the Setup Assistant |
| `generic_donor_list` (record `Generic_Donor_List`) | `generic_contact_list` (record `Generic_Contact_List`) | Import Template key and its `Import_Template_Default` record |
| `nonprofit_admin`, `no_nonprofit_admin` | `admin_role`, `no_admin` | Health Check check and finding keys |
| `Import_Template__c.Donation_Matching__c` | `Import_Template__c.Payment_Matching__c` | field |
| `Core_Import_DonationMatching{Heading,Help,Label}`, `Core_Import_Donation{MatchOrCreate,AlwaysCreate,MatchOnly,NeverMatch}`, `Core_Import_ErrorDonationMatching{Unknown,Range}` | `Core_Import_PaymentMatching{Heading,Help,Label}`, `Core_Import_PaymentMatching{MatchOrCreate,AlwaysCreate,MatchOnly,NeverMatch}`, `Core_Import_ErrorPaymentMatching{Unknown,Range}` | custom labels of the import wizard's payment matching |

`Import_Row__c.Gift_Id__c` and `Soft_Credit_Id__c` keep their API names: they are labelled
Resulting Record and Second Resulting Record (ADR-0059 decision 7), and a module loads them.

`NonprofitCloud` names a Salesforce product, which the neutral-Core rule allows only where that
product is detected; a stored value is never shown, and its label is shown only where the org
has the Nonprofit Cloud objects (ADR-0062).

Historical documents keep the names they were written with: the ADRs before this one, the
release notes, and history rows in the canonical model.

## Alternatives considered

- **Neutral names without the product, such as `Core_Settings__c`, `Manage_Settings` and
  `Core_Admin`.** Rejected by the owner: the BarnCRM names match the labels an administrator
  already reads, and a module's names (`Giving_Settings__c`) already carry their module.
- **Keep the API names and change only labels.** Rejected: the names surface in Setup, URLs
  and reports for every Standard Edition org, and this is the last cheap moment.
- **Rename after the first version.** Not possible for packaged components.

## Consequences

- The test orgs (`oi-test`, `oi-pa`) hold the old components and their settings data. They need
  a reset (recreation, or a destructive deploy of the old names) before the renamed packages
  deploy. The org default of the custom setting (setup progress, coexistence mode) is lost
  there, which is acceptable: no pilot data exists.
- `scripts/ci/check-permission-sets.py` and the other checks name the new API names.
- An administrator who created the optional cache partition under its old name creates it again
  as `BarnCRMSettings`; without it Core falls back to its per-transaction cache.
