/**
 * Finds each installed module's access sync (`ModuleAccessSync`) and asks it to run (ADR-NEXT
 * `NEXT-module-access-sync-by-role.md`): the Module Manager asks the one module it turns on,
 * and the nightly access check (`TabAccessScheduler`) asks every one.
 *
 * Found by namespace and class name, as `HealthCheckExtensions` finds its extensions. A module
 * that is not installed is skipped; one that cannot be built, or throws, is logged and skipped,
 * since turning a module on or the nightly check must not fail over a sync.
 */
@NamespaceAccessible
public with sharing class ModuleAccessSyncs {
    /** Each module's sync class, by module key, added in the PR that adds the class. */
    @NamespaceAccessible
    public static final Map<String, String> CLASSES = new Map<String, String>();

    /** Injected by Core's tests by module key, since no module is there to resolve. */
    @TestVisible
    private static Map<String, ModuleAccessSync> overrides = new Map<String, ModuleAccessSync>();

    private static final String CONTEXT = 'ModuleAccessSyncs';

    /** Asks the named module's sync to run, when the module has one. Never throws. */
    @NamespaceAccessible
    public static void requestFor(String moduleName) {
        for (String key : moduleKeys()) {
            if (key.equalsIgnoreCase(moduleName)) {
                request(key);
            }
        }
    }

    /** Asks every installed module's sync to run. Never throws. */
    @NamespaceAccessible
    public static void requestAll() {
        for (String key : moduleKeys()) {
            request(key);
        }
    }

    private static Set<String> moduleKeys() {
        Set<String> keys = new Set<String>(CLASSES.keySet());
        keys.addAll(overrides.keySet());
        return keys;
    }

    private static void request(String moduleKey) {
        try {
            ModuleAccessSync sync = overrides.containsKey(moduleKey)
                ? overrides.get(moduleKey)
                : resolve(CLASSES.get(moduleKey));
            if (sync != null) {
                sync.requestSync();
            }
        } catch (Exception failed) {
            ErrorLogger.log(failed, CONTEXT);
        }
    }

    private static ModuleAccessSync resolve(String className) {
        Type syncType = NamespaceUtil.resolveType(className);
        if (syncType == null) {
            return null;
        }
        Object candidate = syncType.newInstance();
        if (candidate instanceof ModuleAccessSync) {
            return (ModuleAccessSync) candidate;
        }
        throw new System.TypeException(className + ' does not implement ModuleAccessSync');
    }
}
