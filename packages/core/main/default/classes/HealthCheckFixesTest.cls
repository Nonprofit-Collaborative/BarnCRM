/**
 * The Health Check fix buttons C-21 adds (ADR-0048): each finding names what is missing,
 * counted from this org, and its fix creates exactly that, once, or schedules the nightly
 * run, once. Everything runs as Maria, who holds the permission the checks and the fixes are
 * gated on; the refusal is asserted as Priya.
 *
 * Every test arranges the state it asserts: the shipped rollups and automations are supplied
 * in memory, and the nightly job runs under a name of its own, so no test depends on what the
 * org it runs in happens to have. Import templates are the one exception: their shipped rows
 * are read as shipped, and Core ships two, which the test says before it relies on them.
 */
@IsTest
private class HealthCheckFixesTest {
    private static final String TEST_JOB_NAME = 'BarnCRM Rollups (HealthCheckFixesTest)';

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
        return [SELECT Setting_Name__c, Old_Value__c, New_Value__c FROM Setting_Change__c];
    }

    @IsTest
    static void aMissingShippedRollupIsNamedAndRestoredOnce() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        shipOneRollup('Both');

        System.runAs(maria) {
            HealthCheckService.Finding finding = find('shipped_rollups_missing');
            Assert.isNotNull(finding, 'A shipped rollup the org does not have is reported.');
            Assert.isTrue(
                finding.detail.contains('Household member count'),
                'The finding names what the fix will create.'
            );
            Assert.areEqual(
                HealthCheckService.FIX_ACTION_PREFIX + HealthCheckService.FIX_KEY_RESTORE_ROLLUPS,
                finding.fixTarget,
                'It carries the restore fix.'
            );
            Assert.areEqual(
                new List<String>{ 'Household member count' },
                finding.fixScope,
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
                report.fixOutcome.contains('Household member count'),
                'The panel is told what the fix created.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Rollup_Definition__c],
                'Pressing the fix twice is pressing it once.'
            );
            List<Setting_Change__c> logged = changesLogged();
            Assert.areEqual(1, logged.size(), 'The fix is recorded once in the change history.');
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

    @IsTest
    static void aRollupTheAdminSwitchedOffStaysOffAfterARestore() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        shipTwoRollups();
        // Maria switched the shipped member count off; the other total was never created.
        insert existingMemberCount('Core_Household_Member_Count', false, true);

        System.runAs(maria) {
            HealthCheckService.Finding finding = find('shipped_rollups_missing');
            Assert.areEqual(
                new List<String>{ 'Other total' },
                finding.fixScope,
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

    @IsTest
    static void aShippedTotalWhoseFieldTheAdminAlreadyWritesIsSkippedAndSaidSo() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        shipTwoRollups();
        // Maria's own member count writes the field the shipped one would write.
        insert existingMemberCount('Maria_Member_Count', true, false);

        System.runAs(maria) {
            HealthCheckService.Finding finding = find('shipped_rollups_missing');
            Assert.areEqual(
                new List<String>{ 'Other total' },
                finding.fixScope,
                'The shipped member count is not offered: it would write her field twice.'
            );
            Assert.isTrue(
                finding.detail.contains('Household member count'),
                'The finding says which total is left out, rather than hiding it.'
            );

            Test.startTest();
            HealthCheckService.Report report = press(finding);
            Test.stopTest();

            Assert.isTrue(
                report.fixOutcome.contains('Household member count'),
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

    @IsTest
    static void aFixThatFailsAfterWritingLeavesNothingBehind() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        shipOneRollup('Both');

        System.runAs(maria) {
            HealthCheckService.Finding finding = find('shipped_rollups_missing');
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

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Rollup_Definition__c],
            'The total the fix created is rolled back.'
        );
        Assert.areEqual(0, changesLogged().size(), 'And so is its change history entry.');
    }

    @IsTest
    static void missingAutomationSwitchesAreRestoredAndASwitchTurnedOffStaysOff() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        Automation_Registry__mdt lock = TestDataFactory.registryEntry('Test_Receipt_Lock', true);
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
        Assert.areEqual(1, changesLogged().size(), 'The fix is recorded in the change history.');
    }

    @IsTest
    static void missingImportTemplatesAreRestoredOnce() {
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

    @IsTest
    static void aNightlyOnlyRollupWithNoNightlyRunIsAWarningAndTheFixSchedulesIt() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        shipOneRollup(RollupService.MODE_SCHEDULED);
        RollupService.skipEngine = true;
        RollupScheduler.jobNameInUse = TEST_JOB_NAME;

        System.runAs(maria) {
            RollupService.ensureDefaults();
            HealthCheckService.Finding finding = find('nightly_rollups_not_scheduled');
            Assert.isNotNull(finding, 'A rollup waiting on a run nobody scheduled is reported.');
            Assert.areEqual(
                HealthCheckService.SEVERITY_WARNING,
                finding.severity,
                'A rollup that recalculates only at night is going stale.'
            );

            // No startTest: the scheduled run must not execute inside the test.
            HealthCheckService.Report report = press(finding);
            assertPressingAgainIsRefused(finding);

            Assert.isTrue(RollupScheduler.isScheduled(), 'The nightly run is scheduled.');
            Assert.isNull(
                find(report, 'nightly_rollups_not_scheduled'),
                'The re-run report no longer has the finding.'
            );
            Assert.areEqual(
                System.Label.Core_HealthCheck_FixScheduled,
                report.fixOutcome,
                'The panel is told the run is scheduled.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM CronJobDetail WHERE Name = :TEST_JOB_NAME],
                'Pressing the fix twice schedules one run.'
            );
        }
    }

    @IsTest
    static void aRollupThatAlsoRunsInRealTimeIsOnlyInformation() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        shipOneRollup(RollupService.MODE_BOTH);
        RollupScheduler.jobNameInUse = TEST_JOB_NAME;

        System.runAs(maria) {
            RollupService.ensureDefaults();
            HealthCheckService.Finding finding = find('nightly_rollups_not_scheduled');
            Assert.isNotNull(finding, 'The unscheduled run is still reported.');
            Assert.areEqual(
                HealthCheckService.SEVERITY_INFO,
                finding.severity,
                'It still updates as records change; only the nightly correction is missed.'
            );
        }
    }

    @IsTest
    static void theFixesNeedThePermissionAndTheChecksAreNotShownWithoutIt() {
        User priya = HealthCheckTestHelper.priyaWithoutManageSettings();
        shipOneRollup('Both');

        System.runAs(priya) {
            Assert.isNull(
                find('shipped_rollups_missing'),
                'Only somebody who can press the fix is told about it.'
            );
            try {
                HealthCheckController.applyFix(
                    HealthCheckService.FIX_KEY_RESTORE_ROLLUPS,
                    new List<String>{ 'Household member count' }
                );
                Assert.fail('Without the permission the fix is refused.');
            } catch (AuraHandledException expected) {
                Assert.isNotNull(expected.getMessage(), 'Refused with a sentence.');
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Definition__c], 'Nothing was created.');
    }

    @IsTest
    static void aFixHealthCheckDoesNotHaveIsRefusedAndChangesNothing() {
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

    @IsTest
    static void aFixWhoseScopeChangedSinceTheScanIsRefusedAndCreatesNothing() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        shipTwoRollups();

        System.runAs(maria) {
            try {
                // The panel read one missing total; the org now has two missing.
                HealthCheckController.applyFix(
                    HealthCheckService.FIX_KEY_RESTORE_ROLLUPS,
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
