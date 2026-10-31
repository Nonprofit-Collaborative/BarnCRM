/**
 * The shared run of a module's access sync (ADR-0131 `0131-module-access-sync-by-role.md`):
 * gives each of the module's permission sets to the holders of the Core permission sets, and of
 * the BarnCRM roles (permission set groups), named for it, a slice at a time, through
 * `TabAccessService`. A module supplies its constants and, when it needs one, a step after each
 * pass (`afterSync`).
 *
 * It only gives, never takes away: a set may also be given by hand. It does nothing while the
 * module is turned off. Core finds a module's sync by its name, the module key followed by
 * `AccessSync` (`ModuleAccessSyncs`), so each module class keeps that name.
 */
@NamespaceAccessible
public abstract with sharing class ModuleAccessSyncBase implements ModuleAccessSync {
    @NamespaceAccessible
    public ModuleAccessSyncBase() {
        // Each module's class is built by name, so it and this need public constructors.
    }

    /** The module key in the Module Manager. */
    @NamespaceAccessible
    public abstract String moduleName();

    /** The context a failure is logged under: the module's class name. */
    @NamespaceAccessible
    public abstract String logContext();

    /** Each set, and the Core permission sets whose holders get it. */
    @NamespaceAccessible
    public abstract Map<String, List<String>> setsByPermissionSet();

    /** Each set, and the BarnCRM roles (permission set groups) whose holders get it. */
    @NamespaceAccessible
    public abstract Map<String, List<String>> setsByRole();

    /** Assignments one run gives per set, so all the sets together stay inside the DML rows. */
    @NamespaceAccessible
    public abstract Integer sliceSize();

    /** A module's own step after each pass; a failure is logged and never stops the sync. */
    @NamespaceAccessible
    public virtual void afterSync() {
        return;
    }

    /** Queues one sync. Never throws: a failure is logged, and the hourly check tries again. */
    @NamespaceAccessible
    public void requestSync() {
        try {
            System.enqueueJob(new Job(this));
        } catch (Exception e) {
            ErrorLogger.log(e, logContext());
        }
    }

    /**
     * One slice of each set now. Returns true when more is left. Nothing while the module is
     * turned off.
     */
    @NamespaceAccessible
    public Boolean sync() {
        if (ModuleManagerService.turnedOff().contains(moduleName().toLowerCase())) {
            return false;
        }
        Boolean more = false;
        Map<String, List<String>> bySet = setsByPermissionSet();
        for (String setName : bySet.keySet()) {
            Boolean left = TabAccessService.giveToHolders(
                setName,
                bySet.get(setName),
                sliceSize(),
                logContext()
            );
            more = more || left;
        }
        Map<String, List<String>> byRole = setsByRole();
        for (String setName : byRole.keySet()) {
            Boolean left = TabAccessService.giveToGroupHolders(
                setName,
                byRole.get(setName),
                sliceSize(),
                logContext()
            );
            more = more || left;
        }
        try {
            afterSync();
        } catch (Exception e) {
            ErrorLogger.log(e, logContext());
        }
        return more;
    }

    /**
     * The queued sync: a permission set assignment is a setup object write, so it never shares
     * a transaction with the install's or Turn on's record writes (mixed DML). It queues itself
     * again while more is left.
     */
    @NamespaceAccessible
    public with sharing class Job implements Queueable {
        private final ModuleAccessSyncBase module;

        @NamespaceAccessible
        public Job(ModuleAccessSyncBase module) {
            this.module = module;
        }

        @NamespaceAccessible
        public void execute(QueueableContext jobContext) {
            try {
                // A test cannot chain one queued job from another.
                if (module.sync() && !Test.isRunningTest()) {
                    System.enqueueJob(new Job(module));
                }
            } catch (Exception e) {
                ErrorLogger.log(e, module.logContext());
            }
        }
    }
}
