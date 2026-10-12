/**
 * The Giving module's three nightly jobs, and the schedule an administrator starts and stops
 * from the Nightly Jobs page of the Nonprofit Settings console (ADR-0038).
 *
 * The schedule is an administrator's, not Setup's. Until this page existed nothing called
 * `scheduleAll` outside its own test, so in a real org no recurring schedule was ever topped up
 * and no installment was ever marked Overdue: the jobs were built, shipped, and never started.
 *
 * All three jobs are safe to run twice on the same day: topping up a schedule adds only the
 * installments that are missing, and marking overdue and placing donors on their giving level
 * are both recalculations.
 */
public with sharing class GivingScheduler {
    /** The names the scheduled jobs carry, so the settings page can find them again. */
    public static final String TOP_UP_JOB_NAME = 'BarnCRM Giving: installment top up';
    public static final String OVERDUE_JOB_NAME = 'BarnCRM Giving: installments overdue';
    public static final String LEVELS_JOB_NAME = 'BarnCRM Giving: donor levels';

    /**
     * The times, and why they are these times. The top up runs first so the overdue pass sees
     * every payment it created, and the donor level pass runs an hour after the rollups start at
     * 02:00, because the ladder reads a giving total the rollups maintain and fifteen minutes was
     * not long enough to call that settled. Nothing here shares an hour with the rollups at 02:00
     * or with the seasonal address swap at 00:30 (ADR-0038).
     */
    private static final String TOP_UP_CRON = '0 15 1 * * ?';
    private static final String OVERDUE_CRON = '0 45 1 * * ?';
    private static final String LEVELS_CRON = '0 0 3 * * ?';

    /** The scheduled Apex job type, which is what CronJobDetail calls a scheduled class. */
    private static final String SCHEDULED_APEX = '7';

    /** What the settings page knows about one of the three jobs. */
    public class JobStatus {
        public String jobName;
        public Boolean scheduled = false;
        public Datetime nextRunAt;
        /**
         * When the platform last fired this job, which is not when the job last finished. The
         * two together are how the page tells "fired and recorded nothing" from "never fired".
         */
        public Datetime previousFireTime;
    }

    /**
     * Schedules all three nightly jobs and returns the identifiers of the jobs that are now
     * scheduled, so the caller can show what it started.
     *
     * A job already scheduled under the same name is left exactly as it is and its identifier is
     * returned. The check is a query rather than a caught duplicate name exception, because an
     * administrator pressing the button twice is ordinary and must not fill the Error Log.
     */
    public static List<Id> scheduleAll() {
        Map<String, JobStatus> current = statuses();
        List<Id> jobIds = new List<Id>();
        addIfNotNull(
            jobIds,
            scheduleJob(current, TOP_UP_JOB_NAME, TOP_UP_CRON, new InstallmentTopUpSchedulable())
        );
        addIfNotNull(
            jobIds,
            scheduleJob(current, OVERDUE_JOB_NAME, OVERDUE_CRON, new InstallmentSchedulable())
        );
        addIfNotNull(
            jobIds,
            scheduleJob(current, LEVELS_JOB_NAME, LEVELS_CRON, new DonorLevelSchedulable())
        );
        return jobIds;
    }

    /**
     * Stops all three nightly jobs. Nothing already generated, marked Overdue or placed on a
     * level is changed: the schedules simply stop being extended and nothing new is marked.
     */
    public static void stopAll() {
        for (CronTrigger job : jobTriggers()) {
            try {
                System.abortJob(job.Id);
            } catch (Exception abortFailure) {
                // A job somebody else has already aborted, or a user who may not abort Apex.
                ErrorLogger.log(abortFailure, 'GivingScheduler.stopAll');
            }
        }
    }

    /**
     * True when all three jobs are scheduled. Two out of three is not "on": the overdue pass
     * without the top up marks payments overdue on a schedule nothing is extending, so the page
     * offers Schedule in that state and `scheduleAll` fills in whichever job is missing.
     */
    public static Boolean isScheduled() {
        Map<String, JobStatus> current = statuses();
        for (String jobName : jobNames()) {
            if (current.get(jobName).scheduled != true) {
                return false;
            }
        }
        return true;
    }

    /** When the next of the three jobs is due, or null when none of them is scheduled. */
    public static Datetime nextRunAt() {
        Datetime earliest = null;
        for (JobStatus status : statuses().values()) {
            if (status.nextRunAt == null) {
                continue;
            }
            if (earliest == null || status.nextRunAt < earliest) {
                earliest = status.nextRunAt;
            }
        }
        return earliest;
    }

    /**
     * Starts the top up and the overdue pass now, without waiting for tonight. Donor levels are
     * not included: that pass has its own Recalculate now button on the Donor Levels page, and a
     * second button for the same work is a second thing to keep true (ADR-0038).
     */
    public static void runNow() {
        new InstallmentTopUpSchedulable().execute(null);
        new InstallmentSchedulable().execute(null);
    }

    /** What is scheduled right now, by job name, with an entry for every job whether or not it is. */
    public static Map<String, JobStatus> statuses() {
        Map<String, JobStatus> byName = new Map<String, JobStatus>();
        for (String jobName : jobNames()) {
            JobStatus status = new JobStatus();
            status.jobName = jobName;
            byName.put(jobName, status);
        }
        for (CronTrigger job : jobTriggers()) {
            JobStatus status = byName.get(job.CronJobDetail.Name);
            if (status == null) {
                continue;
            }
            status.scheduled = true;
            status.nextRunAt = job.NextFireTime;
            status.previousFireTime = job.PreviousFireTime;
        }
        return byName;
    }

    private static List<String> jobNames() {
        return new List<String>{ TOP_UP_JOB_NAME, OVERDUE_JOB_NAME, LEVELS_JOB_NAME };
    }

    private static List<CronTrigger> jobTriggers() {
        List<String> names = jobNames();
        return [
            SELECT Id, NextFireTime, PreviousFireTime, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name IN :names AND CronJobDetail.JobType = :SCHEDULED_APEX
            WITH SYSTEM_MODE
            LIMIT 10
        ];
    }

    private static Id scheduleJob(
        Map<String, JobStatus> current,
        String jobName,
        String cron,
        Schedulable job
    ) {
        try {
            JobStatus status = current.get(jobName);
            if (status != null && status.scheduled == true) {
                return null;
            }
            return System.schedule(jobName, cron, job);
        } catch (Exception scheduleFailure) {
            // The running user cannot schedule Apex, or the job was scheduled between the
            // query above and this line. Either way the rest of the jobs still get their turn.
            ErrorLogger.log(scheduleFailure, 'GivingScheduler.' + jobName);
            return null;
        }
    }

    private static void addIfNotNull(List<Id> jobIds, Id jobId) {
        if (jobId != null) {
            jobIds.add(jobId);
        }
    }
}
