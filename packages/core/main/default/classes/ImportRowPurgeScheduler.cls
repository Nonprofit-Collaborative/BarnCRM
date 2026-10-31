/**
 * The nightly Import row cleanup's schedule (R-IR5). Health Check lists it among the
 * nightly jobs and its Schedule all nightly jobs fix starts it (`NightlyJobs`, ADR-0075). When
 * rows are deleted is the Import setting Delete Import Rows; Never keeps them, so the job
 * needs no stop button of its own.
 */
public with sharing class ImportRowPurgeScheduler implements Schedulable {
    /** The name the scheduled job carries, so it is found again rather than doubled. */
    public static final String JOB_NAME = 'BarnCRM Import Row Cleanup';

    /** A quarter past one: clear of the seasonal addresses at 0:30 and the rollups at 2:00. */
    private static final String NIGHTLY_CRON = '0 15 1 * * ?';

    public void execute(SchedulableContext context) {
        Database.executeBatch(new ImportRowPurgeBatch(), ImportRowPurgeBatch.CHUNK_SIZE);
    }

    /** Starts the nightly cleanup, or does nothing when it is already scheduled. */
    public static Id start() {
        Id existing = ScheduledJobSelector.triggerIdByName(JOB_NAME);
        if (existing != null) {
            return existing;
        }
        return ScheduledJobSelector.schedule(JOB_NAME, NIGHTLY_CRON, new ImportRowPurgeScheduler());
    }

    /** True when the nightly cleanup is scheduled. */
    public static Boolean isScheduled() {
        return ScheduledJobSelector.triggerIdByName(JOB_NAME) != null;
    }
}
