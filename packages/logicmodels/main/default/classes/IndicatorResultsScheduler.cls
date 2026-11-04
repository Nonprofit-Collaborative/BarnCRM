/**
 * The Logic Models nightly job (L-03; ADR-0158 `0158-indicator-sources.md`, canonical model
 * R-IN5): at 3:30 AM it starts `IndicatorResultsBatch` for every computed indicator. Health
 * Check's "Schedule all nightly jobs" fix schedules it through `LogicModelsNightlyJobProvider`.
 *
 * A separate class from the batch, so a change to the batch deploys while the job is scheduled.
 */
public with sharing class IndicatorResultsScheduler implements Schedulable {
    /** The name the scheduled job carries, so it can be found again. */
    public static final String JOB_NAME = 'BarnCRM Indicator Results';

    /**
     * The name in use. A test gives it a name of its own, because the org a test runs in may
     * already have the nightly job, which a test can neither see past nor stop.
     */
    @TestVisible
    private static String jobNameInUse = JOB_NAME;

    private static final Integer MAX_INDICATORS = 10000;

    public void execute(SchedulableContext context) {
        if (context != null) {
            // Still scheduled on its own from before the nightly run (R-NJ5).
            NightlyJobs.adoptOldSchedules();
        }
        refreshAll();
    }

    /**
     * Starts working out every computed indicator, one after another. Read in system mode: the
     * job works for the organization, whoever scheduled it.
     *
     * @return the first run's job Id, or null when no indicator is computed
     */
    public static Id refreshAll() {
        List<Id> computed = new List<Id>();
        for (Indicator__c indicator : [
            SELECT Id
            FROM Indicator__c
            WHERE Source__c = :IndicatorSourceService.COMPUTED
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT :MAX_INDICATORS
        ]) {
            computed.add(indicator.Id);
        }
        return IndicatorResultsBatch.run(computed);
    }

    /**
     * The job as a step of the nightly run (ADR-NEXT nightly-job-dispatcher): half past three in
     * the morning, after the rollups and the volunteer schedules.
     */
    public static NightlyStep step() {
        return new NightlyStep(
            jobNameInUse,
            System.Label.LogicModels_NightlyJobs_ResultsName,
            3,
            30,
            new IndicatorResultsScheduler()
        );
    }
}
