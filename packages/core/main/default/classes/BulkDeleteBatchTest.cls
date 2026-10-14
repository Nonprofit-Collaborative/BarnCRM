/**
 * Running a bulk delete (C-37, canonical model R-BD3): 200 records deleted as the person, only
 * records that still match, each deleted Id journaled for the undo, and a job whose object is
 * no longer allowed stopped before deleting anything.
 *
 * A test runs one queued job, at Test.stopTest; a test that changes records part way drives the
 * job through its own start query, as BulkUpdateBatchTest does.
 *
 * No org has run these yet; they are written against the behaviour the classes document.
 */
@IsTest(testFor='ApexClass:BulkDeleteBatch')
private class BulkDeleteBatchTest {
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

    /** `volunteers` contacts titled Volunteer and `staff` titled Staff. */
    private static void makePeople(Integer volunteers, Integer staff) {
        DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
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

    private static User deleter() {
        return TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Bulk_Delete' }
        );
    }

    private static Import_Batch__c reread(Id jobId) {
        return [
            SELECT
                Status__c,
                Operation__c,
                Row_Count__c,
                Rows_Deleted__c,
                Rows_Rejected__c,
                Run_Log__c,
                Undo_Deadline__c,
                Started_At__c
            FROM Import_Batch__c
            WHERE Id = :jobId
        ];
    }

    private static List<Map<String, Object>> journal(Id jobId) {
        List<Map<String, Object>> entries = new List<Map<String, Object>>();
        for (Import_Journal__c page : [
            SELECT Entries_JSON__c
            FROM Import_Journal__c
            WHERE Import_Batch__c = :jobId AND Phase__c = :ImportJournalService.PHASE_COMMIT
        ]) {
            entries.addAll(ImportJournalService.entries(page));
        }
        return entries;
    }

    private static List<SObject> startQuery(BulkDeleteBatch job) {
        List<SObject> scope = new List<SObject>();
        Database.QueryLocatorIterator records = job.start(null).iterator();
        while (records.hasNext()) {
            scope.add(records.next());
        }
        return scope;
    }

    @IsTest
    static void deletesTwoHundredRecordsAsThePersonAndJournalsEachId() {
        System.runAs(TestUsers.admin()) {
            makePeople(200, 30);
            Import_Batch__c job;
            Test.startTest();
            System.runAs(deleter()) {
                job = BulkDeleteService.start(VOLUNTEERS, 200);
            }
            Test.stopTest();
            job = reread(job.Id);

            System.Assert.areEqual(
                ImportBatchService.STATUS_COMPLETE,
                job.Status__c,
                job.Run_Log__c
            );
            System.Assert.areEqual(BulkDeleteService.OPERATION_DELETE, job.Operation__c);
            System.Assert.areEqual(200, job.Row_Count__c, 'The count confirmed at the start');
            System.Assert.areEqual(200, job.Rows_Deleted__c, 'Every match is deleted');
            System.Assert.areEqual(0, job.Rows_Rejected__c, 'None refused');
            System.Assert.isTrue(
                job.Undo_Deadline__c <=
                job.Started_At__c.addDays(BulkDeleteService.RECYCLE_BIN_DAYS),
                'The undo ends before the Recycle Bin empties'
            );
            System.Assert.areEqual(0, [SELECT COUNT() FROM Contact WHERE Title = 'Volunteer']);
            System.Assert.areEqual(30, [SELECT COUNT() FROM Contact WHERE Title = 'Staff']);
            System.Assert.areEqual(
                200,
                [SELECT COUNT() FROM Contact WHERE IsDeleted = TRUE ALL ROWS],
                'In the Recycle Bin'
            );
            List<Map<String, Object>> entries = journal(job.Id);
            System.Assert.areEqual(200, entries.size(), 'One entry per record deleted');
            Set<String> names = new Set<String>();
            for (Map<String, Object> entry : entries) {
                System.Assert.areEqual(ImportJournalService.ACTION_DELETED, entry.get('action'));
                System.Assert.areEqual('Contact', entry.get('object'));
                names.add((String) entry.get('label'));
            }
            System.Assert.isTrue(names.contains('Person 0000'), 'Each record by name');
        }
    }

    @IsTest
    static void leavesARecordThatNoLongerMatches() {
        System.runAs(TestUsers.admin()) {
            makePeople(200, 0);
            System.runAs(deleter()) {
                Import_Batch__c created = BulkDeleteService.createJob(
                    BulkDeleteService.plan(VOLUNTEERS),
                    200,
                    200
                );
                BulkDeleteBatch job = new BulkDeleteBatch(created.Id);
                List<SObject> scope = startQuery(job);
                System.Assert.areEqual(200, scope.size(), 'The confirmed records');
                Contact promoted = [SELECT Id FROM Contact LIMIT 1];
                update new Contact(Id = promoted.Id, Title = 'Treasurer');
                job.execute(null, scope);
                job.finish(null);

                Import_Batch__c done = reread(created.Id);
                System.Assert.areEqual(199, done.Rows_Deleted__c, done.Run_Log__c);
                System.Assert.isTrue(done.Run_Log__c.contains('1'), 'Counted in the run log');
                System.Assert.areEqual(1, [SELECT COUNT() FROM Contact], 'Left alone');
            }
        }
    }

    /**
     * A refusal found when a later chunk checks the definition again stops the job: the chunks
     * after it return at once, the run log says why, and no Error Log row is written per chunk.
     */
    @IsTest
    static void aRefusalPartWayStopsTheJobAndSaysWhy() {
        System.runAs(TestUsers.admin()) {
            makePeople(200, 0);
            Import_Batch__c created = BulkDeleteService.createJob(
                BulkDeleteService.plan(VOLUNTEERS),
                200,
                200
            );
            BulkDeleteBatch job = new BulkDeleteBatch(created.Id);
            List<SObject> scope = startQuery(job);
            List<SObject> first = new List<SObject>();
            List<SObject> second = new List<SObject>();
            List<SObject> third = new List<SObject>();
            for (Integer i = 0; i < scope.size(); i++) {
                (i < 100 ? first : (i < 150 ? second : third)).add(scope[i]);
            }
            job.execute(null, first);
            // Stands for access taken away after the first chunk.
            job.definition = JSON.serialize(
                new Map<String, Object>{
                    'version' => 1,
                    'query' => new Map<String, Object>{
                        'version' => 1,
                        'object' => 'Import_Journal__c',
                        'fields' => new List<Object>{ 'Id' }
                    },
                    'confirmedCount' => 200
                }
            );
            job.execute(null, second);
            job.execute(null, third);
            job.finish(null);

            Import_Batch__c done = reread(created.Id);
            System.Assert.areEqual(ImportBatchService.STATUS_FAILED, done.Status__c);
            System.Assert.areEqual(100, done.Rows_Deleted__c, done.Run_Log__c);
            System.Assert.areEqual(100, [SELECT COUNT() FROM Contact], 'The rest stay');
            System.Assert.isTrue(
                done.Run_Log__c.contains(
                    System.Label.Core_BulkDelete_LogStopped.substringBefore('{0}')
                ),
                done.Run_Log__c
            );
            System.Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'BulkDeleteBatch.execute'],
                'A refusal the person can fix is not an error'
            );
        }
    }

    @IsTest
    static void aJobWhoseObjectIsNoLongerAllowedStopsBeforeDeleting() {
        System.runAs(TestUsers.admin()) {
            makePeople(10, 0);
            Import_Batch__c created = BulkDeleteService.createJob(
                BulkDeleteService.plan(VOLUNTEERS),
                10,
                10
            );
            // A definition that names an object the protected list refuses.
            created.Operation_JSON__c = JSON.serialize(
                new Map<String, Object>{
                    'version' => 1,
                    'query' => new Map<String, Object>{
                        'version' => 1,
                        'object' => 'Import_Journal__c',
                        'fields' => new List<Object>{ 'Id' }
                    },
                    'confirmedCount' => 10
                }
            );
            update created;
            BulkDeleteBatch job = new BulkDeleteBatch(created.Id);
            List<SObject> scope = startQuery(job);
            job.execute(null, scope);
            job.finish(null);

            Import_Batch__c done = reread(created.Id);
            System.Assert.areEqual(0, scope.size(), 'Nothing read');
            System.Assert.areEqual(ImportBatchService.STATUS_FAILED, done.Status__c);
            System.Assert.areEqual(0, done.Rows_Deleted__c, 'Nothing deleted');
            System.Assert.areEqual(10, [SELECT COUNT() FROM Contact], 'Every record stays');
        }
    }
}
