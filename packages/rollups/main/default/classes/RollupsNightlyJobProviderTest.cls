/**
 * The Rollup Builder module hands Health Check its nightly recalculation through the provider
 * Core finds by name (ADR-0075, ADR-NEXT `NEXT-rollup-builder-module.md`), so "Schedule all
 * nightly jobs" counts and schedules it. The job runs under a name of its own, so the test does
 * not depend on what the org it runs in has scheduled.
 */
@IsTest(testFor='ApexClass:RollupsNightlyJobProvider')
private class RollupsNightlyJobProviderTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    @IsTest
    static void theNightlyRecalculationIsOfferedAndScheduledOnce() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupScheduler.jobNameInUse = 'BarnCRM Rollups (RollupsNightlyJobProviderTest)';
            List<NightlyJob> jobs = new RollupsNightlyJobProvider().nightlyJobs();

            Assert.areEqual(1, jobs.size(), 'The module offers one nightly job.');
            NightlyJob job = jobs[0];
            Assert.areEqual(
                System.Label.Core_HealthCheck_JobRollups,
                job.label(),
                'Named from a label.'
            );
            Assert.isFalse(job.isScheduled(), 'Not scheduled before the fix.');

            // No startTest: the scheduled run must not execute inside the test.
            job.schedule();

            Assert.isTrue(job.isScheduled(), 'Scheduled by the fix.');
        }
    }
}
