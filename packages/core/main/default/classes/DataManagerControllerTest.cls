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
    static void theRealPermissionDecidesWhenNothingIsStated() {
        List<Import_Template__c> rows = templates(2);
        System.runAs(TestUsers.admin()) {
            insert rows;
            Test.startTest();
            List<DataManagerController.Mapping> forAdmin = DataManagerController.getMappings();
            Test.stopTest();

            Assert.areEqual(
                2,
                forAdmin.size(),
                'A person holding Manage BarnCRM Settings through the Admin permission set sees the mappings'
            );
        }
        System.runAs(TestUsers.standardUser('Unpermitted')) {
            Assert.isTrue(
                DataManagerController.getMappings().isEmpty(),
                'A person without the permission sees an empty card, not an error'
            );
        }
    }

    @IsTest
    static void aReaderWhoCannotSeeMappingsGetsAUserMessageNotAStackTrace() {
        System.runAs(TestUsers.admin()) {
            insert templates(1);
        }
        System.runAs(TestUsers.standardUser('Blocked')) {
            DataManagerController.permissionOverride = true;
            try {
                DataManagerController.getMappings();
                Assert.fail('A user without access to the mapping object is refused');
            } catch (AuraHandledException refused) {
                Assert.isFalse(
                    String.isBlank(refused.getMessage()),
                    'The screen is given the reason to show'
                );
            }
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

    @IsTest
    static void namesTheFindToolStateKeyForThisNamespace() {
        System.runAs(TestUsers.admin()) {
            String key = DataManagerController.findToolStateKey();
            Assert.areEqual(
                NamespaceUtil.stateKey('tool'),
                key,
                'Find reads the key by its __tool suffix, whatever the prefix.'
            );
            Assert.isTrue(key.endsWith('__tool'), 'The key ends in __tool.');
        }
    }
}
