/**
 * The old Import row cleanup schedule (R-IR5), kept as a shell. The cleanup is now a pass of the
 * nightly Record Cleanup step (`RecordRetentionBatch`, ADR-0166 nightly-job-dispatcher), which
 * follows the Import setting Delete Import Rows; Never keeps the rows.
 *
 * Still schedulable: an org upgraded from before the nightly run may have this job scheduled on
 * its own, and when it fires it adopts the old schedules (R-NJ5), this one included, and the
 * nightly run does the work.
 */
public with sharing class ImportRowPurgeScheduler implements Schedulable {
    /** The name the job was scheduled under; the nightly run adopts it as a retired key. */
    public static final String JOB_NAME = 'BarnCRM Import Row Cleanup';

    public void execute(SchedulableContext context) {
        if (context != null) {
            NightlyJobs.adoptOldSchedules();
        }
    }
}
