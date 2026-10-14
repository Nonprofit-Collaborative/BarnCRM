/**
 * Import row rules (canonical model R-IT18, R-IT19; ADR-NEXT `NEXT-import-row-rules.md`): Skip
 * rows and One row per decide as the file is staged, a skipped row is never processed and is
 * counted apart from rejected rows, and an empty cell clears a field only where its column says
 * so, counted in the dry run, journaled by the commit and put back by undo.
 *
 * Duplicate dismissals stand for an org's own object, as in `ImportObjectLoaderTest`. Every test
 * runs as a minimal-profile user holding only BarnCRM Admin.
 */
@IsTest
private class ImportRowRulesTest {
    static {
        DataProtectedFields.ordinaryForTest.add('duplicate_dismissal__c');
    }

    private static final Integer MANY = 200;

    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    private static User admin() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static ImportMapping.SkipRule rule(String column, String test, String text) {
        ImportMapping.SkipRule result = new ImportMapping.SkipRule();
        result.column = column;
        result.test = test;
        result.text = text;
        return result;
    }

    /** A dismissal mapping with these row rules, and a batch for it with no rows yet. */
    private static Import_Batch__c batchWith(ImportMapping mapping, String operation) {
        mapping.columns.add(new ImportMapping.Column('Pair Key', 'Record.Pair_Key__c'));
        Import_Template__c template = ImportTestDataFactory.template(mapping.serialize(), null);
        template.Target_Object__c = 'Duplicate_Dismissal__c';
        template.Load_Operation__c = operation;
        template.Load_Match_Field__c = 'Pair_Key__c';
        update template;
        return ImportTestDataFactory.batch(template);
    }

    private static List<Map<String, Object>> page(Integer first, Integer count) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Integer i = first; i < first + count; i++) {
            // Every tenth row is cancelled; email repeats every 50 rows, across pages.
            result.add(
                new Map<String, Object>{
                    'Pair Key' => 'K' + i,
                    'Status' => Math.mod(i, 10) == 0 ? ' CANCELLED ' : 'Paid',
                    'Email' => 'person' +
                    Math.mod(i, 50) +
                    '@example.org'
                }
            );
        }
        return result;
    }

    @IsTest
    static void twoHundredRowsAreSkippedByRuleAndByKeyAsTheyAreStaged() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                ImportMapping mapping = new ImportMapping();
                mapping.skipRows = new List<ImportMapping.SkipRule>{
                    rule('Status', 'equals', 'cancelled')
                };
                mapping.uniqueBy = new List<String>{ 'Email' };
                Import_Batch__c batch = batchWith(mapping, ImportObjectSchema.OPERATION_UPSERT);

                Test.startTest();
                // Two pages, so a key an earlier page kept is found by its digest.
                ImportBatchService.stageRows(batch.Id, page(0, MANY / 2), 2);
                ImportBatchService.stageRows(batch.Id, page(MANY / 2, MANY / 2), 2 + MANY / 2);
                Test.stopTest();

                Map<String, Integer> counts = ImportBatchSelector.countRowsByStatus(batch.Id);
                // 50 emails; the 5 whose rows are all cancelled (0, 10, ... 40) never load, so 45
                // rows load: the first of each other email.
                Integer pending = counts.get(ImportRowProcessor.STATUS_PENDING);
                Assert.areEqual(45, pending, 'One row per email loads.');
                Assert.areEqual(MANY - 45, counts.get(ImportRowProcessor.STATUS_SKIPPED));
                Import_Row__c cancelled = [
                    SELECT Status__c, Error_Message__c, Row_Key__c
                    FROM Import_Row__c
                    WHERE Import_Batch__c = :batch.Id AND Row_Number__c = 2
                ];
                Assert.isTrue(cancelled.Error_Message__c.contains('Status'), 'Says which rule.');
                Assert.isNull(cancelled.Row_Key__c, 'A skipped row keeps no key.');
                Import_Row__c repeat = [
                    SELECT Error_Message__c
                    FROM Import_Row__c
                    WHERE Import_Batch__c = :batch.Id AND Row_Number__c = 153
                ];
                Assert.isTrue(repeat.Error_Message__c.contains('Email'), repeat.Error_Message__c);

                Integer read = 0;
                Database.QueryLocatorIterator rows = new ImportProcessorBatch(batch.Id, true)
                    .start(null)
                    .iterator();
                while (rows.hasNext()) {
                    Import_Row__c row = (Import_Row__c) rows.next();
                    Assert.areNotEqual(ImportRowProcessor.STATUS_SKIPPED, row.Status__c);
                    read++;
                }
                Assert.areEqual(45, read, 'No pass reads a skipped row.');
                Import_Batch__c finished = ImportBatchService.finish(
                    batch.Id,
                    true,
                    false,
                    new List<String>(),
                    null,
                    null
                );
                Assert.areEqual(0, finished.Rows_Rejected__c, 'Skipped is not rejected.');
                Assert.isTrue(
                    finished.Run_Log__c.contains(String.valueOf(MANY - 45)),
                    finished.Run_Log__c
                );
            }
        }
    }

    @IsTest
    static void incompleteRowRulesAreNamedAndSkipNothing() {
        System.runAs(TestUsers.admin()) {
            ImportMapping mapping = new ImportMapping();
            mapping.skipRows = new List<ImportMapping.SkipRule>{ rule('Status', 'equals', ' ') };
            mapping.uniqueBy = new List<String>{ '' };
            Assert.areEqual(2, ImportRowFilter.problems(mapping).size());
            mapping.skipRows = new List<ImportMapping.SkipRule>{ rule('Status', 'blank', null) };
            mapping.uniqueBy = new List<String>{ 'Email', 'Event' };
            Assert.isTrue(ImportRowFilter.problems(mapping).isEmpty());
            for (Integer i = 0; i < 6; i++) {
                mapping.uniqueBy.add('Column ' + i);
            }
            Assert.areEqual(1, ImportRowFilter.problems(mapping).size(), 'At most five.');
        }
    }

    @IsTest
    static void theNextFileStartsFromTheSavedRowRulesAndClearingColumns() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Import_Template__c template = clearingTemplate(true);
                ImportMapping saved = ImportMapping.parse(template.Column_Mapping_JSON__c);
                saved.skipRows = new List<ImportMapping.SkipRule>{ rule('Reason', 'blank', null) };
                saved.uniqueBy = new List<String>{ 'Id' };
                template.Column_Mapping_JSON__c = saved.serialize();
                update template;

                ImportMapping suggested = ImportMapping.parse(
                    ImportController.suggestMapping(template.Id, new List<String>{ 'Id', 'Reason' })
                );

                Assert.areEqual('blank', suggested.skipRows[0].test);
                Assert.areEqual(new List<String>{ 'Id' }, suggested.uniqueBy);
                Assert.isTrue(suggested.clearingAttributes().contains('reason__c'));
            }
        }
    }

    @IsTest
    static void theNextFileStartsFromTheSavedChangesToValues() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = clearingTemplate(false);
            ImportMapping saved = ImportMapping.parse(template.Column_Mapping_JSON__c);
            DataTransform.Step trim = new DataTransform.Step('trim');
            saved.columns[1].transforms = new List<DataTransform.Step>{ trim };
            template.Column_Mapping_JSON__c = saved.serialize();
            update template;

            ImportMapping next = ImportMapping.parse(
                ImportController.suggestMapping(template.Id, new List<String>{ 'Id', 'Reason' })
            );
            Assert.isTrue(
                next.columns[0].transforms == null || next.columns[0].transforms.isEmpty()
            );
            Assert.areEqual(1, next.columns[1].transforms.size());
            Assert.areEqual('trim', next.columns[1].transforms[0].op);

            ImportMapping renamed = ImportMapping.parse(
                ImportController.suggestMapping(template.Id, new List<String>{ 'Id', 'Why' })
            );
            for (ImportMapping.Column column : renamed.columns) {
                Assert.isTrue(
                    column.transforms == null || column.transforms.isEmpty(),
                    'A renamed column starts with no changes.'
                );
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // Empty cells that clear (R-IT19)
    // -------------------------------------------------------------------------------------

    private static Import_Template__c clearingTemplate(Boolean blankClears) {
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Id', 'Record.Id'));
        ImportMapping.Column reason = new ImportMapping.Column('Reason', 'Record.Reason__c');
        reason.blankClears = blankClears;
        mapping.columns.add(reason);
        Import_Template__c template = ImportTestDataFactory.template(mapping.serialize(), null);
        template.Target_Object__c = 'Duplicate_Dismissal__c';
        template.Load_Operation__c = ImportObjectSchema.OPERATION_UPDATE;
        update template;
        return ImportTemplateSelector.selectById(template.Id);
    }

    private static ImportRowProcessor.Outcome load(
        Import_Template__c template,
        Import_Batch__c batch,
        Boolean dryRun
    ) {
        ImportBatchService.beginPass(batch.Id);
        return ImportRowProcessor.process(
            ImportBatchSelector.selectById(batch.Id),
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c, template.Default_Values_JSON__c),
            ImportTestDataFactory.reload(batch.Id),
            dryRun
        );
    }

    private static Import_Batch__c clearingBatch(Import_Template__c template) {
        List<Duplicate_Dismissal__c> stored = new List<Duplicate_Dismissal__c>();
        for (Integer i = 0; i < MANY; i++) {
            stored.add(new Duplicate_Dismissal__c(Pair_Key__c = 'K' + i, Reason__c = 'Old'));
        }
        insert stored;
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Duplicate_Dismissal__c record : stored) {
            values.add(new Map<String, String>{ 'Id' => record.Id, 'Reason' => '' });
        }
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, values);
        return batch;
    }

    private static Integer withReason() {
        return [SELECT COUNT() FROM Duplicate_Dismissal__c WHERE Reason__c = 'Old'];
    }

    @IsTest
    static void emptyCellsLeaveFieldsAloneUnlessTheColumnSaysClear() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Import_Template__c template = clearingTemplate(false);
                Import_Batch__c batch = clearingBatch(template);
                Test.startTest();
                ImportRowProcessor.Outcome outcome = load(template, batch, false);
                Test.stopTest();
                Assert.areEqual(0, outcome.cleared);
                Assert.areEqual(MANY, withReason(), 'By default an empty cell clears nothing.');
            }
        }
    }

    @IsTest
    static void twoHundredEmptyCellsClearAfterADryRunCountsThemAndUndoPutsThemBack() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Import_Template__c template = clearingTemplate(true);
                Import_Batch__c batch = clearingBatch(template);

                ImportRowProcessor.Outcome dry = load(template, batch, true);
                Assert.areEqual(MANY, dry.cleared, 'The dry run counts what it would clear.');
                Assert.areEqual(MANY, withReason(), 'and clears nothing.');

                batch.Is_Dry_Run__c = false;
                batch.Status__c = ImportBatchService.STATUS_COMMITTING;
                batch.Started_At__c = Datetime.now().addMinutes(-1);
                batch.Committed_By__c = UserInfo.getUserId();
                batch.Undo_Deadline__c = Datetime.now().addDays(30);
                update batch;
                ImportRowProcessor.Outcome committed = load(template, batch, false);
                Assert.areEqual(MANY, committed.updated, 'Each record is updated.');
                Assert.areEqual(0, withReason(), 'Every value is cleared.');
                update new Import_Batch__c(
                    Id = batch.Id,
                    Status__c = ImportBatchService.STATUS_COMPLETE,
                    Completed_At__c = Datetime.now()
                );

                Test.startTest();
                Integer total = ImportUndoService.preview(batch.Id).total;
                Datetime undoStartedAt = Datetime.now();
                for (String pass : ImportUndoBatch.passes()) {
                    ImportUndoBatch job = new ImportUndoBatch(
                        batch.Id,
                        total,
                        pass,
                        0,
                        false,
                        undoStartedAt
                    );
                    Database.QueryLocatorIterator records = job.start(null).iterator();
                    while (records.hasNext()) {
                        job.execute(null, new List<SObject>{ records.next() });
                    }
                }
                Test.stopTest();
                Assert.areEqual(MANY, withReason(), 'Undo puts every cleared value back.');
            }
        }
    }
}
