# ADR-0096: First-visit tips are packaged In-App Guidance prompts, single step, managed in Setup

**Status:** Proposed (builder decision)
**Date:** 2026-10-13
**Source:** Core quality pass Q-10 (owner decision 2026-10-13: adopt the recommended platform
features). Admin guide `in-app-guidance.md`. Builds on ADR-0087 (What's new) and C-12 (Setup
Assistant).

## Context

People opening Settings, Import, Find, Bulk Update or Field Utilization for the first time get
no pointer to how the page works except the admin guide. Salesforce In-App Guidance (the
`Prompt` metadata type, API 46.0 and later) shows a short tip on a page without any code.

What the platform allows, from the Metadata API Developer Guide (Prompt), the Second-Generation
Managed Packaging Developer Guide (Prompts (In-App Guidance)) and Salesforce Help (Limits for
In-App Guidance, Considerations for Creating In-App Guidance), all Summer '26:

- **Packaging.** `Prompt` is packageable in 2GP and 1GP. It is updated on upgrade; a subscriber
  cannot delete it; **the package developer cannot remove it from the package once released**.
  Building a package version needs the `GuidanceHubAllowed` and `Enablement` features in the
  build org's scratch definition.
- **Limits.** Without the Enablement add-on an org may have three active walkthroughs. Prompts
  and walkthroughs installed from a package have no enforced limit today (500 recommended).
  Walkthroughs from a package other than a security-reviewed 1GP need a licence to be seen.
- **Targeting.** Since API 51.0 a prompt targets a page by `targetPageType` and
  `targetPageKey1..4`, plus the app in `customApplication`. A Lightning app page tab is
  `standard__navItemPage` with the tab's API name as key 1. Navigation style does not change the
  page reference, so a console app is targeted the same way as a standard one.
- **Coexistence with the org's own prompts.** Salesforce waits 24 hours, per app, between any
  two prompts, counting Salesforce's, the org's and installed ones. Admins can deactivate one
  prompt, change the delay, or turn off all custom and installed prompts on the In-App Guidance
  Setup page. Seeing a prompt needs no permission.

## Decision

1. **Single-step prompts only, no walkthroughs.** Four in Core: a docked prompt on BarnCRM
   Settings and floating prompts on Import, Find and Bulk Update; a fifth, floating, on Field
   Utilization once that tab is on main. No licence, and far inside the limits.
2. **They point to What's new and the Setup Assistant, never repeat them.** Both already show
   themselves on the Home tab, so Home gets no prompt; the Settings prompt says where they are.
3. **Shown once per person** (`timesToDisplay` 1), in the BarnCRM app only, to everyone who can
   open the tab (tab visibility already limits the audience, so no permission filter that would
   need a namespaced custom permission name). They respect the 24-hour delay
   (`shouldIgnoreGlobalDelay` false), so an org with its own prompts keeps control of how often
   its people are interrupted.
4. **No action buttons.** A button needs a URL, and a URL to a BarnCRM tab would carry the tab
   name without the future namespace. The text names the tab instead.
5. **Turned off in Setup, not in BarnCRM Settings.** This is a documented exception to "every
   admin setting in the Settings console": the platform has no supported call for an app to
   activate or deactivate a prompt, and building one through the Metadata API would be a custom
   framework for a one-click Setup action that also governs the org's own prompts. The admin
   guide page says where (Setup, In-App Guidance) and what each control does.
6. **English text in the metadata, not custom labels.** Prompt text is translated with
   Translation Workbench (PromptVersionTranslation), as an org's own prompts are.
7. **A CI check guards the metadata**: `check-metadata-lengths.py` checks each prompt's text
   limits, that its tab and app exist in the repo, and that it is not a walkthrough and names
   no namespace.

## Consequences

- A released prompt can never be removed from the package. Each one added is permanent; to
  retire one, a later version deactivates it (`isPublished` false). Keep the set small.
- The tips depend on tab and app API names. Renaming `BarnCRM`, `BarnCRM_Settings`, `Import`,
  `Find`, `Bulk_Update` or `Field_Utilization` needs the prompts changed in the same branch; the
  CI check fails otherwise.
- When the namespace is chosen, confirm in a packaging org that `targetPageKey1` and
  `customApplication` resolve to the namespaced tab and app on install (the API also has
  `TargetPageKey1Ref`, a reference, which suggests they do).
- No Apex or LWC depends on the prompts. An org that turns them off, or lacks in-app guidance
  (the Salesforce mobile app), loses only the tips.
