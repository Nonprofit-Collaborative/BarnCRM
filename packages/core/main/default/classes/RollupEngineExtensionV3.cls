/**
 * The third rollup engine seam (ADR-0125, `0125-rollup-builder-module.md`, decision 4; ADR-0136).
 * `RollupEngineExtension` never gains a method once a module implements it, so a new need is a
 * new interface the module's engine implements beside the others; `RollupEngineExtensions.findV3`
 * answers it only when the installed engine does.
 */
@NamespaceAccessible
public interface RollupEngineExtensionV3 {
    /**
     * Called by the settings service after a save changed settings, with the settings object's
     * API name and the API names of the fields that changed, both without a namespace prefix.
     * The engine acts only for its own settings: the nightly run moves when its hour changes.
     */
    void afterSettingsSaved(String settingsObject, Set<String> changedKeys);
}
