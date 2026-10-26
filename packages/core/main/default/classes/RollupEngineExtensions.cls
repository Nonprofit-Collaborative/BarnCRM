/**
 * Finds the rollup engine the BarnCRM Rollup Builder module installs, or answers that there is
 * none, which is the ordinary case in an org that keeps its totals with another tool (ADR-0125,
 * `0125-rollup-builder-module.md`).
 *
 * Found by namespace and class name, as `HealthCheckExtensions` finds its extensions
 * (ADR-0017). A class that cannot be built, or does not implement the interface, is treated as
 * absent and logged: a save, a merge or the home page must not fail over totals Core can do
 * without.
 */
@NamespaceAccessible
public with sharing class RollupEngineExtensions {
    /** The class name the module registers. */
    @NamespaceAccessible
    public static final String EXTENSION_CLASS = 'RollupsEngineExtension';

    /** Injected by Core's tests, since the module may not be there to resolve. */
    @TestVisible
    private static RollupEngineExtension extensionOverride;

    /** Set by Core's tests to see the org as having no engine. */
    @TestVisible
    private static Boolean noneForTest = false;

    private static Boolean looked = false;
    private static RollupEngineExtension found;

    /** The installed engine, or null when the module is not installed. Looked up once. */
    @NamespaceAccessible
    public static RollupEngineExtension find() {
        if (extensionOverride != null) {
            return extensionOverride;
        }
        if (noneForTest == true) {
            return null;
        }
        if (!looked) {
            found = resolve(EXTENSION_CLASS);
            looked = true;
        }
        return found;
    }

    /** True when the module's engine is installed. */
    @NamespaceAccessible
    public static Boolean isInstalled() {
        return find() != null;
    }

    /**
     * The installed engine's second seam (`RollupEngineExtensionV2`), or null when there is no
     * engine or it predates that seam.
     */
    @NamespaceAccessible
    public static RollupEngineExtensionV2 findV2() {
        RollupEngineExtension engine = find();
        return engine instanceof RollupEngineExtensionV2 ? (RollupEngineExtensionV2) engine : null;
    }

    /**
     * The installed engine's third seam (`RollupEngineExtensionV3`), or null when there is no
     * engine or it predates that seam.
     */
    @NamespaceAccessible
    public static RollupEngineExtensionV3 findV3() {
        RollupEngineExtension engine = find();
        return engine instanceof RollupEngineExtensionV3 ? (RollupEngineExtensionV3) engine : null;
    }

    @TestVisible
    private static RollupEngineExtension resolve(String className) {
        Type extensionType = NamespaceUtil.resolveType(className);
        if (extensionType == null) {
            return null;
        }
        Object candidate;
        try {
            candidate = extensionType.newInstance();
        } catch (Exception cannotBuild) {
            ErrorLogger.log(cannotBuild, 'RollupEngineExtensions.resolve');
            return null;
        }
        if (candidate instanceof RollupEngineExtension) {
            return (RollupEngineExtension) candidate;
        }
        ErrorLogger.log(
            new System.TypeException(className + ' does not implement RollupEngineExtension'),
            'RollupEngineExtensions.resolve'
        );
        return null;
    }
}
