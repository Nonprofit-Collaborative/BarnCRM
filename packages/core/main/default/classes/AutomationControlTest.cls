/**
 * The switches Maria uses on the Automation page: pause everything, switch one thing off, and
 * the materialization that keeps her choices through an upgrade.
 *
 * Every test that writes runs as a user on a minimal profile whose only access is the packaged
 * BarnCRM Admin permission set, because a test that runs as the system administrator proves
 * nothing about what the package grants.
 */
@IsTest(testFor='ApexClass:AutomationControl')
private class AutomationControlTest {
    private static final String NAMING = 'Household_Naming';
    private static final String HOUSEHOLDS = 'Household_Creation';
    private static final String LOCK = 'Gift_Receipt_Lock';

    private static User barnCrmAdmin() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static User staffOnly() {
        return TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
    }

    @IsTest
    static void mariaPausesForTwoHoursAndTheBannerKnowsWhenItEnds() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            User maria = barnCrmAdmin();

            Test.startTest();
            System.runAs(maria) {
                Datetime until = AutomationControl.pauseAll(2);

                Assert.isTrue(AutomationControl.isPaused(), 'Automation is paused.');
                Assert.isNotNull(AutomationControl.pausedUntil(), 'The banner has an end time.');
                Assert.isTrue(
                    until > System.now().addMinutes(110),
                    'Two hours from now, give or take the time the test took.'
                );
            }
            Test.stopTest();

            List<Setting_Change__c> audit = [
                SELECT Setting_Name__c, Old_Value__c, New_Value__c, Changed_By__c
                FROM Setting_Change__c
            ];
            Assert.areEqual(1, audit.size(), 'Pausing is one audited change.');
            Assert.areEqual(
                AutomationControl.PAUSE_SETTING_NAME,
                audit[0].Setting_Name__c,
                'The audit row names the pause setting.'
            );
            Assert.isTrue(String.isBlank(audit[0].Old_Value__c), 'Nothing was paused before.');
            Assert.isTrue(
                String.isNotBlank(audit[0].New_Value__c),
                'And now there is an end time.'
            );
            Assert.areEqual(
                maria.Id,
                audit[0].Changed_By__c,
                'Maria made the change, not the admin.'
            );
        }
    }

    @IsTest
    static void mariaResumesBeforeThePauseExpires() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.pausedSettings(2);
            User maria = barnCrmAdmin();
            Assert.isTrue(AutomationControl.isPaused(), 'Set up as paused.');

            Test.startTest();
            System.runAs(maria) {
                AutomationControl.resumeAll();
                Assert.isFalse(AutomationControl.isPaused(), 'Resuming starts automation again.');
                Assert.isNull(AutomationControl.pausedUntil(), 'There is no end time to show.');
            }
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Setting_Change__c],
                'Resuming is one audited change.'
            );
        }
    }

    @IsTest
    static void davidCannotPauseResumeOrSwitchAnything() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.insertAutomationSettings(new Map<String, Boolean>{ NAMING => true });
            TestDataFactory.defaultSettings();
            User david = staffOnly();

            Test.startTest();
            System.runAs(david) {
                Assert.isFalse(AutomationControl.canManage(), 'David has no settings permission.');
                for (String action : new List<String>{ 'pause', 'resume', 'switch' }) {
                    try {
                        if (action == 'pause') {
                            AutomationControl.pauseAll(2);
                        } else if (action == 'resume') {
                            AutomationControl.resumeAll();
                        } else {
                            AutomationControl.setEnabled(NAMING, false);
                        }
                        Assert.fail('David should not be able to ' + action + '.');
                    } catch (AutomationControl.AutomationControlException expected) {
                        Assert.areEqual(
                            Label.Core_Automation_NoPermission,
                            expected.getMessage(),
                            'The message names the permission David needs.'
                        );
                    }
                }
            }
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM Setting_Change__c], 'Nothing was changed.');
            Assert.isFalse(AutomationControl.isPaused(), 'And nothing is paused.');
        }
    }

    @IsTest
    static void aPauseThatHasExpiredIsNotAPause() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.pausedSettings(-1);

            Assert.isFalse(
                AutomationControl.isPaused(),
                'A pause in the past has ended by itself.'
            );
            Assert.isNull(AutomationControl.pausedUntil(), 'So there is no banner.');
        }
    }

    @IsTest
    static void anEmptySettingIsNotAPause() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();

            Assert.isFalse(AutomationControl.isPaused(), 'A fresh org is not paused.');
        }
    }

    @IsTest
    static void onlyTheOfferedPauseLengthsAreAccepted() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            User maria = barnCrmAdmin();
            Assert.areEqual(
                new Set<Integer>{ 1, 2, 4, 8, 24 },
                AutomationControl.allowedPauseHours(),
                'The page offers 1, 2, 4, 8 and 24 hours.'
            );

            Test.startTest();
            System.runAs(maria) {
                for (Integer hours : new List<Integer>{ 3, 0, -2, 100, null }) {
                    try {
                        AutomationControl.pauseAll(hours);
                        Assert.fail('A pause of ' + hours + ' hours should be refused.');
                    } catch (AutomationControl.AutomationControlException expected) {
                        Assert.areEqual(
                            Label.Core_Automation_PauseHoursInvalid,
                            expected.getMessage(),
                            'Maria is told which lengths she can choose.'
                        );
                    }
                }
            }
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM Setting_Change__c], 'And nothing is audited.');
        }
    }

    @IsTest
    static void switchingOneAutomationOffIsAuditedAndTakesEffect() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.insertAutomationSettings(
                new Map<String, Boolean>{ NAMING => true, HOUSEHOLDS => true }
            );
            User maria = barnCrmAdmin();
            Assert.isTrue(AutomationControl.isEnabled(NAMING), 'It starts switched on.');

            Test.startTest();
            System.runAs(maria) {
                AutomationControl.setEnabled(NAMING, false);
            }
            Test.stopTest();

            AutomationControl.clearCache();
            Assert.isFalse(AutomationControl.isEnabled(NAMING), 'It is switched off.');
            Assert.isTrue(AutomationControl.isEnabled(HOUSEHOLDS), 'And nothing else changed.');
            List<Setting_Change__c> audit = [
                SELECT Setting_Name__c, Old_Value__c, New_Value__c
                FROM Setting_Change__c
            ];
            Assert.areEqual(1, audit.size(), 'One switch, one audit row.');
            Assert.areEqual('Automation: ' + NAMING, audit[0].Setting_Name__c, 'Named in the row.');
            Assert.areEqual('true', audit[0].Old_Value__c, 'It was on.');
            Assert.areEqual('false', audit[0].New_Value__c, 'Now it is off.');
        }
    }

    @IsTest
    static void switchingSomethingToTheValueItAlreadyHasChangesNothing() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.insertAutomationSettings(new Map<String, Boolean>{ NAMING => true });
            User maria = barnCrmAdmin();

            Test.startTest();
            System.runAs(maria) {
                AutomationControl.setEnabled(NAMING, true);
            }
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Setting_Change__c],
                'Saving without changing anything writes nothing.'
            );
        }
    }

    @IsTest
    static void switchingSomethingThatDoesNotExistSaysSo() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            User maria = barnCrmAdmin();

            Test.startTest();
            System.runAs(maria) {
                try {
                    AutomationControl.setEnabled('Not_An_Automation', false);
                    Assert.fail('An unknown automation should be refused.');
                } catch (AutomationControl.AutomationControlException expected) {
                    Assert.areEqual(
                        Label.Core_Automation_NotFound,
                        expected.getMessage(),
                        'Maria is told to refresh the page.'
                    );
                }
                try {
                    AutomationControl.setEnabled('   ', false);
                    Assert.fail('An empty automation name should be refused.');
                } catch (AutomationControl.AutomationControlException expected) {
                    Assert.areEqual(
                        Label.Core_Automation_NameRequired,
                        expected.getMessage(),
                        'Maria is told to pick an automation.'
                    );
                }
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void anAlwaysRunsAutomationCannotBeSwitched() {
        System.runAs(TestUsers.admin()) {
            Automation_Setting__c lockRow = new Automation_Setting__c(
                Name = 'Gift: receipt lock',
                Automation_Name__c = LOCK,
                Description__c = 'Protects the receipt a donor is holding.',
                Enabled__c = true,
                Always_Runs__c = true,
                Is_Package_Default__c = true
            );
            insert lockRow;
            AutomationControl.clearCache();
            User maria = barnCrmAdmin();

            Test.startTest();
            System.runAs(maria) {
                try {
                    AutomationControl.setEnabled(LOCK, false);
                    Assert.fail('An automation that enforces a rule must not be switchable.');
                } catch (AutomationControl.AutomationControlException expected) {
                    Assert.areEqual(
                        Label.Core_Automation_AlwaysRuns,
                        expected.getMessage(),
                        'Maria is told why the switch will not move.'
                    );
                }
            }
            Test.stopTest();

            Assert.isTrue(
                [SELECT Enabled__c FROM Automation_Setting__c WHERE Id = :lockRow.Id].Enabled__c,
                'And the row was not changed.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Setting_Change__c],
                'A refused change is not an audited change.'
            );
        }
    }

    @IsTest
    static void materializingCarriesAlwaysRunsFromTheShippedRegistry() {
        System.runAs(TestUsers.admin()) {
            Automation_Registry__mdt lockEntry = TestDataFactory.registryEntry(LOCK, true);
            lockEntry.Always_Runs__c = true;
            AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{
                lockEntry,
                TestDataFactory.registryEntry(NAMING, true)
            };

            Test.startTest();
            AutomationControl.ensureDefaults();
            Test.stopTest();

            Map<String, Automation_Setting__c> byName = new Map<String, Automation_Setting__c>();
            for (Automation_Setting__c setting : [
                SELECT Automation_Name__c, Always_Runs__c
                FROM Automation_Setting__c
            ]) {
                byName.put(setting.Automation_Name__c, setting);
            }
            Assert.isTrue(
                byName.get(LOCK).Always_Runs__c,
                'The console can only say why a switch will not move if the flag reaches the row.'
            );
            Assert.isFalse(
                byName.get(NAMING).Always_Runs__c,
                'And an ordinary automation is still an ordinary automation.'
            );
        }
    }

    @IsTest
    static void anAutomationWithNoRowYetStillRuns() {
        System.runAs(TestUsers.admin()) {
            Assert.isTrue(
                AutomationControl.isEnabled('Shipped_But_Not_Materialized_Yet'),
                'A newly shipped automation works from the moment it is installed.'
            );
            Assert.isFalse(
                AutomationControl.isEnabled(null),
                'An automation with no name does not.'
            );
            Assert.isFalse(AutomationControl.isEnabled('  '), 'Nor one with an empty name.');
        }
    }

    @IsTest
    static void bypassIsPerNameAndPerTransaction() {
        System.runAs(TestUsers.admin()) {
            Assert.isFalse(
                AutomationControl.isBypassed(NAMING),
                'Nothing is bypassed to begin with.'
            );

            AutomationControl.bypass(NAMING);
            Assert.isTrue(AutomationControl.isBypassed(NAMING), 'This one is bypassed.');
            Assert.isFalse(AutomationControl.isBypassed(HOUSEHOLDS), 'That one is not.');
            Assert.isFalse(AutomationControl.isBypassed(null), 'An empty name is never bypassed.');

            AutomationControl.bypass(null);
            AutomationControl.clearBypass(null);
            AutomationControl.clearBypass(NAMING);
            Assert.isFalse(AutomationControl.isBypassed(NAMING), 'And the bypass can be cleared.');
        }
    }

    @IsTest
    static void shippedAutomationsAreMaterializedOnceAndNeverOverwritten() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.insertAutomationSettings(new Map<String, Boolean>{ NAMING => false });
            AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{
                TestDataFactory.registryEntry(NAMING, true),
                TestDataFactory.registryEntry(HOUSEHOLDS, true)
            };

            Test.startTest();
            Integer firstRun = AutomationControl.ensureDefaults();
            Integer secondRun = AutomationControl.ensureDefaults();
            Test.stopTest();

            Assert.areEqual(1, firstRun, 'Only the automation with no row yet is created.');
            Assert.areEqual(0, secondRun, 'Running it again creates nothing.');
            Assert.isFalse(
                AutomationControl.isEnabled(NAMING),
                'The choice to switch this one off survives materialization.'
            );
            List<Automation_Setting__c> created = [
                SELECT Automation_Name__c, Enabled__c, Handler_Class__c, Is_Package_Default__c
                FROM Automation_Setting__c
                WHERE Automation_Name__c = :HOUSEHOLDS
            ];
            Assert.areEqual(1, created.size(), 'The new automation has a row.');
            Assert.isTrue(created[0].Enabled__c, 'On by default, as shipped.');
            Assert.isTrue(
                created[0].Is_Package_Default__c,
                'And marked as one the package created.'
            );
            Assert.areEqual(
                HOUSEHOLDS + 'Handler',
                created[0].Handler_Class__c,
                'With the handler from the registry.'
            );
        }
    }

    @IsTest
    static void materializingAnEmptyRegistryDoesNothing() {
        System.runAs(TestUsers.admin()) {
            AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>();

            Assert.areEqual(
                0,
                AutomationControl.ensureDefaults(),
                'v0.1 ships no registry records.'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Automation_Setting__c], 'So there is nothing.');
        }
    }

    @IsTest
    static void materializingIgnoresARegistryEntryWithNoName() {
        System.runAs(TestUsers.admin()) {
            AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{
                new Automation_Registry__mdt(Description__c = 'No developer name.')
            };

            Assert.areEqual(
                0,
                AutomationControl.ensureDefaults(),
                'An entry with no name is skipped.'
            );
        }
    }

    @IsTest
    static void twoHundredAutomationsAreReadInOneQuery() {
        System.runAs(TestUsers.admin()) {
            Map<String, Boolean> many = new Map<String, Boolean>();
            for (Integer i = 0; i < 200; i++) {
                many.put('Bulk_Automation_' + i, Math.mod(i, 2) == 0);
            }
            TestDataFactory.insertAutomationSettings(many);

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            Boolean first = AutomationControl.isEnabled('Bulk_Automation_0');
            Boolean last = AutomationControl.isEnabled('Bulk_Automation_199');
            Integer queriesAfter = Limits.getQueries();
            Test.stopTest();

            Assert.isTrue(first, 'Even numbered automations are on.');
            Assert.isFalse(last, 'Odd numbered ones are off.');
            Assert.areEqual(
                1,
                queriesAfter - queriesBefore,
                'The list is read once per transaction.'
            );
        }
    }
}
