/**
 * The Seasonal Addresses switch on the Addresses page of BarnCRM Settings: saving it on
 * schedules the nightly swap, saving it off stops it, and neither doubles or loses the job.
 *
 * An org may already have BarnCRM jobs scheduled, so every count is taken against what the org
 * held before the test changed anything, and the swap's own job is cleared first.
 */
@IsTest(testFor='ApexClass:SeasonalAddressScheduler')
private class SeasonalAddressSwitchTest {
    private static final String KEY = 'Seasonal_Addresses_Enabled__c';

    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** The org with the switch off and the swap not scheduled, whatever it held before. */
    private static void startFromOff() {
        SettingsService.saveBookkeeping(new Map<String, Object>{ KEY => false });
        TestDataFactory.clearScheduledJobs(new List<String>{ SeasonalAddressScheduler.JOB_NAME });
        ScheduledJobSelector.forget();
        SettingsService.clearCaches();
    }

    private static Integer swapJobs() {
        return [
            SELECT COUNT()
            FROM CronTrigger
            WHERE CronJobDetail.Name = :SeasonalAddressScheduler.JOB_NAME
        ];
    }

    private static Integer allApexJobs() {
        return [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.JobType = '7'];
    }

    private static void saveSwitch(Boolean enabled) {
        SettingsController.saveSettings(new Map<String, Object>{ KEY => enabled });
    }

    @IsTest
    static void theSwitchIsOffUntilAnAdministratorTurnsItOn() {
        System.runAs(TestUsers.admin()) {
            delete [SELECT Id FROM BarnCRM_Settings__c];
            SettingsService.clearCaches();
            TestDataFactory.clearScheduledJobs(
                new List<String>{ SeasonalAddressScheduler.JOB_NAME }
            );
            ScheduledJobSelector.forget();

            Assert.isFalse(
                SeasonalAddressScheduler.isEnabled(),
                'A new install has Seasonal Addresses off'
            );
            Assert.isFalse(
                SeasonalAddressScheduler.isScheduled(),
                'And nothing schedules the job behind its back'
            );
        }
    }

    @IsTest
    static void turningItOnSchedulesTheNightlyJob() {
        System.runAs(TestUsers.admin()) {
            startFromOff();
            Integer before = allApexJobs();

            Test.startTest();
            saveSwitch(true);
            Test.stopTest();

            Assert.isTrue(SeasonalAddressScheduler.isEnabled(), 'The switch is on');
            Assert.areEqual(1, swapJobs(), 'One nightly swap is scheduled, under its usual name');
            Assert.areEqual(before + 1, allApexJobs(), 'And nothing else was scheduled');
            Assert.isNotNull(
                SeasonalAddressScheduler.nextRunAt(),
                'The job shows when it runs next'
            );
        }
    }

    @IsTest
    static void turningItOffStopsTheNightlyJob() {
        System.runAs(TestUsers.admin()) {
            startFromOff();
            saveSwitch(true);
            Integer scheduled = allApexJobs();

            Test.startTest();
            saveSwitch(false);
            Test.stopTest();

            Assert.isFalse(SeasonalAddressScheduler.isEnabled(), 'The switch is off');
            Assert.areEqual(0, swapJobs(), 'The nightly swap is no longer scheduled');
            Assert.areEqual(scheduled - 1, allApexJobs(), 'Only the swap was stopped');
        }
    }

    @IsTest
    static void turningItOnWhenTheJobIsAlreadyScheduledLeavesOneJob() {
        System.runAs(TestUsers.admin()) {
            startFromOff();
            // The job already exists, as when Health Check scheduled it or an upgrade kept it.
            Id existing = SeasonalAddressScheduler.start();
            Integer before = allApexJobs();

            Test.startTest();
            saveSwitch(true);
            SeasonalAddressScheduler.applySwitch(true);
            SeasonalAddressScheduler.scheduleIfEnabled();
            Test.stopTest();

            Assert.areEqual(1, swapJobs(), 'Never two jobs under the one name');
            Assert.areEqual(before, allApexJobs(), 'No extra job was scheduled');
            Assert.areEqual(
                existing,
                ScheduledJobSelector.triggerIdByName(SeasonalAddressScheduler.JOB_NAME),
                'The job that was there is the one that stays'
            );
        }
    }

    @IsTest
    static void turningItOffWhenNoJobIsScheduledIsHarmless() {
        System.runAs(TestUsers.admin()) {
            startFromOff();
            saveSwitch(true);
            SeasonalAddressScheduler.stop();
            Integer before = allApexJobs();

            Test.startTest();
            saveSwitch(false);
            Test.stopTest();

            Assert.areEqual(0, swapJobs(), 'Still not scheduled');
            Assert.areEqual(before, allApexJobs(), 'Nothing else was touched');
        }
    }

    @IsTest
    static void savingAnotherSettingLeavesTheJobAlone() {
        System.runAs(TestUsers.admin()) {
            startFromOff();
            saveSwitch(true);
            Id scheduled = ScheduledJobSelector.triggerIdByName(SeasonalAddressScheduler.JOB_NAME);

            Test.startTest();
            SettingsController.saveSettings(
                new Map<String, Object>{
                    'Contact_Address_Change_Behavior__c' => 'Create personal address'
                }
            );
            Test.stopTest();

            Assert.areEqual(
                scheduled,
                ScheduledJobSelector.triggerIdByName(SeasonalAddressScheduler.JOB_NAME),
                'A save that does not touch the switch does not reschedule the job'
            );
        }
    }

    @IsTest
    static void aPersonWithoutThePermissionCannotChangeTheSwitchOrTheJob() {
        System.runAs(TestUsers.admin()) {
            // The person is made before any settings write, which keeps setup and data writes apart.
            User reader = TestDataFactory.createUser('Reader', new List<String>());
            startFromOff();

            Test.startTest();
            System.runAs(reader) {
                try {
                    saveSwitch(true);
                    Assert.fail('Saving Seasonal Addresses must need Manage BarnCRM Settings');
                } catch (AuraHandledException expected) {
                    Assert.areEqual(
                        System.Label.Core_Settings_PermissionRequiredError,
                        expected.getMessage(),
                        'The refusal names the permission'
                    );
                }
            }
            Test.stopTest();

            SettingsService.clearCaches();
            Assert.isFalse(SeasonalAddressScheduler.isEnabled(), 'The switch stayed off');
            Assert.areEqual(0, swapJobs(), 'And no job was scheduled');
        }
    }

    @IsTest
    static void theSwapPanelShowsTheSwitchAndTheSchedule() {
        System.runAs(TestUsers.admin()) {
            startFromOff();
            SeasonalAddressController.SwapView before = SeasonalAddressController.getSwap();
            saveSwitch(true);
            SeasonalAddressController.SwapView after = SeasonalAddressController.getSwap();

            Assert.isFalse(before.enabled, 'Off before it is turned on');
            Assert.isFalse(before.scheduled, 'And not scheduled');
            Assert.isTrue(after.enabled, 'On once saved');
            Assert.isTrue(after.scheduled, 'And scheduled by that save, with no button pressed');
        }
    }

    @IsTest
    static void healthCheckSchedulesTheSwapOnlyWhileTheSwitchIsOn() {
        System.runAs(TestUsers.admin()) {
            startFromOff();
            for (String className : NightlyJobs.PROVIDER_CLASSES) {
                NightlyJobs.providerOverrides.put(className, new EmptyProvider());
            }

            Boolean listedWhileOff = hasSeasonalJob(NightlyJobs.all());
            saveSwitch(true);
            SeasonalAddressScheduler.stop();
            Boolean listedWhileOn = hasSeasonalJob(NightlyJobs.all());

            Assert.isFalse(
                listedWhileOff,
                'An administrator who switched the swap off is not told to schedule it'
            );
            Assert.isTrue(listedWhileOn, 'With the switch on, a missing job is listed');
        }
    }

    private static Boolean hasSeasonalJob(List<NightlyJob> jobs) {
        for (NightlyJob job : jobs) {
            if (job instanceof NightlyJobs.SeasonalAddressJob) {
                return true;
            }
        }
        return false;
    }

    /** A module provider that has no jobs, so the modules in the test org change nothing. */
    private class EmptyProvider implements NightlyJobProvider {
        public List<NightlyJob> nightlyJobs() {
            return new List<NightlyJob>();
        }
    }
}
