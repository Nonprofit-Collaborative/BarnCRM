/** The console reads what to show from the shipped Setting Definition rows. */
@IsTest(testFor='ApexClass:SettingDefinitionSelector')
private class SettingDefinitionSelectorTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void readsTheShippedRows() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<Setting_Definition__mdt> rows = SettingDefinitionSelector.getAll();
            Test.stopTest();

            Assert.isNotNull(
                rows,
                'The console always gets a list, even in a package with no rows yet'
            );
        }
    }

    @IsTest
    static void usesStubbedRowsWhenATestSuppliesThem() {
        System.runAs(TestUsers.admin()) {
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
                new Setting_Definition__mdt(
                    DeveloperName = 'Household_Name_Pattern',
                    MasterLabel = 'Household name pattern',
                    Setting_Key__c = 'Household_Name_Pattern__c',
                    Section__c = 'Households',
                    Module__c = 'Core',
                    Data_Type__c = 'Text',
                    Sort_Order__c = 1
                )
            };

            Test.startTest();
            List<Setting_Definition__mdt> rows = SettingDefinitionSelector.getAll();
            Test.stopTest();

            Assert.areEqual(
                1,
                rows.size(),
                'Custom metadata cannot be created in a test, so tests supply rows directly'
            );
            Assert.areEqual(
                'Households',
                rows[0].Section__c,
                'The row keeps the section it was given'
            );
        }
    }
}
