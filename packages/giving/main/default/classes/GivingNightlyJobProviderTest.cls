/**
 * Giving's nightly jobs as Health Check sees them (ADR-0075,
 * health-check-schedules-every-nightly-job): the three jobs are listed, each is scheduled on its
 * own and only once, and the acknowledgment send, which emails donors, is never one of them.
 */
@IsTest(testFor='ApexClass:GivingNightlyJobProvider')
private class GivingNightlyJobProviderTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static Integer givingTriggerCount() {
        return [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'BarnCRM Giving%'];
    }

    @IsTest
    static void listsTheThreeNightlyJobsAndNotTheAcknowledgmentSend() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<NightlyJob> jobs = new GivingNightlyJobProvider().nightlyJobs();

            Assert.areEqual(
                3,
                jobs.size(),
                'The top up, the overdue pass and the donor levels pass.'
            );
            Set<String> labels = new Set<String>();
            for (NightlyJob job : jobs) {
                labels.add(job.label());
                Assert.isFalse(job.isScheduled(), 'Nothing is scheduled on a fresh org.');
            }
            Assert.isTrue(labels.contains(System.Label.Giving_NightlyJobs_TopUpName));
            Assert.isTrue(labels.contains(System.Label.Giving_NightlyJobs_OverdueName));
            Assert.isTrue(labels.contains(System.Label.Giving_NightlyJobs_LevelsName));
            Assert.areEqual(
                3,
                labels.size(),
                'Each job has its own name, so the finding can list them apart.'
            );
        }
    }

    @IsTest
    static void schedulingEachJobTwiceSchedulesItOnce() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<NightlyJob> jobs = new GivingNightlyJobProvider().nightlyJobs();

            Test.startTest();
            for (NightlyJob job : jobs) {
                job.schedule();
                job.schedule();
            }
            Test.stopTest();

            Assert.areEqual(3, givingTriggerCount(), 'A second press adds no second job.');
            for (NightlyJob job : jobs) {
                Assert.isTrue(job.isScheduled(), job.label() + ' is scheduled.');
            }
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE '%cknowledg%'],
                'The acknowledgment send is not scheduled, because it emails donors.'
            );
        }
    }

    @IsTest
    static void schedulingOneJobLeavesTheOthersAlone() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<NightlyJob> jobs = new GivingNightlyJobProvider().nightlyJobs();

            Test.startTest();
            jobs[1].schedule();
            Test.stopTest();

            Assert.areEqual(1, givingTriggerCount());
            Assert.isFalse(jobs[0].isScheduled());
            Assert.isTrue(jobs[1].isScheduled());
            Assert.isFalse(jobs[2].isScheduled());
        }
    }

    @IsTest
    static void anUnknownJobNameSchedulesNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            GivingScheduler.scheduleJobNamed('BarnCRM Giving: not a job');
            Test.stopTest();

            Assert.areEqual(0, givingTriggerCount());
            Assert.isFalse(GivingScheduler.isJobScheduled('BarnCRM Giving: not a job'));
        }
    }

    @IsTest
    static void healthCheckSeesTheJobsAsWaitingUntilTheyAreScheduled() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            NightlyJobs.providerOverrides.remove('GivingNightlyJobProvider');

            List<String> before = NightlyJobs.unscheduledLabels();
            Assert.isTrue(
                before.contains(System.Label.Giving_NightlyJobs_LevelsName),
                'Core finds this provider by name and counts its jobs.'
            );

            Test.startTest();
            GivingScheduler.scheduleAll();
            Test.stopTest();

            Assert.areEqual(3, givingTriggerCount());
            Assert.isFalse(
                NightlyJobs.unscheduledLabels()
                    .contains(System.Label.Giving_NightlyJobs_LevelsName),
                'Once scheduled the job is no longer waiting.'
            );
        }
    }
}
