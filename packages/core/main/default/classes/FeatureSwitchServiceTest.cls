/**
 * Core features are off on a new install, all on after an upgrade, and turned on for good
 * (ADR-NEXT): a tool through Features Turned On, a feature group with its automations too.
 */
@IsTest(testFor='ApexClass:FeatureSwitchService')
private class FeatureSwitchServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void anUpgradedOrgHasEveryFeatureOn() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Set<String> tabSets = FeatureSwitchService.tabSetsOn();
            Set<String> hidden = FeatureSwitchService.hiddenSettingRows();
            Set<String> stopped = FeatureSwitchService.automationsOff();
            Test.stopTest();

            Assert.areEqual(5, tabSets.size(), 'Every feature tab is on');
            Assert.isTrue(hidden.isEmpty(), 'No settings row is hidden');
            Assert.isTrue(stopped.isEmpty(), 'And no automation is stopped');
        }
    }

    @IsTest
    static void aNewInstallHidesEverythingUntilFirstRunSetup() {
        System.runAs(TestUsers.admin()) {
            FeatureSwitchService.markNewInstall();

            Test.startTest();
            Boolean dataManagerOn = FeatureSwitchService.isOn(FeatureSwitchService.DATA_MANAGER);
            Set<String> hidden = FeatureSwitchService.hiddenSettingRows();
            Boolean relationshipsRun = AutomationControl.isEnabled('Relationship_Reciprocal');
            Test.stopTest();

            Assert.isFalse(dataManagerOn, 'Data Manager is off');
            Assert.isTrue(FeatureSwitchService.tabSetsOn().isEmpty(), 'No feature tab is on');
            Assert.isTrue(hidden.contains('Duplicate_Review'), 'Feature rows are hidden');
            Assert.isFalse(relationshipsRun, 'A feature that is off runs no automation');
        }
    }

    @IsTest
    static void mariaTurnsRelationshipsOnForGood() {
        System.runAs(TestUsers.admin()) {
            FeatureSwitchService.markNewInstall();

            Test.startTest();
            FeatureSwitchService.turnOn(FeatureSwitchService.RELATIONSHIPS);
            FeatureSwitchService.turnOn(FeatureSwitchService.RELATIONSHIPS);
            Test.stopTest();

            Assert.areEqual(
                FeatureSwitchService.RELATIONSHIPS,
                SettingsService.getSettings().Features_Turned_On__c,
                'Only the feature turned on is listed, once'
            );
            Assert.isTrue(
                AutomationControl.isEnabled('Relationship_Reciprocal'),
                'Its automation runs'
            );
            Assert.isFalse(
                FeatureSwitchService.hiddenSettingRows().contains('Relationship_Auto_Reciprocal'),
                'Its settings row shows'
            );
            Assert.isFalse(
                FeatureSwitchService.isOn(FeatureSwitchService.ADDRESSES),
                'Other features stay off'
            );
        }
    }

    @IsTest
    static void firstRunSetupTurnsOnTheTickedFeatures() {
        System.runAs(TestUsers.admin()) {
            FeatureSwitchService.markNewInstall();

            Test.startTest();
            FeatureSwitchService.turnOn(
                new Set<String>{
                    FeatureSwitchService.DATA_MANAGER,
                    FeatureSwitchService.HOUSEHOLD_UPKEEP
                }
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<String>{ 'datamanager', 'householdupkeep' },
                FeatureSwitchService.featuresOn(),
                'The two ticked features are on'
            );
            Assert.isTrue(
                FeatureSwitchService.tabSetsOn().contains(TabAccessService.FIND_TAB),
                'Data Manager brings its tabs'
            );
        }
    }

    @IsTest
    static void refusesAKeyThatIsNotAFeature() {
        System.runAs(TestUsers.admin()) {
            Exception refused;

            Test.startTest();
            try {
                FeatureSwitchService.turnOn('Rollups');
            } catch (FeatureSwitchService.FeatureSwitchException e) {
                refused = e;
            }
            Test.stopTest();

            Assert.isNotNull(refused, 'Rollup Builder is a module, not a Core feature');
        }
    }

    @IsTest
    static void everyAutomationAndRowItNamesShips() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            for (FeatureSwitchService.Item item : FeatureSwitchService.all()) {
                for (String automation : item.automations) {
                    Assert.isNotNull(
                        Automation_Registry__mdt.getInstance(automation),
                        item.key + ' names a shipped automation: ' + automation
                    );
                }
                for (String row : item.settingRows) {
                    Assert.isNotNull(
                        Setting_Definition__mdt.getInstance(row),
                        item.key + ' names a shipped settings row: ' + row
                    );
                }
            }
            Test.stopTest();

            Assert.areEqual(3, FeatureSwitchService.tools().size(), 'Three tools');
            Assert.areEqual(5, FeatureSwitchService.featureGroups().size(), 'Five groups');
        }
    }
}
