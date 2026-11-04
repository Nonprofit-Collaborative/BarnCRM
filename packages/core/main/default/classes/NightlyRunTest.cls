/**
 * The nightly run itself (ADR-NEXT nightly-job-dispatcher, R-NJ2, R-NJ3, R-NJ6): each test
 * drives the links by hand, with chaining off and the platform's job count given, so it checks
 * what every link decides without waiting for any of them.
 */
@IsTest(testFor='ApexClass:NightlyRun')
private class NightlyRunTest {
    private static final String FIRST = 'BarnCRM Run Test First';
    private static final String SECOND = 'BarnCRM Run Test Second';

    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private class CountingWork implements Schedulable {
        public Integer runs = 0;
        public void execute(SchedulableContext context) {
            runs++;
        }
    }

    private class FailingWork implements Schedulable {
        public void execute(SchedulableContext context) {
            throw new System.IllegalArgumentException('Nothing to do it with');
        }
    }

    /** Takes a place in the queue and does nothing. */
    private class Filler implements Queueable {
        public void execute(QueueableContext context) {
            return;
        }
    }

    private static void only(List<NightlyStep> steps) {
        NightlyRun.chain = false;
        NightlyJobs.overrideStepsForTest(steps);
        NightlyJobs.forget();
        NightlyJobs.overrideStepsForTest(steps);
    }

    private static Nightly_Job__c row(String key) {
        NightlyJobs.forget();
        return NightlyJobs.rowFor(key);
    }

    @IsTest
    static void aStepRunsIsWaitedForAndAStepSwitchedOffIsSkipped() {
        System.runAs(TestUsers.admin()) {
            CountingWork work = new CountingWork();
            only(
                new List<NightlyStep>{
                    new NightlyStep(FIRST, 'First', 0, 0, work),
                    new NightlyStep(SECOND, 'Second', 0, 0, new CountingWork()).withSwitch(false)
                }
            );
            NightlyRun run = new NightlyRun();

            run.execute((SchedulableContext) null);
            Assert.areEqual(0, NightlyRun.lastDelay, 'Begun, the plan link follows at once');
            run.advance();
            Assert.areEqual(NightlyRun.RUN, run.phase, 'The first step is due at midnight');
            Assert.areEqual(NightlyJobs.RUNNING, row(FIRST).Last_Outcome__c, 'Marked running');
            run.advance();
            Assert.areEqual(1, work.runs, 'Its work started');
            Assert.areEqual(1, NightlyRun.lastDelay, 'And the run looks again in a minute');
            NightlyRun.busyOverride = 1;
            run.advance();
            Assert.areEqual(NightlyRun.POLL_MINUTES, NightlyRun.lastDelay, 'Still busy: wait');
            NightlyRun.busyOverride = 0;
            run.advance();

            Assert.areEqual(NightlyJobs.DONE, row(FIRST).Last_Outcome__c, 'Done once idle');
            Assert.isNotNull(row(FIRST).Last_Finished__c, 'With when it finished');
            Assert.areEqual(NightlyJobs.SKIPPED, row(SECOND).Last_Outcome__c, 'Off: skipped');
            Assert.areEqual(
                NightlyJobs.DONE,
                row(NightlyJobs.JOB_NAME).Last_Outcome__c,
                'The run ends after its last step'
            );
        }
    }

    @IsTest
    static void aStepThatThrowsIsRecordedAsFailedAndTheRunGoesOn() {
        System.runAs(TestUsers.admin()) {
            CountingWork after = new CountingWork();
            only(
                new List<NightlyStep>{
                    new NightlyStep(FIRST, 'First', 0, 0, new FailingWork()),
                    new NightlyStep(SECOND, 'Second', 0, 0, after)
                }
            );
            NightlyRun.busyOverride = 0;
            NightlyRun run = new NightlyRun();
            run.begin();
            run.advance();
            run.advance();
            run.advance();
            run.advance();

            Nightly_Job__c failed = row(FIRST);
            Assert.areEqual(NightlyJobs.FAILED, failed.Last_Outcome__c, 'Failed');
            Assert.areEqual('Nothing to do it with', failed.Last_Message__c, 'With why');
            Assert.areEqual(1, after.runs, 'The next step still ran');
        }
    }

    @IsTest
    static void theRunGivesUpWaitingAfterSixHours() {
        System.runAs(TestUsers.admin()) {
            only(
                new List<NightlyStep>{ new NightlyStep(FIRST, 'First', 0, 0, new CountingWork()) }
            );
            NightlyRun run = new NightlyRun();
            run.begin();
            run.advance();
            run.advance();
            NightlyRun.busyOverride = 1;
            run.polls = NightlyRun.MAX_POLLS;
            run.advance();

            Nightly_Job__c gaveUp = row(FIRST);
            Assert.areEqual(NightlyJobs.GAVE_UP, gaveUp.Last_Outcome__c, 'Gave up');
            Assert.isTrue(String.isNotBlank(gaveUp.Last_Message__c), 'And says so');
            Assert.areEqual(MAX_HOURS, NightlyRun.MAX_POLLS * NightlyRun.POLL_MINUTES / 60, 'Six');
        }
    }

    private static final Integer MAX_HOURS = 6;

    @IsTest
    static void anOlderRunStopsOnceANewerOneHasBegun() {
        System.runAs(TestUsers.admin()) {
            CountingWork work = new CountingWork();
            only(new List<NightlyStep>{ new NightlyStep(FIRST, 'First', 0, 0, work) });
            NightlyRun older = new NightlyRun();
            older.begin();
            older.runStarted = older.runStarted.addSeconds(-5);
            new NightlyRun().begin();

            older.advance();

            Assert.areEqual(NightlyRun.PLAN, older.phase, 'The older run did nothing');
            Assert.areEqual(0, older.cursor, 'And took no step');
            Assert.areEqual(0, work.runs, 'Nothing ran');
        }
    }

    @IsTest
    static void aRunThatFindsAStepLeftRunningWaitsForItFirst() {
        System.runAs(TestUsers.admin()) {
            only(
                new List<NightlyStep>{ new NightlyStep(FIRST, 'First', 0, 0, new CountingWork()) }
            );
            Nightly_Job__c left = NightlyJobs.rowFor(SECOND);
            left.Last_Outcome__c = NightlyJobs.RUNNING;
            left.Last_Started__c = Datetime.now().addHours(-20);
            NightlyJobs.save(new List<Nightly_Job__c>{ left });
            NightlyJobs.forget();

            NightlyRun run = new NightlyRun();
            run.begin();

            Assert.areEqual(NightlyRun.WAIT, run.phase, 'It waits for what that step started');
            Assert.areEqual(NightlyRun.POLL_MINUTES, NightlyRun.lastDelay, 'Checking again soon');
            Nightly_Job__c superseded = row(SECOND);
            Assert.areEqual(
                NightlyJobs.GAVE_UP,
                superseded.Last_Outcome__c,
                'Recorded as given up'
            );
            Assert.isTrue(String.isNotBlank(superseded.Last_Message__c), 'And says why');

            NightlyRun.busyOverride = 0;
            run.advance();
            Assert.areEqual(NightlyRun.RUN, run.phase, 'Then tonight\'s first step');
        }
    }

    @IsTest
    static void aStepWhoseTimeHasNotComeIsWaitedFor() {
        Datetime now = Datetime.now();
        if (now.hour() >= 23) {
            // Late in the evening every later step is less than an hour away; the rest covers it.
            return;
        }
        System.runAs(TestUsers.admin()) {
            CountingWork work = new CountingWork();
            only(new List<NightlyStep>{ new NightlyStep(FIRST, 'First', 23, 59, work) });
            NightlyRun run = new NightlyRun();
            run.begin();
            run.advance();

            Assert.areEqual(-1, NightlyRun.lastDelay, 'Over ten minutes away: the one-time job');
            Assert.areEqual(NightlyRun.PLAN, run.phase, 'Still planning');
            Assert.areEqual(0, work.runs, 'Nothing ran early');
        }
    }

    @IsTest
    static void aLongWaitResumesThroughTheOneTimeJob() {
        System.runAs(TestUsers.admin()) {
            if (ScheduledJobSelector.isScheduled(NightlyJobs.CONTINUE_JOB_NAME)) {
                // The org has a real run waiting, which a test must not stop.
                return;
            }
            only(
                new List<NightlyStep>{ new NightlyStep(FIRST, 'First', 0, 0, new CountingWork()) }
            );
            NightlyRun run = new NightlyRun();
            run.begin();
            NightlyRun.chain = true;
            run.phase = NightlyRun.WAIT;
            run.stepStarted = Datetime.now();
            NightlyRun.busyOverride = 1;

            Test.startTest();
            // Fill the queue, so the next link cannot be a queueable.
            while (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                System.enqueueJob(new Filler());
            }
            run.advance();
            ScheduledJobSelector.forget();
            Boolean resumes = ScheduledJobSelector.isScheduled(NightlyJobs.CONTINUE_JOB_NAME);
            ScheduledJobSelector.stopNamed(NightlyJobs.CONTINUE_JOB_NAME);
            Test.stopTest();

            Assert.isTrue(resumes, 'A full queue resumes from the one-time job');
        }
    }
}
