/**
 * Gives the Programs permission sets to BarnCRM's roles (ADR-0151 `0151-programs-module.md`,
 * decision 7): Programs Admin to everyone holding BarnCRM Admin, directly or through a role,
 * Programs Staff to the Team Member and Coordinator roles, and Programs Read Only to the Read
 * Only role. The roles are permission set groups, followed through
 * `TabAccessService.giveToGroupHolders` (ADR-0131 `0131-module-access-sync-by-role.md`).
 *
 * It only gives, never takes away: a set may also be given by hand. It runs at install
 * (`ProgramsPostInstall`), and Core asks it when a role is given on the Access page, at each
 * Turn on and with the hourly access check, which also catches roles given in Setup. Core finds
 * it by its name, the module key followed by `AccessSync` (`ModuleAccessSyncs`), so the class
 * keeps this name. It does nothing while the module is turned off.
 */
@NamespaceAccessible
public with sharing class ProgramsAccessSync implements ModuleAccessSync {
    /** The module key in the Module Manager. */
    public static final String MODULE_NAME = 'Programs';
    /** The set the installer and BarnCRM Admin holders get. */
    public static final String ADMIN_SET = 'Programs_Admin';
    private static final String CONTEXT = 'ProgramsAccessSync';

    /** The Admin set, and the Core permission set whose holders get it. */
    @TestVisible
    private static final Map<String, List<String>> BY_SET = new Map<String, List<String>>{
        ADMIN_SET => new List<String>{ 'BarnCRM_Admin' }
    };

    /** Each other set, and the BarnCRM roles (permission set groups) whose holders get it. */
    @TestVisible
    private static final Map<String, List<String>> BY_ROLE = new Map<String, List<String>>{
        'Programs_Staff' => new List<String>{ 'Program_Staff', 'Volunteer_Coordinator' },
        'Programs_Read_Only' => new List<String>{ 'Read_Only' }
    };

    /** Assignments one run gives per set: all three together stay inside the 10,000 DML rows. */
    @TestVisible
    private static Integer rowsPerSet = 3000;

    @NamespaceAccessible
    public ProgramsAccessSync() {
        // Built by name from Core (ModuleAccessSyncs), so it needs a public constructor.
    }

    /** Queues one sync. Never throws: a failure is logged, and the hourly check tries again. */
    public void requestSync() {
        try {
            System.enqueueJob(new Job());
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT);
        }
    }

    /**
     * One slice of each set now. Returns true when more is left. Nothing while the module is
     * turned off.
     */
    public static Boolean syncOnce() {
        if (ModuleManagerService.turnedOff().contains(MODULE_NAME.toLowerCase())) {
            return false;
        }
        Boolean more = false;
        for (String setName : BY_SET.keySet()) {
            Boolean left = TabAccessService.giveToHolders(
                setName,
                BY_SET.get(setName),
                rowsPerSet,
                CONTEXT
            );
            more = more || left;
        }
        for (String setName : BY_ROLE.keySet()) {
            Boolean left = TabAccessService.giveToGroupHolders(
                setName,
                BY_ROLE.get(setName),
                rowsPerSet,
                CONTEXT
            );
            more = more || left;
        }
        return more;
    }

    /**
     * The queued sync: a permission set assignment is a setup object write, so it never shares
     * a transaction with the install's or Turn on's record writes (mixed DML). It queues itself
     * again while more is left.
     */
    public with sharing class Job implements Queueable {
        public void execute(QueueableContext jobContext) {
            try {
                // A test cannot chain one queued job from another.
                if (syncOnce() && !Test.isRunningTest()) {
                    System.enqueueJob(new Job());
                }
            } catch (Exception e) {
                ErrorLogger.log(e, CONTEXT);
            }
        }
    }
}
