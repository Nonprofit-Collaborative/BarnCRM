/**
 * Mirror's steps of the nightly run (ADR-0166 nightly-job-dispatcher): the Opportunity mirror's
 * run is in tonight's run only while a direction is chosen, and its page switches it on and off.
 */
@IsTest(testFor='ApexClass:MirrorNightlyJobProvider, ApexClass:OpportunityMirrorSchedulable')
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

    private static NightlyStep opportunityStep() {
        for (NightlyStep step : new MirrorNightlyJobProvider().nightlySteps()) {
            if (step.key == OpportunityMirrorSchedulable.JOB_NAME) {
                return step;
            }
        }
        return null;
    }

    @IsTest
    static void bothMirrorsAreStepsAtTheirTimes() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<NightlyStep> steps = new MirrorNightlyJobProvider().nightlySteps();

            Assert.areEqual(2, steps.size(), 'The Opportunity and Gift Transaction mirrors.');
            Assert.areEqual(90, steps[0].minute, '1:30');
            Assert.areEqual(95, steps[1].minute, '1:35');
            Assert.areEqual(System.Label.Mirror_NightlyJob_MirrorName, steps[0].label);
            Assert.isTrue(steps[0].switchDefault, 'Shipped on.');
        }
    }

    @IsTest
    static void theMirrorRunIsLeftOutWhileTheMirrorIsOff() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            choose(OpportunityMirrorService.OFF);

            Assert.isFalse(
                NightlyJobs.isOn(opportunityStep()),
                'A mirror that is Off has no run worth doing.'
            );
        }
    }

    @IsTest
    static void theMirrorRunIsInTonightsRunOnceADirectionIsChosen() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            choose(OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES);

            Assert.areEqual(
                OpportunityMirrorService.isAvailable(),
                NightlyJobs.isOn(opportunityStep()),
                'On wherever the org has Opportunities.'
            );
        }
    }

    @IsTest
    static void thePageSwitchesTheRunOnAndOff() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.clearScheduledJobs(new List<String>{ NightlyJobs.jobName() });
            ScheduledJobSelector.forget();
            Boolean before = OpportunityMirrorSchedulable.isScheduled();

            Id first = OpportunityMirrorSchedulable.schedule();
            Id second = OpportunityMirrorSchedulable.schedule();
            ScheduledJobSelector.forget();
            NightlyJobs.forget();
            Boolean switchedOn = OpportunityMirrorSchedulable.isScheduled();
            Datetime scheduledAt = OpportunityMirrorSchedulable.scheduledAt();
            OpportunityMirrorSchedulable.stop();
            NightlyJobs.forget();

            Assert.isFalse(before, 'Not before the run is scheduled.');
            Assert.areEqual(first, second, 'A second press returns the run already there.');
            Assert.isTrue(switchedOn, 'Switched on.');
            Assert.isNotNull(scheduledAt, 'Health Check sees when.');
            Assert.isFalse(OpportunityMirrorSchedulable.isScheduled(), 'Switched off.');
            Assert.isNull(OpportunityMirrorSchedulable.nextRunAt(), 'With no next run.');
        }
    }
}
