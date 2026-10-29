/**
 * The hourly tab access check (ADR-0124, edition gates visibility): queues the sync that gives
 * the BarnCRM Tab permission sets to people given a role or an add-on outside BarnCRM's Access
 * page, and takes them from people who lost it. Hourly since 2026-10-29 (owner decision), so
 * people given a role in Setup get their tabs within an hour; Salesforce has no trigger on
 * permission set assignments, so a schedule is the only way. Health Check lists it among the
 * scheduled jobs and its Schedule all nightly jobs fix starts it (`NightlyJobs`, ADR-0075). It
 * also asks each installed module's access sync to give its sets to people given a role since
 * (ADR-0131 `0131-module-access-sync-by-role.md`).
 */
public with sharing class TabAccessScheduler implements Schedulable {
    /** The name the scheduled job carries, so it is found again rather than doubled. */
    public static final String JOB_NAME = 'BarnCRM Tab Access Check';

    /** Every hour, on the hour. The job was nightly ('0 0 1 * * ?') before 2026-10-29. */
    @TestVisible
    private static final String HOURLY_CRON = '0 0 * * * ?';

    public void execute(SchedulableContext context) {
        TabAccessService.requestSync();
        ModuleAccessSyncs.requestAll();
    }

    /**
     * Starts the hourly check, or does nothing when it is already scheduled hourly. A job an
     * earlier version scheduled nightly is aborted and scheduled again under the same name, so
     * an install or upgrade moves it to the hourly cron and never leaves two.
     */
    public static Id start() {
        Id existing = ScheduledJobSelector.triggerIdByName(JOB_NAME);
        if (existing != null) {
            if (HOURLY_CRON == ScheduledJobSelector.cronExpressionByName(JOB_NAME)) {
                return existing;
            }
            ScheduledJobSelector.abort(existing);
        }
        return ScheduledJobSelector.schedule(JOB_NAME, HOURLY_CRON, new TabAccessScheduler());
    }

    /** True when the hourly check is scheduled. */
    public static Boolean isScheduled() {
        return ScheduledJobSelector.triggerIdByName(JOB_NAME) != null;
    }
}
