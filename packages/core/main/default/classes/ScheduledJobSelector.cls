/**
 * Finds a scheduled Apex job by the name it was scheduled under, and is the one place BarnCRM
 * schedules and aborts its named jobs.
 *
 * Every job BarnCRM schedules carries a fixed name starting "BarnCRM", so pressing a button
 * twice finds the job that is already there instead of relying on the duplicate name exception
 * (ADR-0038). All of them are read in one query the first time any is asked about in a
 * transaction (ADMIN-11): one Health Check run asks about ten to twenty of them, and each
 * scheduler used to make two or three queries of its own. Scheduling or aborting through this
 * class forgets what was read, so a later question in the same transaction sees the change.
 *
 * The setup objects are read in system mode: an administrator without View Setup must still
 * see whether a job the package owns is running, and only the package's own jobs are read.
 */
@NamespaceAccessible
public with sharing class ScheduledJobSelector {
    private static final String NAME_PATTERN = 'BarnCRM%';

    /** The package's scheduled jobs by name, read once per transaction; null until asked. */
    private static Map<String, CronTrigger> byName;

    /** The Id of the trigger behind the named scheduled Apex job, or null when there is none. */
    @NamespaceAccessible
    public static Id triggerIdByName(String jobName) {
        CronTrigger found = triggerByName(jobName);
        return found == null ? null : found.Id;
    }

    /**
     * When the named job runs next, or null when it is not scheduled. A one-time job that has
     * already fired keeps its trigger with no next run, and counts as not scheduled.
     */
    @NamespaceAccessible
    public static Datetime nextFireTime(String jobName) {
        CronTrigger found = triggerByName(jobName);
        return found == null ? null : found.NextFireTime;
    }

    /**
     * The names of the package's scheduled jobs whose owner is no longer active. A scheduled
     * job runs as the person who scheduled it and stops when that user is deactivated, while
     * its trigger stays, so it still reads as scheduled (ADMIN-12).
     */
    @NamespaceAccessible
    public static List<String> namesOwnedByInactiveUsers() {
        Map<String, Id> ownerByName = new Map<String, Id>();
        for (String name : all().keySet()) {
            ownerByName.put(name, ownerOverride != null ? ownerOverride : all().get(name).OwnerId);
        }
        Set<Id> ownerIds = new Set<Id>(ownerByName.values());
        Set<Id> inactive = new Set<Id>();
        if (!ownerIds.isEmpty()) {
            for (User owner : [
                SELECT Id
                FROM User
                WHERE Id IN :ownerIds AND IsActive = FALSE
                WITH SYSTEM_MODE
            ]) {
                inactive.add(owner.Id);
            }
        }
        List<String> names = new List<String>();
        for (String name : ownerByName.keySet()) {
            if (inactive.contains(ownerByName.get(name))) {
                names.add(name);
            }
        }
        names.sort();
        return names;
    }

    /** Schedules a named job and forgets what was read, so the next question sees it. */
    @NamespaceAccessible
    public static Id schedule(String jobName, String cron, Schedulable job) {
        byName = null;
        return System.schedule(jobName, cron, job);
    }

    /** Aborts a scheduled job and forgets what was read. */
    @NamespaceAccessible
    public static void abort(Id triggerId) {
        byName = null;
        System.abortJob(triggerId);
    }

    /** Forgets what was read, for a caller that scheduled or aborted some other way. */
    @NamespaceAccessible
    public static void forget() {
        byName = null;
    }

    /**
     * Test seam: the owner a job is read with, so a test can see a job as owned by an inactive
     * user without deactivating anyone. Null in production.
     */
    @TestVisible
    private static Id ownerOverride;

    private static CronTrigger triggerByName(String jobName) {
        if (String.isBlank(jobName)) {
            return null;
        }
        return all().get(jobName);
    }

    private static Map<String, CronTrigger> all() {
        if (byName == null) {
            byName = new Map<String, CronTrigger>();
            // At most 100 rows: an org may hold only 100 scheduled Apex jobs.
            for (CronTrigger job : [
                SELECT Id, NextFireTime, OwnerId, CronJobDetail.Name
                FROM CronTrigger
                WHERE CronJobDetail.JobType = '7' AND CronJobDetail.Name LIKE :NAME_PATTERN
                WITH SYSTEM_MODE
            ]) {
                byName.put(job.CronJobDetail.Name, job);
            }
        }
        return byName;
    }
}
