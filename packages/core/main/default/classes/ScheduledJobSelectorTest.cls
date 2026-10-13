/**
 * The one lookup for BarnCRM's scheduled jobs (ADMIN-11), and the deactivated owner finding
 * and fix built on it (ADMIN-12).
 */
@IsTest(testFor='ApexClass:ScheduledJobSelector, ApexClass:NightlyJobs')
private class ScheduledJobSelectorTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String DAILY = '0 0 3 * * ?';
    private static final String OTHER_JOB = 'BarnCRM Selector test job';

    /** A user who has left: inactive, so a job they own has stopped running. */
    private static Id inactiveUserId() {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User gone = new User(
            FirstName = 'Former',
            LastName = 'Admin',
            Alias = 'former',
            Email = 'former.barncrm@example.com',
            Username = 'former.barncrm.' + Datetime.now().getTime() + '@example.com',
            ProfileId = standard.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive = false
        );
        insert gone;
        return gone.Id;
    }

    @IsTest
    static void everyQuestionInATransactionCostsOneQuery() {
        System.runAs(TestUsers.admin()) {
            ScheduledJobSelector.schedule(OTHER_JOB, DAILY, new ErrorDigestScheduler());

            Test.startTest();
            Integer before = Limits.getQueries();
            Id found = ScheduledJobSelector.triggerIdByName(OTHER_JOB);
            Datetime next = ScheduledJobSelector.nextFireTime(OTHER_JOB);
            Boolean rollups = RollupScheduler.isScheduled();
            Boolean addresses = SeasonalAddressScheduler.isScheduled();
            Datetime digest = ErrorDigestScheduler.nextRunAt();
            Integer used = Limits.getQueries() - before;
            Test.stopTest();

            Assert.isNotNull(found, 'The job is found by its name');
            Assert.isNotNull(next, 'with its next run');
            Assert.areEqual(1, used, 'Five questions about scheduled jobs cost one query');
            Assert.isNotNull(rollups, 'Each scheduler answers from the same read');
            Assert.isNotNull(addresses, 'So does this one');
            Assert.areEqual(
                ScheduledJobSelector.nextFireTime(ErrorDigestScheduler.JOB_NAME),
                digest,
                'And this one'
            );
        }
    }

    @IsTest
    static void aChangeMadeThroughTheSelectorIsSeenAtOnce() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Id before = ScheduledJobSelector.triggerIdByName(OTHER_JOB);
            Id scheduled = ScheduledJobSelector.schedule(
                OTHER_JOB,
                DAILY,
                new ErrorDigestScheduler()
            );
            Id afterSchedule = ScheduledJobSelector.triggerIdByName(OTHER_JOB);
            ScheduledJobSelector.abort(scheduled);
            Id afterAbort = ScheduledJobSelector.triggerIdByName(OTHER_JOB);
            Test.stopTest();

            Assert.isNull(before, 'Not scheduled at first');
            Assert.areEqual(scheduled, afterSchedule, 'Seen as soon as it is scheduled');
            Assert.isNull(afterAbort, 'And gone as soon as it is aborted');
        }
    }

    @IsTest
    static void namesTheJobsOfADeactivatedOwnerAndHealthCheckSaysSo() {
        System.runAs(TestUsers.admin()) {
            Id gone = inactiveUserId();
            ScheduledJobSelector.schedule(OTHER_JOB, DAILY, new ErrorDigestScheduler());

            Test.startTest();
            List<String> whileActive = ScheduledJobSelector.namesOwnedByInactiveUsers();
            ScheduledJobSelector.ownerOverride = gone;
            ScheduledJobSelector.forget();
            List<String> afterLeaving = ScheduledJobSelector.namesOwnedByInactiveUsers();
            HealthCheckService.Finding finding = new HealthCheckSettingsChecks.InactiveOwnerJobsCheck()
                .run();
            Test.stopTest();

            Assert.isFalse(
                whileActive.contains(OTHER_JOB),
                'A job of an active owner is not named'
            );
            Assert.isTrue(afterLeaving.contains(OTHER_JOB), 'The job is named');
            Assert.areEqual('jobs_inactive_owner', finding.key, 'Health Check says so');
            Assert.areEqual(afterLeaving, finding.fixScope, 'and its fix covers exactly those');
            Assert.isTrue(
                finding.fixTarget.endsWith(
                    HealthCheckService.FIX_KEY_RESCHEDULE_INACTIVE_OWNER_JOBS
                ),
                'The finding carries the reschedule fix'
            );
        }
    }

    @IsTest
    static void theFixSchedulesKnownJobsAgainAndNamesTheRest() {
        System.runAs(TestUsers.admin()) {
            Id gone = inactiveUserId();
            ErrorDigestScheduler.start();
            ScheduledJobSelector.schedule(OTHER_JOB, DAILY, new ErrorDigestScheduler());
            NightlyJobs.jobsOverride = new List<NightlyJob>{ new NightlyJobs.ErrorDigestJob() };
            Id oldDigest = ScheduledJobSelector.triggerIdByName(ErrorDigestScheduler.JOB_NAME);

            Test.startTest();
            List<String> stoppedOnly = NightlyJobs.rescheduleAsRunningUser(
                new List<String>{ ErrorDigestScheduler.JOB_NAME, OTHER_JOB }
            );
            Id newDigest = ScheduledJobSelector.triggerIdByName(ErrorDigestScheduler.JOB_NAME);
            Test.stopTest();

            Assert.isNotNull(gone, 'A deactivated owner exists');
            Assert.isNotNull(newDigest, 'The digest is scheduled again');
            Assert.areNotEqual(oldDigest, newDigest, 'as a new job, owned by the running user');
            Assert.areEqual(
                new List<String>{ OTHER_JOB },
                stoppedOnly,
                'A job Health Check never schedules is stopped and named'
            );
        }
    }
}
