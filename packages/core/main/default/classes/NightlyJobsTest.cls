/**
 * Maria presses one button and every BarnCRM nightly job that is not scheduled gets scheduled:
 * Core's own and any a module registers (ADR-0075, health-check-schedules-every-nightly-job).
 * Every test supplies the jobs in memory, so none depends on what the org it runs in has
 * scheduled, and none schedules a real job.
 */
@IsTest
private class NightlyJobsTest {
    /** A job that only remembers whether it was scheduled. */
    private class FakeJob implements NightlyJob {
        private final String name;
        private Boolean scheduled;
        private Integer timesScheduled = 0;

        FakeJob(String name, Boolean scheduled) {
            this.name = name;
            this.scheduled = scheduled;
        }

        public String label() {
            return name;
        }

        public Boolean isScheduled() {
            return scheduled;
        }

        public void schedule() {
            if (!scheduled) {
                timesScheduled++;
            }
            scheduled = true;
        }
    }

    private class FakeProvider implements NightlyJobProvider {
        private final List<NightlyJob> jobs;

        FakeProvider(List<NightlyJob> jobs) {
            this.jobs = jobs;
        }

        public List<NightlyJob> nightlyJobs() {
            return jobs;
        }
    }

    private class BrokenProvider implements NightlyJobProvider {
        public List<NightlyJob> nightlyJobs() {
            throw new System.NullPointerException();
        }
    }

    @IsTest
    static void coreListsItsOwnJobsThenThoseAModuleRegisters() {
        FakeJob moduleJob = new FakeJob('Module nightly job', false);
        NightlyJobs.providerOverrides.put(
            NightlyJobs.PROVIDER_CLASSES[0],
            new FakeProvider(new List<NightlyJob>{ moduleJob })
        );

        Test.startTest();
        List<NightlyJob> jobs = NightlyJobs.all();
        Test.stopTest();

        Assert.isTrue(jobs[0] instanceof NightlyJobs.RollupJob, 'Rollups first.');
        Assert.isTrue(jobs[1] instanceof NightlyJobs.SeasonalAddressJob, 'Then addresses.');
        Assert.isTrue(jobs[2] instanceof NightlyJobs.ErrorDigestJob, 'Then the digest.');
        Assert.areEqual(moduleJob, jobs[jobs.size() - 1], 'A registered job is counted last.');
        Assert.areEqual(
            System.Label.Core_HealthCheck_JobSeasonalAddresses,
            jobs[1].label(),
            'Each job is named from a label.'
        );
    }

    @IsTest
    static void aModuleWhoseProviderFailsCostsOnlyItsOwnJobs() {
        NightlyJobs.providerOverrides.put(NightlyJobs.PROVIDER_CLASSES[0], new BrokenProvider());
        NightlyJobs.providerOverrides.put(
            NightlyJobs.PROVIDER_CLASSES[1],
            new FakeProvider(new List<NightlyJob>{ new FakeJob('Other module job', true) })
        );

        Test.startTest();
        List<NightlyJob> jobs = NightlyJobs.all();
        Test.stopTest();

        Assert.areEqual(4, jobs.size(), 'Core three, plus the module that answered.');
    }

    @IsTest
    static void theWeeklyCountIsListedOnceObjectsAreChosen() {
        NightlyJobs.providerOverrides.put(NightlyJobs.PROVIDER_CLASSES[0], new FakeProvider(null));
        NightlyJobs.providerOverrides.put(NightlyJobs.PROVIDER_CLASSES[1], new FakeProvider(null));
        BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
        settings.Field_Utilization_Objects__c = null;
        settings = HouseholdTestDataFactory.save(settings);

        Test.startTest();
        Integer withoutObjects = NightlyJobs.all().size();
        settings.Field_Utilization_Objects__c = 'Contact';
        HouseholdTestDataFactory.save(settings);
        List<NightlyJob> withObjects = NightlyJobs.all();
        Test.stopTest();

        Assert.areEqual(3, withoutObjects, 'With nothing chosen, Core lists its three jobs.');
        Assert.areEqual(4, withObjects.size(), 'Choosing an object adds the weekly count.');
        Assert.isTrue(
            withObjects[3] instanceof NightlyJobs.FieldUtilizationJob,
            'The weekly count comes after Core\'s nightly jobs.'
        );
    }

    @IsTest
    static void theFieldUtilizationCountIsScheduledLikeTheNightlyJobs() {
        NightlyJobs.FieldUtilizationJob job = new NightlyJobs.FieldUtilizationJob();

        Test.startTest();
        job.schedule();
        Boolean after = job.isScheduled();
        Test.stopTest();

        Assert.isTrue(after, 'The fix schedules the weekly count, or leaves a scheduled one.');
        Assert.areEqual(
            System.Label.Core_FieldUtilization_JobLabel,
            job.label(),
            'It is named from its label.'
        );
    }

    @IsTest
    static void scheduleAllSchedulesWhatIsWaitingAndOnlyOnce() {
        FakeJob waiting = new FakeJob('Waiting job', false);
        FakeJob running = new FakeJob('Running job', true);
        NightlyJobs.jobsOverride = new List<NightlyJob>{ waiting, running };

        Test.startTest();
        List<String> before = NightlyJobs.unscheduledLabels();
        List<String> first = NightlyJobs.scheduleAll();
        List<String> second = NightlyJobs.scheduleAll();
        Test.stopTest();

        Assert.areEqual(new List<String>{ 'Waiting job' }, before, 'Only the waiting job.');
        Assert.areEqual(new List<String>{ 'Waiting job' }, first, 'It is the one scheduled.');
        Assert.isTrue(second.isEmpty(), 'Pressing again schedules nothing.');
        Assert.areEqual(1, waiting.timesScheduled, 'Scheduled once.');
        Assert.areEqual(0, running.timesScheduled, 'A running job is left alone.');
    }

    @IsTest
    static void mariaSchedulesEveryWaitingJobFromOneFinding() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        FakeJob addresses = new FakeJob('Addresses', false);
        FakeJob levels = new FakeJob('Donor levels', false);
        NightlyJobs.jobsOverride = new List<NightlyJob>{ addresses, levels };

        System.runAs(maria) {
            HealthCheckService.Finding finding = findNightlyJobs(HealthCheckService.run());
            Assert.isNotNull(finding, 'Unscheduled jobs are reported.');
            Assert.isTrue(finding.detail.contains('Addresses, Donor levels'), 'Each is named.');
            Assert.areEqual(
                System.Label.Core_HealthCheck_NightlyJobsFix,
                finding.fixLabel,
                'With one button.'
            );

            HealthCheckService.Report report = HealthCheckController.applyFix(
                HealthCheckService.FIX_KEY_SCHEDULE_NIGHTLY_JOBS,
                finding.fixScope
            );

            Assert.isTrue(addresses.scheduled && levels.scheduled, 'Both are scheduled.');
            Assert.isNull(findNightlyJobs(report.findings), 'The finding is gone.');
        }
        Integer recorded = 0;
        for (Setting_Change__c change : [SELECT New_Value__c FROM Setting_Change__c]) {
            if (change.New_Value__c == 'Addresses, Donor levels') {
                recorded++;
            }
        }
        Assert.areEqual(1, recorded, 'The fix is recorded once, naming what it scheduled.');
    }

    @IsTest
    static void staffAreNotShownTheFindingAndCannotPressTheFix() {
        User priya = HealthCheckTestHelper.priyaWithoutManageSettings();
        FakeJob addresses = new FakeJob('Addresses', false);
        NightlyJobs.jobsOverride = new List<NightlyJob>{ addresses };

        System.runAs(priya) {
            Assert.isNull(findNightlyJobs(HealthCheckService.run()), 'Not shown to staff.');
            try {
                HealthCheckController.applyFix(
                    HealthCheckService.FIX_KEY_SCHEDULE_NIGHTLY_JOBS,
                    new List<String>{ 'Addresses' }
                );
                Assert.fail('Without the permission the fix is refused.');
            } catch (AuraHandledException expected) {
                Assert.isNotNull(expected.getMessage(), 'Refused with a sentence.');
            }
        }
        Assert.isFalse(addresses.scheduled, 'Nothing was scheduled.');
    }

    private static HealthCheckService.Finding findNightlyJobs(
        List<HealthCheckService.Finding> findings
    ) {
        for (HealthCheckService.Finding finding : findings) {
            if (finding.key == 'nightly_jobs_not_scheduled') {
                return finding;
            }
        }
        return null;
    }
}
