/**
 * Connect's nightly job as Health Check sees it (ADR-NEXT, health-check-schedules-every-nightly-job):
 * the Opportunity mirror's run is listed only while a direction is chosen, and scheduling it
 * twice leaves one job.
 */
@IsTest
private class ConnectNightlyJobProviderTest {
    private static void choose(String direction) {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        settings.Opportunity_Mirror_Direction__c = direction;
        upsert settings;
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
        choose(OpportunityMirrorService.OFF);

        Assert.isTrue(
            new ConnectNightlyJobProvider().nightlyJobs().isEmpty(),
            'A mirror that is Off has no run worth scheduling.'
        );
    }

    @IsTest
    static void listsNothingWhenNoDirectionHasEverBeenChosen() {
        Assert.isTrue(new ConnectNightlyJobProvider().nightlyJobs().isEmpty());
    }

    @IsTest
    static void listsTheMirrorRunOnceADirectionIsChosen() {
        if (!OpportunityMirrorService.isAvailable()) {
            // No Opportunity in this org: the provider must skip, and says so by listing nothing.
            choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
            Assert.isTrue(new ConnectNightlyJobProvider().nightlyJobs().isEmpty());
            return;
        }
        choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);

        List<NightlyJob> jobs = new ConnectNightlyJobProvider().nightlyJobs();

        Assert.areEqual(1, jobs.size());
        Assert.areEqual(System.Label.Connect_NightlyJob_MirrorName, jobs[0].label());
        Assert.isFalse(jobs[0].isScheduled(), 'Nothing is scheduled yet.');
    }

    @IsTest
    static void schedulingTwiceLeavesOneJobAndItCountsAsScheduled() {
        if (!OpportunityMirrorService.isAvailable()) {
            return;
        }
        choose(OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS);
        NightlyJob job = new ConnectNightlyJobProvider().nightlyJobs()[0];

        Test.startTest();
        job.schedule();
        job.schedule();
        Test.stopTest();

        Assert.areEqual(1, mirrorTriggerCount(), 'A second press returns the job already there.');
        Assert.isTrue(job.isScheduled());
    }

    @IsTest
    static void aScheduledRunIsNoLongerWaiting() {
        if (!OpportunityMirrorService.isAvailable()) {
            return;
        }
        choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);
        Test.startTest();
        OpportunityMirrorSchedulable.schedule();
        Test.stopTest();

        NightlyJob job = new ConnectNightlyJobProvider().nightlyJobs()[0];
        Assert.isTrue(job.isScheduled(), 'The job the Opportunity mirror page scheduled is seen.');
    }
}
