/**
 * The empty household tidy-up (R-H12a, ADR-0120), a step of the nightly run at 1:45 (ADR-0166
 * nightly-job-dispatcher). Whether it removes anything is the Households setting Keep the
 * households of deleted people, so the step needs no switch of its own.
 *
 * Still schedulable: an org upgraded from before the nightly run may have this job scheduled on
 * its own, and when it fires it adopts the old schedules (R-NJ5) and does tonight's work.
 */
public with sharing class EmptyHouseholdTidyScheduler implements Schedulable {
    /** The name the job was scheduled under, now the step's key. */
    public static final String JOB_NAME = 'BarnCRM Empty Household Tidy-up';

    public void execute(SchedulableContext context) {
        if (context != null) {
            NightlyJobs.adoptOldSchedules();
        }
        Database.executeBatch(new EmptyHouseholdTidyBatch(), EmptyHouseholdTidyBatch.CHUNK_SIZE);
    }

    /** The tidy-up as a step of the nightly run: a quarter to two, after the import cleanup. */
    public static NightlyStep step() {
        return new NightlyStep(
            JOB_NAME,
            System.Label.Core_HealthCheck_JobEmptyHouseholds,
            1,
            45,
            new EmptyHouseholdTidyScheduler()
        );
    }
}
