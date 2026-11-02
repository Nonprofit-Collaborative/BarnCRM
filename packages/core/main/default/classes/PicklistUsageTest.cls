/**
 * PicklistUsageService and the picklist methods of FieldUtilizationController: records per
 * picklist value and the newest Last Modified Date among them (canonical model Section 29F,
 * R-FU9 to R-FU11). Counting runs as Maria, a Standard User holding only BarnCRM Admin, on
 * Error Log's Status field (a restricted picklist Core owns). The unit tests of the join work on
 * plain maps, since an inactive value cannot be saved into a restricted field.
 */
@IsTest(testFor='ApexClass:PicklistUsageService')
private class PicklistUsageTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String LOG = Error_Log__c.SObjectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
        )
        .getName();
    private static final String STATUS = Error_Log__c.Status__c.getDescribe().getName();

    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static void insertLogs(Integer howMany, String status) {
        List<Error_Log__c> logs = new List<Error_Log__c>();
        for (Integer i = 0; i < howMany; i++) {
            logs.add(
                new Error_Log__c(
                    Timestamp__c = System.now(),
                    Context__c = 'Picklist usage test',
                    Message__c = 'A test entry.',
                    Severity__c = ErrorLogger.SEVERITY_ERROR,
                    Status__c = status
                )
            );
        }
        insert logs;
    }

    private static Map<String, FieldUtilizationController.PicklistValueRow> byValue(
        FieldUtilizationController.PicklistChunk chunk,
        String fieldName
    ) {
        Map<String, FieldUtilizationController.PicklistValueRow> found = new Map<String, FieldUtilizationController.PicklistValueRow>();
        for (FieldUtilizationController.PicklistValueRow row : chunk.rows) {
            if (row.fieldName == fieldName) {
                found.put(row.value, row);
            }
        }
        return found;
    }

    @IsTest
    static void recordsAndLastUseArePerValueAndUnusedValuesAreListed() {
        System.runAs(TestUsers.admin()) {
            insertLogs(3, 'Acknowledged');
            insertLogs(1, 'Ignored');
            FieldUtilizationController.PicklistPlan planned;
            FieldUtilizationController.PicklistChunk chunk;
            System.runAs(maria()) {
                Test.startTest();
                planned = FieldUtilizationController.getPicklistPlan(LOG);
                chunk = FieldUtilizationController.getPicklistUsage(
                    LOG,
                    new List<String>{ STATUS }
                );
                Test.stopTest();
            }

            Set<String> offered = new Set<String>();
            for (FieldUtilizationController.FieldInfo info : planned.fields) {
                offered.add(info.fieldName);
            }
            Assert.isTrue(offered.contains(STATUS), 'Status is a single-select picklist.');
            Assert.isFalse(planned.tooLarge, 'Well under the size limit.');
            Map<String, FieldUtilizationController.PicklistValueRow> rows = byValue(
                chunk,
                STATUS
            );
            Assert.areEqual(3, rows.get('Acknowledged').records, 'Records holding the value.');
            Assert.areEqual('Active', rows.get('Acknowledged').status, 'An active value.');
            Assert.isNotNull(rows.get('Acknowledged').lastUsed, 'Last Modified Date is read.');
            Assert.areEqual(1, rows.get('Ignored').records, 'Another value.');
            Assert.areEqual(0, rows.get('Resolved').records, 'A value no record holds.');
            Assert.areEqual('NeverUsed', rows.get('Resolved').status, 'Listed as never used.');
            Assert.isNull(rows.get('Resolved').lastUsed, 'Nothing to date.');
            Assert.isTrue(chunk.failed.isEmpty(), 'Nothing failed.');
        }
    }

    @IsTest
    static void recordsWithNoValueAreListedOnce() {
        System.runAs(TestUsers.admin()) {
            Error_Log__c blank = new Error_Log__c(
                Timestamp__c = System.now(),
                Context__c = 'Picklist usage test',
                Message__c = 'A test entry.',
                Severity__c = ErrorLogger.SEVERITY_ERROR
            );
            insert blank;
            update new Error_Log__c(Id = blank.Id, Status__c = null);
            FieldUtilizationController.PicklistChunk chunk;
            System.runAs(maria()) {
                chunk = FieldUtilizationController.getPicklistUsage(
                    LOG,
                    new List<String>{ STATUS }
                );
            }
            Map<String, FieldUtilizationController.PicklistValueRow> rows = byValue(
                chunk,
                STATUS
            );
            Assert.areEqual('NoValue', rows.get('').status, 'Blank is its own row.');
            Assert.areEqual(1, rows.get('').records, 'The one record with no value.');
        }
    }

    @IsTest
    static void aValueInTheDataThatIsNotActiveIsInactiveAndOrderingIsMostUsedFirst() {
        // runs-as: deploying user (pure join of plain maps, no data, query or permission)
        PicklistUsageService.Usage retired = new PicklistUsageService.Usage();
        retired.records = 9;
        retired.lastUsed = Datetime.newInstance(2024, 1, 1);
        PicklistUsageService.Usage live = new PicklistUsageService.Usage();
        live.records = 2;
        PicklistUsageService.Usage blank = new PicklistUsageService.Usage();
        blank.records = 5;
        PicklistUsageService.FieldResult result = PicklistUsageService.combine(
            new Map<String, String>{ 'Open' => 'Open', 'Closed' => 'Closed' },
            new Map<String, PicklistUsageService.Usage>{
                'Old' => retired,
                'Open' => live,
                '' => blank
            }
        );
        Assert.areEqual(4, result.values.size(), 'Three in the data and one never used.');
        Assert.areEqual('Old', result.values[0].value, 'Most used first.');
        Assert.areEqual(PicklistUsageService.INACTIVE, result.values[0].status, 'Not active.');
        Assert.areEqual(PicklistUsageService.NO_VALUE, result.values[1].status, 'Blank.');
        Assert.areEqual(PicklistUsageService.ACTIVE, result.values[2].status, 'Active.');
        Assert.areEqual('Closed', result.values[3].value, 'Never used comes last.');
        Assert.areEqual(PicklistUsageService.NEVER_USED, result.values[3].status, 'Unused.');
        Assert.isFalse(result.truncated, 'Few values.');
    }

    @IsTest
    static void valuesInTheDataAreCutAtTheLimit() {
        // runs-as: deploying user (pure join of plain maps, no data, query or permission)
        Map<String, PicklistUsageService.Usage> observed = new Map<String, PicklistUsageService.Usage>();
        for (Integer i = 0; i < PicklistUsageService.MAX_VALUES + 1; i++) {
            PicklistUsageService.Usage seen = new PicklistUsageService.Usage();
            seen.records = 1;
            observed.put('v' + i, seen);
        }
        PicklistUsageService.FieldResult result = PicklistUsageService.combine(
            new Map<String, String>(),
            observed
        );
        Assert.isTrue(result.truncated, 'More values than the limit.');
        Assert.areEqual(PicklistUsageService.MAX_VALUES, result.values.size(), 'Cut to the limit.');
    }

    @IsTest
    static void aPersonWithoutThePermissionIsRefusedAndOtherNamesAreIgnored() {
        System.runAs(TestUsers.admin()) {
            FieldUtilizationController.PicklistChunk chunk;
            System.runAs(maria()) {
                chunk = FieldUtilizationController.getPicklistUsage(
                    LOG,
                    new List<String>{ 'Message__c', 'NotAField__c' }
                );
            }
            Assert.isTrue(chunk.rows.isEmpty(), 'Only picklist fields are read.');

            User plain = TestDataFactory.createUser('Plain', new List<String>{ 'BarnCRM_Staff' });
            String refusal;
            System.runAs(plain) {
                try {
                    FieldUtilizationController.getPicklistPlan(LOG);
                } catch (AuraHandledException caught) {
                    refusal = caught.getMessage();
                }
            }
            Assert.areEqual(
                System.Label.Core_FieldUtilization_PermissionRequired,
                refusal,
                'Manage BarnCRM Settings is required.'
            );
        }
    }

    @IsTest
    static void tooManyFieldsInOneCallAreRefused() {
        System.runAs(TestUsers.admin()) {
            List<String> names = new List<String>();
            for (Integer i = 0; i <= PicklistUsageService.CHUNK_SIZE; i++) {
                names.add('F' + i + '__c');
            }
            String refusal;
            System.runAs(maria()) {
                try {
                    FieldUtilizationController.getPicklistUsage(LOG, names);
                } catch (AuraHandledException caught) {
                    refusal = caught.getMessage();
                }
            }
            Assert.isNotNull(refusal, 'A chunk is at most CHUNK_SIZE fields.');
        }
    }
}
