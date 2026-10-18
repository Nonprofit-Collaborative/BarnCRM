/**
 * The nightly tab access check (ADR-0124, edition gates visibility): queues the sync that gives
 * the BarnCRM Tab permission sets to people given a role or an add-on outside BarnCRM's Access
 * page, and takes them from people who lost it. Health Check lists it among the nightly jobs
 * and its Schedule all nightly jobs fix starts it (`NightlyJobs`, ADR-0075). It also asks each
 * installed module's access sync to give its sets to people given a role since (ADR-NEXT
 * `NEXT-module-access-sync-by-role.md`).
 */
public with sharing class TabAccessScheduler implements Schedulable {
    /** The name the scheduled job carries, so it is found again rather than doubled. */
    public static final String JOB_NAME = 'BarnCRM Tab Access Check';

    /** One o'clock: clear of the seasonal addresses at 0:30 and the import rows at 1:15. */
    private static final String NIGHTLY_CRON = '0 0 1 * * ?';

    public void execute(SchedulableContext context) {
        TabAccessService.requestSync();
        ModuleAccessSyncs.requestAll();
    }

    /** Starts the nightly check, or does nothing when it is already scheduled. */
    public static Id start() {
        Id existing = ScheduledJobSelector.triggerIdByName(JOB_NAME);
        if (existing != null) {
            return existing;
        }
        return ScheduledJobSelector.schedule(JOB_NAME, NIGHTLY_CRON, new TabAccessScheduler());
    }

    /** True when the nightly check is scheduled. */
    public static Boolean isScheduled() {
        return ScheduledJobSelector.triggerIdByName(JOB_NAME) != null;
    }
}
