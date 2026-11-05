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
    public static final String JOB_NAME = 'BarnCRM Giving Pledge Reminders';

    private static final String LOG_CONTEXT = 'PledgeReminderScheduler.execute';

    public void execute(SchedulableContext context) {
        if (context != null) {
            // Still scheduled on its own from before the nightly run (R-NJ5).
            NightlyJobs.adoptOldSchedules();
        }
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

    /** Switches the reminder run on, scheduling the nightly run when it is not (R-NJ4). */
    public static Id start() {
        return NightlyJobs.turnOn(JOB_NAME);
    }

    /** Switches the reminder run off. The log stays exactly as it is. */
    public static void stop() {
        NightlyJobs.turnOff(JOB_NAME);
    }

    /** True when the reminder run is switched on and the nightly run is scheduled. */
    public static Boolean isScheduled() {
        return NightlyJobs.isStepScheduled(JOB_NAME, false);
    }

    /** When the reminder run is next due, or null when it is not scheduled. */
    public static Datetime nextRunAt() {
        return isScheduled() ? NightlyJobs.nextRunAt(step()) : null;
    }

    /**
     * The reminders as a step of the nightly run (ADR-0166 nightly-job-dispatcher): three
     * fifteen, after the installment overdue pass, so an installment that went overdue overnight
     * carries its status before the donor hears about it. Shipped off: it emails donors.
     */
    public static NightlyStep step() {
        return new NightlyStep(
                JOB_NAME,
                System.Label.Giving_PledgeReminders_Title,
                3,
                15,
                new PledgeReminderScheduler()
            )
            .withSwitch(false);
    }
}
