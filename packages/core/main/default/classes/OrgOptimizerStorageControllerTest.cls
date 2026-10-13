/**
 * OrgOptimizerStorageController: the Storage and limits section reads the org's limits and
 * counts BarnCRM's own objects, capped, and refuses a person without Manage BarnCRM Settings.
 */
@IsTest(testFor='ApexClass:OrgOptimizerStorageController')
private class OrgOptimizerStorageControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void readsTheLimitsAndCountsOwnObjects() {
        System.runAs(TestUsers.admin()) {
            List<Error_Log__c> entries = new List<Error_Log__c>();
            for (Integer index = 0; index < 200; index++) {
                entries.add(new Error_Log__c(Message__c = 'Entry ' + index, Status__c = 'New'));
            }
            insert entries;
            OrgOptimizerStorageController.permissionOverride = true;
            OrgOptimizerStorageController.limitsOverride = new Map<String, List<Integer>>{
                'DataStorageMB' => new List<Integer>{ 150, 200 },
                'FileStorageMB' => new List<Integer>{ 10, 0 }
            };

            Test.startTest();
            OrgOptimizerStorageController.Storage storage = OrgOptimizerStorageController.getStorage();
            Test.stopTest();

            Assert.areEqual(2, storage.limits.size(), 'Only the limits the org reports are shown.');
            Assert.areEqual(
                'DataStorageMB',
                storage.limits[0].name,
                'In the order the page shows them.'
            );
            Assert.areEqual(75, storage.limits[0].percent, 'Used over allowed, as a percentage.');
            Assert.areEqual(
                0,
                storage.limits[1].percent,
                'A limit of zero reads as 0%, not an error.'
            );

            OrgOptimizerStorageController.OwnObject errorLog;
            for (OrgOptimizerStorageController.OwnObject own : storage.ownObjects) {
                if (own.apiName.endsWith('Error_Log__c')) {
                    errorLog = own;
                }
            }
            Assert.isNotNull(errorLog, 'The Error Log is one of BarnCRM\'s own objects.');
            Assert.areEqual(200, errorLog.records, 'Every entry is counted.');
            Assert.isFalse(errorLog.moreThan, 'Under the cap.');
            Assert.areEqual(0.4, errorLog.estimatedMB, 'At 2 KB a record.');
        }
    }

    @IsTest
    static void readsTheRealLimitsWithoutAnOverride() {
        System.runAs(TestUsers.admin()) {
            OrgOptimizerStorageController.permissionOverride = true;

            Test.startTest();
            OrgOptimizerStorageController.Storage storage = OrgOptimizerStorageController.getStorage();
            Test.stopTest();

            for (OrgOptimizerStorageController.LimitUse use : storage.limits) {
                Assert.isTrue(use.percent >= 0 && use.percent <= 100, 'A percentage: ' + use.name);
            }
        }
    }

    @IsTest
    static void refusesAPersonWhoCannotManageSettings() {
        System.runAs(TestUsers.admin()) {
            OrgOptimizerStorageController.permissionOverride = false;
            try {
                OrgOptimizerStorageController.getStorage();
                Assert.fail('A person without the permission is refused.');
            } catch (AuraHandledException refused) {
                Assert.areEqual(
                    Label.Core_OrgOptimizer_ErrorNoPermission,
                    refused.getMessage(),
                    'With the sentence that says which permission.'
                );
            }
        }
    }
}
