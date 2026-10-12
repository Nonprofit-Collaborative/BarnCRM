/**
 * The nightly seasonal address swap's schedule, and the two buttons on the Addresses page of
 * the Nonprofit Settings console that start and stop it.
 *
 * The schedule is an administrator's, not Setup's: it is started and stopped from the settings
 * console, which is what "every admin setting lives in the in-app console" means for something
 * that is a scheduled job rather than a field. A job with no in-app way to schedule it is a job
 * nobody schedules, and this package already has one of those.
 */
public with sharing class SeasonalAddressScheduler implements Schedulable {
    /** The name the scheduled job carries, so the settings page can find it again. */
    public static final String JOB_NAME = 'BarnCRM Seasonal Addresses';

    /**
     * Half past midnight. Early enough that a season that starts today is in place before the
     * day's mail merges, and far enough from the rollups at 2:00 AM that the two are not
     * competing for the org's batch slots.
     */
    private static final String NIGHTLY_CRON = '0 30 0 * * ?';

    public void execute(SchedulableContext context) {
        Database.executeBatch(new SeasonalAddressBatch(), SeasonalAddressBatch.CHUNK_SIZE);
    }

    /** Starts the nightly swap, or does nothing when it is already scheduled. */
    public static Id start() {
        Id existing = scheduledJobId();
        if (existing != null) {
            return existing;
        }
        return System.schedule(JOB_NAME, NIGHTLY_CRON, new SeasonalAddressScheduler());
    }

    /** Stops the nightly swap. The addresses stay exactly as the last run left them. */
    public static void stop() {
        Id existing = scheduledJobId();
        if (existing != null) {
            System.abortJob(existing);
        }
    }

    /** Runs the swap now, without waiting for tonight. */
    public static Id runNow() {
        return Database.executeBatch(new SeasonalAddressBatch(), SeasonalAddressBatch.CHUNK_SIZE);
    }

    /** True when the nightly swap is scheduled. */
    public static Boolean isScheduled() {
        return scheduledJobId() != null;
    }

    /** When the nightly swap is next due, or null when it is not scheduled. */
    public static Datetime nextRunAt() {
        Id jobId = scheduledJobId();
        if (jobId == null) {
            return null;
        }
        List<CronTrigger> triggers = [
            SELECT NextFireTime
            FROM CronTrigger
            WHERE Id = :jobId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return triggers.isEmpty() ? null : triggers[0].NextFireTime;
    }

    private static Id scheduledJobId() {
        List<CronJobDetail> details = [
            SELECT Id
            FROM CronJobDetail
            WHERE Name = :JOB_NAME AND JobType = '7'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (details.isEmpty()) {
            return null;
        }
        List<CronTrigger> triggers = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetailId = :details[0].Id
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return triggers.isEmpty() ? null : triggers[0].Id;
    }
}
