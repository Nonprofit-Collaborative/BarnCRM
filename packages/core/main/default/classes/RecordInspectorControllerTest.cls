/**
 * The Record Inspector (C-55): that an administrator sees every field they may read with its
 * label, API name and value, that nothing they may not read appears, that a person without
 * Manage BarnCRM Settings is refused, and that bad input and oversize values are handled.
 *
 * Runs as permission-set users. The record inspected is an Error Log entry, a BarnCRM object,
 * so the test needs nothing outside Core.
 */
@IsTest(testFor='ApexClass:RecordInspectorController')
private class RecordInspectorControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static RecordInspectorController.FieldRow find(
        RecordInspectorController.Inspection inspection,
        String apiName
    ) {
        for (RecordInspectorController.FieldRow row : inspection.fields) {
            if (row.apiName == apiName) {
                return row;
            }
        }
        return null;
    }

    @IsTest
    static void anAdminSeesEveryReadableFieldWithItsValue() {
        System.runAs(TestUsers.admin()) {
            Error_Log__c entry = TestDataFactory.insertErrorLogs(1, ErrorLogger.STATUS_NEW)[0];

            Test.startTest();
            RecordInspectorController.Inspection inspection = RecordInspectorController.inspect(
                entry.Id
            );
            Test.stopTest();

            Assert.areEqual('Error_Log__c', inspection.objectApiName);
            Assert.areEqual(String.valueOf(entry.Id), inspection.recordId);
            Assert.isFalse(inspection.fieldsCut, 'Nothing is cut on a small object.');
            RecordInspectorController.FieldRow context = find(inspection, 'Context__c');
            Assert.isNotNull(context, 'A BarnCRM field is listed.');
            Assert.areEqual('Test context 0', context.value, 'With its value.');
            Assert.isTrue(context.isCustom, 'Marked custom.');
            Assert.isNotNull(context.label, 'With its label.');
            Assert.isNotNull(find(inspection, 'Id'), 'The standard fields are listed too.');
            Assert.isNotNull(find(inspection, 'CreatedDate').value, 'A date reads as text.');

            Map<String, Schema.SObjectField> described = Schema.Error_Log__c.SObjectType
                .getDescribe()
                .fields.getMap();
            String previous = '';
            for (RecordInspectorController.FieldRow row : inspection.fields) {
                Assert.isTrue(
                    described.get(row.apiName).getDescribe().isAccessible(),
                    'Only readable fields are listed: ' + row.apiName
                );
                Assert.isTrue(previous <= row.label.toLowerCase(), 'Sorted by label.');
                previous = row.label.toLowerCase();
            }
        }
    }

    @IsTest
    static void aLongValueIsCutAndMarked() {
        System.runAs(TestUsers.admin()) {
            Error_Log__c entry = TestDataFactory.insertErrorLogs(1, ErrorLogger.STATUS_NEW)[0];
            entry.Technical_Detail__c = 'x'.repeat(RecordInspectorController.VALUE_LIMIT + 500);
            update entry;

            RecordInspectorController.Inspection inspection = RecordInspectorController.inspect(
                entry.Id
            );

            RecordInspectorController.FieldRow detail = find(inspection, 'Technical_Detail__c');
            Assert.isTrue(detail.truncated, 'The row says it was cut.');
            Assert.areEqual(RecordInspectorController.VALUE_LIMIT, detail.value.length());
            Assert.isFalse(find(inspection, 'Context__c').truncated, 'Short values are whole.');
        }
    }

    @IsTest
    static void tooManyFieldsAreCutAndSaid() {
        System.runAs(TestUsers.admin()) {
            Error_Log__c entry = TestDataFactory.insertErrorLogs(1, ErrorLogger.STATUS_NEW)[0];
            RecordInspectorController.fieldLimit = 5;

            RecordInspectorController.Inspection inspection = RecordInspectorController.inspect(
                entry.Id
            );

            Assert.isTrue(inspection.fieldsCut, 'The result says it is partial.');
            Assert.areEqual(5, inspection.fields.size());
        }
    }

    @IsTest
    static void aPersonWithoutManageSettingsIsRefused() {
        System.runAs(TestUsers.admin()) {
            Error_Log__c entry = TestDataFactory.insertErrorLogs(1, ErrorLogger.STATUS_NEW)[0];
            User jen = TestDataFactory.createUser('Jen', new List<String>{ 'BarnCRM_Staff' });
            System.runAs(jen) {
                try {
                    RecordInspectorController.inspect(entry.Id);
                    Assert.fail('Staff may not use the inspector.');
                } catch (AuraHandledException refused) {
                    Assert.areEqual(
                        Label.Core_RecordInspector_ErrorNoPermission,
                        refused.getMessage()
                    );
                }
            }
        }
    }

    @IsTest
    static void anIdThatIsNotAnIdOrAMissingRecordIsRefused() {
        System.runAs(TestUsers.admin()) {
            Error_Log__c entry = TestDataFactory.insertErrorLogs(1, ErrorLogger.STATUS_NEW)[0];
            Id gone = entry.Id;
            delete entry;
            for (String bad : new List<String>{ 'not an id', null, String.valueOf(gone) }) {
                try {
                    RecordInspectorController.inspect(bad);
                    Assert.fail('Expected a refusal for ' + bad);
                } catch (AuraHandledException refused) {
                    Assert.areEqual(
                        Label.Core_RecordInspector_ErrorNotFound,
                        refused.getMessage(),
                        'A reason written for a person.'
                    );
                }
            }
        }
    }
}
