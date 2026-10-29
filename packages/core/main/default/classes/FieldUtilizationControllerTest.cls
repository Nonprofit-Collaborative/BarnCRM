/**
 * FieldUtilizationController and FieldUtilizationService: the Field Utilization tab counts one
 * object on demand, a chunk of fields per call, and saves the counts only when asked
 * (canonical model Section 29F, R-FU1 to R-FU8).
 *
 * Counting tests run as Maria, a Standard User holding only BarnCRM Admin, so the user-mode
 * counts and writes prove what that permission set grants. Duplicate Dismissal has a single
 * countable field, so its counts do not depend on the org's other fields.
 */
@IsTest(testFor='ApexClass:FieldUtilizationController')
private class FieldUtilizationControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
        // Holds the Manage BarnCRM Settings permission and reads the counted object (Staff), but
        // has no delete access on the snapshots. Without read access on the object she would be
        // refused for that instead: a Standard User profile need not grant it.
        System.runAs(TestUsers.admin()) {
            User dana = TestDataFactory.createUser(
                'DanaNoDelete',
                new List<String>{ 'BarnCRM_Staff' }
            );
            SettingsTestPermissions.grantTo('Snapshot_No_Delete_Test', dana.Id);
        }
    }

    private static final String DISMISSAL = Duplicate_Dismissal__c.SObjectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
        )
        .getName();
    private static final String REASON = Duplicate_Dismissal__c.Reason__c.getDescribe().getName();
    private static final String PHONE = Account.Phone.getDescribe().getName();
    // Not named ACCOUNT: Apex names are case-insensitive, so that would shadow the Account type.
    private static final String ACCOUNT_TYPE = Account.SObjectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
        )
        .getName();

    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static List<Duplicate_Dismissal__c> insertDismissals(
        Integer howMany,
        Integer withReason
    ) {
        List<Duplicate_Dismissal__c> rows = new List<Duplicate_Dismissal__c>();
        for (Integer i = 0; i < howMany; i++) {
            rows.add(
                new Duplicate_Dismissal__c(
                    Pair_Key__c = 'barn-pair-' + i,
                    Reason__c = i < withReason ? 'Not the same person' : null
                )
            );
        }
        insert rows;
        return rows;
    }

    private static FieldUtilizationController.Chunk countOne(String objectName, String field) {
        return FieldUtilizationController.countFields(objectName, new List<String>{ field });
    }

    /** The row key of the organization record type (ADR-0141): blank for No record type. */
    private static String organizationKey() {
        String name = AccountKinds.organizationRecordTypeName();
        return name == AccountKinds.NO_RECORD_TYPE ? '' : name;
    }

    private static Map<String, FieldUtilizationController.CountRow> byRecordType(
        List<FieldUtilizationController.CountRow> rows
    ) {
        Map<String, FieldUtilizationController.CountRow> found = new Map<String, FieldUtilizationController.CountRow>();
        for (FieldUtilizationController.CountRow row : rows) {
            found.put(row.recordType, row);
        }
        return found;
    }

    private static String refusalOf(String objectName, List<String> fields) {
        try {
            FieldUtilizationController.countFields(objectName, fields);
        } catch (AuraHandledException caught) {
            return caught.getMessage();
        }
        return null;
    }

    @IsTest
    static void everyFilledValueIsCountedAcross200Records() {
        System.runAs(TestUsers.admin()) {
            FieldUtilizationController.Plan planned;
            FieldUtilizationController.Chunk chunk;
            System.runAs(maria()) {
                insertDismissals(200, 120);
                Test.startTest();
                planned = FieldUtilizationController.getPlan(DISMISSAL);
                chunk = countOne(DISMISSAL, REASON);
                Test.stopTest();
            }

            Assert.areEqual(200, planned.total, 'The plan counts the records first.');
            Assert.isFalse(planned.tooLarge, 'Well under the size limit.');
            Assert.areEqual(FieldUtilizationService.CHUNK_SIZE, planned.chunkSize, 'Full chunks.');
            Set<String> planFields = new Set<String>();
            for (FieldUtilizationController.FieldInfo info : planned.fields) {
                planFields.add(info.fieldName);
            }
            Assert.isTrue(planFields.contains(REASON), 'Reason is to be counted.');
            Assert.isFalse(
                planFields.contains(Duplicate_Dismissal__c.Pair_Key__c.getDescribe().getName()),
                'A field required on every record is always filled, so it is not counted (R-FU2).'
            );
            Assert.areEqual(1, chunk.rows.size(), 'No record types, so one row per field.');
            Assert.areEqual(120, chunk.rows[0].filled, 'Every filled Reason is counted.');
            Assert.areEqual(200, chunk.rows[0].total, 'Every dismissal is looked at.');
            Assert.areEqual(60.0, chunk.rows[0].percent, 'As a percentage.');
            Assert.areEqual('', chunk.rows[0].recordTypeLabel, 'No record type to name.');
            Assert.isFalse(chunk.rows[0].sampled, 'A text field is counted, not sampled.');
            Assert.isTrue(chunk.failed.isEmpty(), 'Nothing failed.');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Field_Utilization_Snapshot__c],
                'Counting stores nothing until the counts are saved.'
            );
        }
    }

    @IsTest
    static void eachRecordTypeIsCountedOnItsOwn() {
        System.runAs(TestUsers.admin()) {
            FieldUtilizationController.Chunk chunk;
            System.runAs(maria()) {
                List<Account> accounts = new List<Account>();
                for (Integer i = 0; i < 100; i++) {
                    Account organization = AddressTestDataFactory.newOrganization('Barn Org ' + i);
                    organization.Phone = i < 80 ? '555-0100' : null;
                    accounts.add(organization);
                    Account household = HouseholdTestDataFactory.newHousehold(
                        'The Barn ' + i + ' Family'
                    );
                    household.Phone = i < 20 ? '555-0199' : null;
                    accounts.add(household);
                }
                Database.insert(accounts, AccessLevel.SYSTEM_MODE);
                Test.startTest();
                chunk = countOne(ACCOUNT_TYPE, PHONE);
                Test.stopTest();
            }

            Map<String, FieldUtilizationController.CountRow> rows = byRecordType(chunk.rows);
            Assert.areEqual(80, rows.get(organizationKey()).filled, 'Organizations with a phone.');
            Assert.areEqual(100, rows.get(organizationKey()).total, 'Every organization.');
            Assert.areEqual(20, rows.get('Household').filled, 'Households with a phone.');
            Assert.areEqual(100, rows.get('Household').total, 'Every household.');
            Assert.isFalse(
                String.isBlank(rows.get('Household').recordTypeLabel),
                'The record type is shown by its label.'
            );
        }
    }

    @IsTest
    static void theRecordTypeFieldItselfIsCountedWithoutAnError() {
        System.runAs(TestUsers.admin()) {
            FieldUtilizationController.Chunk chunk;
            System.runAs(maria()) {
                List<Account> accounts = new List<Account>();
                for (Integer i = 0; i < 20; i++) {
                    accounts.add(AddressTestDataFactory.newOrganization('Barn Org ' + i));
                    accounts.add(
                        HouseholdTestDataFactory.newHousehold('The Barn ' + i + ' Family')
                    );
                }
                Database.insert(accounts, AccessLevel.SYSTEM_MODE);
                Test.startTest();
                chunk = countOne(ACCOUNT_TYPE, 'RecordTypeId');
                Test.stopTest();
            }

            Map<String, FieldUtilizationController.CountRow> rows = byRecordType(chunk.rows);
            Assert.areEqual(
                20,
                rows.get(organizationKey()).total,
                'Every organization is counted.'
            );
            Assert.areEqual(
                20,
                rows.get('Household').filled,
                'Every household has a type: the field is sampled, not lost to a duplicate select.'
            );
        }
    }

    @IsTest
    static void aLongTextFieldIsSampledOnRecentRecords() {
        System.runAs(TestUsers.admin()) {
            String description = Account.Description.getDescribe().getName();
            FieldUtilizationController.Chunk chunk;
            System.runAs(maria()) {
                List<Account> accounts = new List<Account>();
                for (Integer i = 0; i < 200; i++) {
                    Account organization = AddressTestDataFactory.newOrganization('Barn Org ' + i);
                    organization.Description = i < 50 ? 'Funds the after school program.' : null;
                    accounts.add(organization);
                }
                insert accounts;
                Test.startTest();
                chunk = countOne(ACCOUNT_TYPE, description);
                Test.stopTest();
            }

            Assert.areEqual(1, chunk.rows.size(), 'Only organizations exist: one row.');
            Assert.isTrue(chunk.rows[0].sampled, 'A long text field is sampled.');
            Assert.areEqual(
                FieldUtilizationService.SAMPLE_SIZE,
                chunk.rows[0].total,
                'Sample size.'
            );
            Assert.areEqual(50, chunk.rows[0].filled, 'Every filled description in the sample.');
        }
    }

    @IsTest
    static void anObjectOverTheSizeLimitIsNotCounted() {
        System.runAs(TestUsers.admin()) {
            FieldUtilizationService.sizeLimit = 100;
            FieldUtilizationController.Plan planned;
            String refusal;
            System.runAs(maria()) {
                insertDismissals(200, 200);
                planned = FieldUtilizationController.getPlan(DISMISSAL);
                refusal = refusalOf(DISMISSAL, new List<String>{ REASON });
            }

            Assert.isTrue(planned.tooLarge, 'The plan says the object is too large (R-FU5).');
            Assert.isTrue(planned.fields.isEmpty(), 'No field is offered for counting.');
            Assert.areEqual(
                String.format(
                    System.Label.Core_FieldUtilization_TooLarge,
                    new List<Object>{ Integer.valueOf(100).format() }
                ),
                refusal,
                'A count call is refused too.'
            );
        }
    }

    @IsTest
    static void savedCountsComeBackAsThePreviousCount() {
        System.runAs(TestUsers.admin()) {
            Integer saved;
            FieldUtilizationController.Plan planned;
            System.runAs(maria()) {
                insertDismissals(200, 100);
                FieldUtilizationController.Chunk chunk = countOne(DISMISSAL, REASON);
                Test.startTest();
                saved = FieldUtilizationController.saveCounts(DISMISSAL, chunk.rows);
                planned = FieldUtilizationController.getPlan(DISMISSAL);
                Test.stopTest();
            }

            Assert.areEqual(1, saved, 'One row saved.');
            List<Field_Utilization_Snapshot__c> rows = [
                SELECT Field_Name__c, Field_Label__c, Filled_Count__c, Record_Count__c, Taken_At__c
                FROM Field_Utilization_Snapshot__c
            ];
            Assert.areEqual(REASON, rows[0].Field_Name__c, 'The field, by API name.');
            Assert.areEqual(
                Duplicate_Dismissal__c.Reason__c.getDescribe().getLabel(),
                rows[0].Field_Label__c,
                'The label comes from describe.'
            );
            Assert.areEqual(100, rows[0].Filled_Count__c, 'Filled.');
            Assert.isNotNull(rows[0].Taken_At__c, 'Stamped when saved.');
            Assert.areEqual(rows[0].Taken_At__c, planned.previousTakenAt, 'The latest save.');
            Assert.areEqual(1, planned.previous.size(), 'Its rows come back.');
            Assert.areEqual(50.0, planned.previous[0].percent, '100 of 200.');
            Assert.areEqual(REASON + '|', planned.previous[0].key, 'Keyed like a count row.');
        }
    }

    @IsTest
    static void saveLeavesOutRowsDescribeDoesNotKnowAndCapsFilled() {
        System.runAs(TestUsers.admin()) {
            Integer saved;
            System.runAs(maria()) {
                List<FieldUtilizationController.CountRow> rows = new List<FieldUtilizationController.CountRow>();
                rows.add(row(REASON, '', 250, 200));
                rows.add(row('Not_A_Field__c', '', 1, 2));
                rows.add(row(REASON, 'Not_A_Record_Type', 1, 2));
                rows.add(row(REASON, '', 0, 0));
                saved = FieldUtilizationController.saveCounts(DISMISSAL, rows);
            }

            Assert.areEqual(1, saved, 'Only the row describe knows, with records, is saved.');
            Field_Utilization_Snapshot__c only = [
                SELECT Filled_Count__c, Record_Count__c
                FROM Field_Utilization_Snapshot__c
            ];
            Assert.areEqual(200, only.Filled_Count__c, 'Never above the record count.');
        }
    }

    private static FieldUtilizationController.CountRow row(
        String fieldName,
        String recordType,
        Integer filled,
        Integer total
    ) {
        FieldUtilizationController.CountRow sent = new FieldUtilizationController.CountRow();
        sent.fieldName = fieldName;
        sent.recordType = recordType;
        sent.filled = filled;
        sent.total = total;
        sent.sampled = false;
        return sent;
    }

    @IsTest
    static void unknownObjectsAndOversizedChunksAreRefused() {
        System.runAs(TestUsers.admin()) {
            String unknown;
            String oversized;
            System.runAs(maria()) {
                unknown = refusalOf('Not_A_Real_Object__c', new List<String>{ 'Name' });
                List<String> tooMany = new List<String>();
                for (Integer i = 0; i <= FieldUtilizationService.CHUNK_SIZE; i++) {
                    tooMany.add('Field_' + i + '__c');
                }
                oversized = refusalOf(DISMISSAL, tooMany);
            }

            Assert.areEqual(
                String.format(
                    System.Label.Core_FieldUtilization_UnknownObject,
                    new List<Object>{ 'Not_A_Real_Object__c' }
                ),
                unknown,
                'An object describe does not offer is refused by name (R-FU1).'
            );
            Assert.areEqual(
                System.Label.Core_FieldUtilization_UnexpectedError,
                oversized,
                'More fields than one chunk is refused.'
            );
        }
    }

    @IsTest
    static void someoneWithoutThePermissionCannotCount() {
        System.runAs(TestUsers.admin()) {
            User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
            String refusal;
            System.runAs(david) {
                refusal = refusalOf(DISMISSAL, new List<String>{ REASON });
            }

            Assert.areEqual(
                System.Label.Core_FieldUtilization_PermissionRequired,
                refusal,
                'Refused.'
            );
        }
    }

    @IsTest
    static void thePickerOffersWhatFindOffersButNotTheSnapshots() {
        System.runAs(TestUsers.admin()) {
            List<FieldUtilizationController.Option> options;
            System.runAs(maria()) {
                options = FieldUtilizationController.listObjects();
            }

            Set<String> offered = new Set<String>();
            for (FieldUtilizationController.Option option : options) {
                offered.add(option.value);
            }
            Assert.isTrue(offered.contains(ACCOUNT_TYPE), 'Account.');
            Assert.isTrue(
                offered.contains(
                    Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName()
                ),
                'Contact.'
            );
            Assert.isTrue(offered.contains(DISMISSAL), 'A custom object.');
            Assert.isFalse(
                offered.contains(
                    Field_Utilization_Snapshot__c.SObjectType.getDescribe(
                            SObjectDescribeOptions.DEFERRED
                        )
                        .getName()
                ),
                'Never its own snapshots.'
            );
            Assert.isFalse(
                offered.contains(
                    BarnCRM_Settings__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                        .getName()
                ),
                'Never a custom setting.'
            );
        }
    }

    @IsTest
    static void formulaCheckboxAndAutomaticFieldsAreLeftOut() {
        System.runAs(TestUsers.admin()) {
            Set<String> counted = FieldUtilizationService.countableFieldsByName(
                    Field_Utilization_Snapshot__c.SObjectType.getDescribe(
                        SObjectDescribeOptions.DEFERRED
                    )
                )
                .keySet();
            Assert.isTrue(
                counted.contains(
                    Field_Utilization_Snapshot__c.Field_Name__c.getDescribe().getName()
                ),
                'Text.'
            );
            Assert.isFalse(
                counted.contains(
                    Field_Utilization_Snapshot__c.Fill_Rate__c.getDescribe().getName()
                ),
                'Formula.'
            );
            Assert.isFalse(
                counted.contains(Field_Utilization_Snapshot__c.Sampled__c.getDescribe().getName()),
                'Checkbox.'
            );
            Assert.isFalse(counted.contains('Name'), 'Auto number.');
            Assert.isFalse(counted.contains('Id'), 'Identifier.');
        }
    }

    private static final Datetime FIRST_OF_MONTH = Datetime.newInstanceGmt(2026, 10, 1, 9, 0, 10);

    /** One saved row for the dismissal object, taken at the given time. */
    private static Field_Utilization_Snapshot__c savedRow(
        Datetime takenAt,
        String fieldName,
        Integer filled,
        Integer total
    ) {
        return new Field_Utilization_Snapshot__c(
            Object_Name__c = DISMISSAL,
            Field_Name__c = fieldName,
            Field_Label__c = fieldName,
            Filled_Count__c = filled,
            Record_Count__c = total,
            Taken_At__c = takenAt
        );
    }

    @IsTest
    static void historyListsEachSaveNewestFirstEvenWhenTwoShareAnHour() {
        System.runAs(TestUsers.admin()) {
            User person = maria();
            FieldUtilizationController.History listed;
            System.runAs(person) {
                insert new List<Field_Utilization_Snapshot__c>{
                    savedRow(FIRST_OF_MONTH, REASON, 60, 100),
                    savedRow(FIRST_OF_MONTH, 'Other_Field', 40, 100),
                    savedRow(FIRST_OF_MONTH.addSeconds(30), REASON, 80, 100),
                    savedRow(FIRST_OF_MONTH.addDays(-1), REASON, 10, 100)
                };
                Test.startTest();
                listed = FieldUtilizationController.getHistory(DISMISSAL);
                Test.stopTest();
            }

            Assert.areEqual(3, listed.snapshots.size(), 'Two saves in one hour stay two.');
            Assert.isTrue(listed.canDelete, 'BarnCRM Admin may delete saved counts.');
            Assert.areEqual(50, listed.maxSnapshots, 'The list is capped at 50.');
            Assert.areEqual(FIRST_OF_MONTH.addSeconds(30), listed.snapshots[0].takenAt, 'Newest.');
            Assert.areEqual(1, listed.snapshots[0].fieldCount, 'One field in the newest.');
            Assert.areEqual(80.0, listed.snapshots[0].averagePercent, '80 of 100.');
            Assert.areEqual(FIRST_OF_MONTH, listed.snapshots[1].takenAt, 'The one before it.');
            Assert.areEqual(2, listed.snapshots[1].fieldCount, 'Two different fields.');
            Assert.areEqual(2, listed.snapshots[1].rowCount, 'Two saved rows.');
            Assert.areEqual(50.0, listed.snapshots[1].averagePercent, '100 of 200.');
            Assert.areEqual(FIRST_OF_MONTH.addDays(-1), listed.snapshots[2].takenAt, 'Oldest.');
            Assert.areEqual(10.0, listed.snapshots[2].averagePercent, '10 of 100.');
            Assert.areEqual(
                [SELECT Name FROM User WHERE Id = :person.Id].Name,
                listed.snapshots[0].savedBy,
                'The name of the person who saved.'
            );
        }
    }

    @IsTest
    static void historyListsAtMostTheNewest50() {
        System.runAs(TestUsers.admin()) {
            FieldUtilizationController.History listed;
            System.runAs(maria()) {
                List<Field_Utilization_Snapshot__c> rows = new List<Field_Utilization_Snapshot__c>();
                for (Integer hour = 0; hour < 52; hour++) {
                    rows.add(savedRow(FIRST_OF_MONTH.addHours(hour), REASON, 1, 2));
                }
                insert rows;
                listed = FieldUtilizationController.getHistory(DISMISSAL);
            }

            Assert.areEqual(50, listed.snapshots.size(), 'No more than the limit.');
            Assert.areEqual(FIRST_OF_MONTH.addHours(51), listed.snapshots[0].takenAt, 'Newest.');
            Assert.areEqual(FIRST_OF_MONTH.addHours(2), listed.snapshots[49].takenAt, 'Cut off.');
        }
    }

    @IsTest
    static void historyIsEmptyWhenNothingWasSaved() {
        System.runAs(TestUsers.admin()) {
            FieldUtilizationController.History listed;
            System.runAs(maria()) {
                listed = FieldUtilizationController.getHistory(DISMISSAL);
            }

            Assert.isTrue(listed.snapshots.isEmpty(), 'Nothing saved, nothing listed.');
        }
    }

    @IsTest
    static void aChosenSnapshotsRowsComeBackAsCountRows() {
        System.runAs(TestUsers.admin()) {
            List<FieldUtilizationController.CountRow> rows;
            List<FieldUtilizationController.CountRow> none;
            System.runAs(maria()) {
                insert new List<Field_Utilization_Snapshot__c>{
                    savedRow(FIRST_OF_MONTH, REASON, 60, 100),
                    savedRow(FIRST_OF_MONTH.addDays(1), REASON, 90, 100)
                };
                rows = FieldUtilizationController.getSnapshotRows(DISMISSAL, FIRST_OF_MONTH);
                none = FieldUtilizationController.getSnapshotRows(DISMISSAL, null);
            }

            Assert.areEqual(1, rows.size(), 'Only the chosen save.');
            Assert.areEqual(60.0, rows[0].percent, 'Its own percentage.');
            Assert.areEqual(REASON + '|', rows[0].key, 'Keyed like a count row.');
            Assert.isTrue(none.isEmpty(), 'No time, no rows.');
        }
    }

    @IsTest
    static void deletingASnapshotRemovesOnlyThatSave() {
        System.runAs(TestUsers.admin()) {
            Integer deleted;
            System.runAs(maria()) {
                insert new List<Field_Utilization_Snapshot__c>{
                    savedRow(FIRST_OF_MONTH, REASON, 60, 100),
                    savedRow(FIRST_OF_MONTH, 'Other_Field', 40, 100),
                    savedRow(FIRST_OF_MONTH.addDays(1), REASON, 90, 100)
                };
                Test.startTest();
                deleted = FieldUtilizationController.deleteSnapshot(DISMISSAL, FIRST_OF_MONTH);
                Test.stopTest();
            }

            Assert.areEqual(2, deleted, 'Both rows of the save.');
            List<Field_Utilization_Snapshot__c> left = [
                SELECT Taken_At__c
                FROM Field_Utilization_Snapshot__c
            ];
            Assert.areEqual(1, left.size(), 'The other save is untouched.');
            Assert.areEqual(FIRST_OF_MONTH.addDays(1), left[0].Taken_At__c, 'The later save.');
        }
    }

    @IsTest
    static void someoneWithoutDeleteAccessCannotDeleteASnapshot() {
        System.runAs(TestUsers.admin()) {
            User dana = [SELECT Id FROM User WHERE LastName = 'DanaNoDelete' LIMIT 1];
            System.runAs(maria()) {
                insert savedRow(FIRST_OF_MONTH, REASON, 60, 100);
            }
            String refusal;
            System.runAs(dana) {
                try {
                    FieldUtilizationController.deleteSnapshot(DISMISSAL, FIRST_OF_MONTH);
                } catch (AuraHandledException caught) {
                    refusal = caught.getMessage();
                }
            }

            Assert.areEqual(
                System.Label.Core_FieldUtilization_DeleteNoAccess,
                refusal,
                'Refused without delete access.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Field_Utilization_Snapshot__c],
                'Nothing was deleted.'
            );
        }
    }

    @IsTest
    static void historyCallsNeedThePermission() {
        System.runAs(TestUsers.admin()) {
            User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
            List<String> refusals = new List<String>();
            System.runAs(david) {
                try {
                    FieldUtilizationController.getHistory(DISMISSAL);
                } catch (AuraHandledException caught) {
                    refusals.add(caught.getMessage());
                }
                try {
                    FieldUtilizationController.getSnapshotRows(DISMISSAL, FIRST_OF_MONTH);
                } catch (AuraHandledException caught) {
                    refusals.add(caught.getMessage());
                }
                try {
                    FieldUtilizationController.deleteSnapshot(DISMISSAL, FIRST_OF_MONTH);
                } catch (AuraHandledException caught) {
                    refusals.add(caught.getMessage());
                }
            }

            Assert.areEqual(3, refusals.size(), 'Each call is refused.');
            for (String refusal : refusals) {
                Assert.areEqual(
                    System.Label.Core_FieldUtilization_PermissionRequired,
                    refusal,
                    'The permission is required.'
                );
            }
        }
    }
}
