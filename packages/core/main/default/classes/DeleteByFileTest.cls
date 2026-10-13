/**
 * Delete by file (canonical model R-BD7, ADR-NEXT `NEXT-delete-by-file.md`): a one-object
 * import whose rows name records by ID is dry run as an import, refuses the import commit, and
 * starts as a bulk delete of exactly the Matched rows once the count is typed; the job deletes
 * as the person, journals each record and is undone by undelete.
 *
 * Every test runs as a minimal-profile user holding BarnCRM Admin and, where it deletes,
 * BarnCRM Bulk Delete.
 */
@IsTest
private class DeleteByFileTest {
    private static final Integer MANY = 200;

    private static User deleter() {
        return TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Bulk_Delete' }
        );
    }

    /** `volunteers` contacts titled Volunteer and `staff` titled Staff, in name order. */
    private static List<Contact> makePeople(Integer volunteers, Integer staff) {
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
        return people;
    }

    private static Import_Template__c deleteTemplate() {
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Id', 'Record.Id'));
        mapping.columns.add(new ImportMapping.Column('Name', 'Record.LastName'));
        Import_Template__c template = ImportTestDataFactory.template(mapping.serialize(), null);
        template.Target_Object__c = 'Contact';
        template.Load_Operation__c = ImportObjectSchema.OPERATION_DELETE;
        update template;
        return ImportTemplateSelector.selectById(template.Id);
    }

    /**
     * A file naming every volunteer, then a repeat, an ID that is not one and an account's ID,
     * dry run as an import.
     */
    private static Import_Batch__c dryRun(Import_Template__c template, List<Contact> volunteers) {
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Contact person : volunteers) {
            values.add(new Map<String, String>{ 'Id' => person.Id, 'Name' => 'ignored' });
        }
        values.add(new Map<String, String>{ 'Id' => volunteers[0].Id });
        values.add(new Map<String, String>{ 'Id' => 'not an id' });
        values.add(new Map<String, String>{ 'Id' => volunteers[0].AccountId });
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, values);
        ImportBatchService.beginPass(batch.Id);
        ImportRowProcessor.Outcome outcome = ImportRowProcessor.process(
            ImportBatchSelector.selectById(batch.Id),
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c, template.Default_Values_JSON__c),
            ImportTestDataFactory.reload(batch.Id),
            true
        );
        Assert.areEqual(volunteers.size(), outcome.matched, 'Each named record would go.');
        Assert.areEqual(3, outcome.rejected, 'The repeat, the bad ID and the account.');
        update new Import_Batch__c(
            Id = batch.Id,
            Status__c = ImportBatchService.STATUS_DRY_RUN_COMPLETE
        );
        return batch;
    }

    private static Integer journaledDeletes(Id jobId) {
        Integer total = 0;
        for (Import_Journal__c page : [
            SELECT Entries_JSON__c
            FROM Import_Journal__c
            WHERE Import_Batch__c = :jobId AND Phase__c = :ImportJournalService.PHASE_COMMIT
        ]) {
            for (Map<String, Object> entry : ImportJournalService.entries(page)) {
                if (ImportJournalService.ACTION_DELETED.equals(entry.get('action'))) {
                    total++;
                }
            }
        }
        return total;
    }

    @IsTest
    static void twoHundredRecordsAFileNamesAreDeletedOnceTheCountIsTyped() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = makePeople(MANY, 30);
            List<Contact> volunteers = new List<Contact>();
            for (Integer i = 0; i < MANY; i++) {
                volunteers.add(people[i]);
            }
            Import_Batch__c batch;
            System.runAs(deleter()) {
                Import_Template__c template = deleteTemplate();
                Assert.isTrue(
                    ImportObjectSchema.operationsFor(Contact.SObjectType)
                        .contains(ImportObjectSchema.OPERATION_DELETE),
                    'Offered to a person who may bulk delete.'
                );
                batch = dryRun(template, volunteers);
                Assert.areEqual(
                    MANY + 30,
                    [SELECT COUNT() FROM Contact],
                    'The dry run deletes nothing.'
                );

                BulkDeleteService.Preview preview = BulkDeleteService.filePreview(batch.Id);
                Assert.areEqual(MANY, preview.count, 'The count to type is the Matched rows.');
                Assert.areEqual(BulkDeleteService.SAMPLE_SIZE, preview.sample.size());
                Assert.isTrue(preview.sample[0].name.startsWith('Person '), 'Named.');

                try {
                    ImportBatchService.startCommit(batch.Id);
                    Assert.fail('The import commit is refused.');
                } catch (ImportException refused) {
                    Assert.areEqual(
                        Label.Core_Import_ErrorDeleteNeedsConfirm,
                        refused.getMessage()
                    );
                }
                try {
                    BulkDeleteService.startFromFile(batch.Id, MANY - 1);
                    Assert.fail('A count that is not the dry run count is refused.');
                } catch (BulkDeleteService.BulkDeleteException refused) {
                    Assert.isTrue(
                        refused.getMessage().contains(MANY.format()),
                        refused.getMessage()
                    );
                }
            }
            // Somebody deletes one of them after the dry run.
            delete volunteers[MANY - 1];

            Test.startTest();
            System.runAs(deleter()) {
                BulkDeleteService.startFromFile(batch.Id, MANY);
            }
            Test.stopTest();

            Import_Batch__c job = [
                SELECT Status__c, Operation__c, Operation_JSON__c, Rows_Deleted__c, Run_Log__c
                FROM Import_Batch__c
                WHERE Id = :batch.Id
            ];
            Assert.areEqual(ImportBatchService.STATUS_COMPLETE, job.Status__c, job.Run_Log__c);
            Assert.areEqual(BulkDeleteService.OPERATION_DELETE, job.Operation__c);
            Assert.isTrue(job.Operation_JSON__c.contains('"source":"file"'), job.Operation_JSON__c);
            Assert.areEqual(
                MANY - 1,
                job.Rows_Deleted__c,
                'The one already gone is counted apart.'
            );
            Assert.areEqual(MANY - 1, journaledDeletes(job.Id), 'Each deleted Id is journaled.');
            Assert.areEqual(0, [SELECT COUNT() FROM Contact WHERE Title = 'Volunteer']);
            Assert.areEqual(30, [SELECT COUNT() FROM Contact WHERE Title = 'Staff']);
            Assert.isFalse(
                new Map<Id, Import_Batch__c>(ImportBatchSelector.selectRecent(10))
                    .containsKey(job.Id),
                'It has left the import history.'
            );
        }
    }

    @IsTest
    static void theUndoBringsBackWhatADeleteByFileDeleted() {
        System.runAs(TestUsers.admin()) {
            List<Contact> volunteers = makePeople(MANY, 0);
            Id jobId;
            System.runAs(deleter()) {
                Import_Batch__c batch = dryRun(deleteTemplate(), volunteers);
                BulkDeleteService.Plan checked = BulkDeleteService.planForFile('Contact');
                update new Import_Batch__c(
                    Id = batch.Id,
                    Operation__c = BulkDeleteService.OPERATION_DELETE,
                    Operation_JSON__c = checked.definition(MANY),
                    Status__c = ImportBatchService.STATUS_COMMITTING,
                    Is_Dry_Run__c = false,
                    Started_At__c = Datetime.now(),
                    Committed_By__c = UserInfo.getUserId(),
                    Undo_Deadline__c = BulkDeleteService.undoDeadlineFrom(Datetime.now())
                );
                BulkDeleteBatch job = new BulkDeleteBatch(batch.Id);
                List<SObject> scope = new List<SObject>();
                Database.QueryLocatorIterator rows = job.start(null).iterator();
                while (rows.hasNext()) {
                    scope.add(rows.next());
                }
                job.execute(null, scope);
                job.finish(null);
                jobId = batch.Id;
            }
            Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'Every named record is deleted.');

            Test.startTest();
            System.runAs(deleter()) {
                BulkDeleteController.JobView view = BulkDeleteController.getJob(jobId);
                Assert.isTrue(view.canUndo, 'Listed and undoable with the bulk deletes.');
                Assert.areEqual(MANY, view.recordsToUndo);
                BulkDeleteController.undo(jobId, view.recordsToUndo);
            }
            Test.stopTest();
            Assert.areEqual(MANY, [SELECT COUNT() FROM Contact], 'The undo brings them back.');
        }
    }

    @IsTest
    static void aPersonWithoutBulkDeleteIsNeitherOfferedNorAllowedIt() {
        System.runAs(TestUsers.admin()) {
            List<Contact> volunteers = makePeople(2, 0);
            System.runAs(TestUsers.withPermissionSets(new List<String>{ TestUsers.CORE_ADMIN })) {
                Assert.isFalse(
                    ImportObjectSchema.operationsFor(Contact.SObjectType)
                        .contains(ImportObjectSchema.OPERATION_DELETE)
                );
                Import_Template__c template = deleteTemplate();
                Assert.areEqual(
                    Label.Core_Import_ErrorDeleteNeedsPermission,
                    ImportObjectSchema.refusal(
                        template,
                        ImportMapping.parse(template.Column_Mapping_JSON__c)
                    )
                );
                ImportTemplateService.LoadChoices choices = new ImportTemplateService.LoadChoices();
                choices.operation = ImportObjectSchema.OPERATION_DELETE;
                try {
                    ImportTemplateService.saveLoad(template.Id, choices);
                    Assert.fail('Saving a delete is refused.');
                } catch (ImportException refused) {
                    Assert.areEqual(
                        Label.Core_Import_ErrorDeleteNeedsPermission,
                        refused.getMessage()
                    );
                }
                try {
                    BulkDeleteController.previewFile(volunteers[0].Id);
                    Assert.fail('The preview is refused.');
                } catch (AuraHandledException refused) {
                    Assert.isNotNull(refused.getMessage());
                }
            }
        }
    }
}
