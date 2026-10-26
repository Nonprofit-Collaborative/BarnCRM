/**
 * Mirror's nightly job as Health Check sees it (ADR-0075, health-check-schedules-every-nightly-job):
 * the Opportunity mirror's run is listed only while a direction is chosen, and scheduling it
 * twice leaves one job.
 */
@IsTest(testFor='ApexClass:MirrorNightlyJobProvider')
private class MirrorNightlyJobProviderTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static void choose(String direction) {
        Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
        settings.Opportunity_Mirror_Direction__c = direction;
        upsert settings;
    }

    /** The org's own mirror job, if an administrator scheduled it, would be counted otherwise. */
    private static void clearOrgMirrorJob() {
        TestDataFactory.clearScheduledJobs(
            new List<String>{ OpportunityMirrorSchedulable.JOB_NAME }
        );
        ScheduledJobSelector.forget();
    }

    private static Integer mirrorTriggerCount() {
        return [
            SELECT COUNT()
            FROM CronTrigger
            WHERE CronJobDetail.Name = :OpportunityMirrorSchedulable.JOB_NAME
        ];
    }

    @IsTest
    static void listsNothingWhileTheMirrorIsOff() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            choose(OpportunityMirrorService.OFF);

            Assert.isTrue(
                new MirrorNightlyJobProvider().nightlyJobs().isEmpty(),
                'A mirror that is Off has no run worth scheduling.'
            );
        }
    }

    @IsTest
    static void listsNothingWhenNoDirectionHasEverBeenChosen() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.isTrue(new MirrorNightlyJobProvider().nightlyJobs().isEmpty());
        }
    }

    @IsTest
    static void listsTheMirrorRunOnceADirectionIsChosen() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            clearOrgMirrorJob();
            if (!OpportunityMirrorService.isAvailable()) {
                // No Opportunity in this org: the provider must skip, and says so by listing nothing.
                choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
                Assert.isTrue(new MirrorNightlyJobProvider().nightlyJobs().isEmpty());
                return;
            }
            choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);

            List<NightlyJob> jobs = new MirrorNightlyJobProvider().nightlyJobs();

            Assert.areEqual(1, jobs.size());
            Assert.areEqual(System.Label.Mirror_NightlyJob_MirrorName, jobs[0].label());
            Assert.isFalse(jobs[0].isScheduled(), 'Nothing is scheduled yet.');
        }
    }

    @IsTest
    static void schedulingTwiceLeavesOneJobAndItCountsAsScheduled() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            clearOrgMirrorJob();
            if (!OpportunityMirrorService.isAvailable()) {
                return;
            }
            choose(OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS);
            NightlyJob job = new MirrorNightlyJobProvider().nightlyJobs()[0];

            Test.startTest();
            job.schedule();
            job.schedule();
            Test.stopTest();

            Assert.areEqual(
                1,
                mirrorTriggerCount(),
                'A second press returns the job already there.'
            );
            Assert.isTrue(job.isScheduled());
        }
    }

    @IsTest
    static void aScheduledRunIsNoLongerWaiting() {
        // The run reads in user mode as whoever scheduled it, so it is scheduled by someone
        // who holds the mirror's permission set, as on the Opportunity mirror page.
        User maria = TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'Giving_Admin', 'Opportunity_Mirror' }
        );
        System.runAs(maria) {
            if (!OpportunityMirrorService.isAvailable()) {
                return;
            }
            choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
            Test.startTest();
            OpportunityMirrorSchedulable.schedule();
            Test.stopTest();

            NightlyJob job = new MirrorNightlyJobProvider().nightlyJobs()[0];
            Assert.isTrue(
                job.isScheduled(),
                'The job the Opportunity mirror page scheduled is seen.'
            );
        }
    }
}
