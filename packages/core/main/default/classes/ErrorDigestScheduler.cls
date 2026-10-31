/**
 * The error digest's schedule (C-23, R-E5): one job every morning at 07:00, started and stopped
 * from the Error Log page of the BarnCRM Settings console, as ADR-0038 has the nightly jobs
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
        // The daily Error Log run also deletes entries past their retention (R-E6). Its own
        // try, so neither half stops the other.
        try {
            ErrorLogRetention.start();
        } catch (Exception failed) {
            ErrorLogger.log(failed, 'Error Log retention');
        }
        try {
            ErrorDigestService.runScheduled();
        } catch (Exception failed) {
            ErrorLogger.log(failed, 'Error digest');
        }
    }

    /** Starts the daily run, or returns the one already scheduled. */
    public static Id start() {
        return ScheduledJobSelector.ensure(JOB_NAME, DAILY_CRON, new ErrorDigestScheduler());
    }

    /** Stops the daily run. Nothing already sent is affected. */
    public static void stop() {
        ScheduledJobSelector.stopNamed(JOB_NAME);
    }

    /** The daily run as Health Check's nightly jobs list sees it. */
    public static NightlyJob nightlyJob() {
        return new NamedNightlyJob(
            System.Label.Core_HealthCheck_JobErrorDigest,
            JOB_NAME,
            DAILY_CRON,
            new ErrorDigestScheduler()
        );
    }

    /** When the digest job runs next, or null when it is not scheduled. */
    public static Datetime nextRunAt() {
        return ScheduledJobSelector.nextFireTime(JOB_NAME);
    }
}
