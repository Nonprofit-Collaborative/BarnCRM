/**
 * What the Rollup Builder shows and hands out for instant totals on an object BarnCRM ships no
 * trigger for (ADR-0137): the names, the generated code and packages, each object's state read
 * from the org, and the switch. A test cannot deploy a trigger, so the org's generated triggers
 * and which objects can carry one are put in front of the class through its two seams. Account
 * has no packaged rollup trigger; Contact has one (the Core_Rollups_Contact registry row).
 */
@IsTest(testFor='ApexClass:RollupInstantTotals')
private class RollupInstantTotalsTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    private static User admin() {
        return TestUsers.adminWith('Rollup_Builder_Admin');
    }

    private static void insertInstantRollupOnAccount() {
        insert new Rollup_Definition__c(
            Name = 'Child organization count',
            Definition_Key__c = 'Custom_Instant_Totals_Count',
            Source_Object__c = 'Account',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'NumberOfEmployees',
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    private static void orgHas(String triggerStatus) {
        RollupInstantTotals.triggersOverride = new List<RollupInstantTotals.GeneratedTrigger>();
        if (triggerStatus != null) {
            RollupInstantTotals.triggersOverride.add(
                new RollupInstantTotals.GeneratedTrigger(
                    'BarnRollup_Account',
                    triggerStatus,
                    'Account'
                )
            );
        }
        RollupInstantTotals.triggerableOverride = new Set<String>{ 'Account', 'Contact' };
    }

    private static RollupInstantTotals.ObjectState accountState() {
        for (RollupInstantTotals.ObjectState state : RollupInstantTotals.getStates()) {
            if (state.objectApiName == 'Account') {
                return state;
            }
        }
        return null;
    }

    @IsTest
    static void theCodeIsOneLineAndATestThatToleratesARefusedRecord() {
        System.runAs(admin()) {
            orgHas(null);
            RollupInstantTotals.GeneratedCode code = RollupInstantTotals.getCode('Account');

            System.Assert.isTrue(
                code.triggerSource.contains(
                    'trigger BarnRollup_Account on Account (before insert, after insert, after update, before delete, after delete, after undelete) {'
                ),
                'The trigger covers every event a total depends on: ' + code.triggerSource
            );
            System.Assert.isTrue(
                code.triggerSource.contains(RollupInstantTrigger.class.getName() + '.run();'),
                'Its body is the one entry point, named as subscriber code must name it.'
            );
            System.Assert.isTrue(
                code.testSource.contains('private class BarnRollup_Account_Test'),
                'The test is named after the trigger.'
            );
            System.Assert.isTrue(
                code.testSource.contains(
                    'Database.insert(new List<SObject>{ new Account() }, false, AccessLevel.SYSTEM_MODE);'
                ),
                'The insert may be refused without failing the test.'
            );
            System.Assert.isTrue(
                code.testSource.contains('.hasRun()'),
                'The test asserts that the trigger ran.'
            );

            Compression.ZipReader deploy = new Compression.ZipReader(
                EncodingUtil.base64Decode(code.deployPackage)
            );
            Set<String> entries = new Set<String>();
            for (Compression.ZipEntry entry : deploy.getEntries()) {
                entries.add(entry.getName());
            }
            System.Assert.areEqual(
                new Set<String>{
                    'package.xml',
                    'triggers/BarnRollup_Account.trigger',
                    'triggers/BarnRollup_Account.trigger-meta.xml',
                    'classes/BarnRollup_Account_Test.cls',
                    'classes/BarnRollup_Account_Test.cls-meta.xml'
                },
                entries,
                'The deploy package is a Metadata API zip of the trigger and its test.'
            );
            System.Assert.areEqual(
                code.triggerSource,
                deploy.extract(deploy.getEntry('triggers/BarnRollup_Account.trigger')).toString(),
                'The package holds the code the Builder shows.'
            );

            Compression.ZipReader removal = new Compression.ZipReader(
                EncodingUtil.base64Decode(code.removalPackage)
            );
            String destructive = removal.extract(removal.getEntry('destructiveChanges.xml'))
                .toString();
            System.Assert.isTrue(
                destructive.contains('<members>BarnRollup_Account</members>') &&
                destructive.contains('<members>BarnRollup_Account_Test</members>'),
                'The removal package deletes the trigger and its test: ' + destructive
            );
            System.Assert.isFalse(
                removal.extract(removal.getEntry('package.xml')).toString().contains('<types>'),
                'Its package.xml names nothing to deploy.'
            );
        }
    }

    @IsTest
    static void codeIsRefusedWhereItCannotOrNeedNotRun() {
        System.runAs(admin()) {
            orgHas(null);
            RollupInstantTotals.triggerableOverride = new Set<String>{ 'Contact' };
            Map<String, String> refusals = new Map<String, String>{
                'Contact' => Label.Core_RollupBuilder_InstantBuiltInError,
                'Account' => Label.Core_RollupBuilder_InstantNotAvailableError,
                'Not_An_Object__c' => Label.Core_Rollups_ErrorUnknownObject
            };
            for (String objectName : refusals.keySet()) {
                try {
                    RollupInstantTotals.getCode(objectName);
                    System.Assert.fail('No code for ' + objectName);
                } catch (AuraHandledException refused) {
                    System.Assert.areEqual(
                        refusals.get(objectName),
                        refused.getMessage(),
                        'Refused in plain words for ' + objectName
                    );
                }
            }
        }
    }

    @IsTest
    static void eachObjectShowsItsRealState() {
        System.runAs(admin()) {
            insertInstantRollupOnAccount();

            orgHas(null);
            RollupInstantTotals.ObjectState state = accountState();
            System.Assert.areEqual(
                RollupInstantTotals.STATUS_NOT_SET_UP,
                state.status,
                'No trigger yet.'
            );
            System.Assert.areEqual(1, state.instantRollups, 'One Both rollup counts accounts.');
            System.Assert.areEqual('BarnRollup_Account', state.triggerName, 'Named for the steps.');

            orgHas('Active');
            System.Assert.areEqual(
                RollupInstantTotals.STATUS_ON,
                accountState().status,
                'Deployed.'
            );

            orgHas('Inactive');
            System.Assert.areEqual(
                RollupInstantTotals.STATUS_INACTIVE,
                accountState().status,
                'Deployed but deactivated in Setup.'
            );

            orgHas(null);
            RollupInstantTotals.triggerableOverride = new Set<String>();
            System.Assert.areEqual(
                RollupInstantTotals.STATUS_NOT_AVAILABLE,
                RollupInstantTotals.getState('Account').status,
                'The platform allows no trigger on it.'
            );
            System.Assert.areEqual(
                RollupInstantTotals.STATUS_BUILT_IN,
                RollupInstantTotals.getState('Contact').status,
                'BarnCRM ships the trigger for people.'
            );
        }
    }

    @IsTest
    static void aTriggerNoRollupUsesIsStillListed() {
        System.runAs(admin()) {
            orgHas('Active');
            RollupInstantTotals.ObjectState state = accountState();
            System.Assert.isNotNull(state, 'Listed so it can be turned off or removed.');
            System.Assert.areEqual(0, state.instantRollups, 'No rollup counts it any more.');
            System.Assert.areEqual(RollupInstantTotals.STATUS_ON, state.status, 'It still runs.');
        }
    }

    @IsTest
    static void turningOffNeedsNoDeployAndCanBeUndone() {
        System.runAs(admin()) {
            orgHas('Active');

            Test.startTest();
            RollupInstantTotals.ObjectState turnedOff = RollupInstantTotals.setTurnedOn(
                'Account',
                false
            );
            RollupInstantTotals.ObjectState turnedOn = RollupInstantTotals.setTurnedOn(
                'Account',
                true
            );
            Test.stopTest();

            System.Assert.areEqual(
                RollupInstantTotals.STATUS_OFF,
                turnedOff.status,
                'Off at once.'
            );
            System.Assert.areEqual(RollupInstantTotals.STATUS_ON, turnedOn.status, 'On again.');
            Automation_Setting__c row = [
                SELECT Name, Object_Name__c, Is_Package_Default__c
                FROM Automation_Setting__c
                WHERE Automation_Name__c = 'BarnRollup_Account'
            ];
            System.Assert.areEqual('Account', row.Object_Name__c, 'The switch names its object.');
            System.Assert.isFalse(row.Is_Package_Default__c, 'It is not a shipped switch.');
        }
    }

    @IsTest
    static void staffCannotSwitchIt() {
        System.runAs(admin()) {
            orgHas('Active');
            User david = TestDataFactory.createUser(
                'David',
                new List<String>{ 'BarnCRM_Staff', 'Rollup_Builder_User' }
            );
            System.runAs(david) {
                try {
                    RollupInstantTotals.setTurnedOn('Account', false);
                    System.Assert.fail('Staff cannot change an automation switch.');
                } catch (AuraHandledException refused) {
                    System.Assert.areEqual(
                        Label.Core_Automation_NoPermission,
                        refused.getMessage(),
                        'Refused, with the permission named.'
                    );
                }
            }
        }
    }
}
