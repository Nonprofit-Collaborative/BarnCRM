# ADR-0224: Patch the Highland Cow Is the BarnCRM Brand

**Status:** Accepted (owner decision, 2026-11-14)
**Date:** 2026-11-14
**Source:** Brandon, 2026-11-14 (W5 product branding rollout): replace the barn logo with the
highland cow mascot "Patch" across the Salesforce product. Supersedes ADR-0102 decision 4 (the
drawn blue barn and the `#007A9E` header) and the barn images and header colors of ADR-0137
decision 5. ADR-0137's rule that each package ships its own logo asset stands.

## Context

ADR-0102 drew a blue barn in code (`scripts/brand/make-logos.py`, standard library only) and
ADR-0137 added a colored badge per app. The brand now has a mascot, Patch, drawn by hand and
cut out as transparent PNGs, with a fixed palette: Barn Navy `#1E2A3A`, Patch Rust `#D35400`,
Sage Green `#8EB397`, Cream `#F5F4EE`, Charcoal `#2B2B2B`. Patch is never redrawn, recolored
or stretched. The masters live outside the repository, in the brand folder's `patch-assets/`
(`marks/`, `modules/`, `hires/` 1024 px versions, `poses/`, and a `manifest.md` recording each
file's source and processing).

## Decision

1. **Logos.** Every app's `<brand><logo>` is a Patch ContentAsset, 256 x 256 RGBA PNG, scaled
   from the 1024 px master: `BarnCRM_Patch_Logo` (Patch's face on a sage circle) for BarnCRM and
   BarnCRM Standard, `BarnCRM_Patch_Admin_Logo` (the circular badge) for the two admin apps, and
   a module badge in each module's own package (`BarnCRM_Patch_Fundraising_Logo`, `_Volunteers_`,
   `_Programs_`, `_Funders_` for BarnCRM Grants, `_Logic_Models_` for its Module Manager tile,
   `_Forms_`, `_Events_`, `_Projects_`, `_Portal_`, `_Corporate_Hub_`). The Corporate Hub master
   was repaired before first release: the source caption overlapped its tie tip, so the tip was
   redrawn in the art's own colors (recorded in the masters' manifest).
2. **New names, old ones removed.** Redeploying a ContentAsset under its old name keeps the
   org's existing image, so the Patch logos have new API names. The barn assets
   (`BarnCRM_Logo`, `BarnCRM_Admin_Logo`, `BarnCRM_Fundraising_Logo`, `BarnCRM_Volunteers_Logo`,
   `BarnCRM_Programs_Logo`, `BarnCRM_Funders_Logo`, `BarnCRM_Logic_Models_Logo`,
   `BarnCRM_Forms_Logo`, `BarnCRM_Events_Logo`, `BarnCRM_Projects_Logo`,
   `BarnCRM_Corporate_Hub_Logo`, `BarnCRM_Portal_Logo`) are removed from the repository, so
   `scripts/org/build-destructive-manifest.py` lists them as `ContentAsset` members in the next
   release's destructive manifest and orgs lose the old images. A later change to a Patch image
   again needs a new name.
3. **One header color.** Every app, everyday, admin and module, has the Barn Navy header
   `#1E2A3A`. Lightning puts white text on it: 14.5:1 (the old `#007A9E` gave 4.91:1, `#032D60`
   13.56:1). The logo, not the header, tells the admin apps apart. A static test
   (`scripts/ci/tests/test_core_navigation.py`) holds every app to this color and to a shipped
   `BarnCRM_Patch_` asset in its own package.
4. **Colors in the UI stay on SLDS.** BarnCRM screens use SLDS 2 styling hooks, never hard-coded
   colors (UX kit), and no screen used `#007A9E`, so no screen color changes. Where a brand
   color is ever needed: Barn Navy for text, buttons and headers; Patch Rust only for large or
   decorative accents (white on it is 4.17:1 and navy on it 3.48:1, both under 4.5:1, so never
   small text on rust or rust text). Status colors are unchanged.
5. **Patch on Home.** `c/hubWelcome` shows Core's static resource `BarnPatchWelcome` (the "Hi!
   I'm Patch!" pose, 400 px wide, about 156 KB, lossless) at 96 px beside the welcome, on wide
   screens only, with the alternative text "Patch, the BarnCRM highland cow, waving hello" in
   the Core help catalog (`Core_HubHome_PatchAlt`), not a custom label.
6. **The script scales, it does not draw.** `scripts/brand/make-logos.py --source
   <patch-assets>` writes every asset, the welcome image and the `docs/brand/` copies with
   Pillow (Lanczos on premultiplied alpha, deterministic). `docs/brand/README.md` lists the
   palette, the rules and the asset names.

## Consequences

- Orgs that have the barn assets keep them until a release deploy carries the destructive
  manifest; the apps point at the new assets from the first deploy, so the barn stops showing
  at once.
- The script needs Pillow and the masters folder, neither of which CI has; it runs by hand when
  the masters change. The generated files are committed.
- The capped-org app logic (ADR-0223) is unchanged: it decides which apps deploy, not their
  logos.
- Not decided here: a Patch favicon or images for Portal Builder portals, and more poses in
  the product (empty states, the Setup Assistant). Each would be its own change.
