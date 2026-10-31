/**
 * DataDictionaryController: the Data Dictionary section lists an object's fields from describe
 * (plan Section 6.1.1 item 13, D-154). Tests run as Maria, a Standard User holding only BarnCRM
 * Admin, so what comes back is what that permission set lets her see.
 */
@IsTest(testFor='ApexClass:DataDictionaryController')
private class DataDictionaryControllerTest {
    private static final String DISMISSAL = Duplicate_Dismissal__c.SObjectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
        )
        .getName();
    private static final String PAIR_KEY = Duplicate_Dismissal__c.Pair_Key__c.getDescribe()
        .getName();
    private static final String IS_ORGANIZATION = Account.Is_Organization__c.getDescribe()
        .getName();
    private static final String ROW_STATUS = Import_Row__c.Status__c.getDescribe().getName();

    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static Map<String, DataDictionaryController.FieldRow> byName(
        DataDictionaryController.ObjectDictionary dictionary
    ) {
        Map<String, DataDictionaryController.FieldRow> found = new Map<String, DataDictionaryController.FieldRow>();
        for (DataDictionaryController.FieldRow row : dictionary.fields) {
            found.put(row.fieldName, row);
        }
        return found;
    }

    private static String refusalOf(String objectName) {
        try {
            DataDictionaryController.describeObject(objectName);
        } catch (AuraHandledException caught) {
            return caught.getMessage();
        }
        return null;
    }

    @IsTest
    static void aFieldIsDescribedWithItsRulesAndHelpText() {
        System.runAs(TestUsers.admin()) {
            DataDictionaryController.ObjectDictionary dictionary;
            System.runAs(maria()) {
                dictionary = DataDictionaryController.describeObject(DISMISSAL);
            }

            Assert.areEqual(DISMISSAL, dictionary.objectName, 'The object API name.');
            Assert.isTrue(dictionary.isCustom, 'Duplicate Dismissal is a custom object.');
            DataDictionaryController.FieldRow key = byName(dictionary).get(PAIR_KEY);
            Assert.isNotNull(key, 'Pair Key is listed.');
            Assert.areEqual('Pair Key', key.fieldLabel, 'Label.');
            Assert.areEqual('string', key.dataType, 'Type.');
            Assert.areEqual(40, key.length, 'Length.');
            Assert.isTrue(key.required, 'Required.');
            Assert.isTrue(key.isUnique, 'Unique.');
            Assert.isTrue(key.externalId, 'External ID.');
            Assert.isTrue(key.isCustom, 'Custom.');
            Assert.areEqual(
                'The two records that are not duplicates of each other.',
                key.helpText,
                'Help text.'
            );
            Assert.isNull(key.formula, 'Not a formula.');
            Assert.isNull(key.picklistValues, 'Not a picklist.');
        }
    }

    @IsTest
    static void aFormulaPicklistAndLookupShowTheirDetail() {
        System.runAs(TestUsers.admin()) {
            DataDictionaryController.ObjectDictionary account;
            DataDictionaryController.ObjectDictionary rows;
            System.runAs(maria()) {
                account = DataDictionaryController.describeObject('Account');
                rows = DataDictionaryController.describeObject(
                    Import_Row__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName()
                );
            }

            Assert.isFalse(account.isCustom, 'Account is a standard object.');
            DataDictionaryController.FieldRow formula = byName(account).get(IS_ORGANIZATION);
            Assert.isFalse(String.isBlank(formula.formula), 'The formula text is shown.');
            DataDictionaryController.FieldRow status = byName(rows).get(ROW_STATUS);
            String first = Import_Row__c.Status__c.getDescribe().getPicklistValues()[0].getValue();
            Assert.isTrue(
                status.picklistValues.startsWith(first),
                'Active picklist values are listed in order.'
            );
            DataDictionaryController.FieldRow parent = byName(account).get('ParentId');
            Assert.areEqual('Account', parent.relatedTo, 'A lookup names what it points to.');
        }
    }

    @IsTest
    static void aManyFieldObjectListsEveryVisibleFieldOnceInLabelOrder() {
        System.runAs(TestUsers.admin()) {
            DataDictionaryController.ObjectDictionary account;
            System.runAs(maria()) {
                account = DataDictionaryController.describeObject('Account');
            }

            Assert.isTrue(account.fields.size() > 40, 'Account has dozens of fields.');
            Set<String> names = new Set<String>();
            String previous = '';
            for (DataDictionaryController.FieldRow row : account.fields) {
                Assert.isTrue(names.add(row.fieldName), 'Each field once: ' + row.fieldName);
                Assert.isTrue(
                    previous <= row.fieldLabel.toLowerCase(),
                    'Sorted by label at ' + row.fieldLabel
                );
                previous = row.fieldLabel.toLowerCase();
            }
        }
    }

    @IsTest
    static void aFieldThePersonCannotSeeIsNotListed() {
        System.runAs(TestUsers.admin()) {
            DataDictionaryController.ObjectDictionary dictionary;
            System.runAs(maria()) {
                dictionary = DataDictionaryController.describeObject(DISMISSAL);
                for (
                    Schema.SObjectField token : Duplicate_Dismissal__c.SObjectType.getDescribe(
                            SObjectDescribeOptions.DEFERRED
                        )
                        .fields.getMap()
                        .values()
                ) {
                    Schema.DescribeFieldResult field = token.getDescribe();
                    Assert.areEqual(
                        field.isAccessible(),
                        byName(dictionary).containsKey(field.getName()),
                        'Listed only when readable: ' + field.getName()
                    );
                }
            }
        }
    }

    @IsTest
    static void thePickerMarksBarnCrmObjectsAndTheCommonStandardOnes() {
        System.runAs(TestUsers.admin()) {
            List<DataDictionaryController.Option> options;
            System.runAs(maria()) {
                options = DataDictionaryController.listObjects();
            }

            Map<String, DataDictionaryController.Option> byValue = new Map<String, DataDictionaryController.Option>();
            for (DataDictionaryController.Option option : options) {
                byValue.put(option.value, option);
            }
            Assert.isTrue(byValue.get('Account').isDefault, 'Account is chosen to start.');
            Assert.isTrue(byValue.get('Contact').isDefault, 'Contact is chosen to start.');
            Assert.isTrue(byValue.get(DISMISSAL).isDefault, 'A BarnCRM object is chosen to start.');
            Assert.isFalse(
                byValue.containsKey(
                    Field_Utilization_Snapshot__c.SObjectType.getDescribe(
                            SObjectDescribeOptions.DEFERRED
                        )
                        .getName()
                ),
                'The snapshot table is not documented.'
            );
        }
    }

    @IsTest
    static void someoneWithoutThePermissionIsRefused() {
        System.runAs(TestUsers.admin()) {
            User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
            String refusal;
            String listRefusal;
            System.runAs(david) {
                refusal = refusalOf(DISMISSAL);
                try {
                    DataDictionaryController.listObjects();
                } catch (AuraHandledException caught) {
                    listRefusal = caught.getMessage();
                }
            }

            Assert.areEqual(
                System.Label.Core_DataDictionary_PermissionRequired,
                refusal,
                'Refused.'
            );
            Assert.areEqual(
                System.Label.Core_DataDictionary_PermissionRequired,
                listRefusal,
                'The list is refused too.'
            );
        }
    }

    @IsTest
    static void anUnknownOrBlankObjectIsRefusedByName() {
        System.runAs(TestUsers.admin()) {
            String unknown;
            String blank;
            System.runAs(maria()) {
                unknown = refusalOf('Nothing_Here__c');
                blank = refusalOf(' ');
            }

            Assert.areEqual(
                String.format(
                    System.Label.Core_DataDictionary_UnknownObject,
                    new List<Object>{ 'Nothing_Here__c' }
                ),
                unknown,
                'The name is in the message.'
            );
            Assert.isNotNull(blank, 'A blank name is refused.');
        }
    }
}
