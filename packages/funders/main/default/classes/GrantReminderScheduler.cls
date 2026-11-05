/**
 * The Funders morning job (F-02, R-GQ3): at 6:00 AM it starts `GrantReminderBatch`, which reminds
 * the grant requirements coming due. Health Check's "Schedule all nightly jobs" fix schedules it
 * through `FundersNightlyJobProvider`.
 *
 * It stays scheduled while reminders are off and does nothing until a reminder setting is on, so
 * turning a setting on needs no other step.
 *
 * A separate class from the batch, so a change to the batch deploys while the job is scheduled.
 */
public with sharing class GrantReminderScheduler implements Schedulable {
    /** The name the scheduled job carries, so it can be found again. */
    public static final String JOB_NAME = 'BarnCRM Grant Reminders';

    /** A test gives it a name of its own, because the org a test runs in may already have it. */
    @TestVisible
    private static String jobNameInUse = JOB_NAME;

    public void execute(SchedulableContext context) {
        if (context != null) {
            // Still scheduled on its own from before the nightly run (R-NJ5).
            NightlyJobs.adoptOldSchedules();
        }
        GrantReminderBatch.startMorning();
    }

    /**
     * The job as a step of the nightly run (ADR-0166 nightly-job-dispatcher): six in the
     * morning, before the working day.
     */
    public static NightlyStep step() {
        return new NightlyStep(
            jobNameInUse,
            System.Label.Funders_NightlyJobs_RemindersName,
            6,
            0,
            new GrantReminderScheduler()
        );
    }
}
