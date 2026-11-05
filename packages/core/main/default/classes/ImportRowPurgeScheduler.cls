/**
 * The Import row cleanup (R-IR5), a step of the nightly run at 1:15 (ADR-0166
 * nightly-job-dispatcher). When rows are deleted is the Import setting Delete Import Rows; Never
 * keeps them, so the step needs no switch of its own.
 *
 * Still schedulable: an org upgraded from before the nightly run may have this job scheduled on
 * its own, and when it fires it adopts the old schedules (R-NJ5) and does tonight's work.
 */
public with sharing class ImportRowPurgeScheduler implements Schedulable {
    /** The name the job was scheduled under, now the step's key. */
    public static final String JOB_NAME = 'BarnCRM Import Row Cleanup';

    public void execute(SchedulableContext context) {
        if (context != null) {
            NightlyJobs.adoptOldSchedules();
        }
        Database.executeBatch(new ImportRowPurgeBatch(), ImportRowPurgeBatch.CHUNK_SIZE);
    }

    /** Makes sure the nightly run, which does the cleanup, is scheduled. */
    public static Id start() {
        return NightlyJobs.start();
    }

    /** True when the nightly run, which does the cleanup, is scheduled. */
    public static Boolean isScheduled() {
        return NightlyJobs.isScheduled();
    }

    /** The cleanup as a step of the nightly run: a quarter past one. */
    public static NightlyStep step() {
        return new NightlyStep(
            JOB_NAME,
            System.Label.Core_HealthCheck_JobImportRows,
            1,
            15,
            new ImportRowPurgeScheduler()
        );
    }
}
