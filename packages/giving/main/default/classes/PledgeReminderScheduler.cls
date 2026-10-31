/**
 * The nightly pledge reminder run's schedule, and the toggle on the Pledge Reminders page that
 * starts and stops it.
 *
 * Like the acknowledgment send (ADR-0032), this is an administrator's schedule, so it lives on
 * her page rather than in a module turn-on step. Scheduling it is not the same as turning
 * reminders on: `Pledge_Reminders_Enabled__c` is off by default, and a scheduled run with the
 * setting off does nothing at all.
 */
public with sharing class PledgeReminderScheduler implements Schedulable {
    /** The name the scheduled job carries, so the page can find it again. */
    public static final String JOB_NAME = 'BarnCRM Giving: pledge reminders';

    /**
     * Three fifteen in the morning: after the installment overdue pass, so an installment that
     * went overdue overnight carries its status before the donor hears about it.
     */
    private static final String NIGHTLY_CRON = '0 15 3 * * ?';

    private static final String LOG_CONTEXT = 'PledgeReminderScheduler.execute';

    public void execute(SchedulableContext context) {
        try {
            if (!PledgeReminderService.isEnabled()) {
                // Switched off since the schedule was started. Nothing to do, and nothing wrong.
                return;
            }
            Database.executeBatch(new PledgeReminderBatch(), PledgeReminderBatch.SCOPE);
        } catch (Exception nightlyFailure) {
            // A scheduled job's exception goes nowhere a person will ever look, so it goes here.
            ErrorLogger.log(nightlyFailure, LOG_CONTEXT);
        }
    }

    /** Starts the nightly run, or does nothing when it is already scheduled. */
    public static Id start() {
        Id existing = scheduledJobId();
        if (existing != null) {
            return existing;
        }
        return ScheduledJobSelector.schedule(JOB_NAME, NIGHTLY_CRON, new PledgeReminderScheduler());
    }

    /** Stops the nightly run. The log stays exactly as it is. */
    public static void stop() {
        Id existing = scheduledJobId();
        if (existing != null) {
            ScheduledJobSelector.abort(existing);
        }
    }

    /** True when the nightly run is scheduled. */
    public static Boolean isScheduled() {
        return scheduledJobId() != null;
    }

    /** When the nightly run is next due, or null when it is not scheduled. */
    public static Datetime nextRunAt() {
        return ScheduledJobSelector.nextFireTime(JOB_NAME);
    }

    private static Id scheduledJobId() {
        return ScheduledJobSelector.triggerIdByName(JOB_NAME);
    }
}
