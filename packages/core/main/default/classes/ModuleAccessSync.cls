/**
 * A module's sync that gives its own permission sets to BarnCRM's roles (ADR-NEXT
 * `NEXT-module-access-sync-by-role.md`). Core asks it through `ModuleAccessSyncs` when the
 * Module Manager turns the module on and with the nightly access check, so people given a role
 * since get the module's sets. The module's class needs a public no-argument constructor, since
 * Core builds it by name.
 */
@NamespaceAccessible
public interface ModuleAccessSync {
    /**
     * Queues the module's sync, which only gives and does nothing while the module is turned
     * off. Never throws: a failure is logged and the next nightly check tries again.
     */
    void requestSync();
}
