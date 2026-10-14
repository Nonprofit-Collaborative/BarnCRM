/**
 * Checking and previewing a bulk delete (C-37, canonical model R-BD1, R-BD2 and R-BD4): the
 * query compiled as the person, protected and unrecoverable objects refused, and a count that
 * is the number the person confirms.
 *
 * No org has run these yet; they are written against the behaviour the class documents.
 */
@IsTest(testFor='ApexClass:BulkDeleteService')
private class BulkDeleteServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static String query(String objectName, String field, String value) {
        Map<String, Object> document = new Map<String, Object>{
            'version' => 1,
            'object' => objectName,
            'fields' => new List<Object>{ 'Id' }
        };
        if (field != null) {
            document.put(
                'filter',
                new Map<String, Object>{
                    'version' => 1,
                    'conditions' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 1,
                            'field' => field,
                            'operator' => 'equals',
                            'value' => value
                        }
                    }
                }
            );
        }
        return JSON.serialize(document);
    }

    private static final String VOLUNTEERS = query('Contact', 'Title', 'Volunteer');

    /** `volunteers` contacts titled Volunteer and `staff` titled Staff. */
    private static void makePeople(Integer volunteers, Integer staff) {
        DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
        Account organization = new Account(Name = 'Springfield Food Bank');
        insert organization;
        List<Contact> people = new List<Contact>();
        for (Integer index = 0; index < volunteers + staff; index++) {
            people.add(
                new Contact(
                    AccountId = organization.Id,
                    LastName = 'Person ' + String.valueOf(index).leftPad(4, '0'),
                    Title = index < volunteers ? 'Volunteer' : 'Staff'
                )
            );
        }
        insert people;
    }

    /** A person holding the bulk delete permission set beside BarnCRM Admin (R-BD6). */
    private static User deleter() {
        return TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Bulk_Delete' }
        );
    }

    @IsTest
    static void previewCountsTwoHundredNamesFiveAndSaysWhenUndoEnds() {
        System.runAs(TestUsers.admin()) {
            makePeople(200, 30);
            BulkDeleteService.Preview preview;
            Test.startTest();
            System.runAs(deleter()) {
                preview = BulkDeleteService.preview(VOLUNTEERS);
            }
            Test.stopTest();

            System.Assert.areEqual(200, preview.count, 'Only matching records are counted');
            System.Assert.areEqual(
                BulkDeleteService.DEFAULT_RUN_LIMIT,
                BulkDeleteService.runLimit()
            );
            System.Assert.areEqual(5, preview.sample.size(), 'Five named');
            System.Assert.areEqual('Person 0000', preview.sample[0].name, 'In Id order, by name');
            System.Assert.isNotNull(preview.cascades, 'The kinds deleted with each record');
            System.Assert.isTrue(
                preview.undoDeadline <= Datetime.now().addDays(BulkDeleteService.RECYCLE_BIN_DAYS),
                'Never past the Recycle Bin'
            );
            System.Assert.areEqual(230, [SELECT COUNT() FROM Contact], 'Nothing deleted');
        }
    }

    @IsTest
    static void refusesTheObjectsBarnCrmAndSetupKeep() {
        System.runAs(TestUsers.admin()) {
            DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
            for (
                String objectName : new List<String>{
                    'Import_Batch__c',
                    'Import_Journal__c',
                    'Household_Member__c',
                    'User',
                    'PermissionSet'
                }
            ) {
                try {
                    BulkDeleteService.plan(query(objectName, null, null));
                    System.Assert.fail('Refused: ' + objectName);
                } catch (BulkDeleteService.BulkDeleteException expected) {
                    System.Assert.isTrue(String.isNotBlank(expected.getMessage()), objectName);
                } catch (QueryCompiler.QueryCompilerException alsoRefused) {
                    System.Assert.isTrue(String.isNotBlank(alsoRefused.getMessage()), objectName);
                }
            }
        }
    }

    @IsTest
    static void refusesMoreThanTheRunLimitAndNothingMatching() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = TestDataFactory.defaultSettings();
            settings.Bulk_Delete_Run_Limit__c = 150;
            TestDataFactory.saveSettings(settings);
            makePeople(200, 0);
            System.runAs(deleter()) {
                System.Assert.areEqual(150, BulkDeleteService.runLimit(), 'From the settings');
                try {
                    BulkDeleteService.preview(VOLUNTEERS);
                    System.Assert.fail('Over the limit');
                } catch (BulkDeleteService.BulkDeleteException expected) {
                    System.Assert.isTrue(expected.getMessage().contains('150'), 'Names the limit');
                }
                try {
                    BulkDeleteService.preview(query('Contact', 'Title', 'Treasurer'));
                    System.Assert.fail('Nothing matches');
                } catch (BulkDeleteService.BulkDeleteException expected) {
                    System.Assert.areEqual(
                        System.Label.Core_BulkDelete_ErrorNothingMatches,
                        expected.getMessage()
                    );
                }
            }
        }
    }

    @IsTest
    static void refusesToStartWhenMoreMatchThanWereConfirmed() {
        System.runAs(TestUsers.admin()) {
            makePeople(200, 0);
            System.runAs(deleter()) {
                try {
                    BulkDeleteService.start(VOLUNTEERS, 199);
                    System.Assert.fail('More match than confirmed');
                } catch (BulkDeleteService.BulkDeleteException expected) {
                    System.Assert.isTrue(expected.getMessage().contains('199'), 'Names the count');
                }
                try {
                    BulkDeleteService.start(VOLUNTEERS, 0);
                    System.Assert.fail('Nothing confirmed');
                } catch (BulkDeleteService.BulkDeleteException expected) {
                    System.Assert.areEqual(
                        System.Label.Core_BulkUpdate_ErrorConfirm,
                        expected.getMessage()
                    );
                }
            }
            System.Assert.areEqual(200, [SELECT COUNT() FROM Contact], 'Nothing deleted');
            System.Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Import_Batch__c
                    WHERE Operation__c = :BulkDeleteService.OPERATION_DELETE
                ],
                'No job'
            );
        }
    }

    @IsTest
    static void aJobsDefinitionHoldsTheQueryAndTheCountAndLeavesTheImportHistory() {
        System.runAs(TestUsers.admin()) {
            DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
            BulkDeleteService.Plan checked = BulkDeleteService.plan(VOLUNTEERS);
            String definition = checked.definition(37);
            BulkDeleteService.Plan again = BulkDeleteService.planFromDefinition(definition);
            System.Assert.areEqual(37, DataJobs.confirmedCountOf(definition));
            System.Assert.areEqual('Contact', again.objectName, 'The object');
            System.Assert.areEqual('Name', again.nameField, 'Read for the journal');

            Import_Batch__c job = BulkDeleteService.createJob(checked, 37, 37);
            System.Assert.isFalse(
                new Map<Id, Import_Batch__c>(ImportBatchSelector.selectRecent(10))
                    .containsKey(job.Id),
                'The import history lists imports only'
            );
        }
    }
}
