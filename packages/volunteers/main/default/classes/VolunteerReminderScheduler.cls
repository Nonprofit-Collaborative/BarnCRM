/**
 * The Volunteers morning job (V-10): at 7:00 AM it starts `VolunteerReminderBatch`, which emails
 * the shift reminders due. Health Check's "Schedule all nightly jobs" fix schedules it through
 * `VolunteersNightlyJobProvider`.
 *
 * It stays scheduled while reminders are off and does nothing until the Send Shift Reminders
 * setting is turned on, so turning the setting on needs no other step.
 *
 * A separate class from the batch, so a change to the batch deploys while the job is scheduled.
 */
public with sharing class VolunteerReminderScheduler implements Schedulable {
    /** The name the scheduled job carries, so it can be found again. */
    public static final String JOB_NAME = 'BarnCRM Volunteer Reminders';

    /** A test gives it a name of its own, because the org a test runs in may already have it. */
    @TestVisible
    private static String jobNameInUse = JOB_NAME;

    /** Seven in the morning: after the 3:00 AM shift run has created the day's shifts. */
    private static final String MORNING_CRON = '0 0 7 * * ?';

    public void execute(SchedulableContext context) {
        VolunteerReminderBatch.startMorning();
    }

    /** The morning job as Health Check's nightly jobs list sees it (ADR-0075). */
    public static NightlyJob nightlyJob() {
        return new NamedNightlyJob(
            System.Label.Volunteers_NightlyJobs_RemindersName,
            jobNameInUse,
            MORNING_CRON,
            new VolunteerReminderScheduler()
        );
    }
}
