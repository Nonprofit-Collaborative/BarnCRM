/**
 * The nightly rollup run, and the two buttons on the Rollups page that turn it on and off.
 *
 * The schedule is an administrator's, not Setup's: it is started and stopped from the Nonprofit
 * Settings console, which is what "every admin setting lives in the in-app console" means for
 * something that is a scheduled job rather than a field.
 */
public with sharing class RollupScheduler implements Schedulable {
    /** The name the scheduled job carries, so the console can find it again. */
    public static final String JOB_NAME = 'BarnCRM Rollups';

    /**
     * The name used for the job. A test gives it a name of its own, because the org a test runs
     * in may already have the nightly run, which a test can neither see past nor stop.
     */
    @TestVisible
    private static String jobNameInUse = JOB_NAME;

    /** The name the nightly job is scheduled and found under. */
    public static String jobName() {
        return jobNameInUse;
    }

    /** Two in the morning, which is after the day's data entry and before the day's reporting. */
    private static final String NIGHTLY_CRON = '0 0 2 * * ?';

    /** One definition per chunk: a full recalculation is itself a job chain inside the engine. */
    private static final Integer BATCH_SIZE = 1;

    public void execute(SchedulableContext context) {
        Database.executeBatch(new RollupBatch(), BATCH_SIZE);
    }

    /** Starts the nightly run, or does nothing when it is already scheduled. */
    public static Id start() {
        Id existing = scheduledJobId();
        if (existing != null) {
            return existing;
        }
        return System.schedule(jobNameInUse, NIGHTLY_CRON, new RollupScheduler());
    }

    /** Stops the nightly run. */
    public static void stop() {
        Id existing = scheduledJobId();
        if (existing != null) {
            System.abortJob(existing);
        }
    }

    /** Runs the nightly work now, without waiting for tonight. */
    public static Id runNow() {
        return Database.executeBatch(new RollupBatch(), BATCH_SIZE);
    }

    /** True when the nightly run is scheduled. */
    public static Boolean isScheduled() {
        return scheduledJobId() != null;
    }

    /** When the nightly run is next due, or null when it is not scheduled. */
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
            WHERE Name = :jobNameInUse AND JobType = '7'
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
