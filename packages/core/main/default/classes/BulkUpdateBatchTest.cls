/**
 * Running and undoing a bulk update (C-35, canonical model R-BU2, R-BU3 and R-BU5): set, clear
 * and copy over 200 records as the person, only records that still match, refusals journaled,
 * and an undo that puts back each value nobody has changed since.
 *
 * A test runs one queued job, at Test.stopTest, so a test that also undoes drives the bulk
 * update through the job's own start query, as ImportUndoTest does.
 *
 * No org has run these yet; they are written against the behaviour the classes document.
 */
@IsTest
private class BulkUpdateBatchTest {
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

    private static String changes(Map<String, Object> change) {
        return JSON.serialize(new List<Object>{ change });
    }

    private static final String SET_COORDINATOR = changes(
        new Map<String, Object>{ 'field' => 'Title', 'action' => 'set', 'value' => 'Coordinator' }
    );

    /** `volunteers` contacts titled Volunteer and `staff` titled Staff, with work emails. */
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
                    Title = index < volunteers ? 'Volunteer' : 'Staff',
                    Work_Email__c = 'person' + index + '@example.org'
                )
            );
        }
        insert people;
    }

    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    /** Starts a bulk update as Maria and lets its job run. */
    private static Import_Batch__c run(User person, String changesJson, Integer confirmed) {
        Import_Batch__c job;
        Test.startTest();
        System.runAs(person) {
            job = BulkUpdateService.start(VOLUNTEERS, changesJson, confirmed);
        }
        Test.stopTest();
        return reread(job.Id);
    }

    /** The job record without a queued job: the bulk update is driven by `runNow`. */
    private static Import_Batch__c createJob(String changesJson, Integer count) {
        return BulkUpdateService.createJob(
            BulkUpdateService.plan(VOLUNTEERS, changesJson),
            count,
            count
        );
    }

    /** Drives the job through its own start query, chunk by chunk, then its finish. */
    private static void runNow(BulkUpdateBatch job, List<SObject> scope) {
        job.execute(null, scope);
        job.finish(null);
    }

    private static List<SObject> startQuery(BulkUpdateBatch job) {
        List<SObject> scope = new List<SObject>();
        Database.QueryLocatorIterator records = job.start(null).iterator();
        while (records.hasNext()) {
            scope.add(records.next());
        }
        return scope;
    }

    private static Import_Batch__c reread(Id jobId) {
        return [
            SELECT
                Status__c,
                Operation__c,
                Row_Count__c,
                Rows_Updated__c,
                Rows_Matched__c,
                Rows_Rejected__c,
                Run_Log__c,
                Undo_Deadline__c
            FROM Import_Batch__c
            WHERE Id = :jobId
        ];
    }

    private static List<Map<String, Object>> journal(Id jobId, String phase) {
        List<Map<String, Object>> entries = new List<Map<String, Object>>();
        for (Import_Journal__c page : [
            SELECT Entries_JSON__c
            FROM Import_Journal__c
            WHERE Import_Batch__c = :jobId AND Phase__c = :phase
        ]) {
            entries.addAll(ImportJournalService.entries(page));
        }
        return entries;
    }

    @IsTest
    static void setChangesTwoHundredRecordsAndJournalsEachOne() {
        System.runAs(TestUsers.admin()) {
            makePeople(200, 30);
            Import_Batch__c job = run(maria(), SET_COORDINATOR, 200);

            System.Assert.areEqual(200, [SELECT COUNT() FROM Contact WHERE Title = 'Coordinator']);
            System.Assert.areEqual(30, [SELECT COUNT() FROM Contact WHERE Title = 'Staff']);
            System.Assert.areEqual(
                ImportBatchService.STATUS_COMPLETE,
                job.Status__c,
                job.Run_Log__c
            );
            System.Assert.areEqual(BulkUpdateService.OPERATION_UPDATE, job.Operation__c);
            System.Assert.areEqual(200, job.Row_Count__c, 'The count confirmed at the start');
            System.Assert.areEqual(200, job.Rows_Updated__c, 'Every match is saved');
            System.Assert.isNotNull(
                job.Undo_Deadline__c,
                'The undo window is stamped at the start'
            );
            List<Map<String, Object>> entries = journal(job.Id, ImportJournalService.PHASE_COMMIT);
            System.Assert.areEqual(200, entries.size(), 'One entry per record saved');
            Map<String, Object> title = (Map<String, Object>) ((Map<String, Object>) entries[0]
                    .get('fields'))
                .get('Title');
            System.Assert.areEqual('Volunteer', title.get('before'), 'The value before');
            System.Assert.areEqual('Coordinator', title.get('after'), 'The value written');
        }
    }

    @IsTest
    static void clearEmptiesTheFieldOnTwoHundredRecords() {
        System.runAs(TestUsers.admin()) {
            makePeople(200, 0);
            Import_Batch__c job = run(
                maria(),
                changes(new Map<String, Object>{ 'field' => 'Title', 'action' => 'clear' }),
                200
            );

            System.Assert.areEqual(200, [SELECT COUNT() FROM Contact WHERE Title = NULL]);
            System.Assert.areEqual(200, job.Rows_Updated__c, job.Run_Log__c);
        }
    }

    @IsTest
    static void copyTakesEachRecordsOwnValueOverTwoHundredRecords() {
        System.runAs(TestUsers.admin()) {
            makePeople(200, 0);
            Import_Batch__c job = run(
                maria(),
                changes(
                    new Map<String, Object>{
                        'field' => 'Personal_Email__c',
                        'action' => 'copy',
                        'source' => 'Work_Email__c'
                    }
                ),
                200
            );

            System.Assert.areEqual(200, job.Rows_Updated__c, job.Run_Log__c);
            for (Contact person : [SELECT Work_Email__c, Personal_Email__c FROM Contact]) {
                System.Assert.areEqual(person.Work_Email__c, person.Personal_Email__c, 'Copied');
            }
        }
    }

    @IsTest
    static void refusesToStartWhenMoreMatchThanWereConfirmed() {
        System.runAs(TestUsers.admin()) {
            makePeople(200, 0);
            System.runAs(maria()) {
                try {
                    BulkUpdateService.start(VOLUNTEERS, SET_COORDINATOR, 199);
                    System.Assert.fail('200 match, 199 were confirmed');
                } catch (BulkUpdateFields.BulkUpdateException refused) {
                    System.Assert.isTrue(
                        refused.getMessage().contains('199'),
                        refused.getMessage()
                    );
                }
            }
            System.Assert.areEqual(0, [SELECT COUNT() FROM Import_Batch__c], 'No job is created');
            System.Assert.areEqual(200, [SELECT COUNT() FROM Contact WHERE Title = 'Volunteer']);
        }
    }

    @IsTest
    static void aRecordThatNoLongerMatchesIsLeftAlone() {
        System.runAs(TestUsers.admin()) {
            makePeople(200, 0);
            System.runAs(maria()) {
                BulkUpdateBatch job = new BulkUpdateBatch(createJob(SET_COORDINATOR, 200).Id);
                List<SObject> scope = startQuery(job);
                // Somebody changes one record between the job's start and its chunk.
                update new Contact(Id = scope[0].Id, Title = 'Staff');
                runNow(job, scope);
            }

            System.Assert.areEqual(199, [SELECT COUNT() FROM Contact WHERE Title = 'Coordinator']);
            System.Assert.areEqual(1, [SELECT COUNT() FROM Contact WHERE Title = 'Staff']);
            Import_Batch__c job = [
                SELECT Rows_Updated__c, Run_Log__c
                FROM Import_Batch__c
                LIMIT 1
            ];
            System.Assert.areEqual(199, job.Rows_Updated__c, job.Run_Log__c);
        }
    }

    @IsTest
    static void aRecordThePlatformRefusesIsJournaledWithItsReason() {
        System.runAs(TestUsers.admin()) {
            makePeople(200, 0);
            // An email field takes any text in the check; the save itself refuses it.
            Import_Batch__c job = run(
                maria(),
                changes(
                    new Map<String, Object>{
                        'field' => 'Personal_Email__c',
                        'action' => 'set',
                        'value' => 'not an email'
                    }
                ),
                200
            );

            System.Assert.areEqual(200, job.Rows_Rejected__c, job.Run_Log__c);
            System.Assert.areEqual(0, job.Rows_Updated__c, 'Nothing saved');
            List<Map<String, Object>> entries = journal(job.Id, ImportJournalService.PHASE_COMMIT);
            System.Assert.areEqual(200, entries.size(), 'Each refusal is journaled');
            System.Assert.areEqual(ImportJournalService.ACTION_FAILED, entries[0].get('action'));
            System.Assert.isTrue(
                String.isNotBlank((String) entries[0].get('reason')),
                'The reason'
            );
        }
    }

    /** A household's name is kept by household naming (R-H8); an organization's is not. */
    @IsTest
    static void aHouseholdNameIsLeftAloneAndAnOrganizationsIsChanged() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
            Id organizationType = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId();
            List<Account> accounts = new List<Account>();
            for (Integer index = 0; index < 100; index++) {
                Account household = HouseholdTestDataFactory.newHousehold('Renameme Home ' + index);
                // Named by hand, so household naming keeps this name and the query finds it.
                household.Custom_Name__c = true;
                accounts.add(household);
                accounts.add(
                    new Account(Name = 'Renameme Org ' + index, RecordTypeId = organizationType)
                );
            }
            insert accounts;
            String query = JSON.serialize(
                new Map<String, Object>{
                    'version' => 1,
                    'object' => 'Account',
                    'fields' => new List<Object>{ 'Name' },
                    'filter' => new Map<String, Object>{
                        'version' => 1,
                        'conditions' => new List<Object>{
                            new Map<String, Object>{
                                'id' => 1,
                                'field' => 'Name',
                                'operator' => 'starts with',
                                'value' => 'Renameme'
                            }
                        }
                    }
                }
            );
            String rename = changes(
                new Map<String, Object>{ 'field' => 'Name', 'action' => 'set', 'value' => 'Same' }
            );
            User person = maria();
            Import_Batch__c started;

            Test.startTest();
            System.runAs(person) {
                BulkUpdateService.Preview preview = BulkUpdateService.preview(query, rename);
                System.Assert.areEqual(200, preview.count, 'Both kinds match');
                started = BulkUpdateService.start(query, rename, 200);
            }
            Test.stopTest();

            Import_Batch__c job = reread(started.Id);
            System.Assert.areEqual(100, job.Rows_Updated__c, job.Run_Log__c);
            System.Assert.areEqual(100, job.Rows_Rejected__c, 'Each household is refused');
            System.Assert.areEqual(100, [SELECT COUNT() FROM Account WHERE Name = 'Same']);
            Id householdType = HouseholdService.householdRecordTypeId();
            System.Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Name = 'Same' AND RecordTypeId = :householdType],
                'No household was renamed'
            );
            Boolean reasonGiven = false;
            for (Map<String, Object> entry : journal(job.Id, ImportJournalService.PHASE_COMMIT)) {
                reasonGiven =
                    reasonGiven ||
                    System.Label.Core_BulkUpdate_ErrorHouseholdName.equals(entry.get('reason'));
            }
            System.Assert.isTrue(reasonGiven, 'The reason is journaled');
        }
    }

    /**
     * A chunk the platform stopped (a governor limit, which a test cannot cause) leaves records
     * nobody reached, and the run log says how many rather than four numbers that do not add up.
     */
    @IsTest
    static void aStoppedChunkSaysHowManyRecordsWereNotReached() {
        System.runAs(TestUsers.admin()) {
            makePeople(200, 0);
            Import_Batch__c created;
            System.runAs(maria()) {
                created = createJob(SET_COORDINATOR, 200);
                BulkUpdateBatch job = new BulkUpdateBatch(created.Id);
                List<SObject> scope = startQuery(job);
                List<SObject> firstHalf = new List<SObject>();
                for (Integer i = 0; i < 100; i++) {
                    firstHalf.add(scope[i]);
                }
                // The second chunk rolled back whole: only the first is counted.
                BulkUpdateBatch.jobErrorsForTest = 1;
                runNow(job, firstHalf);
            }

            Import_Batch__c done = reread(created.Id);
            System.Assert.areEqual(ImportBatchService.STATUS_FAILED, done.Status__c);
            System.Assert.areEqual(100, done.Rows_Updated__c, done.Run_Log__c);
            System.Assert.isTrue(
                done.Run_Log__c.contains(
                    String.format(
                        System.Label.Core_BulkUpdate_LogNotReached,
                        new List<Object>{ (100).format() }
                    )
                ),
                done.Run_Log__c
            );
        }
    }

    /**
     * A record whose old and new values are too long for a journal page is refused, never saved
     * without an undo, and the reason is journaled.
     */
    @IsTest
    static void aChangeTooLargeToUndoIsRefusedNotSaved() {
        System.runAs(TestUsers.admin()) {
            makePeople(200, 0);
            ImportJournalService.maxDocumentLength = 1500;
            String longText = changes(
                new Map<String, Object>{
                    'field' => 'Description',
                    'action' => 'set',
                    'value' => 'x'.repeat(2000)
                }
            );
            Import_Batch__c job = run(maria(), longText, 200);

            System.Assert.areEqual(0, job.Rows_Updated__c, job.Run_Log__c);
            System.Assert.areEqual(200, job.Rows_Rejected__c, 'Each record is refused');
            System.Assert.areEqual(
                0,
                [SELECT COUNT() FROM Contact WHERE Description != NULL],
                'Nothing was saved without an undo'
            );
            List<Map<String, Object>> entries = journal(job.Id, ImportJournalService.PHASE_COMMIT);
            System.Assert.areEqual(200, entries.size(), 'One refusal per record');
            System.Assert.areEqual(
                System.Label.Core_BulkUpdate_ErrorTooLargeToUndo,
                entries[0].get('reason')
            );
        }
    }

    @IsTest
    static void undoPutsBackTwoHundredValuesExceptOneChangedSince() {
        System.runAs(TestUsers.admin()) {
            ImportEntityProcessors.noneForTest = true;
            makePeople(200, 0);
            User maria = maria();
            Import_Batch__c created;
            System.runAs(maria) {
                created = createJob(SET_COORDINATOR, 200);
                BulkUpdateBatch job = new BulkUpdateBatch(created.Id);
                runNow(job, startQuery(job));
            }
            Contact corrected = [SELECT Id FROM Contact LIMIT 1];
            update new Contact(Id = corrected.Id, Title = 'Treasurer');
            System.Assert.isFalse(
                new Map<Id, Import_Batch__c>(ImportBatchSelector.selectRecent(10))
                    .containsKey(created.Id),
                'The import history lists imports only'
            );

            Test.startTest();
            System.runAs(maria) {
                ImportUndoService.Preview preview = ImportUndoService.preview(created.Id);
                // The reason is null when the undo is allowed, and an assertion message may not be.
                System.Assert.isTrue(preview.allowed, 'Undo is allowed: ' + preview.reason);
                System.Assert.areEqual(200, preview.updates, 'The records the bulk update saved');
                ImportUndoService.start(created.Id, preview.total);
            }
            Test.stopTest();

            System.Assert.areEqual(199, [SELECT COUNT() FROM Contact WHERE Title = 'Volunteer']);
            System.Assert.areEqual(
                'Treasurer',
                [SELECT Title FROM Contact WHERE Id = :corrected.Id].Title
            );
            System.Assert.areEqual(ImportBatchService.STATUS_UNDONE, reread(created.Id).Status__c);
            List<Map<String, Object>> kept = journal(created.Id, ImportJournalService.PHASE_UNDO);
            System.Assert.areEqual(1, kept.size(), 'The value changed since is journaled');
            System.Assert.areEqual(ImportJournalService.ACTION_NOT_RESTORED, kept[0].get('action'));
        }
    }
}
