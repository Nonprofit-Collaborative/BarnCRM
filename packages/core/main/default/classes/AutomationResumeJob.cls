/**
 * The one-time job that ends a pause on the record (C-23, R-A5, ADR-0055).
 *
 * The comparison with the clock in `AutomationControl.pausedUntil` is what decides whether
 * automation runs, so automation starts again on time whether or not this job runs. What the
 * clock cannot do is write anything: this job clears the stored end and records the resume as
 * a Setting Change, so the audit trail shows every pause with its end.
 *
 * `AutomationControl.pauseAll` schedules it for the moment the pause ends, after checking
 * `Manage_BarnCRM_Settings`; that check is the authorization for what the job does later, as
 * in ADR-0027. `resumeAll` and a second pause cancel it first, so there is never more than one.
 */
public with sharing class AutomationResumeJob implements Schedulable {
    /** The name the job carries, so it can be found, replaced and cancelled. */
    public static final String JOB_NAME = 'BarnCRM Automation Resume';

    private static final String LOG_CONTEXT = 'Automation pause: automatic resume';

    /**
     * The end of the pause this job was scheduled for. The job clears that pause and no other:
     * if an administrator paused again after this job was set, the stored end differs and the
     * newer pause is left to its own job.
     */
    private final Datetime pauseEnds;

    public AutomationResumeJob(Datetime pauseEnds) {
        this.pauseEnds = pauseEnds;
    }

    public void execute(SchedulableContext context) {
        try {
            if (pauseEnds != null && System.now() < pauseEnds) {
                // Fired before the end (a clock change can do that): wait for the end rather
                // than going away and leaving the pause with nothing to record its end.
                scheduleAt(pauseEnds);
                return;
            }
            AutomationControl.resumeExpiredPause(pauseEnds);
        } catch (Exception failed) {
            ErrorLogger.log(failed, LOG_CONTEXT);
        }
        // A one-time job keeps its trigger after it fires. Removing it frees the name for the
        // next pause and keeps a spent job out of the org's 100 scheduled jobs.
        if (context != null) {
            try {
                System.abortJob(context.getTriggerId());
            } catch (Exception failed) {
                ErrorLogger.log(failed, LOG_CONTEXT);
            }
        }
    }

    /**
     * Schedules the resume for the given end, replacing any resume already scheduled. The cron
     * expression has whole seconds and the end has milliseconds, so the job is set one second
     * later: a job that fired a fraction of a second before the end would find the pause still
     * running and leave it alone.
     */
    public static Id scheduleAt(Datetime pauseEnds) {
        return schedule(pauseEnds, pauseEnds.addSeconds(1));
    }

    /** Schedules the resume of the pause ending at `pauseEnds` to run at `runAt`. */
    @TestVisible
    private static Id schedule(Datetime pauseEnds, Datetime runAt) {
        cancel();
        return System.schedule(JOB_NAME, cronFor(runAt), new AutomationResumeJob(pauseEnds));
    }

    /** Cancels the scheduled resume, if there is one. */
    public static void cancel() {
        Id existing = ScheduledJobSelector.triggerIdByName(JOB_NAME);
        if (existing != null) {
            System.abortJob(existing);
        }
    }

    /** When the resume is scheduled to run, or null when nothing is going to end the pause. */
    public static Datetime scheduledAt() {
        return ScheduledJobSelector.nextFireTime(JOB_NAME);
    }

    /**
     * A cron expression for one moment. Both this format and `System.schedule` use the running
     * user's time zone, so the two agree whatever it is.
     */
    @TestVisible
    private static String cronFor(Datetime moment) {
        return moment.format('s m H d M \'?\' yyyy');
    }
}
