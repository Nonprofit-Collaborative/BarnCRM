/**
 * The nightly email send's schedule, and the toggle on the Acknowledgments page that starts and
 * stops it.
 *
 * This follows C-18 rather than `GivingScheduler` on purpose (ADR-0032). `GivingScheduler` is
 * called by a module turn-on step that does not exist, so the jobs it knows about are scheduled
 * in no real org. A job with no in-app way to schedule it is a job nobody schedules, and this
 * package already has three of those. The schedule is an administrator's, so it lives on her
 * page.
 *
 * The nightly send is off by default. Most organizations want to look at the queue for the first
 * month, and a package that started mailing donors on install would deserve everything it got.
 */
public with sharing class AcknowledgmentScheduler implements Schedulable {
    /** The name the scheduled job carries, so the page can find it again. */
    public static final String JOB_NAME = 'BarnCRM Giving: acknowledgments';

    /**
     * Quarter to three in the morning: after the installment top up, the overdue pass and the
     * donor levels, so a gift that arrived overnight has its totals and its level before the
     * donor is thanked for it.
     */
    private static final String NIGHTLY_CRON = '0 45 2 * * ?';

    private static final String LOG_CONTEXT = 'AcknowledgmentScheduler.execute';

    public void execute(SchedulableContext context) {
        try {
            if (!AcknowledgmentService.isEnabled()) {
                // Switched off since the schedule was started. Nothing to do, and nothing wrong.
                return;
            }
            AcknowledgmentRunService.startEmailRun();
        } catch (Exception nightlyFailure) {
            // A scheduled job's exception goes nowhere a person will ever look, so it goes here.
            ErrorLogger.log(nightlyFailure, LOG_CONTEXT);
        }
    }

    /** Starts the nightly send, or does nothing when it is already scheduled. */
    public static Id start() {
        Id existing = scheduledJobId();
        if (existing != null) {
            return existing;
        }
        return System.schedule(JOB_NAME, NIGHTLY_CRON, new AcknowledgmentScheduler());
    }

    /** Stops the nightly send. The queue stays exactly as it is. */
    public static void stop() {
        Id existing = scheduledJobId();
        if (existing != null) {
            System.abortJob(existing);
        }
    }

    /** True when the nightly send is scheduled. */
    public static Boolean isScheduled() {
        return scheduledJobId() != null;
    }

    /** When the nightly send is next due, or null when it is not scheduled. */
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
