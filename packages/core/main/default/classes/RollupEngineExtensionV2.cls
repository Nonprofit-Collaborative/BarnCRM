/**
 * The second rollup engine seam (ADR-NEXT, `NEXT-rollup-builder-module.md`, decisions 4 and 9).
 * `RollupEngineExtension` never gains a method once a module implements it, so a new need is a
 * new interface the module's engine implements beside the first; `RollupEngineExtensions.findV2`
 * answers it only when the installed engine does.
 */
@NamespaceAccessible
public interface RollupEngineExtensionV2 {
    /**
     * Called by the Module Manager after a module is turned on again. The engine acts only for
     * its own module: it puts every total right (the totals waiting in its queue, and a full
     * recalculation, since saves made while it was off were not recorded).
     */
    void afterModuleTurnedOn(String moduleName);
}
