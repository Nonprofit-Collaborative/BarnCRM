/**
 * Finish Setup (FS1): every package's setup records that it ran, Health Check and the Modules
 * page flag a package here whose setup never ran, and Finish Setup runs its steps, once or
 * twice, only for someone who may manage settings. Maria holds that permission; Priya does not.
 *
 * Core's own post-install class is real here. Every other package is a stand-in injected by key
 * (`ModuleSetups.overrides`), with the real classes hidden (`noneForTest`), so no test depends
 * on which modules the org it runs in has.
 */
@IsTest(testFor='ApexClass:ModuleSetups, ApexClass:CorePostInstall')
private class ModuleSetupsTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** A package's setup steps, counted. Like a real one, safe to run any number of times. */
    private class StubSetup implements ModuleSetup {
        public Integer timesRun = 0;
        public Id installer;

        public void runSetup(Id installerId) {
            timesRun++;
            installer = installerId;
        }
    }

    /** An upgrade from 1.0 with no installer, so nothing is queued. */
    private class UpgradeContext implements InstallContext {
        public Id organizationId() {
            return UserInfo.getOrganizationId();
        }
        public Id installerId() {
            return null;
        }
        public Version previousVersion() {
            return new Version(1, 0);
        }
        public Boolean isUpgrade() {
            return true;
        }
        public Boolean isPush() {
            return false;
        }
    }

    /** An org where no setup has run (custom settings are visible to tests). */
    private static void noSetupRunYet() {
        delete [SELECT Id FROM BarnCRM_Settings__c];
        SettingsService.clearCaches();
    }

    /** Core and Giving here, both with stand-in setups; no other package's setup is found. */
    private static Map<String, StubSetup> stubbedPackages() {
        Map<String, StubSetup> stubs = new Map<String, StubSetup>{
            ModuleSetups.CORE => new StubSetup(),
            'Giving' => new StubSetup()
        };
        ModuleSetups.noneForTest = true;
        ModuleSetups.overrides.putAll(stubs);
        ModuleDetectionService.givingPresentOverride = true;
        ModuleSetups.checkInTests = true;
        return stubs;
    }

    private static HealthCheckService.Finding setupFinding() {
        for (HealthCheckService.Finding finding : HealthCheckService.run()) {
            if (finding.key == 'module_setup_not_run') {
                return finding;
            }
        }
        return null;
    }

    private static ModuleManagerService.ModuleStatus row(
        ModuleManagerController.ManagerState state,
        String name
    ) {
        for (ModuleManagerService.ModuleStatus status : state.modules) {
            if (status.name == name) {
                return status;
            }
        }
        return null;
    }

    @IsTest
    static void coresSetupRecordsThatItRanAndSoDoesAnUpgrade() {
        System.runAs(TestUsers.admin()) {
            noSetupRunYet();

            Test.startTest();
            new CorePostInstall().runSetup(null);
            Boolean afterSetup = ModuleSetups.ran().contains('core');
            noSetupRunYet();
            new CorePostInstall().onInstall(new UpgradeContext());
            Test.stopTest();

            Assert.isTrue(afterSetup, 'Core setup adds Core to the marker');
            Assert.isTrue(
                ModuleSetups.ran().contains('core'),
                'So does the next upgrade, which is how an org set up before the marker gets it'
            );
        }
    }

    @IsTest
    static void aPackageWithNoSetupClassIsNeverFlagged() {
        System.runAs(TestUsers.admin()) {
            noSetupRunYet();
            ModuleSetups.noneForTest = true;
            ModuleDetectionService.givingPresentOverride = true;

            Assert.isFalse(
                ModuleSetups.isPending('Giving', ModuleSetups.ran()),
                'A version from before Finish Setup ships no setup class, so it is not flagged'
            );
            Assert.isTrue(ModuleSetups.pending().isEmpty(), 'Nothing is pending');
        }
    }

    @IsTest
    static void healthCheckFlagsEveryPackageWhoseSetupNeverRan() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            noSetupRunYet();
            stubbedPackages();
            ModuleSetups.markRan(ModuleSetups.CORE);

            System.runAs(maria) {
                HealthCheckService.Finding finding = setupFinding();

                Assert.isNotNull(finding, 'Giving never ran its setup');
                Assert.areEqual(1, finding.fixScope.size(), 'Core has run, so only Giving');
                Assert.areEqual(HealthCheckService.SEVERITY_WARNING, finding.severity, 'A warning');
                Assert.areEqual(
                    HealthCheckService.FIX_ACTION_PREFIX + ModuleSetups.FIX_KEY,
                    finding.fixTarget,
                    'Fixed by Finish Setup'
                );
                Assert.areEqual(
                    System.Label.Core_ModuleSetup_FinishButton,
                    finding.fixLabel,
                    'Its button'
                );
            }
        }
    }

    @IsTest
    static void finishSetupRunsTheStepsAndClearsTheFinding() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            noSetupRunYet();
            Map<String, StubSetup> stubs = stubbedPackages();

            System.runAs(maria) {
                HealthCheckService.Finding finding = setupFinding();
                Assert.areEqual(2, finding.fixScope.size(), 'Core and Giving');

                Test.startTest();
                HealthCheckService.Report report = HealthCheckController.applyFix(
                    ModuleSetups.FIX_KEY,
                    finding.fixScope
                );
                Test.stopTest();

                Assert.areEqual(1, stubs.get(ModuleSetups.CORE).timesRun, 'Core setup ran');
                Assert.areEqual(1, stubs.get('Giving').timesRun, 'Giving setup ran');
                Assert.areEqual(maria.Id, stubs.get('Giving').installer, 'Maria is the installer');
                Assert.isTrue(
                    ModuleSetups.ran().containsAll(new Set<String>{ 'core', 'giving' }),
                    'Both marked'
                );
                Assert.isTrue(
                    report.fixOutcome.contains(String.join(finding.fixScope, ', ')),
                    'Says which'
                );
                for (HealthCheckService.Finding after : report.findings) {
                    Assert.areNotEqual('module_setup_not_run', after.key, 'The finding is gone');
                }
            }
        }
    }

    @IsTest
    static void finishingTwiceIsSafeAndMarksOnce() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();
            noSetupRunYet();
            Map<String, StubSetup> stubs = stubbedPackages();

            System.runAs(maria) {
                Test.startTest();
                ModuleManagerController.ManagerState first = ModuleManagerController.finishSetup(
                    'Giving'
                );
                Boolean pendingBefore = row(first, ModuleSetups.CORE).setupPending;
                ModuleManagerController.ManagerState second = ModuleManagerController.finishSetup(
                    'Giving'
                );
                Test.stopTest();

                Assert.areEqual(2, stubs.get('Giving').timesRun, 'Pressed twice, run twice');
                Assert.isFalse(row(second, 'Giving').setupPending, 'The notice is gone');
                Assert.isTrue(pendingBefore, 'Core still needs its own Finish Setup');
                Assert.areEqual(
                    'Giving',
                    SettingsService.getSettings().Modules_Setup_Run__c,
                    'Marked once, however often it runs'
                );
                Assert.areEqual(
                    new List<String>{ ModuleSetups.CORE },
                    setupFinding().fixScope,
                    'Health Check now lists Core alone'
                );
            }
        }
    }

    @IsTest
    static void finishSetupNeedsThePermission() {
        System.runAs(TestUsers.admin()) {
            User priya = HealthCheckTestHelper.priyaWithoutManageSettings();
            noSetupRunYet();
            Map<String, StubSetup> stubs = stubbedPackages();

            System.runAs(priya) {
                try {
                    HealthCheckController.applyFix(
                        ModuleSetups.FIX_KEY,
                        new List<String>{ 'Core' }
                    );
                    Assert.fail('Health Check refuses Priya');
                } catch (AuraHandledException expected) {
                    Assert.isNotNull(expected.getMessage(), 'With a sentence');
                }
                try {
                    ModuleManagerController.finishSetup(ModuleSetups.CORE);
                    Assert.fail('So does the Modules page');
                } catch (AuraHandledException expected) {
                    Assert.isNotNull(expected.getMessage(), 'With a sentence');
                }
            }
            Assert.areEqual(0, stubs.get(ModuleSetups.CORE).timesRun, 'Nothing ran');
            Assert.isFalse(ModuleSetups.ran().contains('core'), 'Nothing was marked');
        }
    }

    @IsTest
    static void aPackageThatIsNotHereIsRefusedBeforeAnythingRuns() {
        System.runAs(TestUsers.admin()) {
            noSetupRunYet();
            Map<String, StubSetup> stubs = stubbedPackages();

            try {
                ModuleSetups.finish(new List<String>{ ModuleSetups.CORE, 'Nowhere' });
                Assert.fail('An unknown package is refused');
            } catch (ModuleManagerService.ModuleManagerException expected) {
                Assert.areEqual(
                    System.Label.Core_ModuleManager_UnknownModuleError,
                    expected.getMessage(),
                    'With the Module Manager sentence'
                );
            }
            Assert.areEqual(0, stubs.get(ModuleSetups.CORE).timesRun, 'Not even Core ran');
        }
    }
}
