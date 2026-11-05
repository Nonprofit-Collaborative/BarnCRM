/**
 * BarnCRM's nightly run as everything but the run itself sees it (ADR-0166
 * nightly-job-dispatcher, R-NJ1 to R-NJ5): the steps in order, their switches, the one schedule,
 * Health Check's view of it, and adopting the separate schedules of an earlier version. Every
 * test supplies its module steps in memory and schedules under the test name of the run, so none
 * depends on what the org it runs in has installed or scheduled.
 */
@IsTest(testFor='ApexClass:NightlyJobs, ApexClass:NightlyStep')
private class NightlyJobsTest {
    private static final String OLD_A = 'BarnCRM Nightly Test Old A';
    private static final String OLD_B = 'BarnCRM Nightly Test Old B';

    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** Work that only counts how often it ran. */
    private class CountingWork implements Schedulable {
        public Integer runs = 0;
        public void execute(SchedulableContext context) {
            runs++;
        }
    }

    private class FakeProvider implements NightlyStepProvider {
        private final List<NightlyStep> steps;
        FakeProvider(List<NightlyStep> steps) {
            this.steps = steps;
        }
        public List<NightlyStep> nightlySteps() {
            return steps;
        }
    }

    private class BrokenProvider implements NightlyStepProvider {
        public List<NightlyStep> nightlySteps() {
            throw new System.NullPointerException();
        }
    }

    /** Every module provider replaced: the first gives `steps`, the second throws. */
    private static void modulesGive(List<NightlyStep> steps) {
        for (String className : NightlyJobs.PROVIDER_CLASSES) {
            NightlyJobs.providerOverrides.put(className, new FakeProvider(new List<NightlyStep>()));
        }
        NightlyJobs.providerOverrides.put(NightlyJobs.PROVIDER_CLASSES[0], new FakeProvider(steps));
        NightlyJobs.providerOverrides.put(NightlyJobs.PROVIDER_CLASSES[1], new BrokenProvider());
        NightlyJobs.forget();
    }

    private static List<String> keys(List<NightlyStep> steps) {
        List<String> found = new List<String>();
        for (NightlyStep step : steps) {
            found.add(step.key);
        }
        return found;
    }

    @IsTest
    static void stepsRunInTimeOrderAndAModuleThatFailsIsSkipped() {
        System.runAs(TestUsers.admin()) {
            modulesGive(
                new List<NightlyStep>{
                    new NightlyStep('BarnCRM Late', 'Late', 3, 0, new CountingWork()),
                    new NightlyStep('BarnCRM Early', 'Early', 0, 10, new CountingWork()),
                    new NightlyStep('BarnCRM Late Too', 'Late too', 3, 0, new CountingWork())
                }
            );

            List<String> order = keys(NightlyJobs.steps());

            Assert.isTrue(
                order.indexOf('BarnCRM Early') < order.indexOf(SeasonalAddressScheduler.JOB_NAME),
                'Ten past midnight comes before the seasonal swap at half past: ' + order
            );
            Assert.isTrue(
                order.indexOf(EmptyHouseholdTidyScheduler.JOB_NAME) < order.indexOf('BarnCRM Late'),
                'A module step at 3:00 comes after Core\'s at 1:45'
            );
            Assert.areEqual(
                order.indexOf('BarnCRM Late') + 1,
                order.indexOf('BarnCRM Late Too'),
                'Steps at the same time keep the order they were registered in'
            );
            Assert.isTrue(
                order.indexOf(ErrorDigestScheduler.JOB_NAME) > order.indexOf('BarnCRM Late'),
                'The digest is last'
            );
            Assert.areEqual('Early', NightlyJobs.step('barncrm  early').label, 'Found by key');
        }
    }

    @IsTest
    static void aSwitchReadsItsShippedValueUntilSavedAndSavingOnSchedulesTheRun() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.clearScheduledJobs(new List<String>{ NightlyJobs.jobName() });
            ScheduledJobSelector.forget();

            Boolean shippedOff = NightlyJobs.isSwitchedOn(OLD_A, false);
            Boolean shippedOn = NightlyJobs.isSwitchedOn(OLD_A, true);
            NightlyJobs.turnOn(OLD_A);
            NightlyJobs.forget();
            Boolean afterOn = NightlyJobs.isStepScheduled(OLD_A, false);
            NightlyJobs.turnOff(OLD_A);
            NightlyJobs.forget();

            Assert.isFalse(shippedOff, 'Shipped off reads off');
            Assert.isTrue(shippedOn, 'Shipped on reads on');
            Assert.isTrue(afterOn, 'Switched on, with the run scheduled');
            Assert.isTrue(NightlyJobs.isScheduled(), 'Switching on scheduled the run');
            Assert.isFalse(NightlyJobs.isSwitchedOn(OLD_A, true), 'Saved off beats shipped on');
            Assert.isTrue(NightlyJobs.isScheduled(), 'The run stays for the other steps');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Nightly_Job__c WHERE Name = :OLD_A],
                'One row per step'
            );
        }
    }

    @IsTest
    static void aStepIsInTonightsRunOnlyWhileItsSettingAndItsSwitchAllowIt() {
        System.runAs(TestUsers.admin()) {
            NightlyStep always = new NightlyStep(OLD_B, 'B', 1, 0, new CountingWork());
            NightlyStep inactive = new NightlyStep(OLD_B, 'B', 1, 0, new CountingWork())
                .activeWhen(false);
            NightlyStep switchedOff = new NightlyStep(OLD_A, 'A', 1, 0, new CountingWork())
                .withSwitch(false);

            Assert.isTrue(NightlyJobs.isOn(always), 'No switch, no setting against it: it runs');
            Assert.isFalse(NightlyJobs.isOn(inactive), 'A setting that has it off');
            Assert.isFalse(NightlyJobs.isOn(switchedOff), 'A switch shipped off');
            Assert.isFalse(NightlyJobs.isOn(null), 'No step');
            Assert.isTrue(switchedOff.hasSwitch(), 'Has a switch');
            Assert.areEqual(60, always.minute, 'One in the morning is minute 60');
        }
    }

    @IsTest
    static void oldSchedulesAreReplacedByTheRunAndKeepTheirSwitchOn() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.clearScheduledJobs(new List<String>{ NightlyJobs.jobName() });
            NightlyJobs.overrideStepsForTest(
                new List<NightlyStep>{
                    new NightlyStep(OLD_A, 'A', 1, 0, new CountingWork()).withSwitch(false),
                    new NightlyStep(OLD_B, 'B', 2, 0, new CountingWork())
                }
            );
            NightlyJobs.adoptInTests = true;
            NightlyRun.chain = false;
            ScheduledJobSelector.schedule(OLD_A, '0 0 1 * * ?', new ErrorDigestScheduler());
            ScheduledJobSelector.schedule(OLD_B, '0 0 2 * * ?', new ErrorDigestScheduler());

            Test.startTest();
            Boolean adopted = NightlyJobs.adoptOldSchedules();
            Boolean again = NightlyJobs.adoptOldSchedules();
            Test.stopTest();

            NightlyJobs.forget();
            Assert.isTrue(adopted, 'Something was adopted');
            Assert.isFalse(again, 'And nothing is left the second time');
            Assert.isFalse(ScheduledJobSelector.isScheduled(OLD_A), 'The old job is gone');
            Assert.isFalse(ScheduledJobSelector.isScheduled(OLD_B), 'So is the other');
            Assert.isTrue(NightlyJobs.isScheduled(), 'The nightly run took their place');
            Assert.isTrue(
                NightlyJobs.isSwitchedOn(OLD_A, false),
                'A step shipped off that was running stays on'
            );
        }
    }

    @IsTest
    static void adoptingDoesNothingInATestThatDidNotAskForIt() {
        System.runAs(TestUsers.admin()) {
            Assert.isFalse(NightlyJobs.adoptOldSchedules(), 'The org\'s real jobs are left alone');
        }
    }

    @IsTest
    static void healthCheckNamesTheMissingRunAndItsFixSchedulesIt() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.clearScheduledJobs(new List<String>{ NightlyJobs.jobName() });
            ScheduledJobSelector.forget();

            NightlyRun.chain = false;
            List<String> missing = NightlyJobs.unscheduledLabels();
            Test.startTest();
            List<String> scheduled = NightlyJobs.scheduleAll();
            Test.stopTest();
            ScheduledJobSelector.forget();

            Assert.isTrue(
                missing.contains(System.Label.Core_NightlyJobs_Title),
                'Named: ' + missing
            );
            Assert.areEqual(missing, scheduled, 'The fix schedules what was named');
            Assert.isTrue(NightlyJobs.unscheduledLabels().isEmpty(), 'Nothing is missing after');
        }
    }

    @IsTest
    static void aStepSaysWhenItRunsNextOnlyWhileTheRunIsScheduled() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.clearScheduledJobs(new List<String>{ NightlyJobs.jobName() });
            ScheduledJobSelector.forget();
            NightlyStep step = new NightlyStep(OLD_B, 'B', 1, 15, new CountingWork());

            Datetime before = NightlyJobs.nextRunAt(step);
            NightlyJobs.start();
            Datetime after = NightlyJobs.nextRunAt(step);

            Assert.isNull(before, 'Not scheduled, so no next run');
            Assert.areEqual(1, after.hour(), 'At its time of day');
            Assert.areEqual(15, after.minute(), 'To the minute');
            Assert.isTrue(after > Datetime.now(), 'And in the future');
            Assert.isNull(NightlyJobs.lastStarted(OLD_B), 'It has never started');
        }
    }
}
