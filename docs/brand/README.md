# BarnCRM Brand

Patch, the highland cow, is BarnCRM's mascot and logo (ADR-NEXT, Patch brand).

## Palette

| Name | Hex | Use |
|---|---|---|
| Barn Navy | `#1E2A3A` | App headers, text, buttons. White on it: 14.5:1. |
| Patch Rust | `#D35400` | Large or decorative accents only. White on it is 4.17:1, so never small text on rust or rust text on white. |
| Sage Green | `#8EB397` | The circle behind Patch in the logos. |
| Cream | `#F5F4EE` | Light backgrounds. Navy on it: 13.17:1. |
| Charcoal | `#2B2B2B` | Body text on cream: 12.85:1. |

BarnCRM screens use SLDS 2 styling hooks, not these colors (UX kit); status colors are SLDS's.

## Rules

- Never redraw, recolor, stretch or crop into Patch. Scale only, keeping the aspect ratio.
- A changed image needs a new ContentAsset name: an org keeps the old image under an old name.
- Alternative text names Patch, for example "Patch, the BarnCRM highland cow, waving hello".

## Masters

The cut-out masters live outside the repository, in the brand folder's `patch-assets/`:
`marks/`, `modules/`, `hires/` (1024 px), `poses/`, `contact-sheet.png` and `manifest.md`
(source and processing of each file). `scripts/brand/make-logos.py --source <patch-assets>`
rebuilds every packaged asset and the copies here from `hires/`.

## Assets

| File here | Asset | Package | App |
|---|---|---|---|
| `barncrm-logo.png` | `BarnCRM_Patch_Logo` | core | BarnCRM, BarnCRM Standard |
| `barncrm-admin-logo.png` | `BarnCRM_Patch_Admin_Logo` | core | BarnCRM Admin, BarnCRM Admin Console |
| `barncrm-giving-logo.png` | `BarnCRM_Patch_Fundraising_Logo` | giving | BarnCRM Fundraising |
| `barncrm-volunteers-logo.png` | `BarnCRM_Patch_Volunteers_Logo` | volunteers | BarnCRM Volunteers |
| `barncrm-programs-logo.png` | `BarnCRM_Patch_Programs_Logo` | programs | BarnCRM Programs |
| `barncrm-funders-logo.png` | `BarnCRM_Patch_Funders_Logo` | funders | BarnCRM Grants |
| `barncrm-logic-models-logo.png` | `BarnCRM_Patch_Logic_Models_Logo` | logicmodels | Module Manager tile |
| `barncrm-forms-logo.png` | `BarnCRM_Patch_Forms_Logo` | forms | BarnCRM Forms |
| `barncrm-events-logo.png` | `BarnCRM_Patch_Events_Logo` | events | BarnCRM Events |
| `barncrm-projects-logo.png` | `BarnCRM_Patch_Projects_Logo` | projects | BarnCRM Projects |
| `barncrm-corporate-hub-logo.png` | `BarnCRM_Patch_Corporate_Hub_Logo` | corporatehub | BarnCRM Corporate Hub (face mark until its master is cut again) |
| `barncrm-portal-logo.png` | `BarnCRM_Patch_Portal_Logo` | portal | BarnCRM Portal Builder |
| (none) | Static resource `BarnPatchWelcome` | core | BarnCRM Home welcome |
