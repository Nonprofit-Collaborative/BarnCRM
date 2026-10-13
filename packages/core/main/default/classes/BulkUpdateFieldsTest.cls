/**
 * What a bulk update may write (C-35, canonical model R-BU4): editable fields of the query's own
 * object, never a field the package keeps, never a bookkeeping or setup object, and copies only
 * between fields whose values fit.
 *
 * No org has run these yet; they are written against the behaviour the class documents.
 */
@IsTest
private class BulkUpdateFieldsTest {
    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static Set<String> names(List<BulkUpdateFields.Target> targets) {
        Set<String> result = new Set<String>();
        for (BulkUpdateFields.Target target : targets) {
            result.add(target.apiName);
        }
        return result;
    }

    @IsTest
    static void offersEditableFieldsAndNeverOnesThePackageOrPlatformKeeps() {
        System.runAs(TestUsers.admin()) {
            DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
            Set<String> offered;
            System.runAs(maria()) {
                offered = names(BulkUpdateFields.targets('Contact'));
            }
            System.Assert.isTrue(offered.contains('Title'), 'An editable field is offered');
            System.Assert.isTrue(offered.contains('Work_Email__c'), 'A custom field is offered');
            for (
                String kept : new List<String>{
                    'Id',
                    'Name',
                    'CreatedDate',
                    'Sample_Data_Key__c',
                    'Created_By_Import_Batch__c'
                }
            ) {
                System.Assert.isFalse(offered.contains(kept), kept + ' is never offered');
            }
        }
    }

    @IsTest
    static void aRollupTargetIsKeptWithoutACodeChange() {
        System.runAs(TestUsers.admin()) {
            DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>{
                new Rollup_Definition__c(Target_Object__c = 'Contact', Target_Field__c = 'Title')
            };
            System.runAs(maria()) {
                System.Assert.isFalse(
                    names(BulkUpdateFields.targets('Contact')).contains('Title'),
                    'A rollup target is not offered'
                );
                try {
                    BulkUpdateFields.writableField(Contact.SObjectType, 'Title');
                    System.Assert.fail('A rollup target is refused');
                } catch (BulkUpdateFields.BulkUpdateException refused) {
                    System.Assert.isTrue(
                        refused.getMessage().contains(System.Label.Core_BulkUpdate_ReasonKept),
                        'The refusal says BarnCRM calculates it: ' + refused.getMessage()
                    );
                }
            }

        }
    }

    @IsTest
    static void bookkeepingAndSetupObjectsAreRefused() {
        System.runAs(TestUsers.admin()) {
            System.runAs(maria()) {
                for (String objectName : new List<String>{ 'Error_Log__c', 'Import_Batch__c' }) {
                    try {
                        BulkUpdateFields.writableObject(objectName);
                        System.Assert.fail(objectName + ' is the package\'s own');
                    } catch (BulkUpdateFields.BulkUpdateException refused) {
                        System.Assert.isTrue(
                            refused.getMessage()
                                .contains(System.Label.Core_BulkUpdate_ReasonBookkeeping),
                            refused.getMessage()
                        );
                    }
                }
                try {
                    BulkUpdateFields.writableObject('User');
                    System.Assert.fail('Users are changed in Setup');
                } catch (BulkUpdateFields.BulkUpdateException refused) {
                    System.Assert.isTrue(
                        refused.getMessage().contains(System.Label.Core_BulkUpdate_ReasonSetup),
                        refused.getMessage()
                    );
                }
            }

        }
    }

    @IsTest
    static void aFieldNameIsFoundInDescribeOrRefused() {
        System.runAs(TestUsers.admin()) {
            System.runAs(maria()) {
                for (Object name : new List<Object>{ 'Account.Name', 'Title; DELETE', '', null }) {
                    try {
                        BulkUpdateFields.writableField(Contact.SObjectType, name);
                        System.Assert.fail('Not a field of the object: ' + name);
                    } catch (BulkUpdateFields.BulkUpdateException refused) {
                        System.Assert.isTrue(
                            refused.getMessage().startsWith('A change names a field'),
                            refused.getMessage()
                        );
                    }
                }
            }

        }
    }

    @IsTest
    static void copySourcesAreFieldsWhoseValuesFit() {
        System.runAs(TestUsers.admin()) {
            DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
            Set<String> intoEmail = new Set<String>();
            Set<String> intoText = new Set<String>();
            System.runAs(maria()) {
                for (
                    QueryFieldCatalog.PicklistOption option : BulkUpdateFields.copySources(
                        'Contact',
                        'Personal_Email__c'
                    )
                ) {
                    intoEmail.add(option.value);
                }
                for (
                    QueryFieldCatalog.PicklistOption option : BulkUpdateFields.copySources(
                        'Contact',
                        'Title'
                    )
                ) {
                    intoText.add(option.value);
                }
            }
            System.Assert.isTrue(intoEmail.contains('Work_Email__c'), 'Email into email');
            System.Assert.isFalse(intoEmail.contains('Deceased__c'), 'Never a checkbox into email');
            System.Assert.isFalse(intoEmail.contains('Personal_Email__c'), 'Never itself');
            System.Assert.isTrue(intoText.contains('Work_Email__c'), 'Email into text');
            System.Assert.isTrue(intoText.contains('Preferred_Email__c'), 'Picklist into text');
        }
    }

    @IsTest
    static void aValueToSetIsTypedForItsFieldOrRefused() {
        System.runAs(TestUsers.admin()) {
            Schema.DescribeFieldResult deceased = Contact.Deceased__c.getDescribe();
            Schema.DescribeFieldResult title = Contact.Title.getDescribe();
            Schema.DescribeFieldResult birthdate = Contact.Birthdate.getDescribe();
            System.Assert.areEqual(true, BulkUpdateFields.typed(deceased, 'TRUE'), 'A checkbox');
            System.Assert.areEqual(
                Date.newInstance(2026, 10, 12),
                BulkUpdateFields.typed(birthdate, '2026-10-12'),
                'A date in ISO form'
            );
            System.Assert.areEqual('Volunteer', BulkUpdateFields.typed(title, 'Volunteer'), 'Text');
            for (
                List<Object> refused : new List<List<Object>>{
                    new List<Object>{ deceased, 'maybe' },
                    new List<Object>{ birthdate, '12/10/2026' },
                    new List<Object>{ title, 'x'.repeat(title.getLength() + 1) },
                    new List<Object>{ title, '' }
                }
            ) {
                try {
                    BulkUpdateFields.typed((Schema.DescribeFieldResult) refused[0], refused[1]);
                    System.Assert.fail('Refused: ' + refused[1]);
                } catch (BulkUpdateFields.BulkUpdateException expected) {
                    System.Assert.isTrue(
                        expected.getMessage()
                            .contains(((Schema.DescribeFieldResult) refused[0]).getLabel()),
                        'The refusal names the field'
                    );
                }
            }
        }
    }
}
