/**
 * Finds each installed module's access sync (`ModuleAccessSync`) and asks it to run (ADR-0131
 * `0131-module-access-sync-by-role.md`): the Module Manager asks the one module it turns on, and
 * the Access page and the nightly access check (`TabAccessScheduler`) ask every one.
 *
 * Found by convention, so Core names no module class: a module's sync is the class named after
 * its key in the module catalog (`BarnCRM_Module__mdt`) followed by `AccessSync`, resolved by
 * namespace and name as `HealthCheckExtensions` resolves its extensions. A module without such a
 * class is skipped; one that cannot be built, or throws, is logged and skipped, since turning a
 * module on, assigning a role or the nightly check must not fail over a sync.
 */
@NamespaceAccessible
public with sharing class ModuleAccessSyncs {
    /** The suffix after the module key that names a module's sync class. */
    @NamespaceAccessible
    public static final String CLASS_SUFFIX = 'AccessSync';

    /** Injected by Core's tests by module key, since no module is there to resolve. */
    @TestVisible
    private static Map<String, ModuleAccessSync> overrides = new Map<String, ModuleAccessSync>();

    private static final String CONTEXT = 'ModuleAccessSyncs';

    /** Asks the named module's sync to run, when the module has one. Never throws. */
    @NamespaceAccessible
    public static void requestFor(String moduleName) {
        if (String.isNotBlank(moduleName)) {
            request(moduleName);
        }
    }

    /** Asks every catalog module's sync to run, where it has one. Never throws. */
    @NamespaceAccessible
    public static void requestAll() {
        Set<String> keys = new Set<String>(overrides.keySet());
        try {
            keys.addAll(BarnCRM_Module__mdt.getAll().keySet());
        } catch (Exception failed) {
            ErrorLogger.log(failed, CONTEXT);
        }
        for (String key : keys) {
            request(key);
        }
    }

    private static void request(String moduleKey) {
        try {
            ModuleAccessSync sync = overrides.containsKey(moduleKey)
                ? overrides.get(moduleKey)
                : resolve(moduleKey + CLASS_SUFFIX);
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
