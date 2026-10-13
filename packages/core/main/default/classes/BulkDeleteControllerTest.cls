/**
 * The bulk delete controller (C-37, canonical model R-BD5 and R-BD6): its own permission, which
 * BarnCRM Admin does not hold, and preview, start, progress and undo through the page's own
 * entry points over 200 records.
 *
 * No org has run these yet; they are written against the behaviour the class documents.
 */
@IsTest(testFor='ApexClass:BulkDeleteController')
private class BulkDeleteControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String VOLUNTEERS = JSON.serialize(
        new Map<String, Object>{
            'version' => 1,
            'object' => 'Contact',
            'fields' => new List<Object>{ 'LastName' },
            'filter' => new Map<String, Object>{
                'version' => 1,
                'conditions' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 1,
                        'field' => 'Title',
                        'operator' => 'equals',
                        'value' => 'Volunteer'
                    }
                }
            }
        }
    );

    private static void makeVolunteers(Integer howMany) {
        DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
        Account organization = new Account(Name = 'Springfield Food Bank');
        insert organization;
        List<Contact> people = new List<Contact>();
        for (Integer index = 0; index < howMany; index++) {
            people.add(
                new Contact(
                    AccountId = organization.Id,
                    LastName = 'Person ' + index,
                    Title = 'Volunteer'
                )
            );
        }
        insert people;
    }

    private static User deleter() {
        return TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Bulk_Delete' }
        );
    }

    @IsTest
    static void barnCrmAdminAloneMayNotBulkDelete() {
        System.runAs(TestUsers.admin()) {
            makeVolunteers(5);
            System.Assert.isFalse(BulkDeleteController.hasPermission(), 'In no role');
            BulkDeleteController.BulkDeletePage page = BulkDeleteController.getPage();
            System.Assert.isFalse(page.allowed, 'The list says so');
            System.Assert.areEqual(0, page.jobs.size(), 'And lists nothing');
            try {
                BulkDeleteController.preview(VOLUNTEERS);
                System.Assert.fail('Refused');
            } catch (AuraHandledException expected) {
                System.Assert.areEqual(
                    System.Label.Core_BulkDelete_ErrorNoPermission,
                    expected.getMessage()
                );
            }
            try {
                BulkDeleteController.start(VOLUNTEERS, 5);
                System.Assert.fail('Refused');
            } catch (AuraHandledException expected) {
                System.Assert.areEqual(5, [SELECT COUNT() FROM Contact], 'Nothing deleted');
            }
        }
    }

    @IsTest
    static void previewStartAndUndoTwoHundredThroughThePage() {
        System.runAs(TestUsers.admin()) {
            makeVolunteers(200);
            BulkDeleteController.JobView started;
            Test.startTest();
            System.runAs(deleter()) {
                System.Assert.isTrue(BulkDeleteController.hasPermission(), 'Both permissions');
                BulkDeleteService.Preview preview = BulkDeleteController.preview(VOLUNTEERS);
                System.Assert.areEqual(200, preview.count, 'Counted');
                started = BulkDeleteController.start(VOLUNTEERS, preview.count);
                System.Assert.areEqual(200, started.matched, 'The count at the start');
            }
            Test.stopTest();

            System.Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'Deleted');
            System.runAs(deleter()) {
                BulkDeleteController.JobView done = BulkDeleteController.getJob(started.recordId);
                System.Assert.areEqual(
                    ImportBatchService.STATUS_COMPLETE,
                    done.status,
                    done.runLog
                );
                System.Assert.areEqual(200, done.deleted, 'Every record');
                System.Assert.isTrue(done.canUndo, 'Within the window');
                System.Assert.areEqual(200, done.recordsToUndo, 'The number to confirm');

                BulkDeleteController.BulkDeletePage page = BulkDeleteController.getPage();
                System.Assert.isTrue(page.allowed, 'Allowed');
                System.Assert.areEqual(1, page.jobs.size(), 'Listed');

                try {
                    BulkDeleteController.undo(started.recordId, 199);
                    System.Assert.fail('A different count');
                } catch (AuraHandledException expected) {
                    System.Assert.isTrue(expected.getMessage().contains('200'), 'Names the count');
                }
                BulkDeleteController.JobView undoing = BulkDeleteController.undo(
                    started.recordId,
                    200
                );
                System.Assert.areEqual(ImportBatchService.STATUS_UNDOING, undoing.status);
                System.Assert.isFalse(undoing.canUndo, 'Once only');
            }
        }
    }

    /** Aborted after its chunk ran: the finish never counted what it deleted. */
    @IsTest
    static void anAbortedJobOffersUndoForWhatItDeleted() {
        System.runAs(TestUsers.admin()) {
            makeVolunteers(200);
            System.runAs(deleter()) {
                Import_Batch__c created = BulkDeleteService.createJob(
                    BulkDeleteService.plan(VOLUNTEERS),
                    200,
                    200
                );
                BulkDeleteBatch job = new BulkDeleteBatch(created.Id);
                List<SObject> scope = new List<SObject>();
                Database.QueryLocatorIterator records = job.start(null).iterator();
                while (records.hasNext()) {
                    scope.add(records.next());
                }
                job.execute(null, scope);

                BulkDeleteController.JobView aborted = BulkDeleteController.getJob(created.Id);
                System.Assert.areEqual(ImportBatchService.STATUS_FAILED, aborted.status);
                System.Assert.areEqual(0, aborted.deleted, 'Never counted');
                System.Assert.isTrue(aborted.canUndo, 'Undo is still offered');
                System.Assert.areEqual(200, aborted.recordsToUndo, 'Counted from the journal');

                Test.startTest();
                BulkDeleteController.JobView undoing = BulkDeleteController.undo(created.Id, 200);
                Test.stopTest();
                System.Assert.areEqual(ImportBatchService.STATUS_UNDOING, undoing.status);
            }
            System.Assert.areEqual(200, [SELECT COUNT() FROM Contact], 'Brought back');
        }
    }

    @IsTest
    static void aJobThatIsNotABulkDeleteIsNotFound() {
        System.runAs(TestUsers.admin()) {
            System.runAs(deleter()) {
                try {
                    BulkDeleteController.getJob('not an id');
                    System.Assert.fail('Refused');
                } catch (AuraHandledException expected) {
                    System.Assert.areEqual(
                        System.Label.Core_BulkDelete_ErrorNotBulkDelete,
                        expected.getMessage()
                    );
                }
            }
        }
    }
}
