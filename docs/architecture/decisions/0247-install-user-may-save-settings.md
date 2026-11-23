# ADR-0247: The Install User May Save Settings During Install Only

**Status:** Accepted (owner decision D-223, 2026-11-23)
**Date:** 2026-11-23
**Source:** Brandon, 2026-11-23, release 1.37 (ST-01). Amends the Manage BarnCRM Settings gate
in `SettingsService` and `SettingsWriter` (ADR-0238 settings as custom metadata).

## Context

Salesforce runs a package's post-install handler as a special install user, who cannot hold the
custom permission Manage BarnCRM Settings. Every settings save needs that permission, so after a
real package install the handler's save of Features Turned On was refused and the setting stayed
blank (ADR-0230 expects it to hold `None`).

## Decision

1. **One allowance, install only.** `BarnCRMPermissions.canSaveSettings()` is true when the
   running user holds Manage BarnCRM Settings, or while Core's install handler is running.
   `SettingsService.sendStoreChanges` and `SettingsWriter.saveOrgDefault` ask it instead of
   `canManageSettings()`. Every other caller still needs the permission.
2. **The switch is a private static flag.** `CorePostInstall.onInstall` calls
   `BarnCRMPermissions.enterInstall()` and, in a `finally`, `leaveInstall()`. The flag is
   private to `BarnCRMPermissions`; the two methods carry no `@NamespaceAccessible`, so no other
   package reaches them. Finish Setup, a source deploy and the retry job do not set it: the
   person running them holds the permission or is refused as before. The platform's request
   quiddity has no post-install value, so it was not an option.
3. **Tests.** A save is refused without the permission outside install; allowed while the
   handler runs; the flag is off again afterward.

## Consequences

- The allowance lives for the length of the install handler's transaction only.
- Module post-install handlers do not save settings today. If one must, it needs its own
  decision, since Core's flag is not reachable from another package.
