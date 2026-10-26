/**
 * The rollup findings and the Restore shipped rollups fix, which the Rollup Builder module adds
 * to Health Check through `RollupsHealthCheckExtension` (ADR-0048, ADR-0125). Moved here
 * unchanged from `HealthCheckFixesTest` when the checks left Core: each finding names what is
 * missing, counted from this org, and its fix creates exactly that, once. Everything runs as
 * Maria, who holds the permission the checks and the fixes are gated on; the refusal is asserted
 * as Priya. The shipped rollups are supplied in memory and the nightly job runs under a name of
 * its own, so no test depends on what the org it runs in happens to have.
 */
@IsTest(testFor='ApexClass:RollupsHealthCheckExtension')
private class RollupsHealthCheckExtensionTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    private static final String TEST_JOB_NAME = 'BarnCRM Rollups (RollupsHealthCheckExtensionTest)';

    private static Rollup_Definition_Default__mdt memberCountDefault(String mode) {
        return new Rollup_Definition_Default__mdt(
            DeveloperName = 'Core_Household_Member_Count',
            MasterLabel = 'Household member count',
            Definition_Key__c = 'Core_Household_Member_Count',
            Source_Object__c = 'Household_Member__c',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'Household__c',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'Member_Count__c',
            Mode__c = mode,
            Fiscal_Year_Aware__c = false,
            Default_Active__c = true,
            Package__c = 'Core'
        );
    }

    /** A second shipped total, writing a field nothing else writes. */
    private static Rollup_Definition_Default__mdt otherDefault() {
        Rollup_Definition_Default__mdt other = memberCountDefault('Both');
        other.DeveloperName = 'Core_Test_Other_Total';
        other.MasterLabel = 'Other total';
        other.Definition_Key__c = 'Core_Test_Other_Total';
        other.Target_Field__c = 'Other_Total__c';
        return other;
    }

    private static void shipOneRollup(String mode) {
        RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
            memberCountDefault(mode)
        };
    }

    private static void shipTwoRollups() {
        RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
            memberCountDefault('Both'),
            otherDefault()
        };
    }

    /** A definition already in the org, as the administrator left it. */
    private static Rollup_Definition__c existingMemberCount(
        String key,
        Boolean active,
        Boolean packageDefault
    ) {
        return new Rollup_Definition__c(
            Name = key,
            Definition_Key__c = key,
            Source_Object__c = 'Household_Member__c',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'Household__c',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'Member_Count__c',
            Mode__c = RollupService.MODE_BOTH,
            Active__c = active,
            Is_Package_Default__c = packageDefault
        );
    }

    private static HealthCheckService.Finding find(String key) {
        return find(HealthCheckService.run(), key);
    }

    private static HealthCheckService.Finding find(HealthCheckService.Report report, String key) {
        return find(report.getFindings(), key);
    }

    /**
     * A finding from a run already made. A test that reads several findings asks Health Check
     * once, as the panel does: each full run costs a few dozen queries with every module there.
     */
    private static HealthCheckService.Finding find(
        List<HealthCheckService.Finding> findings,
        String key
    ) {
        for (HealthCheckService.Finding finding : findings) {
            if (key.equals(finding.getKey())) {
                return finding;
            }
        }
        return null;
    }

    /** Presses a fix the way the panel does: with the scope the finding carried. */
    private static HealthCheckService.Report press(HealthCheckService.Finding finding) {
        return HealthCheckController.applyFixFor(
            finding.getFixTarget().substring(HealthCheckService.FIX_ACTION_PREFIX.length()),
            finding.getFixScope()
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
    static void aMissingShippedRollupIsNamedAndRestoredOnce() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            shipOneRollup('Both');

            System.runAs(maria) {
                HealthCheckService.Finding finding = find('shipped_rollups_missing');
                Assert.isNotNull(finding, 'A shipped rollup the org does not have is reported.');
                Assert.isTrue(
                    finding.getDetail().contains('Household member count'),
                    'The finding names what the fix will create.'
                );
                Assert.areEqual(
                    HealthCheckService.FIX_ACTION_PREFIX +
                    RollupsHealthCheckExtension.FIX_KEY_RESTORE_ROLLUPS,
                    finding.getFixTarget(),
                    'It carries the restore fix.'
                );
                Assert.areEqual(
                    new List<String>{ 'Household member count' },
                    finding.getFixScope(),
                    'And the names the fix is allowed to create.'
                );

                Test.startTest();
                HealthCheckService.Report report = press(finding);
                assertPressingAgainIsRefused(finding);
                Test.stopTest();

                Assert.isNull(
                    find(report, 'shipped_rollups_missing'),
                    'The re-run report no longer has the finding.'
                );
                Assert.isTrue(
                    report.getFixOutcome().contains('Household member count'),
                    'The panel is told what the fix created.'
                );
                Assert.areEqual(
                    1,
                    [SELECT COUNT() FROM Rollup_Definition__c],
                    'Pressing the fix twice is pressing it once.'
                );
                List<Setting_Change__c> logged = changesLogged();
                Assert.areEqual(
                    1,
                    logged.size(),
                    'The fix is recorded once in the change history.'
                );
                Assert.areEqual(
                    'Health Check: ' + System.Label.Core_HealthCheck_RollupsMissingFix,
                    logged[0].Setting_Name__c,
                    'Under the name of the button that made it.'
                );
                Assert.isTrue(
                    logged[0].New_Value__c.contains('Household member count'),
                    'Naming what it created.'
                );
            }
        }
    }

    @IsTest
    static void aRollupTheAdminSwitchedOffStaysOffAfterARestore() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            shipTwoRollups();
            // Maria switched the shipped member count off; the other total was never created.
            insert existingMemberCount('Core_Household_Member_Count', false, true);

            System.runAs(maria) {
                HealthCheckService.Finding finding = find('shipped_rollups_missing');
                Assert.areEqual(
                    new List<String>{ 'Other total' },
                    finding.getFixScope(),
                    'Only the total the org does not have is offered.'
                );

                Test.startTest();
                press(finding);
                Test.stopTest();
            }

            Rollup_Definition__c memberCount = [
                SELECT Active__c
                FROM Rollup_Definition__c
                WHERE Definition_Key__c = 'Core_Household_Member_Count'
            ];
            Assert.isFalse(memberCount.Active__c, 'A total she switched off stays off (ADR-0048).');
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Rollup_Definition__c],
                'The missing one was created beside it.'
            );
        }
    }

    @IsTest
    static void aShippedTotalWhoseFieldTheAdminAlreadyWritesIsSkippedAndSaidSo() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            shipTwoRollups();
            // Maria's own member count writes the field the shipped one would write.
            insert existingMemberCount('Maria_Member_Count', true, false);

            System.runAs(maria) {
                HealthCheckService.Finding finding = find('shipped_rollups_missing');
                Assert.areEqual(
                    new List<String>{ 'Other total' },
                    finding.getFixScope(),
                    'The shipped member count is not offered: it would write her field twice.'
                );
                Assert.isTrue(
                    finding.getDetail().contains('Household member count'),
                    'The finding says which total is left out, rather than hiding it.'
                );

                Test.startTest();
                HealthCheckService.Report report = press(finding);
                Test.stopTest();

                Assert.isTrue(
                    report.getFixOutcome().contains('Household member count'),
                    'The result lists the skipped total.'
                );
            }

            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Rollup_Definition__c
                    WHERE Definition_Key__c = 'Core_Household_Member_Count'
                ],
                'The shipped member count was not created.'
            );
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Rollup_Definition__c
                    WHERE Definition_Key__c = 'Core_Test_Other_Total'
                ],
                'The other total was.'
            );
        }
    }

    // A fix that fails after writing is rolled back by Core's savepoint, whoever owns the fix:
    // HealthCheckFixesTest.aModulesFixThatFailsAfterWritingLeavesNothingBehind. The failure
    // switch it uses is a Core test seam a module cannot reach.

    @IsTest
    static void aNightlyOnlyRollupWithNoNightlyRunIsAWarningWithTheNightlyJobsFix() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            shipOneRollup(RollupService.MODE_SCHEDULED);
            RollupScheduler.jobNameInUse = TEST_JOB_NAME;
            NightlyJobs.overrideJobsForTest(
                new List<NightlyJob>{ new RollupsNightlyJobProvider.RollupJob() }
            );

            System.runAs(maria) {
                RollupService.ensureDefaults();
                List<HealthCheckService.Finding> found = HealthCheckService.run();
                HealthCheckService.Finding finding = find(found, 'nightly_rollups_not_scheduled');
                Assert.isNotNull(
                    finding,
                    'A rollup waiting on a run nobody scheduled is reported.'
                );
                Assert.areEqual(
                    HealthCheckService.SEVERITY_WARNING,
                    finding.getSeverity(),
                    'A rollup that recalculates only at night is going stale.'
                );
                Assert.isNull(
                    finding.getFixTarget(),
                    'One cause, one button: the nightly jobs fix.'
                );

                HealthCheckService.Finding jobs = find(found, 'nightly_jobs_not_scheduled');
                Assert.areEqual(
                    new List<String>{ System.Label.Core_HealthCheck_JobRollups },
                    jobs.getFixScope(),
                    'The nightly jobs finding names the rollup run.'
                );

                // No startTest: the scheduled run must not execute inside the test.
                HealthCheckService.Report report = press(jobs);
                assertPressingAgainIsRefused(jobs);

                Assert.isTrue(RollupScheduler.isScheduled(), 'The nightly run is scheduled.');
                Assert.isNull(
                    find(report, 'nightly_rollups_not_scheduled'),
                    'The re-run report no longer has the rollup finding.'
                );
                Assert.isNull(
                    find(report, 'nightly_jobs_not_scheduled'),
                    'Nor the nightly jobs finding.'
                );
                Assert.areEqual(
                    String.format(
                        System.Label.Core_HealthCheck_FixScheduled,
                        new List<Object>{ System.Label.Core_HealthCheck_JobRollups }
                    ),
                    report.getFixOutcome(),
                    'The panel is told which jobs were scheduled.'
                );
                Assert.areEqual(
                    1,
                    [SELECT COUNT() FROM CronJobDetail WHERE Name = :TEST_JOB_NAME],
                    'Pressing the fix twice schedules one run.'
                );
            }
        }
    }

    @IsTest
    static void aRollupThatAlsoRunsInRealTimeIsOnlyInformation() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            shipOneRollup(RollupService.MODE_BOTH);
            RollupScheduler.jobNameInUse = TEST_JOB_NAME;

            System.runAs(maria) {
                RollupService.ensureDefaults();
                HealthCheckService.Finding finding = find('nightly_rollups_not_scheduled');
                Assert.isNotNull(finding, 'The unscheduled run is still reported.');
                Assert.areEqual(
                    HealthCheckService.SEVERITY_INFO,
                    finding.getSeverity(),
                    'It still updates as records change; only the nightly correction is missed.'
                );
                Assert.areEqual(
                    System.Label.Core_HealthCheck_NightlyOffDetailOne +
                        ' ' +
                        System.Label.Core_HealthCheck_NightlyOffFixHint,
                    finding.getDetail(),
                    'One total, in the singular, and no "0 of them recalculate only then".'
                );
            }
        }
    }

    @IsTest
    static void theFixesNeedThePermissionAndTheChecksAreNotShownWithoutIt() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User priya = HealthCheckTestHelper.priyaWithoutManageSettings();
            shipOneRollup('Both');

            System.runAs(priya) {
                Assert.isNull(
                    find('shipped_rollups_missing'),
                    'Only somebody who can press the fix is told about it.'
                );
                try {
                    HealthCheckController.applyFixFor(
                        RollupsHealthCheckExtension.FIX_KEY_RESTORE_ROLLUPS,
                        new List<String>{ 'Household member count' }
                    );
                    Assert.fail('Without the permission the fix is refused.');
                } catch (AuraHandledException expected) {
                    Assert.isNotNull(expected.getMessage(), 'Refused with a sentence.');
                }
            }
            Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Definition__c], 'Nothing was created.');
        }
    }

    @IsTest
    static void aFixWhoseScopeChangedSinceTheScanIsRefusedAndCreatesNothing() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            shipTwoRollups();

            System.runAs(maria) {
                try {
                    // The panel read one missing total; the org now has two missing.
                    HealthCheckController.applyFixFor(
                        RollupsHealthCheckExtension.FIX_KEY_RESTORE_ROLLUPS,
                        new List<String>{ 'Household member count' }
                    );
                    Assert.fail('A fix that would create more than was confirmed is refused.');
                } catch (AuraHandledException expected) {
                    Assert.areEqual(
                        System.Label.Core_HealthCheck_FixStale,
                        expected.getMessage(),
                        'With the sentence that tells her to read the finding again.'
                    );
                }
            }
            Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Definition__c], 'Nothing was created.');
        }
    }

    @IsTest
    static void aCheckThatThrowsCostsOnlyItsOwnFinding() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            RollupsHealthCheckExtension.queueStuckAfterMinutes = null;

            System.runAs(maria) {
                Test.startTest();
                List<HealthCheckService.Finding> found = new RollupsHealthCheckExtension()
                    .findings();
                Test.stopTest();

                Boolean failedFound = false;
                for (HealthCheckService.Finding finding : found) {
                    failedFound |= 'check_failed_rollup_queue'.equals(finding.getKey());
                }
                Assert.isTrue(failedFound, 'The broken queue check is reported as failed');
            }
        }
    }

    @IsTest
    static void aSettingsManagerWithoutTheRollupPermissionSetGetsEveryCheck() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();

            System.runAs(maria) {
                Test.startTest();
                List<HealthCheckService.Finding> found = new RollupsHealthCheckExtension()
                    .findings();
                Test.stopTest();

                for (HealthCheckService.Finding finding : found) {
                    Assert.isFalse(
                        finding.getKey().startsWith('check_failed_'),
                        'The queue counts run whatever object access she holds: ' + finding.getKey()
                    );
                }
            }
        }
    }
}
