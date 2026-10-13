/**
 * FieldUtilizationController and FieldUtilizationService: the Field Utilization tab counts one
 * object on demand, a chunk of fields per call, and saves the counts only when asked
 * (canonical model Section 29F, R-FU1 to R-FU8).
 *
 * Counting tests run as Maria, a Standard User holding only BarnCRM Admin, so the user-mode
 * counts and writes prove what that permission set grants. Duplicate Dismissal has a single
 * countable field, so its counts do not depend on the org's other fields.
 */
@IsTest
private class FieldUtilizationControllerTest {
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
                insert accounts;
                Test.startTest();
                chunk = countOne(ACCOUNT_TYPE, PHONE);
                Test.stopTest();
            }

            Map<String, FieldUtilizationController.CountRow> rows = byRecordType(chunk.rows);
            Assert.areEqual(80, rows.get('Organization').filled, 'Organizations with a phone.');
            Assert.areEqual(100, rows.get('Organization').total, 'Every organization.');
            Assert.areEqual(20, rows.get('Household').filled, 'Households with a phone.');
            Assert.areEqual(100, rows.get('Household').total, 'Every household.');
            Assert.isFalse(
                String.isBlank(rows.get('Household').recordTypeLabel),
                'The record type is shown by its label.'
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
}
