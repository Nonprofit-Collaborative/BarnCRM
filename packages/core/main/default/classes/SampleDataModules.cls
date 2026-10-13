/**
 * The module sample data sets installed in this org, in load order (C-10).
 *
 * Core names each module's implementation as a string and resolves it with `Type.forName`,
 * which is the mechanism ADR-0017 settled for calling into a package Core cannot compile
 * against. A module that is not installed simply does not resolve, and every caller here
 * copes with the empty list.
 *
 * Loading is one module at a time on purpose. A queueable may enqueue one job, so Core's
 * last stage starts the first module and each module's own last job calls `startAfter` with
 * its name, which starts the module after it. With one module shipped that call is a no-op,
 * and it is what keeps a second module from needing a change in Core.
 */
@NamespaceAccessible
public with sharing class SampleDataModules {
    /**
     * Module sample data classes in load order. Each must be public, `@NamespaceAccessible`,
     * have a no-argument constructor, and implement SampleDataModule.
     */
    private static final List<String> MODULE_CLASS_NAMES = new List<String>{ 'GivingSampleData' };

    /** Injected by the tests, which have no other package to resolve a real module from. */
    @TestVisible
    private static List<SampleDataModule> moduleOverride;

    /** Each class looked up so far this transaction, null when it is not installed. */
    private static Map<String, SampleDataModule> found = new Map<String, SampleDataModule>();

    /** Every module sample data set this org actually has, in load order. */
    public static List<SampleDataModule> installed() {
        if (moduleOverride != null) {
            return moduleOverride;
        }
        List<SampleDataModule> modules = new List<SampleDataModule>();
        for (String className : MODULE_CLASS_NAMES) {
            if (!found.containsKey(className)) {
                found.put(className, resolve(className));
            }
            SampleDataModule module = found.get(className);
            if (module != null) {
                modules.add(module);
            }
        }
        return modules;
    }

    /** Starts the first installed module's load, if there is one. */
    public static void startFirst() {
        start(0);
    }

    /**
     * Starts the module that loads after the named one. Called by a module's own last job,
     * so the chain carries on without Core knowing which modules exist.
     */
    @NamespaceAccessible
    public static void startAfter(String moduleName) {
        List<SampleDataModule> modules = installed();
        for (Integer index = 0; index < modules.size(); index++) {
            if (modules[index].moduleName() == moduleName) {
                start(index + 1);
                return;
            }
        }
    }

    /**
     * Deletes every installed module's sample records and returns how many rows went.
     * Runs before Core deletes its own records, because a module's records point at them.
     */
    public static Integer removeAll() {
        Integer removed = 0;
        for (SampleDataModule module : installed()) {
            removed += module.removeAll();
        }
        return removed;
    }

    /** One count per installed module, for the status card. */
    public static List<SampleDataLoader.ModuleCount> counts() {
        List<SampleDataLoader.ModuleCount> counts = new List<SampleDataLoader.ModuleCount>();
        for (SampleDataModule module : installed()) {
            SampleDataLoader.ModuleCount count = new SampleDataLoader.ModuleCount();
            count.name = module.moduleName();
            count.label = module.countLabel();
            count.recordCount = module.countLoaded();
            counts.add(count);
        }
        return counts;
    }

    private static void start(Integer index) {
        List<SampleDataModule> modules = installed();
        if (index < 0 || index >= modules.size()) {
            return;
        }
        modules[index].enqueueLoad();
    }

    /**
     * One module class as an instance, or null when the package is not installed, the class
     * is not reachable, or it does not implement the interface. A module that is not installed
     * is not an error: an org without Giving is the ordinary case. One that cannot be built,
     * or is the wrong shape, is logged, because it means a package shipped a broken module.
     */
    @TestVisible
    private static SampleDataModule resolve(String className) {
        Type moduleType = NamespaceUtil.resolveType(className);
        if (moduleType == null) {
            return null;
        }
        Object candidate;
        try {
            candidate = moduleType.newInstance();
        } catch (Exception cannotBuild) {
            ErrorLogger.log(cannotBuild, 'SampleDataModules.resolve');
            return null;
        }
        if (candidate instanceof SampleDataModule) {
            return (SampleDataModule) candidate;
        }
        ErrorLogger.log(
            new System.TypeException(className + ' does not implement SampleDataModule'),
            'SampleDataModules.resolve'
        );
        return null;
    }
}
