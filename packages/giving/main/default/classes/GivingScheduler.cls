/**
 * The Giving module's four nightly jobs, switched on and off together from the Nightly Jobs page
 * of the BarnCRM Settings console (ADR-0038). Each is a step of Core's one nightly run (ADR-0166
 * nightly-job-dispatcher), keyed by the name it was once scheduled under, so an upgrade adopts
 * the old schedule (R-NJ5).
 *
 * All four are safe to run twice on the same day: topping up a schedule adds only the
 * installments that are missing, and marking overdue, placing donors on their giving level and
 * the ask reminders are all recalculations or skip what is already done.
 */
public with sharing class GivingScheduler {
    /** The names the jobs were scheduled under, now their step keys. */
    public static final String TOP_UP_JOB_NAME = 'BarnCRM Giving Installment Top Up';
    public static final String OVERDUE_JOB_NAME = 'BarnCRM Giving Installments Overdue';
    public static final String LEVELS_JOB_NAME = 'BarnCRM Giving Donor Levels';
    public static final String ASK_JOB_NAME = 'BarnCRM Giving Ask Reminders';

    /** What the settings page knows about one of the four jobs. */
    public class JobStatus {
        public String jobName;
        public Boolean scheduled = false;
        public Datetime nextRunAt;
        /**
         * When the nightly run last started this job, which is not when the job last finished.
         * The two together are how the page tells "started and recorded nothing" from "never
         * started".
         */
        public Datetime previousFireTime;
    }

    /**
     * The four jobs as steps of the nightly run. The times, and why they are these times: the
     * top up runs first so the overdue pass sees every payment it created, and the donor level
     * pass runs an hour after the rollups at 02:00, because the ladder reads a giving total the
     * rollups maintain. The ask reminders follow half an hour later, on settled data (G-29). The
     * nightly run also never starts a step before the one before it has finished.
     */
    public static List<NightlyStep> steps() {
        return new List<NightlyStep>{
            new NightlyStep(
                    TOP_UP_JOB_NAME,
                    System.Label.Giving_NightlyJobs_TopUpName,
                    1,
                    15,
                    new InstallmentTopUpSchedulable()
                )
                .withSwitch(true),
            new NightlyStep(
                    OVERDUE_JOB_NAME,
                    System.Label.Giving_NightlyJobs_OverdueName,
                    1,
                    45,
                    new InstallmentSchedulable()
                )
                .withSwitch(true),
            new NightlyStep(
                    LEVELS_JOB_NAME,
                    System.Label.Giving_NightlyJobs_LevelsName,
                    3,
                    0,
                    new DonorLevelSchedulable()
                )
                .withSwitch(true),
            new NightlyStep(
                    ASK_JOB_NAME,
                    System.Label.Giving_NightlyJobs_AskRemindersName,
                    3,
                    30,
                    new AskReminderSchedulable()
                )
                .withSwitch(true)
        };
    }

    /**
     * Switches all four jobs on and makes sure the nightly run is scheduled. Returns the run's
     * trigger Id, once.
     */
    public static List<Id> scheduleAll() {
        Id runId;
        for (String jobName : jobNames()) {
            runId = NightlyJobs.turnOn(jobName);
        }
        return runId == null ? new List<Id>() : new List<Id>{ runId };
    }

    /** True when the job with this name is switched on and the nightly run is scheduled. */
    public static Boolean isJobScheduled(String jobName) {
        return jobNames().contains(jobName) && NightlyJobs.isStepScheduled(jobName, true);
    }

    /**
     * Switches just the one job with this name on, doing nothing for a name that is not one of
     * the four.
     */
    public static void scheduleJobNamed(String jobName) {
        if (jobNames().contains(jobName)) {
            NightlyJobs.turnOn(jobName);
        }
    }

    /**
     * Switches all four jobs off. Nothing already generated, marked Overdue or placed on a level
     * is changed. The nightly run stays scheduled for the other steps.
     */
    public static void stopAll() {
        for (String jobName : jobNames()) {
            NightlyJobs.turnOff(jobName);
        }
    }

    /**
     * True when all four jobs are on. Three out of four is not "on": the overdue pass without the
     * top up marks payments overdue on a schedule nothing is extending, so the page offers
     * Schedule in that state and `scheduleAll` switches on whichever job is off.
     */
    public static Boolean isScheduled() {
        for (JobStatus status : statuses().values()) {
            if (status.scheduled != true) {
                return false;
            }
        }
        return true;
    }

    /** When the next of the four jobs is due, or null when none of them is on. */
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
        // Safe to repeat: a donor already reminded for its date is skipped, and it does nothing
        // while the setting is off (G-29).
        new AskReminderSchedulable().execute(null);
    }

    /** Each of the four jobs by name: whether it is on, when it runs next and last started. */
    public static Map<String, JobStatus> statuses() {
        Map<String, JobStatus> byName = new Map<String, JobStatus>();
        Boolean runScheduled = NightlyJobs.isScheduled();
        for (NightlyStep step : steps()) {
            JobStatus status = new JobStatus();
            status.jobName = step.key;
            status.scheduled = runScheduled && NightlyJobs.isSwitchedOn(step.key, true);
            status.nextRunAt = status.scheduled ? NightlyJobs.nextRunAt(step) : null;
            status.previousFireTime = NightlyJobs.lastStarted(step.key);
            byName.put(step.key, status);
        }
        return byName;
    }

    private static List<String> jobNames() {
        return new List<String>{ TOP_UP_JOB_NAME, OVERDUE_JOB_NAME, LEVELS_JOB_NAME, ASK_JOB_NAME };
    }
}
