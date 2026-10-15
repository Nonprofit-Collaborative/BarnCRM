/**
 * Gives the Rollup Builder permission sets to BarnCRM's roles (ADR-0125
 * `0125-rollup-builder-module.md`, D2): Rollup Builder User to everyone holding BarnCRM Staff or
 * BarnCRM Read Only, and Rollup Builder Admin to everyone holding BarnCRM Admin, directly or
 * through a role (a permission set group). Core's roles cannot carry the module's sets, so this
 * keeps them together the way Core keeps its tab sets, through `TabAccessService.giveToHolders`.
 *
 * It only gives, never takes away: a set may also be given by hand, to the person who installed
 * the module or to an integration user whose saves publish `Rollup_Queue_Ready__e` (decision 8).
 * It runs at install (`RollupsPostInstall`), at each Turn on (`RollupsEngineExtension`) and with
 * the nightly run (`RollupScheduler`), which also catches people given a role since, and does
 * nothing while the module is turned off.
 */
public with sharing class RollupAccessSync {
    /** The read-only Builder set, for the Staff and Read Only roles. */
    public static final String USER_SET = 'Rollup_Builder_User';

    private static final String CONTEXT = 'RollupAccessSync';

    /** Each module set, and the Core permission sets whose holders get it. */
    @TestVisible
    private static final Map<String, List<String>> AUDIENCE = new Map<String, List<String>>{
        USER_SET => new List<String>{ 'BarnCRM_Staff', 'BarnCRM_Read_Only' },
        RollupsPostInstall.ADMIN_PERMISSION_SET => new List<String>{ 'BarnCRM_Admin' }
    };

    /** Assignments one run gives per set: both together stay inside the 10,000 DML rows. */
    @TestVisible
    private static Integer rowsPerSet = 4000;

    /**
     * Queues one sync. Never throws: a failure is logged, and the nightly run tries again.
     */
    public static void requestSync() {
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
        if (RollupService.isTurnedOff()) {
            return false;
        }
        Boolean more = false;
        for (String setName : AUDIENCE.keySet()) {
            Boolean left = TabAccessService.giveToHolders(
                setName,
                AUDIENCE.get(setName),
                rowsPerSet,
                CONTEXT
            );
            more = more || left;
        }
        return more;
    }

    /**
     * The queued sync: a permission set assignment is a setup object write, so it never shares
     * a transaction with the install's or the nightly run's record writes (mixed DML). It queues
     * itself again while more is left.
     */
    public class Job implements Queueable {
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
