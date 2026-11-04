/**
 * The Rollup Builder module adds its nightly recalculation to Core's nightly run through the
 * provider Core finds by name (ADR-NEXT nightly-job-dispatcher, ADR-0125): one switched step at
 * the hour the setting holds, which the Rollups page switches on and off.
 */
@IsTest(testFor='ApexClass:RollupsNightlyJobProvider, ApexClass:RollupScheduler')
private class RollupsNightlyJobProviderTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    @IsTest
    static void theNightlyRecalculationIsOneSwitchedStepAtTheNightlyHour() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupScheduler.jobNameInUse = 'BarnCRM Rollups (RollupsNightlyJobProviderTest)';
            TestDataFactory.clearScheduledJobs(new List<String>{ NightlyJobs.jobName() });
            ScheduledJobSelector.forget();
            List<NightlyStep> steps = new RollupsNightlyJobProvider().nightlySteps();

            Assert.areEqual(1, steps.size(), 'The module offers one step.');
            Assert.areEqual(System.Label.Core_JobNotice_Rollups, steps[0].label, 'Its label.');
            Assert.areEqual(RollupScheduler.nightlyHour() * 60, steps[0].minute, 'Its hour.');
            Assert.isTrue(steps[0].switchDefault, 'Shipped on.');
            Assert.isFalse(RollupScheduler.isScheduled(), 'Not before the run is scheduled.');

            // No startTest: the scheduled run must not execute inside the test.
            RollupScheduler.start();
            ScheduledJobSelector.forget();
            NightlyJobs.forget();
            Assert.isTrue(RollupScheduler.isScheduled(), 'On, with the run scheduled.');
            Assert.isNotNull(RollupScheduler.nextRunAt(), 'With its next run.');
            RollupScheduler.stop();
            NightlyJobs.forget();
            Assert.isFalse(RollupScheduler.isScheduled(), 'Switched off.');
        }
    }
}
