/**
 * A trial of a file's first rows, then the rest into the same import (R-IB16): what each part
 * commits, what it counts, and that one undo covers both.
 *
 * A test may start one batch job, so each test starts one part through the service and drives
 * the other through the processor itself, the way the platform would.
 */
@IsTest(testFor='ApexClass:ImportBatchService, ApexClass:ImportProcessorBatch')
private class ImportTrialRunTest {
    private static final Integer FILE_ROWS = 200;
    private static final Integer TRIAL = 25;

    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    /** A 200-row file of new people, previewed. */
    private static Import_Batch__c previewed() {
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
                    'Surname' + i,
                    'trial' + i + '@example.org',
                    null
                )
            );
        }
        ImportTestDataFactory.rows(batch, values);
        drive(batch.Id, true, null, null);
        return ImportBatchSelector.selectById(batch.Id);
    }

    /** One pass, run as the platform runs it, with what starting it stamps on the batch. */
    private static void drive(Id batchId, Boolean dryRun, Integer trialRows, Decimal afterRow) {
        ImportBatchService.beginPass(batchId);
        Import_Batch__c stamp = new Import_Batch__c(
            Id = batchId,
            Is_Dry_Run__c = dryRun,
            Status__c = dryRun
                ? ImportBatchService.STATUS_DRY_RUN
                : ImportBatchService.STATUS_COMMITTING,
            Trial_Rows__c = trialRows
        );
        if (!dryRun) {
            stamp.Committed_By__c = UserInfo.getUserId();
        }
        if (afterRow == null) {
            // The rest of a trial keeps the trial's start, as the service does.
            stamp.Started_At__c = Datetime.now();
        }
        update stamp;
        ImportProcessorBatch job = new ImportProcessorBatch(batchId, dryRun, trialRows, afterRow);
        List<Import_Row__c> rows = new List<Import_Row__c>();
        Database.QueryLocatorIterator found = job.start(null).iterator();
        while (found.hasNext()) {
            rows.add((Import_Row__c) found.next());
        }
        job.execute(null, rows);
        job.finish(null);
    }

    @IsTest
    static void aTrialCommitsOnlyTheFirstRowsAndCountsOnlyThem() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = previewed();
            Assert.areEqual(
                ImportBatchService.STATUS_DRY_RUN_COMPLETE,
                batch.Status__c,
                'Previewed first.'
            );

            Test.startTest();
            ImportBatchService.startTrial(batch.Id, TRIAL);
            Test.stopTest();

            Import_Batch__c after = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(
                ImportBatchService.STATUS_TRIAL_COMPLETE,
                after.Status__c,
                'The trial ends waiting for the rest.'
            );
            Assert.areEqual(TRIAL, after.Trial_Rows__c, 'It records its size.');
            Assert.areEqual(TRIAL, after.Rows_Created__c, 'It counts only the rows it ran.');
            Assert.areEqual(0, after.Rows_Rejected__c, 'None rejected.');
            Assert.areEqual(TRIAL, [SELECT COUNT() FROM Contact], 'Only those people exist.');
            Assert.areEqual(
                TRIAL,
                [
                    SELECT COUNT()
                    FROM Contact
                    WHERE Email LIKE 'trial%' AND LastName IN :surnames(0, TRIAL)
                ],
                'And they are the first rows of the file.'
            );
            Assert.isNull(ImportUndoService.refusal(after), 'A trial can be undone on its own.');
            Assert.isTrue(after.Is_Dry_Run__c == false, 'It is a commit, not a preview.');
        }
    }

    @IsTest
    static void theRestCommitsEveryOtherRowIntoTheSameImport() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = previewed();
            drive(batch.Id, false, TRIAL, null);
            Import_Batch__c tried = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(ImportBatchService.STATUS_TRIAL_COMPLETE, tried.Status__c, 'Tried.');
            Datetime trialStart = tried.Started_At__c;

            Test.startTest();
            ImportBatchService.startCommit(batch.Id);
            Test.stopTest();

            Import_Batch__c after = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(ImportBatchService.STATUS_COMPLETE, after.Status__c, 'Complete.');
            Assert.areEqual(
                FILE_ROWS,
                after.Rows_Created__c,
                'The counts now cover the whole file, trial and rest.'
            );
            Assert.areEqual(FILE_ROWS, [SELECT COUNT() FROM Contact], 'Nobody twice.');
            Assert.areEqual(
                FILE_ROWS,
                [SELECT COUNT() FROM Contact WHERE Created_By_Import_Batch__c = :batch.Id],
                'Every person carries the one import, so one undo removes them all.'
            );
            Assert.areEqual(trialStart, after.Started_At__c, 'The import starts with its trial.');
            Assert.isTrue(
                after.Run_Log__c.contains(Label.Core_Import_LogCommitHeader),
                'The log keeps both parts.'
            );
            Assert.isNull(ImportUndoService.refusal(after), 'And can be undone as one.');
        }
    }

    @IsTest
    static void aPreviewAfterATrialIsRefused() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = previewed();
            drive(batch.Id, false, TRIAL, null);
            ImportBatchService.jobRunningForTest = false;
            try {
                ImportBatchService.startDryRun(batch.Id);
                Assert.fail('A preview over committed rows must be refused.');
            } catch (ImportException e) {
                Assert.areEqual(Label.Core_Import_ErrorDryRunAfterCommit, e.getMessage(), 'Why.');
            }
        }
    }

    @IsTest
    static void aTrialNeedsAFinishedPreviewAndTheRestNeedsTheSamePerson() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c draft = ImportTestDataFactory.batch(template);
            try {
                ImportBatchService.startTrial(draft.Id, TRIAL);
                Assert.fail('No trial before a preview.');
            } catch (ImportException e) {
                Assert.areEqual(Label.Core_Import_ErrorDryRunFirst, e.getMessage(), 'Why.');
            }

            Import_Batch__c batch = previewed();
            drive(batch.Id, false, TRIAL, null);
            User other = TestDataFactory.createUser('Other', new List<String>{ 'BarnCRM_Admin' });
            update new Import_Batch__c(Id = batch.Id, Committed_By__c = other.Id);
            try {
                ImportBatchService.startCommit(batch.Id);
                Assert.fail('The rest is refused to anyone but the trial runner.');
            } catch (ImportException e) {
                Assert.areEqual(Label.Core_Import_ErrorRemainingOtherUser, e.getMessage(), 'Why.');
            }
        }
    }

    @IsTest
    static void aTrialSizeComesFromTheSettingAndIsHeldInRange() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                ImportBatchService.DEFAULT_TRIAL_ROWS,
                ImportBatchService.trialRows(),
                'Twenty-five unless the org says otherwise.'
            );
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Import_Trial_Rows__c = 5000;
            TestDataFactory.saveSettings(settings);
            Assert.areEqual(
                ImportBatchService.MAX_TRIAL_ROWS,
                ImportBatchService.trialRows(),
                'Held at the ceiling.'
            );
        }
    }

    @IsTest
    static void aTrialAsLargeAsTheFileIsTheWholeImport() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = previewed();

            Test.startTest();
            ImportBatchService.startTrial(batch.Id, ImportBatchService.MAX_TRIAL_ROWS);
            Test.stopTest();

            Import_Batch__c after = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(ImportBatchService.STATUS_COMPLETE, after.Status__c, 'Complete.');
            Assert.isNull(after.Trial_Rows__c, 'Not a trial.');
            Assert.areEqual(FILE_ROWS, after.Rows_Created__c, 'Every row.');
        }
    }

    private static List<String> surnames(Integer fromIndex, Integer count) {
        List<String> names = new List<String>();
        for (Integer i = fromIndex; i < fromIndex + count; i++) {
            names.add('Surname' + i);
        }
        return names;
    }
}
