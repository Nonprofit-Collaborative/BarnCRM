/**
 * The nightly Import row cleanup (R-IR5, D-40): the rows of an import that finished longer ago
 * than the org keeps them are removed, the import keeps its counts, 0 keeps every row, and a
 * batch whose rows are gone is refused rather than run over nothing.
 */
@IsTest
private class ImportRowPurgeTest {
    /** A batch with a full chunk of rows, its last pass completed the given days ago. */
    private static Import_Batch__c finishedBatch(Import_Template__c template, Integer daysAgo) {
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < 200; i++) {
            values.add(
                ImportTestDataFactory.donorRow('Ana', 'Row' + i, 'row' + i + '@example.org', null)
            );
        }
        ImportTestDataFactory.rows(batch, values);
        update new Import_Batch__c(
            Id = batch.Id,
            Status__c = daysAgo == null
                ? ImportBatchService.STATUS_DRAFT
                : ImportBatchService.STATUS_COMPLETE,
            Is_Dry_Run__c = daysAgo == null,
            Rows_Created__c = 200,
            Completed_At__c = daysAgo == null ? null : Datetime.now().addDays(-daysAgo)
        );
        return batch;
    }

    private static Integer rowsOf(Id batchId) {
        return [SELECT COUNT() FROM Import_Row__c WHERE Import_Batch__c = :batchId];
    }

    private static void keepRowsFor(Integer days) {
        BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
        settings.Import_Row_Retention_Days__c = days;
        TestDataFactory.saveSettings(settings);
    }

    private static void runCleanup() {
        Database.executeBatch(new ImportRowPurgeBatch(), ImportRowPurgeBatch.CHUNK_SIZE);
    }

    @IsTest
    static void removesTheRowsOfOldImportsOnly() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c old = finishedBatch(template, 100);
            Import_Batch__c recent = finishedBatch(template, 10);
            Import_Batch__c draft = finishedBatch(template, null);

            Test.startTest();
            runCleanup();
            Test.stopTest();

            Assert.areEqual(0, rowsOf(old.Id), 'Rows of an import 100 days old are removed.');
            Assert.areEqual(200, rowsOf(recent.Id), 'Rows of a recent import are kept.');
            Assert.areEqual(200, rowsOf(draft.Id), 'Rows of an import never run are kept.');
            Import_Batch__c kept = [
                SELECT Rows_Created__c, Status__c
                FROM Import_Batch__c
                WHERE Id = :old.Id
            ];
            Assert.areEqual(200, kept.Rows_Created__c, 'The import keeps its counts.');
            Assert.areEqual(ImportBatchService.STATUS_COMPLETE, kept.Status__c);
        }
    }

    @IsTest
    static void theOrgChoosesHowLongAndZeroKeepsEveryRow() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c tenDays = finishedBatch(template, 10);
            Import_Batch__c yearsAgo = finishedBatch(template, 4000);
            keepRowsFor(0);
            ImportRowPurgeBatch keepAll = new ImportRowPurgeBatch();
            keepRowsFor(5);

            Test.startTest();
            Database.executeBatch(keepAll, ImportRowPurgeBatch.CHUNK_SIZE);
            Test.stopTest();

            Assert.areEqual(200, rowsOf(yearsAgo.Id), '0 keeps every row, however old.');
            Assert.areEqual(200, rowsOf(tenDays.Id));
            Assert.areEqual(5, ImportBatchService.rowRetentionDays(), 'The org\'s days are read.');
        }
    }

    @IsTest
    static void aShorterRetentionRemovesMore() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c tenDays = finishedBatch(template, 10);
            keepRowsFor(5);

            Test.startTest();
            runCleanup();
            Test.stopTest();

            Assert.areEqual(
                0,
                rowsOf(tenDays.Id),
                'Kept for five days, a ten day old import goes.'
            );
        }
    }

    @IsTest
    static void aNonsenseRetentionFallsBackAndALongOneIsHeld() {
        System.runAs(TestUsers.admin()) {
            keepRowsFor(-3);
            Integer negative = ImportBatchService.rowRetentionDays();
            keepRowsFor(9999);
            Integer huge = ImportBatchService.rowRetentionDays();
            keepRowsFor(null);
            Integer empty = ImportBatchService.rowRetentionDays();

            Assert.areEqual(
                ImportBatchService.ROW_RETENTION_DAYS,
                negative,
                'Negative reads as 90.'
            );
            Assert.areEqual(3650, huge, 'Over ten years is held at ten years.');
            Assert.areEqual(ImportBatchService.ROW_RETENTION_DAYS, empty, 'Empty reads as 90.');
        }
    }

    @IsTest
    static void aBatchWhoseRowsWereRemovedCannotRunAgain() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c batch = finishedBatch(template, 100);
            update new Import_Batch__c(
                Id = batch.Id,
                Status__c = ImportBatchService.STATUS_DRY_RUN_COMPLETE,
                Is_Dry_Run__c = true
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
                if (job instanceof NightlyJobs.ImportRowPurgeJob) {
                    listed = job.isScheduled();
                }
            }
            Assert.isTrue(listed, 'Health Check sees it among the nightly jobs, scheduled.');
        }
    }
}
