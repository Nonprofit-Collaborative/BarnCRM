/**
 * The nightly Import row cleanup (R-IR5): the rows of a complete import are removed by the
 * org's Delete Import Rows choice (Once Complete, After 30 Days by default, After 90 Days,
 * Never), an uncommitted preview keeps its rows at least 30 days, any other batch keeps them,
 * the import keeps its counts, a batch whose rows are gone is refused rather than run over
 * nothing, and undo still works once the rows are gone (R-IR8).
 */
@IsTest(testFor='ApexClass:ImportRowPurgeBatch, ApexClass:ImportRowPurgeScheduler')
private class ImportRowPurgeTest {
    /** More rows than one chunk of 200, so the cleanup is bulk tested. */
    private static final Integer ROWS = 251;

    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Import_Template__c template() {
        return ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
    }

    /** A batch with `ROWS` rows in the given status, its last pass completed the days ago given. */
    private static Import_Batch__c batchOf(
        Import_Template__c template,
        String status,
        Integer daysAgo
    ) {
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < ROWS; i++) {
            values.add(
                ImportTestDataFactory.donorRow('Ana', 'Row' + i, 'row' + i + '@example.org', null)
            );
        }
        ImportTestDataFactory.rows(batch, values);
        update new Import_Batch__c(
            Id = batch.Id,
            Status__c = status,
            Is_Dry_Run__c = ImportBatchService.STATUS_DRY_RUN_COMPLETE.equals(status),
            Rows_Created__c = ROWS,
            Completed_At__c = daysAgo == null ? null : Datetime.now().addDays(-daysAgo)
        );
        return batch;
    }

    private static Integer rowsOf(Id batchId) {
        return [
            SELECT COUNT()
            FROM Import_Row__c
            WHERE Import_Batch__c = :batchId
            WITH SYSTEM_MODE
        ];
    }

    private static void deleteRows(String choice) {
        BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
        settings.Import_Row_Deletion__c = choice;
        TestDataFactory.saveSettings(settings);
    }

    /** Runs the cleanup's start and execute in this transaction, as the job would. */
    private static void runNow(ImportRowPurgeBatch purge) {
        List<SObject> scope = new List<SObject>();
        Database.QueryLocatorIterator found = purge.start(null).iterator();
        while (found.hasNext()) {
            scope.add(found.next());
        }
        if (!scope.isEmpty()) {
            purge.execute(null, scope);
        }
        purge.finish(null);
    }

    @IsTest
    static void byDefaultCompleteImportsLoseTheirRowsAfterThirtyDays() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = template();
            Import_Batch__c old = batchOf(template, ImportBatchService.STATUS_COMPLETE, 40);
            Import_Batch__c failed = batchOf(template, ImportBatchService.STATUS_FAILED, 40);
            Import_Batch__c recent = batchOf(template, ImportBatchService.STATUS_COMPLETE, 10);
            Import_Batch__c draft = batchOf(template, ImportBatchService.STATUS_DRAFT, null);

            Test.startTest();
            Database.executeBatch(new ImportRowPurgeBatch(), ImportRowPurgeBatch.CHUNK_SIZE);
            Test.stopTest();

            Assert.areEqual(0, rowsOf(old.Id), 'Rows of an import 40 days complete are removed.');
            Assert.areEqual(0, rowsOf(failed.Id), 'So are a failed commit\'s.');
            Assert.areEqual(ROWS, rowsOf(recent.Id), 'Rows of a recent import are kept.');
            Assert.areEqual(ROWS, rowsOf(draft.Id), 'Rows of an import never run are kept.');
            Import_Batch__c kept = [
                SELECT Rows_Created__c, Status__c
                FROM Import_Batch__c
                WHERE Id = :old.Id
            ];
            Assert.areEqual(ROWS, kept.Rows_Created__c, 'The import keeps its counts.');
            Assert.areEqual(ImportBatchService.STATUS_COMPLETE, kept.Status__c);
        }
    }

    @IsTest
    static void onceCompleteRemovesAtOnceButAPreviewAndAnOpenBatchKeepTheirRows() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = template();
            Import_Batch__c done = batchOf(template, ImportBatchService.STATUS_COMPLETE, 0);
            Import_Batch__c undone = batchOf(template, ImportBatchService.STATUS_UNDONE, 0);
            Import_Batch__c preview = batchOf(
                template,
                ImportBatchService.STATUS_DRY_RUN_COMPLETE,
                10
            );
            Import_Batch__c oldPreview = batchOf(
                template,
                ImportBatchService.STATUS_DRY_RUN_COMPLETE,
                31
            );
            Import_Batch__c trial = batchOf(template, ImportBatchService.STATUS_TRIAL_COMPLETE, 50);
            Import_Batch__c retrying = batchOf(template, ImportBatchService.STATUS_RETRYING, 50);
            deleteRows(ImportBatchService.ROWS_ONCE_COMPLETE);

            Test.startTest();
            runNow(new ImportRowPurgeBatch());
            Test.stopTest();

            Assert.areEqual(0, rowsOf(done.Id), 'Once complete, the rows go the same night.');
            Assert.areEqual(0, rowsOf(undone.Id), 'An undone import is complete too.');
            Assert.areEqual(ROWS, rowsOf(preview.Id), 'A preview keeps its rows 30 days.');
            Assert.areEqual(0, rowsOf(oldPreview.Id), 'Then they go.');
            Assert.areEqual(ROWS, rowsOf(trial.Id), 'A trial waiting for the rest keeps them.');
            Assert.areEqual(ROWS, rowsOf(retrying.Id), 'So does an open retry.');
        }
    }

    @IsTest
    static void ninetyDaysAndNeverAreHonoured() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = template();
            Import_Batch__c sixtyDays = batchOf(template, ImportBatchService.STATUS_COMPLETE, 60);
            Import_Batch__c yearsAgo = batchOf(template, ImportBatchService.STATUS_COMPLETE, 4000);
            deleteRows(ImportBatchService.ROWS_NEVER);
            ImportRowPurgeBatch never = new ImportRowPurgeBatch();
            runNow(never);
            Assert.areEqual(ROWS, rowsOf(yearsAgo.Id), 'Never keeps every row, however old.');

            deleteRows(ImportBatchService.ROWS_AFTER_90_DAYS);
            Test.startTest();
            runNow(new ImportRowPurgeBatch());
            Test.stopTest();

            Assert.areEqual(ROWS, rowsOf(sixtyDays.Id), 'Kept for 90 days, 60 days stays.');
            Assert.areEqual(0, rowsOf(yearsAgo.Id), 'Older goes.');
        }
    }

    @IsTest
    static void eachChoiceReadsAsItsDaysAndNonsenseAsThirty() {
        System.runAs(TestUsers.admin()) {
            Map<String, Integer> expected = new Map<String, Integer>{
                ImportBatchService.ROWS_ONCE_COMPLETE => 0,
                ImportBatchService.ROWS_AFTER_30_DAYS => 30,
                ImportBatchService.ROWS_AFTER_90_DAYS => 90,
                ImportBatchService.ROWS_NEVER => null,
                'Sometimes' => 30
            };
            for (String choice : expected.keySet()) {
                deleteRows(choice);
                Assert.areEqual(
                    expected.get(choice),
                    ImportBatchService.rowRetentionDays(),
                    choice
                );
            }
            deleteRows(null);
            Assert.areEqual(30, ImportBatchService.rowRetentionDays(), 'Blank reads as 30 days.');
        }
    }

    /**
     * Undo reads the tag and the journal, never the rows (R-IR8): once the cleanup removed
     * every row, the undo still deletes what the import created and puts back what it changed.
     */
    @IsTest
    static void undoStillWorksAfterTheRowsAreRemoved() {
        System.runAs(TestUsers.admin()) {
            ImportEntityProcessors.noneForTest = true;
            TestDataFactory.defaultSettings();
            Import_Batch__c batch = batchOf(template(), ImportBatchService.STATUS_COMPLETE, 0);
            update new Import_Batch__c(
                Id = batch.Id,
                Is_Dry_Run__c = false,
                Started_At__c = Datetime.now().addMinutes(-5),
                Completed_At__c = Datetime.now().addMinutes(1),
                Committed_By__c = UserInfo.getUserId(),
                Undo_Deadline__c = Datetime.now().addDays(30)
            );
            Contact created = new Contact(
                FirstName = 'Ana',
                LastName = 'Ramirez',
                Created_By_Import_Batch__c = batch.Id
            );
            Contact updated = new Contact(LastName = 'Okafor', MailingCity = 'Portland');
            insert new List<Contact>{ created, updated };
            created = [SELECT Id, AccountId FROM Contact WHERE Id = :created.Id];
            update new Account(Id = created.AccountId, Created_By_Import_Batch__c = batch.Id);
            ImportJournalService.write(
                batch.Id,
                ImportJournalService.PHASE_COMMIT,
                new List<Map<String, Object>>{
                    ImportJournalService.updated(
                        'Contact',
                        updated.Id,
                        2,
                        new Map<String, Object>{ 'MailingCity' => 'Salem' },
                        new Map<String, Object>{ 'MailingCity' => 'Portland' }
                    )
                }
            );
            deleteRows(ImportBatchService.ROWS_ONCE_COMPLETE);
            ImportRowPurgeBatch purge = new ImportRowPurgeBatch();
            purge.cutoff = Datetime.now().addMinutes(5);
            runNow(purge);
            Assert.areEqual(0, rowsOf(batch.Id), 'The cleanup removed every row first.');

            Integer total = ImportUndoService.preview(batch.Id).total;
            // Latched only: the passes below run here, the restore among them.
            System.abortJob(ImportUndoService.start(batch.Id, total));
            Test.startTest();
            new ImportUndoTestSupport.Run(batch.Id, total, Datetime.now()).rest();
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM Contact WHERE Id = :created.Id], 'Deleted.');
            Assert.areEqual(
                'Salem',
                [SELECT MailingCity FROM Contact WHERE Id = :updated.Id].MailingCity,
                'Put back.'
            );
            Assert.areEqual(
                ImportBatchService.STATUS_UNDONE,
                [SELECT Status__c FROM Import_Batch__c WHERE Id = :batch.Id].Status__c,
                'The undo finished without the rows.'
            );
        }
    }

    @IsTest
    static void aBatchWhoseRowsWereRemovedCannotRunAgain() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = batchOf(
                template(),
                ImportBatchService.STATUS_DRY_RUN_COMPLETE,
                100
            );
            delete [SELECT Id FROM Import_Row__c WHERE Import_Batch__c = :batch.Id];

            String refused;
            Test.startTest();
            try {
                ImportBatchService.startCommit(batch.Id);
            } catch (ImportException e) {
                refused = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(Label.Core_Import_ErrorRowsRemoved, refused, 'Refused, saying why.');
        }
    }

    @IsTest
    static void rowsThatCannotBeDeletedAreLoggedOncePerChunkAndTheJobFinishes() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c old = batchOf(template(), ImportBatchService.STATUS_COMPLETE, 100);
            List<Import_Row__c> rows = [
                SELECT Id
                FROM Import_Row__c
                WHERE Import_Batch__c = :old.Id
            ];
            // Gone before the chunk runs, so every delete in it is refused.
            delete rows;

            Test.startTest();
            ImportRowPurgeBatch purge = new ImportRowPurgeBatch();
            purge.execute(null, rows);
            purge.finish(null);
            Test.stopTest();

            List<Error_Log__c> entries = [
                SELECT Message__c, Severity__c
                FROM Error_Log__c
                WHERE Context__c = 'ImportRowPurgeBatch'
            ];
            Assert.areEqual(1, entries.size(), 'One entry for the chunk, not one per row');
            Assert.areEqual(ErrorLogger.SEVERITY_WARNING, entries[0].Severity__c);
            Assert.isTrue(
                entries[0].Message__c.contains(String.valueOf(rows.size())),
                'It says how many rows were not removed: ' + entries[0].Message__c
            );
        }
    }

    @IsTest
    static void theCleanupIsScheduledOnceAndListedAsANightlyJob() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Id first = ImportRowPurgeScheduler.start();
            Id second = ImportRowPurgeScheduler.start();
            Test.stopTest();

            Assert.areEqual(first, second, 'Starting again finds the job already there.');
            Assert.isTrue(ImportRowPurgeScheduler.isScheduled());
            Boolean listed = false;
            for (NightlyJob job : NightlyJobs.all()) {
                if (job.label() == System.Label.Core_HealthCheck_JobImportRows) {
                    listed = job.isScheduled();
                }
            }
            Assert.isTrue(listed, 'Health Check sees it among the nightly jobs, scheduled.');
        }
    }
}
