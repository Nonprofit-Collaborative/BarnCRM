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

    /** Six in the morning, before the working day. */
    private static final String MORNING_CRON = '0 0 6 * * ?';

    public void execute(SchedulableContext context) {
        GrantReminderBatch.startMorning();
    }

    /** The morning job as Health Check's nightly jobs list sees it (ADR-0075). */
    public static NightlyJob nightlyJob() {
        return new NamedNightlyJob(
            System.Label.Funders_NightlyJobs_RemindersName,
            jobNameInUse,
            MORNING_CRON,
            new GrantReminderScheduler()
        );
    }
}
