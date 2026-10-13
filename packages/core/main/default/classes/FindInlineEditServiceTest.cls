/**
 * Saving values edited in Find's grid (C-36, canonical model R-SQ10): typed and checked as a
 * bulk update's, saved in user mode, and journaled as an Update data job the import undo can
 * put back.
 *
 * No org has run these yet; they are written against the behaviour the class documents.
 */
@IsTest
private class FindInlineEditServiceTest {
    private static List<Contact> makePeople(Integer count) {
        Account organization = new Account(Name = 'Springfield Food Bank');
        insert organization;
        List<Contact> people = new List<Contact>();
        for (Integer index = 0; index < count; index++) {
            people.add(
                new Contact(
                    AccountId = organization.Id,
                    LastName = 'Person ' + String.valueOf(index).leftPad(4, '0'),
                    Title = 'Volunteer'
                )
            );
        }
        insert people;
        return people;
    }

    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static String edits(List<Contact> people, String title, Integer keepFirst) {
        List<Object> rows = new List<Object>();
        for (Integer index = 0; index < people.size(); index++) {
            rows.add(
                new Map<String, Object>{
                    'Id' => people[index].Id,
                    'Title' => index < keepFirst ? 'Volunteer' : title
                }
            );
        }
        return JSON.serialize(rows);
    }

    @IsTest
    static void savesTwoHundredEditsAsOneUndoableJob() {
        System.runAs(TestUsers.admin()) {
            DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
            List<Contact> people = makePeople(200);
            FindInlineEditService.SaveSummary summary;

            Test.startTest();
            System.runAs(maria()) {
                summary = FindController.saveEdits('Contact', edits(people, 'Coordinator', 10));
            }
            Test.stopTest();

            System.Assert.areEqual(190, summary.saved, 'Every changed record is saved');
            System.Assert.areEqual(10, summary.unchanged, 'A value already held is not written');
            System.Assert.isTrue(summary.errors.isEmpty(), 'Nothing refused: ' + summary.errors);
            System.Assert.areEqual(
                190,
                [SELECT COUNT() FROM Contact WHERE Title = 'Coordinator'],
                'The values are saved'
            );
            Import_Batch__c job = [
                SELECT
                    Id,
                    Operation__c,
                    Status__c,
                    Is_Dry_Run__c,
                    Rows_Updated__c,
                    Rows_Matched__c,
                    Undo_Deadline__c,
                    Completed_At__c,
                    Run_Log__c
                FROM Import_Batch__c
                WHERE Id = :summary.jobId
            ];
            System.Assert.areEqual(
                BulkUpdateService.OPERATION_UPDATE,
                job.Operation__c,
                'An Update job'
            );
            System.Assert.areEqual(ImportBatchService.STATUS_COMPLETE, job.Status__c, 'Complete');
            System.Assert.areEqual(190, job.Rows_Updated__c, 'Counted on the job');
            System.Assert.isTrue(job.Run_Log__c.startsWith('Edited in Find'), job.Run_Log__c);
            System.Assert.areEqual(
                190,
                ImportJournalService.entryCount(job.Id, ImportJournalService.PHASE_COMMIT),
                'One journal entry per saved record'
            );
            System.Assert.isNull(ImportUndoService.refusal(job), 'The save can be undone');
        }
    }

    @IsTest
    static void anEmptyValueClearsAndNothingChangedWritesNoJob() {
        System.runAs(TestUsers.admin()) {
            DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
            List<Contact> people = makePeople(2);
            FindInlineEditService.SaveSummary cleared;
            FindInlineEditService.SaveSummary nothing;

            System.runAs(maria()) {
                cleared = FindInlineEditService.save('Contact', edits(people, '', 1));
                // The same values again: the first is still Volunteer, the second already empty.
                nothing = FindInlineEditService.save('Contact', edits(people, '', 1));
            }

            System.Assert.areEqual(1, cleared.saved, 'The empty value cleared the field');
            System.Assert.areEqual(1, [SELECT COUNT() FROM Contact WHERE Title = NULL], 'Cleared');
            System.Assert.isNull(nothing.jobId, 'No change, no job');
        }
    }

    @IsTest
    static void editsOutsideTheRulesAreRefused() {
        System.runAs(TestUsers.admin()) {
            DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
            List<Contact> people = makePeople(1);
            Account organization = [SELECT Id FROM Account LIMIT 1];
            List<Object> tooMany = new List<Object>();
            for (Integer index = 0; index < 201; index++) {
                tooMany.add(new Map<String, Object>{ 'Id' => people[0].Id, 'Title' => 'X' });
            }

            System.runAs(maria()) {
                Map<String, String> expected = new Map<String, String>{
                    JSON.serialize(tooMany) => System.Label.Core_Find_ErrorEditTooMany,
                    JSON.serialize(
                        new List<Object>{
                            new Map<String, Object>{ 'Id' => organization.Id, 'Title' => 'X' }
                        }
                    ) => System.Label.Core_Find_ErrorEditRecord,
                    '[]' => System.Label.Core_BulkUpdate_ErrorNoChanges
                };
                for (String sent : expected.keySet()) {
                    try {
                        FindInlineEditService.save('Contact', sent);
                        System.Assert.fail('Refused: ' + sent.abbreviate(80));
                    } catch (BulkUpdateFields.BulkUpdateException refused) {
                        System.Assert.areEqual(expected.get(sent), refused.getMessage(), 'Why');
                    }
                }
                try {
                    FindInlineEditService.save(
                        'Contact',
                        JSON.serialize(
                            new List<Object>{
                                new Map<String, Object>{
                                    'Id' => people[0].Id,
                                    'Sample_Data_Key__c' => 'x'
                                }
                            }
                        )
                    );
                    System.Assert.fail('A field BarnCRM keeps is not edited');
                } catch (BulkUpdateFields.BulkUpdateException refused) {
                    System.Assert.isTrue(String.isNotBlank(refused.getMessage()), 'It says why');
                }
            }

        }
    }

    @IsTest
    static void findAloneCannotSaveEdits() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = makePeople(1);
            User david = TestDataFactory.createUser(
                'David',
                new List<String>{ 'BarnCRM_Find_And_Export' }
            );

            System.runAs(david) {
                try {
                    FindController.saveEdits('Contact', edits(people, 'Coordinator', 0));
                    System.Assert.fail('Editing needs the bulk update permission');
                } catch (AuraHandledException refused) {
                    System.Assert.areEqual(
                        System.Label.Core_BulkUpdate_ErrorNoPermission,
                        refused.getMessage(),
                        'It names the permission'
                    );
                }
            }

        }
    }
}
