/**
 * Retrying a committed import's fixed rejected rows into it (R-IB17): what the retry's
 * preview and commit read and count, that the replaced rejects are marked Retried, that one
 * undo still covers the import, and when a retry is refused.
 *
 * A test may start one batch job, so each test starts at most one pass through the service
 * and drives the others through the processor itself, the way the platform would.
 */
@IsTest(
    testFor='ApexClass:ImportBatchService, ApexClass:ImportProcessorBatch, ApexClass:ImportController'
)
private class ImportRetryRejectsTest {
    private static final Integer FILE_ROWS = 200;
    /** Every tenth row of the file has no last name, so 20 rows are rejected. */
    private static final Integer REJECTS = 20;

    /**
     * The committed import every test starts from, built once: its preview and commit are
     * driven synchronously and start no async work, and they run as the same admin user each
     * test runs as (TestUsers finds the setup user again), so Committed By is that user.
     */
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            commitFile();
        }
    }

    /** The import setup committed. */
    private static Import_Batch__c committed() {
        return ImportBatchSelector.selectById([SELECT Id FROM Import_Batch__c LIMIT 1].Id);
    }

    /** A 200-row file of new people, previewed and committed, with 20 rows rejected. */
    private static void commitFile() {
        Import_Template__c template = ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < FILE_ROWS; i++) {
            values.add(
                ImportTestDataFactory.donorRow(
                    'Person' + i,
                    Math.mod(i, 10) == 0 ? '' : 'Surname' + i,
                    'retry' + i + '@example.org',
                    null
                )
            );
        }
        ImportTestDataFactory.rows(batch, values);
        drive(batch.Id, true);
        drive(batch.Id, false);
    }

    /** The rejected rows with their last names put right, as the fixed file holds them. */
    private static List<Map<String, Object>> fixedRows() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Integer i = 0; i < FILE_ROWS; i += 10) {
            Map<String, String> donor = ImportTestDataFactory.donorRow(
                'Person' + i,
                'Fixed' + i,
                'retry' + i + '@example.org',
                null
            );
            Map<String, Object> row = new Map<String, Object>();
            for (String heading : donor.keySet()) {
                row.put(heading, donor.get(heading));
            }
            rows.add(row);
        }
        return rows;
    }

    /** Opens a retry and stages the fixed rows the way the wizard does. */
    private static Import_Batch__c retryStaged(Id batchId) {
        ImportBatchService.openRetry(batchId);
        ImportBatchService.stageRows(batchId, fixedRows(), 2);
        return ImportBatchSelector.selectById(batchId);
    }

    /**
     * One pass, run as the platform runs it, with what starting it stamps on the batch. A
     * retry's pass keeps the import's start and its cleared Is Dry Run, as the service does.
     */
    private static void drive(Id batchId, Boolean dryRun) {
        Boolean retrying = ImportBatchService.isRetrying(ImportBatchSelector.selectById(batchId));
        ImportBatchService.beginPass(batchId);
        Import_Batch__c stamp = new Import_Batch__c(
            Id = batchId,
            Status__c = dryRun
                ? ImportBatchService.STATUS_DRY_RUN
                : ImportBatchService.STATUS_COMMITTING
        );
        if (!retrying) {
            stamp.Is_Dry_Run__c = dryRun;
            stamp.Started_At__c = Datetime.now();
        }
        if (!dryRun) {
            stamp.Committed_By__c = UserInfo.getUserId();
        }
        update stamp;
        ImportProcessorBatch job = new ImportProcessorBatch(batchId, dryRun);
        List<Import_Row__c> rows = new List<Import_Row__c>();
        Database.QueryLocatorIterator found = job.start(null).iterator();
        while (found.hasNext()) {
            rows.add((Import_Row__c) found.next());
        }
        job.execute(null, rows);
        job.finish(null);
    }

    private static Integer rowsWithStatus(Id batchId, String status) {
        return [
            SELECT COUNT()
            FROM Import_Row__c
            WHERE Import_Batch__c = :batchId AND Status__c = :status
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void aRetryPreviewCountsOnlyTheFixedRowsAndWritesNothing() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committed();
            Assert.areEqual(REJECTS, batch.Rows_Rejected__c, 'Twenty rows were rejected.');
            Assert.areEqual(FILE_ROWS - REJECTS, [SELECT COUNT() FROM Contact], 'The rest exist.');
            Datetime completed = batch.Completed_At__c;
            Import_Batch__c staged = retryStaged(batch.Id);
            Assert.areEqual(ImportBatchService.STATUS_RETRYING, staged.Status__c, 'Retrying.');
            Assert.areEqual(FILE_ROWS + 1, staged.Retry_After_Row__c, 'After the last file row.');
            Assert.areEqual(FILE_ROWS + REJECTS, staged.Row_Count__c, 'The fixed rows join.');
            Assert.areEqual(
                REJECTS,
                [
                    SELECT COUNT()
                    FROM Import_Row__c
                    WHERE Import_Batch__c = :batch.Id AND Row_Number__c > :FILE_ROWS + 1
                ],
                'Numbered after every row the import had.'
            );

            Test.startTest();
            ImportBatchService.startDryRun(batch.Id);
            Test.stopTest();

            Import_Batch__c after = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(
                ImportBatchService.STATUS_DRY_RUN_COMPLETE,
                after.Status__c,
                'Previewed.'
            );
            Assert.areEqual(REJECTS, after.Rows_Created__c, 'It counts only the fixed rows.');
            Assert.areEqual(0, after.Rows_Rejected__c, 'None of them rejected.');
            Assert.areEqual(FILE_ROWS - REJECTS, [SELECT COUNT() FROM Contact], 'Nothing written.');
            Assert.areEqual(
                REJECTS,
                rowsWithStatus(batch.Id, ImportRowProcessor.STATUS_REJECTED),
                'The rejects stand until the commit replaces them.'
            );
            Assert.isTrue(after.Is_Dry_Run__c == false, 'The import stays committed.');
            Assert.areEqual(completed, after.Completed_At__c, 'Its end is unchanged.');
            Assert.isNull(ImportUndoService.refusal(after), 'And it can still be undone.');
            ImportController.BatchView view = ImportController.getBatch(batch.Id);
            Assert.isTrue(view.isDryRun, 'The screen shows a preview.');
            Assert.isTrue(view.retrying, 'Of a retry.');
            Assert.isTrue(view.controlTotalsAgree, 'Which the totals do not hold up.');
        }
    }

    @IsTest
    static void aRetryCommitReplacesTheRejectsInTheSameImport() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committed();
            Datetime started = batch.Started_At__c;
            retryStaged(batch.Id);
            drive(batch.Id, true);

            Test.startTest();
            ImportBatchService.startCommit(batch.Id);
            Test.stopTest();

            Import_Batch__c after = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(ImportBatchService.STATUS_COMPLETE, after.Status__c, 'Complete.');
            Assert.isNull(after.Retry_After_Row__c, 'The retry is closed.');
            Assert.areEqual(FILE_ROWS, after.Rows_Created__c, 'Every person of the file now.');
            Assert.areEqual(0, after.Rows_Rejected__c, 'No row left rejected.');
            Assert.areEqual(
                REJECTS,
                rowsWithStatus(batch.Id, ImportBatchService.ROW_STATUS_RETRIED),
                'Each replaced reject is marked Retried.'
            );
            Assert.areEqual(FILE_ROWS, [SELECT COUNT() FROM Contact], 'Nobody twice.');
            Assert.areEqual(
                FILE_ROWS,
                [SELECT COUNT() FROM Contact WHERE Created_By_Import_Batch__c = :batch.Id],
                'Every person carries the one import, so one undo removes them all.'
            );
            Assert.areEqual(started, after.Started_At__c, 'The import keeps its start.');
            Assert.isTrue(
                after.Run_Log__c.contains(Label.Core_Import_LogCommitHeader),
                'The log keeps both runs.'
            );
            Assert.isNull(ImportUndoService.refusal(after), 'And it is undone as one.');
            Assert.isFalse(
                ImportController.getBatch(batch.Id).canRetry,
                'With nothing rejected, nothing is left to retry.'
            );
        }
    }

    @IsTest
    static void aRetryIsRefusedWhereItCannotJoinTheImport() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committed();
            Assert.isNull(ImportBatchService.retryRefusal(batch), 'This one may retry.');

            Import_Batch__c otherUser = batch.clone(true, true, true, true);
            Id me = UserInfo.getUserId();
            otherUser.Committed_By__c = [SELECT Id FROM User WHERE Id != :me LIMIT 1].Id;
            Assert.areEqual(
                Label.Core_Import_ErrorRetryOtherUser,
                ImportBatchService.retryRefusal(otherUser),
                'Only the person who committed it.'
            );

            Import_Batch__c nothingRejected = batch.clone(true, true, true, true);
            nothingRejected.Rows_Rejected__c = 0;
            Assert.areEqual(
                Label.Core_Import_ErrorRetryNotOpen,
                ImportBatchService.retryRefusal(nothingRejected),
                'Nothing to retry.'
            );

            Import_Batch__c dataJob = batch.clone(true, true, true, true);
            dataJob.Operation__c = BulkUpdateService.OPERATION_UPDATE;
            Assert.areEqual(
                Label.Core_Import_ErrorRetryNotOpen,
                ImportBatchService.retryRefusal(dataJob),
                'A bulk update is not a file import.'
            );

            Import_Batch__c previewOnly = batch.clone(true, true, true, true);
            previewOnly.Status__c = ImportBatchService.STATUS_DRY_RUN_COMPLETE;
            Assert.areEqual(
                Label.Core_Import_ErrorRetryNotOpen,
                ImportBatchService.retryRefusal(previewOnly),
                'Nor an import that was only previewed.'
            );

            try {
                ImportBatchService.stageRows(batch.Id, fixedRows(), 2);
                Assert.fail('A finished import takes rows only through a retry.');
            } catch (ImportException e) {
                Assert.areEqual(Label.Core_Import_ErrorStagingClosed, e.getMessage());
            }
        }
    }

    @IsTest
    static void aReopenedRetryDiscardsItsRowsAndAFileOverTheCapIsRefused() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committed();
            retryStaged(batch.Id);

            Test.startTest();
            Import_Batch__c reopened = ImportBatchService.openRetry(batch.Id);
            Test.stopTest();

            Assert.areEqual(FILE_ROWS + 1, reopened.Retry_After_Row__c, 'The same boundary.');
            Assert.areEqual(FILE_ROWS, reopened.Row_Count__c, 'The unfinished rows are gone.');
            Assert.areEqual(
                FILE_ROWS,
                [SELECT COUNT() FROM Import_Row__c WHERE Import_Batch__c = :batch.Id],
                'Only the file rows remain.'
            );
            try {
                ImportBatchService.stageRows(
                    batch.Id,
                    fixedRows(),
                    ImportBatchService.MAX_RETRY_ROWS - REJECTS + 3
                );
                Assert.fail('A page past the cap is refused.');
            } catch (ImportException e) {
                Assert.isTrue(
                    e.getMessage().contains(ImportBatchService.MAX_RETRY_ROWS.format()),
                    'It names the cap.'
                );
            }
        }
    }
}
