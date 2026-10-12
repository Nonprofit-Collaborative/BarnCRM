/**
 * The error digest's schedule (C-23, R-E5): one job every morning at 07:00, started and stopped
 * from the Error Log page of the Nonprofit Settings console, as ADR-0038 has the nightly jobs
 * started. The job decides for itself whether a digest is due, so changing the frequency from
 * daily to weekly never needs the schedule changed.
 */
public with sharing class ErrorDigestScheduler implements Schedulable {
    /** The name the scheduled job carries, so the settings page can find it again. */
    public static final String JOB_NAME = 'BarnCRM Error Digest';

    /**
     * Seven in the morning: after the nightly jobs (the last, donor levels, starts at 03:00), so
     * a failure in any of them is in the digest the administrator reads with their coffee.
     */
    private static final String DAILY_CRON = '0 0 7 * * ?';

    public void execute(SchedulableContext context) {
        try {
            ErrorDigestService.runScheduled();
        } catch (Exception failed) {
            ErrorLogger.log(failed, 'Error digest');
        }
    }

    /** Starts the daily run, or returns the one already scheduled. */
    public static Id start() {
        Id existing = ScheduledJobSelector.triggerIdByName(JOB_NAME);
        if (existing != null) {
            return existing;
        }
        return System.schedule(JOB_NAME, DAILY_CRON, new ErrorDigestScheduler());
    }

    /** Stops the daily run. Nothing already sent is affected. */
    public static void stop() {
        Id existing = ScheduledJobSelector.triggerIdByName(JOB_NAME);
        if (existing != null) {
            System.abortJob(existing);
        }
    }

    /** When the digest job runs next, or null when it is not scheduled. */
    public static Datetime nextRunAt() {
        return ScheduledJobSelector.nextFireTime(JOB_NAME);
    }
}
