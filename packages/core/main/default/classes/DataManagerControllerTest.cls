/**
 * DataManagerController: the Data Manager tab's import mappings card lists active mappings, in
 * name order, with their recurring source and last import date, and nothing for a person who
 * cannot import.
 */
@IsTest(testFor='ApexClass:DataManagerController')
private class DataManagerControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static List<Import_Template__c> templates(Integer howMany) {
        List<Import_Template__c> result = new List<Import_Template__c>();
        for (Integer index = 0; index < howMany; index++) {
            result.add(
                new Import_Template__c(
                    Name = 'Mapping ' + String.valueOf(1000 + index),
                    Template_Key__c = 'data_manager_test_' + index,
                    Column_Mapping_JSON__c = ImportTestDataFactory.donorMapping(),
                    Default_Values_JSON__c = '{"version":1,"defaults":[]}',
                    Matching_Rule__c = ImportTemplateService.normalizedRule(
                        ImportTemplateService.RULE_EMAIL
                    ),
                    Person_Mode__c = ImportTemplateService.PERSON_MODE_CONTACTS,
                    Is_Package_Default__c = false,
                    Is_Recurring__c = false,
                    Active__c = true
                )
            );
        }
        return result;
    }

    @IsTest
    static void listsActiveMappingsWithTheirRecurringSource() {
        System.runAs(TestUsers.admin()) {
            List<Import_Template__c> rows = templates(200);
            rows[0].Is_Recurring__c = true;
            rows[0].Source_Name__c = 'Monthly processor export';
            rows[0].Last_Import_Date__c = Date.today().addDays(-3);
            rows[1].Active__c = false;
            insert rows;
            DataManagerController.permissionOverride = true;

            Test.startTest();
            List<DataManagerController.Mapping> mappings = DataManagerController.getMappings();
            Test.stopTest();

            Map<String, DataManagerController.Mapping> byName = new Map<String, DataManagerController.Mapping>();
            for (DataManagerController.Mapping mapping : mappings) {
                byName.put(mapping.name, mapping);
            }
            Assert.isTrue(byName.containsKey('Mapping 1199'), 'Every active mapping is listed.');
            Assert.isFalse(byName.containsKey('Mapping 1001'), 'An inactive mapping is left out.');
            DataManagerController.Mapping recurring = byName.get('Mapping 1000');
            Assert.isTrue(recurring.isRecurring, 'A recurring mapping says so.');
            Assert.areEqual('Monthly processor export', recurring.sourceName, 'With its source.');
            Assert.areEqual(
                Date.today().addDays(-3),
                recurring.lastImportDate,
                'And when last used.'
            );
        }
    }

    @IsTest
    static void listsNothingForAPersonWhoCannotImport() {
        System.runAs(TestUsers.admin()) {
            insert templates(2);
            DataManagerController.permissionOverride = false;

            Test.startTest();
            List<DataManagerController.Mapping> mappings = DataManagerController.getMappings();
            Test.stopTest();

            Assert.areEqual(
                0,
                mappings.size(),
                'Without Manage BarnCRM Settings the card is empty.'
            );
        }
    }
}
