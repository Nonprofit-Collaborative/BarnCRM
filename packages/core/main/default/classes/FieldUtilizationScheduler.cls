/**
 * The weekly field utilization count's schedule, started and stopped from the Field
 * Utilization page of the settings console (ADR-0038 shape, ADR-NEXT
 * field-utilization-ships-in-core).
 */
public with sharing class FieldUtilizationScheduler implements Schedulable {
    /** The name the scheduled job carries, so the page and Health Check can find it. */
    public static final String JOB_NAME = 'BarnCRM Field Utilization';

    /** Sundays at 4:00 AM, clear of the nightly jobs between 12:30 and 3:00 AM. */
    private static final String WEEKLY_CRON = '0 0 4 ? * SUN';

    public void execute(SchedulableContext context) {
        runNow();
    }

    /** Starts the weekly count, or returns the job that is already scheduled. */
    public static Id start() {
        Id existing = ScheduledJobSelector.triggerIdByName(JOB_NAME);
        if (existing != null) {
            return existing;
        }
        return System.schedule(JOB_NAME, WEEKLY_CRON, new FieldUtilizationScheduler());
    }

    /** Stops the weekly count. Saved counts stay. */
    public static void stop() {
        Id existing = ScheduledJobSelector.triggerIdByName(JOB_NAME);
        if (existing != null) {
            System.abortJob(existing);
        }
    }

    /** Counts now, without waiting for Sunday. */
    public static Id runNow() {
        return Database.executeBatch(new FieldUtilizationBatch(), FieldUtilizationBatch.CHUNK_SIZE);
    }

    /** True when the weekly count is scheduled. */
    public static Boolean isScheduled() {
        return ScheduledJobSelector.triggerIdByName(JOB_NAME) != null;
    }

    /** When the weekly count is next due, or null. */
    public static Datetime nextRunAt() {
        return ScheduledJobSelector.nextFireTime(JOB_NAME);
    }
}
