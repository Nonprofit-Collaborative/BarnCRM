/**
 * The Volunteers nightly job: at 3:00 AM it starts `ShiftScheduleBatch`, which keeps every
 * active recurring schedule's shifts created to the horizon (R-SSC3). Health Check's "Schedule
 * all nightly jobs" fix schedules it through `VolunteersNightlyJobProvider`.
 *
 * Nothing runs while the module is turned off; an Info entry says the run was skipped, and the
 * schedule stays, so the first night after it is turned back on catches up.
 *
 * A separate class from the batch, so a change to the batch deploys while the job is scheduled.
 */
public with sharing class VolunteersScheduler implements Schedulable {
    /** The name the scheduled job carries, so it can be found again. */
    public static final String JOB_NAME = 'BarnCRM Volunteer Schedules';

    /**
     * The name in use. A test gives it a name of its own, because the org a test runs in may
     * already have the nightly job, which a test can neither see past nor stop.
     */
    @TestVisible
    private static String jobNameInUse = JOB_NAME;

    /** Three in the morning: after the 2:00 AM rollups, before the day's sign-ups. */
    private static final String NIGHTLY_CRON = '0 0 3 * * ?';

    public void execute(SchedulableContext context) {
        if (ShiftScheduleService.isTurnedOff()) {
            ErrorLogger.logMessage(
                System.Label.Volunteers_Schedules_SkippedTurnedOff,
                'VolunteersScheduler',
                ErrorLogger.SEVERITY_INFO
            );
            return;
        }
        ShiftScheduleBatch.startNightly();
    }

    /** The nightly job as Health Check's nightly jobs list sees it (ADR-0075). */
    public static NightlyJob nightlyJob() {
        return new NamedNightlyJob(
            System.Label.Volunteers_NightlyJobs_SchedulesName,
            jobNameInUse,
            NIGHTLY_CRON,
            new VolunteersScheduler()
        );
    }
}
