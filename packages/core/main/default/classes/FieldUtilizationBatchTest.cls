/**
 * FieldUtilizationBatch and FieldUtilizationService: what one run of the field utilization
 * count stores (canonical model Section 29F, R-FU1 to R-FU8).
 *
 * Every test runs as Maria, a Standard User holding only BarnCRM Admin, so the user-mode
 * counts and writes prove what that permission set grants. Duplicate Dismissal has a single
 * countable field, so a run over it fits one test chunk whatever the org's other fields are.
 */
@IsTest(testFor='ApexClass:FieldUtilizationBatch')
private class FieldUtilizationBatchTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
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

    private static void insertDismissals(Integer howMany, Integer withReason) {
        List<Duplicate_Dismissal__c> rows = new List<Duplicate_Dismissal__c>();
        for (Integer i = 0; i < howMany; i++) {
            rows.add(
                new Duplicate_Dismissal__c(
                    Pair_Key__c = 'barn-pair-' + i,
                    Reason__c = i < withReason ? 'Twin sisters at the same address' : null
                )
            );
        }
        insert rows;
    }

    private static void runBatch(FieldUtilizationBatch batch) {
        Test.startTest();
        Database.executeBatch(batch, 2000);
        Test.stopTest();
    }

    private static List<Field_Utilization_Snapshot__c> snapshots(String fieldName) {
        return [
            SELECT Record_Type__c, Filled_Count__c, Record_Count__c, Sampled__c, Taken_At__c
            FROM Field_Utilization_Snapshot__c
            WHERE Field_Name__c = :fieldName
            ORDER BY Record_Type__c
        ];
    }

    @IsTest
    static void everyFilledValueIsCountedAcross200Records() {
        System.runAs(TestUsers.admin()) {
            System.runAs(maria()) {
                insertDismissals(200, 120);
                runBatch(new FieldUtilizationBatch(new List<String>{ DISMISSAL }));
            }

            List<Field_Utilization_Snapshot__c> rows = snapshots(REASON);
            Assert.areEqual(
                1,
                rows.size(),
                'An object without record types gets one row per field.'
            );
            Assert.areEqual(120, rows[0].Filled_Count__c, 'Every filled Reason is counted.');
            Assert.areEqual(200, rows[0].Record_Count__c, 'Every dismissal is looked at.');
            Assert.isNull(rows[0].Record_Type__c, 'There is no record type to name.');
            Assert.isFalse(rows[0].Sampled__c, 'A text field is counted, not sampled.');
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Field_Utilization_Snapshot__c
                    WHERE Field_Name__c LIKE '%Pair_Key__c'
                ],
                'A field required on every record is always filled, so it is not counted (R-FU2).'
            );
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            Assert.isNotNull(
                settings.Field_Utilization_Last_Run__c,
                'The run records when it finished.'
            );
            Assert.isTrue(
                settings.Field_Utilization_Last_Run_Summary__c.contains('0 could not be counted'),
                'The summary says what the run did: ' +
                settings.Field_Utilization_Last_Run_Summary__c
            );
        }
    }

    @IsTest
    static void eachRecordTypeIsCountedOnItsOwn() {
        System.runAs(TestUsers.admin()) {
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
                FieldUtilizationBatch batch = new FieldUtilizationBatch(
                    new List<String>{ ACCOUNT_TYPE }
                );
                batch.onlyFields = new Set<String>{ PHONE };
                runBatch(batch);
            }

            Map<String, Field_Utilization_Snapshot__c> byType = new Map<String, Field_Utilization_Snapshot__c>();
            for (Field_Utilization_Snapshot__c row : snapshots(PHONE)) {
                byType.put(row.Record_Type__c, row);
            }
            Assert.areEqual(
                80,
                byType.get('Organization').Filled_Count__c,
                'Organizations with a phone.'
            );
            Assert.areEqual(100, byType.get('Organization').Record_Count__c, 'Every organization.');
            Assert.areEqual(
                20,
                byType.get('Household').Filled_Count__c,
                'Households with a phone.'
            );
            Assert.areEqual(100, byType.get('Household').Record_Count__c, 'Every household.');
        }
    }

    @IsTest
    static void aLongTextFieldIsSampledOnRecentRecords() {
        System.runAs(TestUsers.admin()) {
            String description = Account.Description.getDescribe().getName();
            System.runAs(maria()) {
                List<Account> accounts = new List<Account>();
                for (Integer i = 0; i < 200; i++) {
                    Account organization = AddressTestDataFactory.newOrganization('Barn Org ' + i);
                    organization.Description = i < 50 ? 'Funds the after school program.' : null;
                    accounts.add(organization);
                }
                insert accounts;
                FieldUtilizationBatch batch = new FieldUtilizationBatch(
                    new List<String>{ ACCOUNT_TYPE }
                );
                batch.onlyFields = new Set<String>{ description };
                runBatch(batch);
            }

            List<Field_Utilization_Snapshot__c> rows = snapshots(description);
            Assert.areEqual(1, rows.size(), 'Only organizations exist, so one record type row.');
            Assert.isTrue(
                rows[0].Sampled__c,
                'A long text field cannot be counted, so it is sampled.'
            );
            Assert.areEqual(
                FieldUtilizationService.SAMPLE_SIZE,
                rows[0].Record_Count__c,
                'The sample size.'
            );
            Assert.areEqual(50, rows[0].Filled_Count__c, 'Every filled description in the sample.');
        }
    }

    @IsTest
    static void anObjectOverTheSizeLimitIsSkippedAndNamed() {
        System.runAs(TestUsers.admin()) {
            FieldUtilizationService.largeObjectRows = 100;
            System.runAs(maria()) {
                insertDismissals(200, 200);
                runBatch(new FieldUtilizationBatch(new List<String>{ DISMISSAL }));
            }

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Field_Utilization_Snapshot__c],
                'Nothing is counted.'
            );
            String summary = BarnCRM_Settings__c.getOrgDefaults()
                .Field_Utilization_Last_Run_Summary__c;
            Assert.isTrue(
                summary.contains(
                    Duplicate_Dismissal__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                        .getLabel()
                ),
                'The summary names what was skipped (R-FU5): ' + summary
            );
        }
    }

    @IsTest
    static void countsOlderThanThirteenMonthsAreDeletedWhenARunFinishes() {
        System.runAs(TestUsers.admin()) {
            System.runAs(maria()) {
                insert new List<Field_Utilization_Snapshot__c>{
                    new Field_Utilization_Snapshot__c(
                        Object_Name__c = DISMISSAL,
                        Field_Name__c = 'Old__c',
                        Taken_At__c = System.now().addMonths(-14)
                    ),
                    new Field_Utilization_Snapshot__c(
                        Object_Name__c = DISMISSAL,
                        Field_Name__c = 'Recent__c',
                        Taken_At__c = System.now().addMonths(-1)
                    )
                };
                runBatch(new FieldUtilizationBatch(new List<String>()));
            }

            Assert.areEqual(
                0,
                snapshots('Old__c').size(),
                'A count past 13 months is deleted (R-FU7).'
            );
            Assert.areEqual(1, snapshots('Recent__c').size(), 'A recent count is kept.');
        }
    }

    @IsTest
    static void aRunThatCountsNothingStillRecordsThatItRan() {
        System.runAs(TestUsers.admin()) {
            System.runAs(maria()) {
                runBatch(new FieldUtilizationBatch(new List<String>{ 'Not_A_Real_Object__c' }));
            }

            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            Assert.isNotNull(
                settings.Field_Utilization_Last_Run__c,
                'Ran and found nothing is a fact.'
            );
            Assert.isTrue(
                settings.Field_Utilization_Last_Run_Summary__c.startsWith(
                    String.format(
                        System.Label.Core_FieldUtilization_RunSummary,
                        new List<Object>{ 0, 0, 0 }
                    )
                ),
                'The summary says nothing was counted: ' +
                settings.Field_Utilization_Last_Run_Summary__c
            );
        }
    }

    @IsTest
    static void formulaCheckboxAndAutomaticFieldsAreLeftOut() {
        System.runAs(TestUsers.admin()) {
            Set<String> counted = new Set<String>();
            for (
                Schema.DescribeFieldResult field : FieldUtilizationService.countableFields(
                    Field_Utilization_Snapshot__c.SObjectType.getDescribe(
                        SObjectDescribeOptions.DEFERRED
                    )
                )
            ) {
                counted.add(field.getName());
            }
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
            Assert.isNull(
                FieldUtilizationService.countable(
                    Field_Utilization_Snapshot__c.SObjectType.getDescribe(
                            SObjectDescribeOptions.DEFERRED
                        )
                        .getName()
                ),
                'The snapshots themselves are never counted.'
            );
        }
    }
}
