/**
 * The Seasonal Addresses switch on the Addresses page of BarnCRM Settings: saving it on makes
 * sure the nightly run is scheduled and puts the swap in tonight's run, saving it off leaves the
 * swap out (ADR-0166 nightly-job-dispatcher), and neither doubles the schedule.
 *
 * An org may already have BarnCRM jobs scheduled, so every count is taken against what the org
 * held before the test changed anything, and the run's own test job is cleared first.
 */
@IsTest(testFor='ApexClass:SeasonalAddressScheduler')
private class SeasonalAddressSwitchTest {
    private static final String KEY = 'Seasonal_Addresses_Enabled__c';

    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** The org with the switch off and the nightly run not scheduled, whatever it held before. */
    private static void startFromOff() {
        SettingsService.saveBookkeeping(new Map<String, Object>{ KEY => false });
        TestDataFactory.clearScheduledJobs(new List<String>{ NightlyJobs.jobName() });
        ScheduledJobSelector.forget();
        SettingsService.clearCaches();
        NightlyJobs.forget();
    }

    private static Integer runJobs() {
        return [
            SELECT COUNT()
            FROM CronTrigger
            WHERE CronJobDetail.Name = :NightlyJobs.jobName()
        ];
    }

    private static Integer allApexJobs() {
        return [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.JobType = '7'];
    }

    private static void saveSwitch(Boolean enabled) {
        SettingsController.saveSettings(new Map<String, Object>{ KEY => enabled });
        NightlyJobs.forget();
    }

    private static Boolean inTonightsRun() {
        return NightlyJobs.isOn(NightlyJobs.step(SeasonalAddressScheduler.JOB_NAME));
    }

    @IsTest
    static void theSwitchIsOffUntilAnAdministratorTurnsItOn() {
        System.runAs(TestUsers.admin()) {
            delete [SELECT Id FROM BarnCRM_Settings__c];
            SettingsService.clearCaches();

            Assert.isFalse(
                SeasonalAddressScheduler.isEnabled(),
                'A new install has Seasonal Addresses off'
            );
            Assert.isFalse(
                SeasonalAddressScheduler.isScheduled(),
                'And nothing runs the swap behind its back'
            );
            Assert.isFalse(inTonightsRun(), 'The nightly run leaves it out');
        }
    }

    @IsTest
    static void turningItOnSchedulesTheNightlyRun() {
        System.runAs(TestUsers.admin()) {
            startFromOff();
            Integer before = allApexJobs();

            Test.startTest();
            saveSwitch(true);
            Test.stopTest();

            Assert.isTrue(SeasonalAddressScheduler.isEnabled(), 'The switch is on');
            Assert.areEqual(1, runJobs(), 'The nightly run is scheduled, once');
            Assert.areEqual(before + 1, allApexJobs(), 'And nothing else was scheduled');
            Assert.isTrue(inTonightsRun(), 'The swap is in tonight\'s run');
            Assert.isNotNull(
                SeasonalAddressScheduler.nextRunAt(),
                'The swap shows when it runs next'
            );
        }
    }

    @IsTest
    static void turningItOffLeavesTheSwapOutOfTheRun() {
        System.runAs(TestUsers.admin()) {
            startFromOff();
            saveSwitch(true);
            Integer scheduled = allApexJobs();

            Test.startTest();
            saveSwitch(false);
            Test.stopTest();

            Assert.isFalse(SeasonalAddressScheduler.isEnabled(), 'The switch is off');
            Assert.isFalse(SeasonalAddressScheduler.isScheduled(), 'The swap reads as stopped');
            Assert.isFalse(inTonightsRun(), 'And the nightly run leaves it out');
            Assert.areEqual(scheduled, allApexJobs(), 'The run itself stays, for the other jobs');
        }
    }

    @IsTest
    static void turningItOnWhenTheRunIsAlreadyScheduledLeavesOneJob() {
        System.runAs(TestUsers.admin()) {
            startFromOff();
            // The run already exists, as when Health Check or another page scheduled it.
            Id existing = NightlyJobs.start();
            Integer before = allApexJobs();

            Test.startTest();
            saveSwitch(true);
            SeasonalAddressScheduler.applySwitch(true);
            SeasonalAddressScheduler.scheduleIfEnabled();
            Test.stopTest();

            Assert.areEqual(1, runJobs(), 'Never two runs under the one name');
            Assert.areEqual(before, allApexJobs(), 'No extra job was scheduled');
            Assert.areEqual(
                existing,
                ScheduledJobSelector.triggerIdByName(NightlyJobs.jobName()),
                'The run that was there is the one that stays'
            );
        }
    }

    @IsTest
    static void savingAnotherSettingLeavesTheRunAlone() {
        System.runAs(TestUsers.admin()) {
            startFromOff();
            saveSwitch(true);
            Id scheduled = ScheduledJobSelector.triggerIdByName(NightlyJobs.jobName());

            Test.startTest();
            SettingsController.saveSettings(
                new Map<String, Object>{
                    'Contact_Address_Change_Behavior__c' => 'Create personal address'
                }
            );
            Test.stopTest();

            Assert.areEqual(
                scheduled,
                ScheduledJobSelector.triggerIdByName(NightlyJobs.jobName()),
                'A save that does not touch the switch does not reschedule the run'
            );
        }
    }

    @IsTest
    static void aPersonWithoutThePermissionCannotChangeTheSwitch() {
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
            Assert.areEqual(0, runJobs(), 'And nothing was scheduled');
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
}
