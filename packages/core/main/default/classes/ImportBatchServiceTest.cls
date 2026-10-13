/**
 * The life of a batch: created, staged in pages, dry run before commit, and finished with
 * counts read back from the rows rather than carried in memory.
 */
@IsTest
private class ImportBatchServiceTest {
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    private static Import_Template__c newTemplate() {
        return ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
    }

    @IsTest
    static void createsABatchWithTheOrgChunkSize() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Import_Chunk_Size__c = 50;
            TestDataFactory.saveSettings(settings);
            Import_Template__c template = newTemplate();

            Test.startTest();
            Import_Batch__c batch = ImportBatchService.create(template.Id, null, 'donors.csv');
            Test.stopTest();

            Assert.areEqual(50, batch.Chunk_Size__c, 'The batch takes the chunk size the org set.');
            Assert.areEqual(
                ImportBatchService.STATUS_DRAFT,
                batch.Status__c,
                'It starts as a draft.'
            );
            Assert.isTrue(
                batch.Is_Dry_Run__c,
                'And as a dry run, because nothing has been committed.'
            );
        }
    }

    @IsTest
    static void fallsBackToTheDefaultChunkSizeWhenTheSettingIsNonsense() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Import_Chunk_Size__c = 0;
            TestDataFactory.saveSettings(settings);
            Test.startTest();
            Integer size = ImportBatchService.chunkSize();
            Test.stopTest();
            Assert.areEqual(
                ImportBatchService.DEFAULT_CHUNK_SIZE,
                size,
                'A chunk of zero rows would never finish, so the shipped default is used.'
            );
        }
    }

    @IsTest
    static void stagesRowsInPagesAndKeepsFileOrder() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());

            Test.startTest();
            Integer afterFirst = ImportBatchService.stageRows(
                batch.Id,
                new List<Map<String, Object>>{
                    new Map<String, Object>{ 'Email' => 'one@example.org', 'Last Name' => 'One' }
                },
                2
            );
            Integer afterSecond = ImportBatchService.stageRows(
                batch.Id,
                new List<Map<String, Object>>{
                    new Map<String, Object>{ 'Email' => 'two@example.org', 'Last Name' => 'Two' }
                },
                3
            );
            Test.stopTest();

            Assert.areEqual(1, afterFirst, 'The first page staged one row.');
            Assert.areEqual(2, afterSecond, 'The count accumulates across pages.');
            List<Import_Row__c> rows = ImportTestDataFactory.reload(batch.Id);
            Assert.areEqual(2, rows[0].Row_Number__c, 'The first data row is file row two.');
            Assert.areEqual(3, rows[1].Row_Number__c, 'And the second is file row three.');
        }
    }

    /** Rows cannot join a batch that has run: it would flip back to Parsing. */
    @IsTest
    static void refusesToStageIntoABatchThatHasRun() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
            batch.Status__c = ImportBatchService.STATUS_COMPLETE;
            update batch;

            Test.startTest();
            String refused;
            try {
                ImportBatchService.stageRows(
                    batch.Id,
                    new List<Map<String, Object>>{
                        new Map<String, Object>{ 'Email' => 'a@b.org' }
                    },
                    2
                );
            } catch (ImportException e) {
                refused = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(Label.Core_Import_ErrorStagingClosed, refused, 'Refused, and why.');
            Import_Batch__c after = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(ImportBatchService.STATUS_COMPLETE, after.Status__c, 'Unchanged.');
            Assert.areEqual(0, ImportTestDataFactory.reload(batch.Id).size(), 'Nothing staged.');
        }
    }

    /** A row too long to hold is refused by its number, not cut into unreadable text. */
    @IsTest
    static void refusesARowTooLongToHold() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
            List<Map<String, Object>> page = new List<Map<String, Object>>{
                new Map<String, Object>{ 'Email' => 'a@b.org' },
                new Map<String, Object>{ 'Notes' => 'x'.repeat(ImportBatchService.MAX_ROW_LENGTH) }
            };

            Test.startTest();
            String refused;
            try {
                ImportBatchService.stageRows(batch.Id, page, 2);
            } catch (ImportException e) {
                refused = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                String.format(Label.Core_Import_ErrorRowTooLong, new List<String>{ '3' }),
                refused,
                'The second row of the page is file row three.'
            );
            Assert.areEqual(
                0,
                ImportTestDataFactory.reload(batch.Id).size(),
                'No row of the page was staged.'
            );
        }
    }

    @IsTest
    static void stagingNothingChangesNothing() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
            Test.startTest();
            Integer total = ImportBatchService.stageRows(batch.Id, null, 2);
            Test.stopTest();
            Assert.areEqual(0, total, 'An empty page is not an error.');
        }
    }

    @IsTest
    static void refusesToStartWithNoRows() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
            Test.startTest();
            try {
                ImportBatchService.startDryRun(batch.Id);
                Assert.fail('A file with no rows cannot be dry run.');
            } catch (ImportException e) {
                Assert.areEqual(Label.Core_Import_ErrorNoRows, e.getMessage(), 'Said plainly.');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void refusesADryRunOnceACommitHasStarted() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = newTemplate();
            List<String> statuses = new List<String>{
                ImportBatchService.STATUS_COMPLETE,
                ImportBatchService.STATUS_FAILED,
                ImportBatchService.STATUS_UNDOING,
                ImportBatchService.STATUS_UNDONE,
                ImportBatchService.STATUS_UNDO_FAILED
            };
            List<Import_Batch__c> batches = new List<Import_Batch__c>();
            for (String status : statuses) {
                Import_Batch__c batch = ImportTestDataFactory.batch(template);
                ImportTestDataFactory.rows(
                    batch,
                    new List<Map<String, String>>{
                        ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
                    }
                );
                batch.Status__c = status;
                batch.Is_Dry_Run__c = false;
                batch.Committed_By__c = UserInfo.getUserId();
                batch.Completed_At__c = Datetime.now();
                batch.Undo_Deadline__c = Datetime.now().addDays(30);
                batches.add(batch);
            }
            update batches;

            Test.startTest();
            for (Import_Batch__c batch : batches) {
                try {
                    ImportBatchService.startDryRun(batch.Id);
                    Assert.fail(
                        'R-IB1: no dry run over a batch in status ' + batch.Status__c + '.'
                    );
                } catch (ImportException e) {
                    Assert.areEqual(
                        Label.Core_Import_ErrorDryRunAfterCommit,
                        e.getMessage(),
                        'Said plainly, for ' + batch.Status__c + '.'
                    );
                }
            }
            Test.stopTest();
            Import_Batch__c after = [
                SELECT Is_Dry_Run__c, Completed_At__c, Undo_Deadline__c
                FROM Import_Batch__c
                WHERE Id = :batches[0].Id
            ];
            Assert.isFalse(after.Is_Dry_Run__c, 'The committed batch is still undoable.');
            Assert.isNotNull(after.Completed_At__c, 'And keeps its completion time.');
        }
    }

    @IsTest
    static void refusesToCommitBeforeADryRun() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = newTemplate();
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
                }
            );

            Test.startTest();
            try {
                ImportBatchService.startCommit(batch.Id);
                Assert.fail('R-IB1: a commit needs a completed dry run first.');
            } catch (ImportException e) {
                Assert.areEqual(
                    Label.Core_Import_ErrorDryRunFirst,
                    e.getMessage(),
                    'And says so in the words the admin guide uses.'
                );
            }
            Test.stopTest();
        }
    }

    /**
     * The commit runs under the template its dry run started with (R-IB1): a column set to
     * Do not load and a rule changed after the preview change nothing in the commit, until the
     * next preview. Two hundred rows, a full default chunk.
     */
    @IsTest
    static void aCommitRunsUnderTheTemplateItsDryRunRecorded() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = newTemplate();
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 200; i++) {
                values.add(
                    ImportTestDataFactory.donorRow('Ana' + i, 'Ramirez', 'ana' + i + '@example.org', null)
                );
            }
            ImportTestDataFactory.rows(batch, values);

            Test.startTest();
            ImportBatchService.startDryRun(batch.Id);
            Test.stopTest();

            String snapshot = ImportBatchSelector.selectTemplateSnapshot(batch.Id);
            Assert.isTrue(
                snapshot.contains('Contact1.MailingCity'),
                'The dry run recorded the template it ran with.'
            );
            // Edited after the preview: City no longer loaded, and a different rule.
            ImportMapping edited = new ImportMapping();
            edited.columns.add(new ImportMapping.Column('First Name', 'Contact1.FirstName'));
            edited.columns.add(new ImportMapping.Column('Last Name', 'Contact1.LastName'));
            edited.columns.add(new ImportMapping.Column('Email', 'Contact1.Email'));
            template.Column_Mapping_JSON__c = edited.serialize();
            template.Matching_Rule__c = ImportTemplateService.normalizedRule(
                ImportTemplateService.RULE_NAME_POSTAL
            );
            update template;

            Import_Template__c ran = ImportBatchService.templateFor(
                ImportBatchSelector.selectById(batch.Id)
            );
            Assert.isTrue(
                ran.Column_Mapping_JSON__c.contains('Contact1.MailingCity'),
                'The commit reads the recorded mapping, not the edited one.'
            );
            Assert.areEqual(
                ImportTemplateService.normalizedRule(ImportTemplateService.RULE_EMAIL),
                ran.Matching_Rule__c,
                'And the recorded rule.'
            );
            ImportProcessorBatch committing = new ImportProcessorBatch(batch.Id, false);
            committing.execute(null, ImportTestDataFactory.reload(batch.Id));

            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Contact WHERE MailingCity = 'Portland'],
                'Every person got the city the preview showed.'
            );
        }
    }

    /** A batch previewed before the copy was kept runs under the template as it stands. */
    @IsTest
    static void aBatchWithNoRecordedTemplateRunsUnderTheTemplate() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = newTemplate();
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            Test.startTest();
            Import_Template__c ran = ImportBatchService.templateFor(batch);
            Test.stopTest();
            Assert.areEqual(template.Id, ran.Id, 'The template itself.');
            Assert.areEqual(template.Column_Mapping_JSON__c, ran.Column_Mapping_JSON__c);
        }
    }

    @IsTest
    static void refusesAMappingThatIdentifiesNobody() {
        System.runAs(TestUsers.admin()) {
            ImportMapping useless = new ImportMapping();
            useless.columns.add(new ImportMapping.Column('City', 'Contact1.MailingCity'));
            Import_Template__c template = ImportTestDataFactory.template(
                useless.serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{ new Map<String, String>{ 'City' => 'Portland' } }
            );

            Test.startTest();
            try {
                ImportBatchService.startDryRun(batch.Id);
                Assert.fail('A mapping that identifies nobody is refused before the run.');
            } catch (ImportException e) {
                Assert.areEqual(
                    Label.Core_Import_ErrorMappingIdentifiesNobody,
                    e.getMessage(),
                    'With the message the admin guide quotes.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void startingAPassWritesNoRowsAndThePassClearsWhatTheLastOneLeft() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 50; i++) {
                values.add(
                    ImportTestDataFactory.donorRow(
                        'Ana' + i,
                        'Ramirez',
                        'ana' + i + '@example.org',
                        null
                    )
                );
            }
            List<Import_Row__c> rows = ImportTestDataFactory.rows(batch, values);
            Contact stale = new Contact(LastName = 'Stale');
            insert stale;
            for (Import_Row__c row : rows) {
                row.Status__c = ImportRowProcessor.STATUS_REJECTED;
                row.Error_Message__c = 'Something went wrong';
                row.Contact_1__c = stale.Id;
                row.Gift_Id__c = 'a stale gift';
                // In no permission set, so written and read in system mode (ADR-0021).
                row.put('Person_1_Key__c', '0123456789abcdef');
            }
            Database.update(rows, AccessLevel.SYSTEM_MODE);

            Test.startTest();
            Integer before = Limits.getDmlRows();
            ImportBatchService.startDryRun(batch.Id);
            Integer written = Limits.getDmlRows() - before;
            Test.stopTest();

            // A reset of every staged row here fails past 10,000 rows (R-IB13).
            Assert.isTrue(written < 5, 'Starting writes the batch, not its 50 rows: ' + written);
            for (
                Import_Row__c after : (List<Import_Row__c>) Database.queryWithBinds(
                    'SELECT Status__c, Error_Message__c, Contact_1__c, Gift_Id__c, Person_1_Key__c' +
                    ' FROM Import_Row__c WHERE Import_Batch__c = :batchId',
                    new Map<String, Object>{ 'batchId' => batch.Id },
                    AccessLevel.SYSTEM_MODE
                )
            ) {
                Assert.areEqual(
                    ImportRowProcessor.STATUS_CREATED,
                    after.Status__c,
                    'Worked out again.'
                );
                Assert.isNull(after.Error_Message__c, 'The old reason is cleared.');
                Assert.areNotEqual(stale.Id, after.Contact_1__c, 'The person is resolved again.');
                Assert.isNull(after.Gift_Id__c, 'A stale gift is never reported.');
                Assert.areNotEqual(
                    '0123456789abcdef',
                    after.get('Person_1_Key__c'),
                    'Nor a stale key.'
                );
            }
            Assert.areEqual(
                1,
                ImportBatchSelector.selectById(batch.Id).Pass_Number__c,
                'The first pass.'
            );
        }
    }

    @IsTest
    static void aSecondStartWhileARunIsInProgressIsRefused() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
                }
            );

            Test.startTest();
            Id jobId = ImportBatchService.startDryRun(batch.Id);
            Assert.areEqual(
                jobId,
                ImportBatchSelector.selectById(batch.Id).Job_Id__c,
                'The job is recorded with the pass.'
            );
            ImportBatchService.jobRunningForTest = true;
            try {
                ImportBatchService.startDryRun(batch.Id);
                Assert.fail('R-IB13: one pass of a batch at a time.');
            } catch (ImportException e) {
                Assert.areEqual(
                    Label.Core_Import_ErrorRunInProgress,
                    e.getMessage(),
                    'Said plainly.'
                );
            }
            ImportBatchService.jobRunningForTest = null;
            Test.stopTest();
        }
    }

    @IsTest
    static void aRunWhoseJobWasAbortedCanStartAgain() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
                }
            );
            // Left in Dry run by a job the platform aborted: no job is running for it.
            update new Import_Batch__c(
                Id = batch.Id,
                Status__c = ImportBatchService.STATUS_DRY_RUN
            );
            ImportBatchService.jobRunningForTest = false;
            Import_Batch__c stuck = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(
                ImportBatchService.STATUS_FAILED,
                ImportUndoService.effectiveStatus(stuck),
                'It reads as failed, not as running for ever.'
            );

            Test.startTest();
            ImportBatchService.startDryRun(batch.Id);
            Test.stopTest();

            Assert.areEqual(
                ImportBatchService.STATUS_DRY_RUN_COMPLETE,
                ImportBatchSelector.selectById(batch.Id).Status__c,
                'The dry run ran again.'
            );
        }
    }

    @IsTest
    static void anAbortedCommitReadsFailedAndCanBeUndone() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
                }
            );
            update new Import_Batch__c(
                Id = batch.Id,
                Status__c = ImportBatchService.STATUS_DRY_RUN_COMPLETE
            );

            Test.startTest();
            ImportBatchService.startCommit(batch.Id);
            // The platform aborts the job before its finish: the batch is still Committing.
            ImportBatchService.jobRunningForTest = false;
            Import_Batch__c stuck = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(ImportBatchService.STATUS_COMMITTING, stuck.Status__c, 'As left.');
            Assert.areEqual(
                ImportBatchService.STATUS_FAILED,
                ImportUndoService.effectiveStatus(stuck),
                'It reads as failed.'
            );
            Assert.isNotNull(stuck.Committed_By__c, 'Stamped when the commit started.');
            Assert.isNull(ImportUndoService.refusal(stuck), 'So what it wrote can be undone.');
            Test.stopTest();
        }
    }

    @IsTest
    static void controlTotalsAreCreatedWithTheBatchAndANegativeCountIsRefused() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = newTemplate();

            Test.startTest();
            Import_Batch__c batch = ImportBatchService.create(
                template.Id,
                null,
                'gifts.csv',
                3,
                250.5
            );
            try {
                ImportBatchService.create(template.Id, null, 'gifts.csv', -1, null);
                Assert.fail('A negative number of rows makes no sense.');
            } catch (ImportException e) {
                Assert.areEqual(
                    Label.Core_Import_ErrorControlCountNegative,
                    e.getMessage(),
                    'And is refused in the words the admin guide uses.'
                );
            }
            Test.stopTest();

            Import_Batch__c saved = ImportBatchSelector.selectById(batch.Id);
            Assert.areEqual(3, saved.Expected_Count__c, 'The expected count is kept.');
            Assert.isTrue(saved.Expected_Amount__c == 250.50, 'And the expected amount.');
        }
    }

    @IsTest
    static void aDryRunThatMatchesTheControlTotalsSaysSoAndMayBeCommitted() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null),
                    ImportTestDataFactory.donorRow('Ben', 'Okafor', 'ben@example.org', null)
                }
            );
            batch.Expected_Count__c = 2;
            batch.Expected_Amount__c = 75;
            update batch;

            Test.startTest();
            Import_Batch__c after = ImportBatchService.finish(batch.Id, true, false, null, 75.00);
            Test.stopTest();

            Assert.isTrue(after.File_Amount__c == 75, 'The amount the run read is kept.');
            Assert.isTrue(ImportBatchService.controlTotalsAgree(after), 'Both totals agree.');
            Assert.isTrue(
                after.Run_Log__c.contains(
                    String.format(Label.Core_Import_LogControlCountAgrees, new List<String>{ '2' })
                ),
                'The run log says the count matched.'
            );
        }
    }

    @IsTest
    static void aDryRunThatDisagreesWithTheControlTotalsCannotBeCommitted() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
                }
            );
            batch.Expected_Count__c = 2;
            batch.Expected_Amount__c = 100;
            update batch;
            Import_Batch__c after = ImportBatchService.finish(batch.Id, true, false, null, 80);

            Test.startTest();
            try {
                ImportBatchService.startCommit(batch.Id);
                Assert.fail(
                    'R-IB10: a commit waits for a dry run that matches the control totals.'
                );
            } catch (ImportException e) {
                Assert.areEqual(
                    Label.Core_Import_ErrorControlTotalsDiffer,
                    e.getMessage(),
                    'And says so.'
                );
            }
            Test.stopTest();

            Assert.isFalse(ImportBatchService.controlTotalsAgree(after), 'Neither total agrees.');
            Assert.isTrue(
                after.Run_Log__c.contains(
                    String.format(
                        Label.Core_Import_LogControlCountDiffers,
                        new List<String>{ '1', '2' }
                    )
                ),
                'The run log gives both counts.'
            );
        }
    }

    @IsTest
    static void anExpectedAmountNothingReadCannotAgree() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
            batch.Expected_Amount__c = 100;
            update batch;

            Test.startTest();
            Import_Batch__c after = ImportBatchService.finish(batch.Id, true, false, null, null);
            Test.stopTest();

            Assert.isFalse(
                ImportBatchService.controlTotalsAgree(after),
                'Without a module that reads gift amounts the amount cannot be checked.'
            );
            Assert.isTrue(
                after.Run_Log__c.contains(Label.Core_Import_LogControlAmountUnread),
                'And the run log says why.'
            );
        }
    }

    @IsTest
    static void finishingADryRunCountsFromTheRowsAndCommitsNothing() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
            List<Import_Row__c> rows = ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null),
                    ImportTestDataFactory.donorRow('Ben', 'Okafor', 'ben@example.org', null)
                }
            );
            rows[0].Status__c = ImportRowProcessor.STATUS_CREATED;
            rows[1].Status__c = ImportRowProcessor.STATUS_REJECTED;
            update rows;

            Test.startTest();
            Import_Batch__c after = ImportBatchService.finish(
                batch.Id,
                true,
                false,
                new List<String>{ 'A line of the run log' }
            );
            Test.stopTest();

            Assert.areEqual(1, after.Rows_Created__c, 'Counted from the rows themselves.');
            Assert.areEqual(1, after.Rows_Rejected__c, 'Including the failures.');
            Assert.areEqual(
                ImportBatchService.STATUS_DRY_RUN_COMPLETE,
                after.Status__c,
                'A dry run ends ready for a commit.'
            );
            Assert.isNull(after.Committed_By__c, 'Nobody committed it.');
            Assert.isNull(after.Undo_Deadline__c, 'And there is nothing to undo.');
        }
    }

    @IsTest
    static void finishingACommitRecordsWhoAndOpensTheUndoWindow() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = newTemplate();
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
                }
            );

            Test.startTest();
            Import_Batch__c after = ImportBatchService.finish(batch.Id, false, false, null);
            Test.stopTest();

            Assert.areEqual(ImportBatchService.STATUS_COMPLETE, after.Status__c, 'It completed.');
            Assert.areEqual(
                UserInfo.getUserId(),
                after.Committed_By__c,
                'The committer is recorded.'
            );
            Assert.isNotNull(after.Undo_Deadline__c, 'And the undo window is open (R-IB6).');
            Assert.isTrue(
                after.Undo_Deadline__c >
                Datetime.now().addDays(ImportBatchService.UNDO_WINDOW_DAYS - 1),
                'With no setting the window is the shipped thirty days.'
            );
            Assert.areEqual(
                Date.today(),
                [SELECT Last_Import_Date__c FROM Import_Template__c WHERE Id = :template.Id]
                .Last_Import_Date__c,
                'The template records that its feed was loaded today.'
            );
        }
    }

    @IsTest
    static void theUndoWindowIsStampedFromTheSettingAtCommit() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Import_Undo_Retention_Days__c = 7;
            TestDataFactory.saveSettings(settings);
            Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());

            Test.startTest();
            Import_Batch__c after = ImportBatchService.finish(batch.Id, false, false, null);
            Test.stopTest();

            Assert.isTrue(
                after.Undo_Deadline__c <= Datetime.now().addDays(7) &&
                    after.Undo_Deadline__c > Datetime.now().addDays(6),
                'The deadline is the commit time plus the days the org set (R-IB7).'
            );
        }
    }

    @IsTest
    static void aNonsenseUndoWindowFallsBackAndALongOneIsHeldAtAYear() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Import_Undo_Retention_Days__c = 0;
            TestDataFactory.saveSettings(settings);
            Assert.areEqual(
                ImportBatchService.UNDO_WINDOW_DAYS,
                ImportBatchService.undoWindowDays(),
                'Zero days would make every import permanent at once, so the default is used.'
            );
            settings.Import_Undo_Retention_Days__c = 900;
            TestDataFactory.saveSettings(settings);
            Assert.areEqual(
                365,
                ImportBatchService.undoWindowDays(),
                'Over a year is held at a year.'
            );
        }
    }

    @IsTest
    static void aFailedRunSaysSoRatherThanReportingSuccess() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
                }
            );
            Test.startTest();
            Import_Batch__c after = ImportBatchService.finish(
                batch.Id,
                false,
                true,
                new List<String>{ 'Chunk 1 failed' }
            );
            Test.stopTest();
            Assert.areEqual(ImportBatchService.STATUS_FAILED, after.Status__c, 'Marked as failed.');
            Assert.isTrue(
                after.Run_Log__c.contains('Chunk 1 failed'),
                'With the reason in the log.'
            );
            Assert.isNotNull(
                after.Undo_Deadline__c,
                'The chunks that ran did write, so a failed commit can be undone too (R-IB7).'
            );
        }
    }

    @IsTest
    static void refusesToActOnABatchThatIsGone() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = ImportTestDataFactory.batch(newTemplate());
            Id batchId = batch.Id;
            delete batch;
            Test.startTest();
            try {
                ImportBatchService.startDryRun(batchId);
                Assert.fail('A deleted batch cannot be run.');
            } catch (ImportException e) {
                Assert.areEqual(Label.Core_Import_ErrorBatchGone, e.getMessage(), 'Said plainly.');
            }
            Test.stopTest();
        }
    }
}
