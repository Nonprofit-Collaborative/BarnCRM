/**
 * Undoing a bulk delete (C-37, canonical model R-BD5): every record the job journaled comes back
 * from the Recycle Bin as the person, a record no longer there is reported as purged, one
 * somebody already restored is left alone, and the import undo's guards apply.
 *
 * The delete is driven through the job's own start query, so the one queued job a test may run
 * is the undo.
 *
 * No org has run these yet; they are written against the behaviour the classes document.
 */
@IsTest
private class BulkDeleteUndoTest {
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

    private static User deleter() {
        return TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Bulk_Delete' }
        );
    }

    /** `count` volunteers, deleted by a bulk delete run now; returns the job's Id. */
    private static Id deleteVolunteers(Integer count) {
        DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
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
        Import_Batch__c created = BulkDeleteService.createJob(
            BulkDeleteService.plan(VOLUNTEERS),
            count,
            count
        );
        BulkDeleteBatch job = new BulkDeleteBatch(created.Id);
        List<SObject> scope = new List<SObject>();
        Database.QueryLocatorIterator records = job.start(null).iterator();
        while (records.hasNext()) {
            scope.add(records.next());
        }
        job.execute(null, scope);
        job.finish(null);
        return created.Id;
    }

    private static Import_Batch__c reread(Id jobId) {
        return [
            SELECT Status__c, Run_Log__c, Rows_Deleted__c
            FROM Import_Batch__c
            WHERE Id = :jobId
        ];
    }

    @IsTest
    static void bringsBackTwoHundredAndReportsThePurgedAndTheAlreadyRestored() {
        System.runAs(TestUsers.admin()) {
            Id jobId;
            System.runAs(deleter()) {
                jobId = deleteVolunteers(200);
            }
            System.Assert.areEqual(200, reread(jobId).Rows_Deleted__c, reread(jobId).Run_Log__c);
            List<Contact> binned = [
                SELECT Id
                FROM Contact
                WHERE IsDeleted = TRUE
                ORDER BY Id
                LIMIT 2
                ALL ROWS
            ];
            undelete binned[0];
            Database.emptyRecycleBin(new List<Id>{ binned[1].Id });

            Test.startTest();
            System.runAs(deleter()) {
                BulkDeleteService.UndoPreview preview = BulkDeleteService.undoPreview(jobId);
                System.Assert.isTrue(preview.allowed, 'Undo is allowed: ' + preview.reason);
                System.Assert.areEqual(200, preview.records, 'The records it deleted');
                BulkDeleteService.undo(jobId, preview.records);
                System.Assert.areEqual(
                    ImportBatchService.STATUS_UNDOING,
                    reread(jobId).Status__c,
                    'Latched'
                );
            }
            Test.stopTest();

            System.Assert.areEqual(199, [SELECT COUNT() FROM Contact], 'All but the purged one');
            Import_Batch__c done = reread(jobId);
            System.Assert.areEqual(
                ImportBatchService.STATUS_UNDONE,
                done.Status__c,
                done.Run_Log__c
            );
            System.Assert.isTrue(done.Run_Log__c.contains('198 brought back'), done.Run_Log__c);
            List<Map<String, Object>> undone = new List<Map<String, Object>>();
            for (Import_Journal__c page : [
                SELECT Entries_JSON__c
                FROM Import_Journal__c
                WHERE Import_Batch__c = :jobId AND Phase__c = :ImportJournalService.PHASE_UNDO
            ]) {
                undone.addAll(ImportJournalService.entries(page));
            }
            System.Assert.areEqual(1, undone.size(), 'Only the purged record is journaled');
            System.Assert.areEqual(
                ImportJournalService.ACTION_NOT_RESTORED,
                undone[0].get('action')
            );
            System.Assert.areEqual(String.valueOf(binned[1].Id), undone[0].get('id'));
            System.Assert.areEqual(
                System.Label.Core_BulkDelete_UndoPurged,
                undone[0].get('reason')
            );
        }
    }

    @IsTest
    static void refusesAWrongCountASecondUndoAndAClosedWindow() {
        System.runAs(TestUsers.admin()) {
            Id jobId;
            System.runAs(deleter()) {
                jobId = deleteVolunteers(20);
                try {
                    BulkDeleteService.undo(jobId, 19);
                    System.Assert.fail('A different count');
                } catch (BulkDeleteService.BulkDeleteException expected) {
                    System.Assert.isTrue(expected.getMessage().contains('20'), 'Names the count');
                }
            }
            update new Import_Batch__c(Id = jobId, Status__c = ImportBatchService.STATUS_UNDONE);
            System.Assert.isFalse(BulkDeleteService.undoPreview(jobId).allowed, 'Once only');
            update new Import_Batch__c(
                Id = jobId,
                Status__c = ImportBatchService.STATUS_COMPLETE,
                Undo_Deadline__c = Datetime.now().addMinutes(-1)
            );
            BulkDeleteService.UndoPreview closed = BulkDeleteService.undoPreview(jobId);
            System.Assert.isFalse(closed.allowed, 'Past the deadline');
            System.Assert.isTrue(String.isNotBlank(closed.reason), 'Says why');
            System.Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'Nothing brought back');
        }
    }

    @IsTest
    static void aJobThatIsNotABulkDeleteIsNotFound() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c updateJob = new Import_Batch__c(
                Operation__c = BulkUpdateService.OPERATION_UPDATE,
                Status__c = ImportBatchService.STATUS_COMPLETE,
                Is_Dry_Run__c = false,
                Completed_At__c = Datetime.now(),
                Undo_Deadline__c = Datetime.now().addDays(1)
            );
            insert updateJob;
            BulkDeleteService.UndoPreview preview = BulkDeleteService.undoPreview(updateJob.Id);
            System.Assert.isFalse(preview.allowed, 'Refused');
            System.Assert.areEqual(System.Label.Core_BulkDelete_ErrorNotBulkDelete, preview.reason);
        }
    }
}
