/**
 * Finds a scheduled Apex job by the name it was scheduled under.
 *
 * Every job BarnCRM schedules carries a fixed name, so pressing a button twice finds the
 * job that is already there instead of relying on the duplicate name exception (ADR-0038).
 * The two setup objects are read in system mode, as `SeasonalAddressScheduler` reads them: an
 * administrator without View Setup must still see whether a job the package owns is running,
 * and only the package's own job names are ever asked for.
 */
public with sharing class ScheduledJobSelector {
    /** The Id of the trigger behind the named scheduled Apex job, or null when there is none. */
    public static Id triggerIdByName(String jobName) {
        CronTrigger found = triggerByName(jobName);
        return found == null ? null : found.Id;
    }

    /**
     * When the named job runs next, or null when it is not scheduled. A one-time job that has
     * already fired keeps its trigger with no next run, and counts as not scheduled.
     */
    public static Datetime nextFireTime(String jobName) {
        CronTrigger found = triggerByName(jobName);
        return found == null ? null : found.NextFireTime;
    }

    private static CronTrigger triggerByName(String jobName) {
        if (String.isBlank(jobName)) {
            return null;
        }
        List<CronTrigger> triggers = [
            SELECT Id, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName AND CronJobDetail.JobType = '7'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return triggers.isEmpty() ? null : triggers[0];
    }
}
