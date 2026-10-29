/**
 * The Health Check fix buttons C-21 adds (ADR-0048): each finding names what is missing,
 * counted from this org, and its fix creates exactly that, once, or schedules the nightly
 * jobs, once. Everything runs as Maria, who holds the permission the checks and the fixes are
 * gated on; the refusal is asserted as Priya.
 *
 * Every test arranges the state it asserts: the shipped automations are supplied in memory, so
 * no test depends on what the org it runs in happens to have. Import templates are the one
 * exception: their shipped rows are read as shipped, and Core ships two, which the test says
 * before it relies on them. A module's fix is run through `HealthCheckFixExtension` under the
 * same rules (ADR-0125); the rollup fix's own tests are `RollupsHealthCheckExtensionTest`.
 */
@IsTest(testFor='ApexClass:HealthCheckService, ApexClass:HealthCheckController')
private class HealthCheckFixesTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String STUB_FIX_KEY = 'restoreStubThings';
    private static final String STUB_FIX_LABEL = 'Restore stub things';

    /**
     * A module's extension with one finding and one fix, standing in for a package Core cannot
     * name. Its fix writes a change history row of its own, so a rollback can be seen.
     */
    private class StubFixer implements HealthCheckExtension, HealthCheckFixExtension {
        public List<String> missing = new List<String>{ 'Stub thing' };
        public Integer timesRun = 0;

        public List<HealthCheckService.Finding> findings() {
            if (missing.isEmpty()) {
                return new List<HealthCheckService.Finding>();
            }
            return new List<HealthCheckService.Finding>{
                new HealthCheckService.Finding(
                        'stub_things_missing',
                        'Stub things are missing',
                        String.join(missing, ', '),
                        HealthCheckService.SEVERITY_WARNING,
                        HealthCheckService.CATEGORY_SETTINGS
                    )
                    .withScope(new List<String>(missing))
                    .withFix(STUB_FIX_LABEL, HealthCheckService.FIX_ACTION_PREFIX + STUB_FIX_KEY)
            };
        }

        public List<String> fixScope(String fixKey) {
            return STUB_FIX_KEY.equals(fixKey) ? new List<String>(missing) : null;
        }

        public String fixLabel(String fixKey) {
            return STUB_FIX_KEY.equals(fixKey) ? STUB_FIX_LABEL : null;
        }

        public String runFix(String fixKey, List<String> scope) {
            timesRun++;
            SettingsService.logChange('Stub fix ran', '', String.join(scope, ', '));
            missing.clear();
            return 'Created ' + String.join(scope, ', ') + '.';
        }
    }

    private static StubFixer installStubFixer() {
        StubFixer fixer = new StubFixer();
        HealthCheckExtensions.noneForTest = true;
        HealthCheckExtensions.overrides.put('RollupsHealthCheckExtension', fixer);
        return fixer;
    }

    private static HealthCheckService.Finding find(String key) {
        for (HealthCheckService.Finding finding : HealthCheckService.run()) {
            if (key.equals(finding.key)) {
                return finding;
            }
        }
        return null;
    }

    private static HealthCheckService.Finding find(HealthCheckService.Report report, String key) {
        for (HealthCheckService.Finding finding : report.findings) {
            if (key.equals(finding.key)) {
                return finding;
            }
        }
        return null;
    }

    /** Presses a fix the way the panel does: with the scope the finding carried. */
    private static HealthCheckService.Report press(HealthCheckService.Finding finding) {
        return HealthCheckController.applyFix(
            finding.fixTarget.substring(HealthCheckService.FIX_ACTION_PREFIX.length()),
            finding.fixScope
        );
    }

    /** Presses a fix again with the scope it was first pressed with, and expects a refusal. */
    private static void assertPressingAgainIsRefused(HealthCheckService.Finding finding) {
        try {
            press(finding);
            Assert.fail('A fix whose scope no longer matches the org is refused.');
        } catch (AuraHandledException expected) {
            Assert.areEqual(
                System.Label.Core_HealthCheck_FixStale,
                expected.getMessage(),
                'Refused with the sentence that says the org changed since the scan.'
            );
        }
    }

    private static List<Setting_Change__c> changesLogged() {
        return [
            SELECT Setting_Name__c, Old_Value__c, New_Value__c
            FROM Setting_Change__c
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void aModulesFixIsRunByCoreUnderTheSameRules() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            StubFixer fixer = installStubFixer();

            System.runAs(maria) {
                HealthCheckService.Finding finding = find('stub_things_missing');
                Assert.isNotNull(finding, 'The module finding is in the report.');

                Test.startTest();
                HealthCheckService.Report report = press(finding);
                assertPressingAgainIsRefused(finding);
                Test.stopTest();

                Assert.areEqual(1, fixer.timesRun, 'Pressing twice runs the fix once.');
                Assert.areEqual('Created Stub thing.', report.fixOutcome, 'In its own words.');
                Assert.isNull(find(report, 'stub_things_missing'), 'The re-run report is clear.');
            }
            Set<String> names = new Set<String>();
            for (Setting_Change__c change : changesLogged()) {
                names.add(change.Setting_Name__c);
            }
            Assert.isTrue(
                names.contains('Health Check: ' + STUB_FIX_LABEL),
                'Core records the fix under its button label: ' + names
            );
        }
    }

    @IsTest
    static void aModulesFixThatFailsAfterWritingLeavesNothingBehind() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            installStubFixer();

            System.runAs(maria) {
                HealthCheckService.Finding finding = find('stub_things_missing');
                HealthCheckController.failAfterFixForTest = true;

                Test.startTest();
                try {
                    press(finding);
                    Assert.fail('The failure reaches the panel.');
                } catch (AuraHandledException expected) {
                    Assert.areEqual(
                        System.Label.Core_HealthCheck_FixFailed,
                        expected.getMessage(),
                        'As a sentence.'
                    );
                }
                Test.stopTest();
            }

            Assert.areEqual(0, changesLogged().size(), 'What the fix wrote is rolled back.');
        }
    }

    @IsTest
    static void aModulesFixNeedsThePermission() {
        System.runAs(TestUsers.admin()) {
            User priya = HealthCheckTestHelper.priyaWithoutManageSettings();
            StubFixer fixer = installStubFixer();

            System.runAs(priya) {
                try {
                    HealthCheckController.applyFix(STUB_FIX_KEY, new List<String>{ 'Stub thing' });
                    Assert.fail('Without the permission the fix is refused.');
                } catch (AuraHandledException expected) {
                    Assert.isNotNull(expected.getMessage(), 'Refused with a sentence.');
                }
            }
            Assert.areEqual(0, fixer.timesRun, 'Nothing ran.');
        }
    }

    @IsTest
    static void missingAutomationSwitchesAreRestoredAndASwitchTurnedOffStaysOff() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            Automation_Registry__mdt lock = TestDataFactory.registryEntry(
                'Test_Receipt_Lock',
                true
            );
            lock.Always_Runs__c = true;
            AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{
                TestDataFactory.registryEntry('Test_Household_Naming', true),
                TestDataFactory.registryEntry('Test_Address_Sync', true),
                lock
            };
            // Maria has already switched household naming off.
            TestDataFactory.insertAutomationSettings(
                new Map<String, Boolean>{ 'Test_Household_Naming' => false }
            );

            System.runAs(maria) {
                HealthCheckService.Finding finding = find('automation_switches_missing');
                Assert.isNotNull(finding, 'Automations with no switch are reported.');
                Assert.areEqual(2, finding.fixScope.size(), 'Two automations have no switch.');
                Assert.isTrue(finding.title.contains('2'), 'The title counts them.');

                Test.startTest();
                HealthCheckService.Report report = press(finding);
                assertPressingAgainIsRefused(finding);
                Test.stopTest();

                Assert.isNull(find(report, 'automation_switches_missing'), 'Every switch is back.');
            }

            Map<String, Automation_Setting__c> byName = new Map<String, Automation_Setting__c>();
            for (Automation_Setting__c setting : [
                SELECT Automation_Name__c, Enabled__c, Always_Runs__c
                FROM Automation_Setting__c
            ]) {
                byName.put(setting.Automation_Name__c, setting);
            }
            Assert.areEqual(3, byName.size(), 'One switch for each automation, none twice.');
            Assert.isFalse(
                byName.get('Test_Household_Naming').Enabled__c,
                'A switch she turned off stays off (ADR-0048).'
            );
            Assert.isTrue(
                byName.get('Test_Address_Sync').Enabled__c,
                'A restored switch leaves its automation running, as it was before.'
            );
            Assert.isTrue(
                byName.get('Test_Receipt_Lock').Always_Runs__c,
                'An automation that always runs is restored as one.'
            );
            Assert.areEqual(
                1,
                changesLogged().size(),
                'The fix is recorded in the change history.'
            );
        }
    }

    @IsTest
    static void missingImportTemplatesAreRestoredOnce() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();

            System.runAs(maria) {
                List<String> missing = ImportTemplateService.missingDefaultNames();
                Assert.isFalse(
                    missing.isEmpty(),
                    'Core ships import templates, and a test org starts without any.'
                );
                HealthCheckService.Finding finding = find('import_templates_missing');
                Assert.isNotNull(finding, 'Shipped templates the org does not have are reported.');

                Test.startTest();
                HealthCheckService.Report report = press(finding);
                assertPressingAgainIsRefused(finding);
                Test.stopTest();

                Assert.isNull(find(report, 'import_templates_missing'), 'Every template is back.');
                Assert.areEqual(
                    missing.size(),
                    [SELECT COUNT() FROM Import_Template__c],
                    'Pressing the fix twice is pressing it once.'
                );
            }
        }
    }

    /** A user who has left: inactive, so a job they own has stopped running. */
    private static Id inactiveUserId() {
        User gone = new User(
            FirstName = 'Former',
            LastName = 'Scheduler',
            Alias = 'formsch',
            Email = 'former.scheduler.barncrm@example.com',
            Username = 'former.scheduler.barncrm.' + Datetime.now().getTime() + '@example.com',
            ProfileId = TestUsers.standardProfileId(),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive = false
        );
        insert gone;
        return gone.Id;
    }

    /**
     * Cancels every BarnCRM scheduled job the org already has, such as the hourly tab access
     * check an install schedules. Scheduled jobs are visible to tests, and the test seam that
     * gives a job an inactive owner applies to every job read, so a test that names the jobs it
     * expects clears the org's own first.
     */
    private static void clearOrgBarnCrmJobs() {
        for (CronTrigger job : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'BarnCRM%'
            WITH SYSTEM_MODE
        ]) {
            System.abortJob(job.Id);
        }
        ScheduledJobSelector.forget();
    }

    @IsTest
    static void jobsOfADeactivatedOwnerAreScheduledAgainAndTheRestNamedAsStopped() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            Id gone = inactiveUserId();
            String otherJob = 'BarnCRM Fix test job';
            clearOrgBarnCrmJobs();
            ErrorDigestScheduler.start();
            ScheduledJobSelector.schedule(otherJob, '0 0 3 * * ?', new ErrorDigestScheduler());
            NightlyJobs.jobsOverride = new List<NightlyJob>{ new NightlyJobs.ErrorDigestJob() };
            ScheduledJobSelector.ownerOverride = gone;
            ScheduledJobSelector.forget();
            String fixKey = HealthCheckService.FIX_KEY_RESCHEDULE_INACTIVE_OWNER_JOBS;

            System.runAs(maria) {
                List<String> scope = HealthCheckService.fixScope(fixKey);
                Assert.isTrue(
                    scope.contains(otherJob),
                    'The job of the deactivated owner is named'
                );

                // No startTest: the scheduled run must not execute inside the test.
                HealthCheckService.Report report = HealthCheckController.applyFix(fixKey, scope);

                Assert.isTrue(
                    report.fixOutcome.contains(ErrorDigestScheduler.JOB_NAME),
                    'A job Health Check schedules is said to be scheduled: ' + report.fixOutcome
                );
                Assert.isTrue(
                    report.fixOutcome.contains(
                        String.format(
                            System.Label.Core_HealthCheck_FixStoppedOnly,
                            new List<Object>{ otherJob }
                        )
                    ),
                    'A job it never schedules is said to be stopped only: ' + report.fixOutcome
                );
                Assert.areEqual(
                    1,
                    [
                        SELECT COUNT()
                        FROM Setting_Change__c
                        WHERE
                            Setting_Name__c = :('Health Check: ' +
                            System.Label.Core_HealthCheck_InactiveOwnerJobsFix)
                    ],
                    'The fix is recorded in the settings change history'
                );
            }
            ScheduledJobSelector.ownerOverride = null;
            ScheduledJobSelector.forget();
            Assert.isNull(
                ScheduledJobSelector.triggerIdByName(otherJob),
                'The unknown job was stopped'
            );
            Assert.isNotNull(
                ScheduledJobSelector.triggerIdByName(ErrorDigestScheduler.JOB_NAME),
                'The known job runs again'
            );
        }
    }

    @IsTest
    static void aJobTheOrgAlreadyHasIsHandledLikeAnyOtherAndOnlyWhenItsOwnerIsGone() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            Id gone = inactiveUserId();
            String otherJob = 'BarnCRM Fix test job';
            String orgJob = TabAccessScheduler.JOB_NAME;
            clearOrgBarnCrmJobs();
            // What an install leaves behind: the tab access check, owned by an active user.
            TabAccessScheduler.start();
            ScheduledJobSelector.schedule(otherJob, '0 0 3 * * ?', new ErrorDigestScheduler());
            NightlyJobs.jobsOverride = new List<NightlyJob>{ new NightlyJobs.TabAccessJob() };
            String fixKey = HealthCheckService.FIX_KEY_RESCHEDULE_INACTIVE_OWNER_JOBS;

            System.runAs(maria) {
                Assert.isTrue(
                    HealthCheckService.fixScope(fixKey).isEmpty(),
                    'Jobs of an active owner are left alone, the org\'s own included'
                );

                ScheduledJobSelector.ownerOverride = gone;
                ScheduledJobSelector.forget();
                List<String> scope = HealthCheckService.fixScope(fixKey);
                Assert.areEqual(
                    new List<String>{ otherJob, orgJob },
                    scope,
                    'Once the owner is gone, every one of the jobs is named'
                );

                // No startTest: the scheduled run must not execute inside the test.
                HealthCheckService.Report report = HealthCheckController.applyFix(fixKey, scope);

                Assert.isTrue(
                    report.fixOutcome.contains(
                        String.format(
                            System.Label.Core_HealthCheck_FixScheduled,
                            new List<Object>{ orgJob }
                        )
                    ),
                    'The org\'s own job Health Check knows is scheduled again: ' + report.fixOutcome
                );
                Assert.isTrue(
                    report.fixOutcome.contains(
                        String.format(
                            System.Label.Core_HealthCheck_FixStoppedOnly,
                            new List<Object>{ otherJob }
                        )
                    ),
                    'The one it never schedules is said to be stopped only: ' + report.fixOutcome
                );
            }
            ScheduledJobSelector.ownerOverride = null;
            ScheduledJobSelector.forget();
            Assert.isNotNull(
                ScheduledJobSelector.triggerIdByName(orgJob),
                'The org\'s own job is scheduled again'
            );
            Assert.isNull(
                ScheduledJobSelector.triggerIdByName(otherJob),
                'The unknown job was stopped'
            );
        }
    }

    @IsTest
    static void aFixHealthCheckDoesNotHaveIsRefusedAndChangesNothing() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();

            System.runAs(maria) {
                try {
                    HealthCheckController.applyFix('deleteEverything', new List<String>());
                    Assert.fail('An unknown fix is refused.');
                } catch (AuraHandledException expected) {
                    Assert.areEqual(
                        System.Label.Core_HealthCheck_FixUnknown,
                        expected.getMessage(),
                        'Refused with a sentence.'
                    );
                }
                try {
                    HealthCheckController.applyFix(null, null);
                    Assert.fail('No fix is refused.');
                } catch (AuraHandledException expected) {
                    Assert.isNotNull(expected.getMessage(), 'Refused with a sentence.');
                }
            }
        }
    }
}
