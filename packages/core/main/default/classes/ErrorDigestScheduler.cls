/**
 * The daily Error Log run (C-23, R-E5, R-E6): a step of the nightly run at 07:00 (ADR-0166
 * nightly-job-dispatcher), switched on and off from the Error Log page of the BarnCRM Settings
 * console. It deletes entries past their retention and sends the digest when one is due, so
 * changing the frequency from daily to weekly never needs the schedule changed.
 *
 * Still schedulable: an org upgraded from before the nightly run may have this job scheduled on
 * its own, and when it fires it adopts the old schedules (R-NJ5) and does today's work.
 */
public with sharing class ErrorDigestScheduler implements Schedulable {
    /** The name the job was scheduled under, now the step's key. */
    public static final String JOB_NAME = 'BarnCRM Error Digest';

    public void execute(SchedulableContext context) {
        if (context != null) {
            NightlyJobs.adoptOldSchedules();
        }
        // The daily Error Log run also deletes entries past their retention (R-E6). Its own
        // try, so neither half stops the other.
        try {
            ErrorLogRetention.start();
        } catch (Exception failed) {
            ErrorLogger.log(failed, 'Error Log retention');
        }
        try {
            ErrorDigestService.runScheduled();
        } catch (Exception failed) {
            ErrorLogger.log(failed, 'Error digest');
        }
    }

    /** Switches the daily run on, scheduling the nightly run when it is not. */
    public static Id start() {
        return NightlyJobs.turnOn(JOB_NAME);
    }

    /** Switches the daily run off. Nothing already sent is affected. */
    public static void stop() {
        NightlyJobs.turnOff(JOB_NAME);
    }

    /** True when the daily run is switched on and the nightly run is scheduled. */
    public static Boolean isScheduled() {
        return NightlyJobs.isStepScheduled(JOB_NAME, true);
    }

    /**
     * The daily run as a step of the nightly run: seven in the morning, after the night's other
     * steps, so a failure in any of them is in the digest read with the morning coffee.
     */
    public static NightlyStep step() {
        return new NightlyStep(
                JOB_NAME,
                System.Label.Core_HealthCheck_JobErrorDigest,
                7,
                0,
                new ErrorDigestScheduler()
            )
            .withSwitch(true);
    }

    /** When the digest step runs next, or null when it is not scheduled. */
    public static Datetime nextRunAt() {
        return isScheduled() ? NightlyJobs.nextRunAt(step()) : null;
    }
}
