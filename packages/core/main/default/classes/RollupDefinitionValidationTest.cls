/**
 * The save check on Rollup Definition (canonical model R-R10 and R-R15): a rollup whose field
 * cannot hold its calculation is refused with a message that says what to choose instead, and
 * the Rollups page names each calculation as the administrator reads it.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest
private class RollupDefinitionValidationTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Rollup_Definition__c definition(
        String key,
        String aggregate,
        String sourceField,
        String targetField
    ) {
        return new Rollup_Definition__c(
            Name = key,
            Definition_Key__c = key,
            Source_Object__c = 'Contact',
            Relationship_Path__c = 'AccountId',
            Aggregate__c = aggregate,
            Source_Field__c = sourceField,
            Target_Object__c = 'Account',
            Target_Field__c = targetField,
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    /** 200 definitions in one save: every second one cannot hold its result, and only those fail. */
    @IsTest
    static void twoHundredSavedAtOnceRefuseOnlyTheOnesTheirFieldCannotHold() {
        System.runAs(TestUsers.admin()) {
            List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>();
            for (Integer i = 0; i < 200; i++) {
                Boolean wrong = Math.mod(i, 2) == 1;
                definitions.add(
                    definition(
                        'Test_Check_' + i,
                        'ANY',
                        null,
                        wrong ? 'NumberOfEmployees' : 'Sample_Data__c'
                    )
                );
            }

            Test.startTest();
            List<Database.SaveResult> saved = Database.insert(definitions, false);
            Test.stopTest();

            for (Integer i = 0; i < saved.size(); i++) {
                if (Math.mod(i, 2) == 0) {
                    Assert.isTrue(saved[i].isSuccess(), 'Any into a checkbox saves');
                } else {
                    Assert.isFalse(saved[i].isSuccess(), 'Any into a number does not');
                    Assert.areEqual(
                        Label.Core_Rollups_ErrorTargetNeedsCheckbox,
                        saved[i].getErrors()[0].getMessage(),
                        'And says which kind of field to choose'
                    );
                }
            }
        }
    }

    @IsTest
    static void anAdministratorIsToldWhatToChooseInPlainWords() {
        System.runAs(TestUsers.admin()) {
            User admin = TestDataFactory.createUser(
                'RollupAdm',
                new List<String>{ 'BarnCRM_Admin' }
            );
            Map<String, Rollup_Definition__c> wrong = new Map<String, Rollup_Definition__c>{
                Label.Core_Rollups_ErrorTargetNeedsText => definition(
                    'Test_List_Into_Date',
                    'TEXT_LIST',
                    'LastName',
                    'Anniversary__c'
                ),
                Label.Core_Rollups_ErrorTextTarget => definition(
                    'Test_Sum_Into_Text',
                    'SUM',
                    'Birthdate',
                    'Site'
                ),
                Label.Core_Rollups_ErrorSourceFieldNeeded => definition(
                    'Test_List_Of_Nothing',
                    'TEXT_LIST',
                    null,
                    'Description'
                )
            };
            Map<String, String> refusedWith = new Map<String, String>();

            Test.startTest();
            System.runAs(admin) {
                for (String expected : wrong.keySet()) {
                    try {
                        insert wrong.get(expected);
                        refusedWith.put(expected, null);
                    } catch (DmlException refused) {
                        refusedWith.put(expected, refused.getDmlMessage(0));
                    }
                }
                insert definition('Test_First_Into_Text', 'FIRST', 'LastName', 'Site');
            }
            Test.stopTest();

            for (String expected : wrong.keySet()) {
                Assert.areEqual(
                    expected,
                    refusedWith.get(expected),
                    'Refused with the plain message'
                );
            }
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Rollup_Definition__c
                    WHERE Definition_Key__c = 'Test_First_Into_Text'
                ],
                'First into a text field saves'
            );
        }
    }

    @IsTest
    static void switchingARollupOffDoesNotCheckItsCalculationAgain() {
        System.runAs(TestUsers.admin()) {
            Rollup_Definition__c before = definition('Test_Old', 'SUM', 'Birthdate', 'Site');
            before.Id = Id.valueOf(
                Rollup_Definition__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                    .getKeyPrefix() + '000000000001'
            );
            Rollup_Definition__c switchedOff = before.clone(true);
            switchedOff.Active__c = false;
            Rollup_Definition__c recalculated = before.clone(true);
            recalculated.Aggregate__c = 'MAX';

            TriggerHandler.testNew = new List<SObject>{ switchedOff, recalculated };
            TriggerHandler.testOldMap = new Map<Id, SObject>{ before.Id => before };
            new RollupDefinitionValidationHandler().beforeUpdate();

            Assert.isFalse(switchedOff.hasErrors(), 'An old definition can still be switched off');
            Assert.isTrue(recalculated.hasErrors(), 'A changed calculation is checked');
        }
    }

    @IsTest
    static void theRollupsPageNamesTheCalculationAndATextListSeparator() {
        System.runAs(TestUsers.admin()) {
            Rollup_Definition__c programs = definition(
                'Test_Programs',
                'TEXT_LIST_DISTINCT',
                'Title',
                'Description'
            );
            programs.Delimiter__c = 'Semicolon';
            insert new List<Rollup_Definition__c>{
                programs,
                definition('Test_Any', 'ANY', null, 'Sample_Data__c')
            };

            RollupController.RollupPageView page = RollupController.getPage();

            Map<String, RollupController.RollupView> byKey = new Map<String, RollupController.RollupView>();
            for (RollupController.RollupView view : page.rollups) {
                byKey.put(view.definitionKey, view);
            }
            Assert.areEqual(
                'Text list, each value once',
                byKey.get('Test_Programs').aggregateLabel,
                'By the picklist name'
            );
            Assert.areEqual(
                'Semicolon',
                byKey.get('Test_Programs').delimiterLabel,
                'And its separator'
            );
            Assert.areEqual('Any', byKey.get('Test_Any').aggregateLabel, 'Any');
            Assert.isNull(byKey.get('Test_Any').delimiterLabel, 'Only a text list has a separator');
        }
    }
}
