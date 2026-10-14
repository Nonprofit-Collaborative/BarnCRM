/**
 * The nightly empty household tidy-up's schedule (R-H12a, ADR-NEXT). Health Check lists it among
 * the nightly jobs and its Schedule all nightly jobs fix starts it (`NightlyJobs`, ADR-0075).
 * Whether it removes anything is the Households setting Keep the households of deleted people,
 * so the job needs no stop button of its own.
 */
public with sharing class EmptyHouseholdTidyScheduler implements Schedulable {
    /** The name the scheduled job carries, so it is found again rather than doubled. */
    public static final String JOB_NAME = 'BarnCRM Empty Household Tidy-up';

    /** A quarter to two: after the import row cleanup at 1:15, clear of the rollups at 2:00. */
    private static final String NIGHTLY_CRON = '0 45 1 * * ?';

    public void execute(SchedulableContext context) {
        Database.executeBatch(new EmptyHouseholdTidyBatch(), EmptyHouseholdTidyBatch.CHUNK_SIZE);
    }

    /** Starts the nightly tidy-up, or does nothing when it is already scheduled. */
    public static Id start() {
        Id existing = ScheduledJobSelector.triggerIdByName(JOB_NAME);
        if (existing != null) {
            return existing;
        }
        return ScheduledJobSelector.schedule(
            JOB_NAME,
            NIGHTLY_CRON,
            new EmptyHouseholdTidyScheduler()
        );
    }

    /** True when the nightly tidy-up is scheduled. */
    public static Boolean isScheduled() {
        return ScheduledJobSelector.triggerIdByName(JOB_NAME) != null;
    }
}
