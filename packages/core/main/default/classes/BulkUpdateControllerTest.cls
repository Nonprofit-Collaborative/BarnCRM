/**
 * The bulk update controller (C-35, canonical model R-BU5 and R-BU6): both permissions, the
 * permission set alone enough to read jobs, and preview, start and undo through the page's own
 * entry points over 200 records.
 *
 * The 200 volunteers and Maria are built once, in setup, and every test finds them again.
 *
 * No org has run these yet; they are written against the behaviour the class documents.
 */
@IsTest(testFor='ApexClass:BulkUpdateController')
private class BulkUpdateControllerTest {
    /** 200 contacts titled Volunteer at one organization, and Maria, who runs the updates. */
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            noRollupTargets();
            Account organization = new Account(Name = 'Springfield Food Bank');
            insert organization;
            List<Contact> people = new List<Contact>();
            for (Integer index = 0; index < 200; index++) {
                people.add(
                    new Contact(
                        AccountId = organization.Id,
                        LastName = 'Person ' + index,
                        Title = 'Volunteer'
                    )
                );
            }
            insert people;
            TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
        }
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

    private static final String SET_COORDINATOR = JSON.serialize(
        new List<Object>{
            new Map<String, Object>{
                'field' => 'Title',
                'action' => 'set',
                'value' => 'Coordinator'
            }
        }
    );

    /**
     * No rollup target fields, so no field is protected as one. A static, so each test sets it
     * again: what setup set is gone by the time a test runs.
     */
    private static void noRollupTargets() {
        DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
    }

    /** Maria, created in setup and found again by her username. */
    private static User maria() {
        return [SELECT Id FROM User WHERE Username LIKE 'barn-test.maria.%' LIMIT 1];
    }

    @IsTest
    static void bothPermissionsAreNeededAndFindSaysWhetherToOffer() {
        System.runAs(TestUsers.admin()) {
            User david = TestDataFactory.createUser(
                'David',
                new List<String>{ 'BarnCRM_Find_And_Export' }
            );
            System.runAs(david) {
                System.Assert.isFalse(FindController.getPage().canBulkUpdate, 'Not offered');
                BulkUpdateController.BulkUpdatePage page = BulkUpdateController.getPage(false);
                System.Assert.isFalse(page.allowed, 'Find alone does not open bulk update');
                System.Assert.isTrue(page.jobs.isEmpty(), 'The tab lists nothing for them');
                try {
                    BulkUpdateController.getTargets('Contact');
                    System.Assert.fail('Find alone does not open bulk update');
                } catch (AuraHandledException refused) {
                    System.Assert.areEqual(
                        System.Label.Core_BulkUpdate_ErrorNoPermission,
                        refused.getMessage(),
                        'The message names both permissions'
                    );
                }
            }
            System.runAs(maria()) {
                System.Assert.isTrue(FindController.getPage().canBulkUpdate, 'Offered to an admin');
                System.Assert.isTrue(
                    BulkUpdateController.getPage(false).allowed,
                    'Listed for an admin'
                );
            }

        }
    }

    @IsTest
    static void thePermissionSetsAloneReadAJobAndItsRefusals() {
        System.runAs(TestUsers.admin()) {
            noRollupTargets();
            User bea = TestDataFactory.createUser(
                'Bea',
                new List<String>{ 'BarnCRM_Find_And_Export', 'BarnCRM_Bulk_Update' }
            );
            Import_Batch__c job;
            System.runAs(bea) {
                job = BulkUpdateService.createJob(
                    BulkUpdateService.plan(VOLUNTEERS, SET_COORDINATOR),
                    1,
                    1
                );
            }
            Contact person = [SELECT Id FROM Contact LIMIT 1];
            ImportJournalService.write(
                job.Id,
                ImportJournalService.PHASE_COMMIT,
                new List<Map<String, Object>>{
                    ImportJournalService.failed('Contact', person.Id, 'A validation rule said no.')
                }
            );
            update new Import_Batch__c(
                Id = job.Id,
                Status__c = ImportBatchService.STATUS_COMPLETE,
                Completed_At__c = Datetime.now(),
                Rows_Rejected__c = 1
            );

            BulkUpdateController.JobView view;
            System.runAs(bea) {
                System.Assert.areEqual(
                    1,
                    BulkUpdateController.getPage(false).jobs.size(),
                    'Listed'
                );
                view = BulkUpdateController.getJob(job.Id);
            }
            System.Assert.areEqual(1, view.failed, 'The refusal is counted');
            System.Assert.areEqual(1, view.failures.size(), 'And listed');
            System.Assert.areEqual('A validation rule said no.', view.failures[0].reason);
            System.Assert.isNotNull(view.objectLabel, 'The object, by its label or its name');
        }
    }

    @IsTest
    static void previewStartAndTheJobOverTwoHundredRecords() {
        System.runAs(TestUsers.admin()) {
            noRollupTargets();
            User maria = maria();
            BulkUpdateService.Preview preview;
            BulkUpdateController.JobView started;
            Test.startTest();
            System.runAs(maria) {
                System.Assert.isFalse(
                    BulkUpdateController.getTargets('Contact').isEmpty(),
                    'Fields are offered'
                );
                preview = BulkUpdateController.preview(VOLUNTEERS, SET_COORDINATOR);
                started = BulkUpdateController.start(VOLUNTEERS, SET_COORDINATOR, preview.count);
            }
            Test.stopTest();

            System.Assert.areEqual(200, preview.count, 'The number to confirm');
            System.Assert.isTrue(started.running, 'Running when it starts');
            BulkUpdateController.JobView finished;
            System.runAs(maria) {
                finished = BulkUpdateController.getJob(started.recordId);
            }
            System.Assert.areEqual(200, finished.updated, finished.runLog);
            System.Assert.isFalse(finished.running, 'Finished');
            System.Assert.isTrue(finished.canUndo, 'And can be undone');
            System.Assert.areEqual(200, finished.updatesToUndo, 'The number an undo confirms');
        }
    }

    @IsTest
    static void undoNeedsTheNumberShownAndPutsBackTwoHundredValues() {
        System.runAs(TestUsers.admin()) {
            ImportEntityProcessors.noneForTest = true;
            noRollupTargets();
            User maria = maria();
            Id jobId;
            System.runAs(maria) {
                jobId = BulkUpdateService.createJob(
                        BulkUpdateService.plan(VOLUNTEERS, SET_COORDINATOR),
                        200,
                        200
                    )
                    .Id;
                BulkUpdateBatch job = new BulkUpdateBatch(jobId);
                List<SObject> scope = new List<SObject>();
                Database.QueryLocatorIterator records = job.start(null).iterator();
                while (records.hasNext()) {
                    scope.add(records.next());
                }
                job.execute(null, scope);
                job.finish(null);
            }

            Test.startTest();
            System.runAs(maria) {
                try {
                    BulkUpdateController.undo(jobId, 199);
                    System.Assert.fail('200 values would be put back, not 199');
                } catch (AuraHandledException refused) {
                    System.Assert.isTrue(
                        refused.getMessage().contains('200'),
                        refused.getMessage()
                    );
                }
                BulkUpdateController.undo(jobId, 200);
            }
            Test.stopTest();

            System.Assert.areEqual(200, [SELECT COUNT() FROM Contact WHERE Title = 'Volunteer']);
        }
    }

    /** Aborted after its chunk ran: the finish never counted what it saved. */
    @IsTest
    static void anAbortedJobAsksForTheNumberItSavedAndUndoesIt() {
        System.runAs(TestUsers.admin()) {
            ImportEntityProcessors.noneForTest = true;
            noRollupTargets();
            User maria = maria();
            Id jobId;
            System.runAs(maria) {
                jobId = BulkUpdateService.createJob(
                        BulkUpdateService.plan(VOLUNTEERS, SET_COORDINATOR),
                        200,
                        200
                    )
                    .Id;
                BulkUpdateBatch job = new BulkUpdateBatch(jobId);
                List<SObject> scope = new List<SObject>();
                Database.QueryLocatorIterator records = job.start(null).iterator();
                while (records.hasNext()) {
                    scope.add(records.next());
                }
                job.execute(null, scope);
            }

            Test.startTest();
            System.runAs(maria) {
                BulkUpdateController.JobView aborted = BulkUpdateController.getJob(jobId);
                System.Assert.areEqual(ImportBatchService.STATUS_FAILED, aborted.status);
                System.Assert.areEqual(0, aborted.updated, 'Never counted');
                System.Assert.isTrue(aborted.canUndo, 'Undo is still offered');
                System.Assert.areEqual(200, aborted.updatesToUndo, 'Counted from the journal');
                BulkUpdateController.undo(jobId, aborted.updatesToUndo);
            }
            Test.stopTest();

            System.Assert.areEqual(200, [SELECT COUNT() FROM Contact WHERE Title = 'Volunteer']);
        }
    }
}
