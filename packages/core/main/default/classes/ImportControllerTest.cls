/**
 * The controller: the permission gate on everything that changes anything, and the shapes the
 * two screens are built against.
 */
@IsTest(testFor='ApexClass:ImportController')
private class ImportControllerTest {
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    /**
     * The person a test that saves a file runs as: an administrator created for that test alone.
     *
     * Not the running user, because the running user's private library is shared with every other
     * test class running in parallel, and a save into it fails when another test's transaction
     * rolls back at the same moment. The full explanation is on `ReceiptTestDataFactory.issuer`.
     */
    private static User importer() {
        return TestDataFactory.createUser('Importer', new List<String>{ 'BarnCRM_Admin' });
    }

    private static Import_Template__c permittedTemplate() {
        ImportController.permissionOverride = true;
        return ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
    }

    /** A page's position, so a failed assertion on an org run says what came back. */
    private static String pageText(ImportController.RowPage page) {
        return '(rows ' +
            page.rows.size() +
            ', nextIndex ' +
            page.nextIndex +
            ', total ' +
            page.total +
            ', hasMore ' +
            page.hasMore +
            ')';
    }

    @IsTest
    static void refusesEveryChangeWithoutThePermission() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = false;
            Test.startTest();
            try {
                ImportController.getTemplates();
                Assert.fail('Importing needs the Manage BarnCRM Settings permission.');
            } catch (Exception e) {
                Assert.isTrue(
                    e.getMessage().contains('Manage BarnCRM Settings'),
                    'And says which permission and who to ask: ' + e.getMessage()
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void reportsWhetherTheUserMayImport() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = true;
            Assert.isTrue(ImportController.canImport(), 'Permitted.');
            ImportController.permissionOverride = false;
            Assert.isFalse(ImportController.canImport(), 'Not permitted.');
        }
    }

    @IsTest
    static void listsTemplatesForTheWizard() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = true;
            Test.startTest();
            List<ImportController.TemplateView> templates = ImportController.getTemplates();
            Test.stopTest();
            Assert.isFalse(templates.isEmpty(), 'The shipped mappings are offered on first use.');
            Assert.isNotNull(templates[0].name, 'Each one has a name to show.');
            Assert.isNotNull(
                templates[0].mapping,
                'And its mapping, so the picker can start from it.'
            );
        }
    }

    @IsTest
    static void suggestsAMappingAndPrefersTheTemplateOwnChoices() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = permittedTemplate();

            Test.startTest();
            String document = ImportController.suggestMapping(
                template.Id,
                new List<String>{ 'First Name', 'Email', 'Board seat expiry' }
            );
            Test.stopTest();

            Map<String, String> targets = ImportMapping.parse(document).targetsBySourceKey();
            Assert.areEqual(
                'Contact1.Email',
                targets.get('email'),
                'A known heading is suggested.'
            );
            Assert.isFalse(
                targets.containsKey('board seat expiry'),
                'And one nobody recognizes loads nothing rather than being guessed at.'
            );
        }
    }

    /**
     * Do not load is a choice, and a saved choice wins over the column library: a heading the
     * library recognizes, set to Do not load and saved, is still Do not load when the next
     * file with that heading is uploaded, rather than silently mapped again.
     */
    @IsTest
    static void aSavedDoNotLoadWinsOverARecognizedHeading() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = permittedTemplate();
            ImportMapping mapping = new ImportMapping();
            mapping.columns.add(new ImportMapping.Column('Last Name', 'Contact1.LastName'));
            mapping.columns.add(new ImportMapping.Column('Email', ImportMapping.TARGET_IGNORE));
            ImportController.createBatch(
                template.Id,
                null,
                'donors.csv',
                mapping.serialize(),
                ImportTemplateService.RULE_EMAIL,
                null
            );

            Test.startTest();
            String document = ImportController.suggestMapping(
                template.Id,
                new List<String>{ 'Last Name', 'Email' }
            );
            Test.stopTest();

            Map<String, String> bySource = new Map<String, String>();
            for (ImportMapping.Column column : ImportMapping.parse(document).columns) {
                bySource.put(column.source, column.target);
            }
            Assert.areEqual(
                ImportMapping.TARGET_IGNORE,
                bySource.get('Email'),
                'The column set to Do not load is still Do not load when the mapping is reopened.'
            );
            Assert.areEqual(
                'Contact1.LastName',
                bySource.get('Last Name'),
                'And the columns the template maps keep their targets.'
            );
        }
    }

    @IsTest
    static void createsABatchAndSavesTheMappingWithIt() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = permittedTemplate();
            ImportMapping mapping = ImportMapping.parse(ImportTestDataFactory.donorMapping());
            mapping.columns.add(new ImportMapping.Column('Phone', 'Contact1.Phone'));

            Test.startTest();
            ImportController.BatchView view = ImportController.createBatch(
                template.Id,
                null,
                'donors.csv',
                mapping.serialize(),
                ImportTemplateService.RULE_EMAIL,
                '{"expectedCount": 12, "expectedAmount": 480.25, "savePaymentMatching": true, ' +
                '"paymentMatching": "Never match", "matchDateWindowDays": 10}'
            );
            Test.stopTest();

            Assert.isNotNull(view.id, 'The batch was created.');
            Import_Batch__c saved = [
                SELECT Expected_Count__c, Expected_Amount__c
                FROM Import_Batch__c
                WHERE Id = :view.id
            ];
            Assert.areEqual(12, saved.Expected_Count__c, 'With the control totals typed in.');
            Assert.isTrue(saved.Expected_Amount__c == 480.25, 'Both of them.');
            Import_Template__c matching = [
                SELECT Payment_Matching__c, Match_Date_Window_Days__c
                FROM Import_Template__c
                WHERE Id = :template.Id
            ];
            Assert.areEqual(
                'Never match',
                matching.Payment_Matching__c,
                'Payment matching is kept.'
            );
            Assert.areEqual(10, matching.Match_Date_Window_Days__c, 'With its window.');
            Assert.areEqual(
                'donors.csv',
                view.fileName,
                'With the name the administrator uploaded.'
            );
            Assert.isTrue(
                [SELECT Column_Mapping_JSON__c FROM Import_Template__c WHERE Id = :template.Id]
                    .Column_Mapping_JSON__c.contains('Contact1.Phone'),
                'And the mapping was saved back, so next month needs no work.'
            );
        }
    }

    /**
     * Everything the wizard settles on is saved in one read and one write of the template, so
     * a preview is the template's write and the batch's insert, whatever the wizard sent.
     */
    @IsTest
    static void aPreviewSavesTheTemplateOnce() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = permittedTemplate();
            String optionsJson =
                '{"savePaymentMatching": true, "paymentMatching": "Match only", ' +
                '"matchDateWindowDays": 5, "matching": {"organizationRule": "Name exact", ' +
                '"severalMatches": "Use the most recently changed"}}';

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            Integer dmlBefore = Limits.getDmlStatements();
            ImportController.createBatch(
                template.Id,
                null,
                'donors.csv',
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_NAME_POSTAL,
                optionsJson
            );
            Integer queries = Limits.getQueries() - queriesBefore;
            Integer dml = Limits.getDmlStatements() - dmlBefore;
            Test.stopTest();

            Assert.areEqual(2, dml, 'One template write and the batch insert.');
            Assert.isTrue(queries <= 3, 'One template read here, one in create: ' + queries);
            Import_Template__c stored = ImportTemplateSelector.selectById(template.Id);
            Assert.areEqual(ImportTemplateService.RULE_NAME_POSTAL, stored.Matching_Rule__c);
            Assert.areEqual('Match only', stored.Payment_Matching__c);
            Assert.areEqual(5, stored.Match_Date_Window_Days__c);
            Assert.areEqual(
                ImportTemplateService.SEVERAL_MOST_RECENT,
                stored.Several_Matches__c,
                'Every choice was saved.'
            );
        }
    }

    /** A commit's job is asked about once per batch shown, not once for its status and again. */
    @IsTest
    static void aRunningCommitIsAskedAboutOnce() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = permittedTemplate();
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            update new Import_Batch__c(
                Id = batch.Id,
                Status__c = ImportBatchService.STATUS_COMMITTING,
                Is_Dry_Run__c = false,
                Job_Id__c = '707000000000000',
                Undo_Deadline__c = Datetime.now().addDays(30)
            );

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            ImportController.BatchView view = ImportController.getBatch(batch.Id);
            Integer queries = Limits.getQueries() - queriesBefore;
            Test.stopTest();

            Assert.areEqual(
                ImportBatchService.STATUS_FAILED,
                view.status,
                'A commit with no job running reads as failed.'
            );
            Assert.isTrue(view.canUndo, 'And can be undone.');
            Assert.isTrue(queries <= 2, 'The batch, and its job once: ' + queries);
        }
    }

    @IsTest
    static void stagesRowsFromTheBrowserPage() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = permittedTemplate();
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            String rowsJson = JSON.serialize(
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
                }
            );

            Test.startTest();
            Integer total = ImportController.stageRows(batch.Id, rowsJson, 2);
            Test.stopTest();

            Assert.areEqual(1, total, 'One row staged.');
            Assert.areEqual(
                2,
                ImportTestDataFactory.reload(batch.Id)[0].Row_Number__c,
                'File row two.'
            );
        }
    }

    @IsTest
    static void runsADryRunAndReportsTheBatchBack() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = permittedTemplate();
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null)
                }
            );

            Test.startTest();
            ImportController.BatchView view = ImportController.startDryRun(batch.Id);
            Test.stopTest();

            Assert.isNotNull(view, 'The screen gets the batch back to poll on.');
            Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'A dry run wrote nothing.');
            Assert.areEqual(
                ImportBatchService.STATUS_DRY_RUN_COMPLETE,
                ImportBatchSelector.selectById(batch.Id).Status__c,
                'And it finished, because the batch ran inside the test.'
            );
        }
    }

    @IsTest
    static void returnsRejectedRowsForTheExceptionsFile() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = permittedTemplate();
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            List<Import_Row__c> rows = ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    ImportTestDataFactory.donorRow('Ana', 'Ramirez', 'ana@example.org', null),
                    ImportTestDataFactory.donorRow('Nobody', null, null, null)
                }
            );
            rows[1].Status__c = ImportRowProcessor.STATUS_REJECTED;
            rows[1].Error_Message__c = Label.Core_Import_ErrorLastNameMissing;
            update rows;

            Test.startTest();
            ImportController.RowPage page = ImportController.getRowPage(
                batch.Id,
                ImportRowProcessor.STATUS_REJECTED,
                null,
                0,
                null
            );
            Test.stopTest();

            List<ImportController.RowView> rejected = page.rows;
            Assert.areEqual(1, page.total, 'The cursor holds only the rejected row.');
            Assert.areEqual(1, page.nextIndex, 'The next page starts after the one row.');
            Assert.isFalse(page.hasMore, 'And one page reads it all. ' + pageText(page));
            Assert.areEqual(1, rejected.size(), 'Only the rejected row comes back.');
            Assert.areEqual(3, rejected[0].rowNumber, 'Named by its row number in the file.');
            Assert.areEqual(
                Label.Core_Import_ErrorLastNameMissing,
                rejected[0].errorMessage,
                'With the reason the administrator can act on.'
            );
            Assert.isNotNull(
                rejected[0].values,
                'And the original values, for the exceptions file.'
            );
        }
    }

    /**
     * The exceptions file must hold every rejected row, not the first 200 (the old page size)
     * or the first 2,000 (the old OFFSET ceiling). 2,400 staged rows, 2,160 of them rejected,
     * read through one cursor in pages of 500.
     */
    @IsTest
    static void readsEveryRejectedRowThroughTheCursor() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = permittedTemplate();
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            List<Import_Row__c> staged = new List<Import_Row__c>();
            Integer expectedRejected = 0;
            for (Integer i = 0; i < 2400; i++) {
                Boolean rejected = Math.mod(i, 10) != 0;
                expectedRejected += rejected ? 1 : 0;
                staged.add(
                    new Import_Row__c(
                        Import_Batch__c = batch.Id,
                        Row_Number__c = i + 2,
                        Raw_Values_JSON__c = '{"Last Name":"Row ' + i + '"}',
                        Status__c = rejected
                            ? ImportRowProcessor.STATUS_REJECTED
                            : ImportRowProcessor.STATUS_PENDING,
                        Error_Message__c = rejected ? Label.Core_Import_ErrorLastNameMissing : null
                    )
                );
            }
            insert staged;

            Test.startTest();
            List<ImportController.RowView> read = new List<ImportController.RowView>();
            ImportController.RowPage page = ImportController.getRowPage(
                batch.Id,
                ImportRowProcessor.STATUS_REJECTED,
                null,
                0,
                500
            );
            read.addAll(page.rows);
            List<String> trace = new List<String>{ pageText(page) };
            Integer calls = 1;
            while (page.hasMore && calls < 20) {
                page = ImportController.getRowPage(
                    batch.Id,
                    ImportRowProcessor.STATUS_REJECTED,
                    page.cursor,
                    page.nextIndex,
                    500
                );
                read.addAll(page.rows);
                trace.add(pageText(page));
                calls++;
            }
            Test.stopTest();

            String pages = ' Pages: ' + String.join(trace, '; ');
            Assert.areEqual(
                expectedRejected,
                page.total,
                'The cursor holds every rejected row.' + pages
            );
            Assert.areEqual(
                expectedRejected,
                read.size(),
                'And every one of them is read.' + pages
            );
            Assert.areEqual(5, calls, 'In pages of 500.' + pages);
            Assert.isFalse(page.hasMore, 'Then the read says it is done.' + pages);
            Integer previous = 0;
            for (ImportController.RowView row : read) {
                Assert.areEqual(
                    ImportRowProcessor.STATUS_REJECTED,
                    row.status,
                    'Only rejected rows; row ' + row.rowNumber + ' is ' + row.status
                );
                Assert.isTrue(
                    row.rowNumber > previous,
                    'In file order, none twice: row ' + row.rowNumber + ' after ' + previous
                );
                previous = row.rowNumber;
            }
            Assert.areEqual(2401, previous, 'Up to the last rejected row of the file.');
        }
    }

    @IsTest
    static void holdsAPageBetweenOneRowAndTheCursorPageLimit() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = permittedTemplate();
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            List<Import_Row__c> staged = new List<Import_Row__c>();
            for (Integer i = 0; i < 2100; i++) {
                staged.add(
                    new Import_Row__c(
                        Import_Batch__c = batch.Id,
                        Row_Number__c = i + 2,
                        Status__c = ImportRowProcessor.STATUS_REJECTED
                    )
                );
            }
            insert staged;

            Test.startTest();
            ImportController.RowPage tooLarge = ImportController.getRowPage(
                batch.Id,
                ImportRowProcessor.STATUS_REJECTED,
                null,
                0,
                5000
            );
            ImportController.RowPage noSize = ImportController.getRowPage(
                batch.Id,
                null,
                tooLarge.cursor,
                tooLarge.nextIndex,
                0
            );
            ImportController.RowPage pastTheEnd = ImportController.getRowPage(
                batch.Id,
                null,
                tooLarge.cursor,
                9999,
                10
            );
            ImportController.RowPage noBatch = ImportController.getRowPage(null, null, null, 0, 10);
            Test.stopTest();

            Assert.areEqual(
                ImportController.MAX_PAGE_ROWS,
                tooLarge.rows.size(),
                'A page never holds more than the platform allows.'
            );
            Assert.areEqual(
                ImportController.MAX_PAGE_ROWS,
                tooLarge.nextIndex,
                'The next page starts after the first. ' + pageText(tooLarge)
            );
            Assert.isTrue(
                tooLarge.hasMore,
                'So the rest is left for the next page. ' + pageText(tooLarge)
            );
            Assert.areEqual(
                2100 - ImportController.MAX_PAGE_ROWS,
                noSize.rows.size(),
                'No size reads a default page, cut at the end of the cursor. ' + pageText(noSize)
            );
            Assert.areEqual(2100, noSize.nextIndex, 'It ends at the end. ' + pageText(noSize));
            Assert.isFalse(noSize.hasMore, 'Which ends the read. ' + pageText(noSize));
            Assert.areEqual(
                0,
                pastTheEnd.rows.size(),
                'A start past the end reads nothing. ' + pageText(pastTheEnd)
            );
            Assert.isFalse(pastTheEnd.hasMore, 'And says it is done. ' + pageText(pastTheEnd));
            Assert.areEqual(
                0,
                noBatch.total,
                'No batch, no rows, and no cursor opened. ' + pageText(noBatch)
            );
            Assert.isNull(noBatch.cursor, 'So no cursor counts against the daily limit.');
        }
    }

    @IsTest
    static void listsRecentImportsWithoutThePermission() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = true;
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            ImportTestDataFactory.batch(template);
            ImportController.permissionOverride = false;

            Test.startTest();
            List<ImportController.BatchView> recent = ImportController.getRecentBatches(5);
            Test.stopTest();

            Assert.areEqual(
                1,
                recent.size(),
                'A colleague can watch how an import is going without the administrator permission.'
            );
        }
    }

    @IsTest
    static void listsRecentImportsWithTheirStartTime() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = true;
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            Datetime started = Datetime.now().addMinutes(-10);
            batch.Started_At__c = started;
            update batch;
            ImportController.permissionOverride = false;

            Test.startTest();
            List<ImportController.BatchView> recent = ImportController.getRecentBatches(5);
            Test.stopTest();

            Assert.areEqual(
                started,
                recent[0].startedAt,
                'The job history sorts imports among bulk jobs by when each started.'
            );
        }
    }

    @IsTest
    static void keepsTheUploadedFileWhenOneIsSent() {
        System.runAs(TestUsers.admin()) {
            System.runAs(importer()) {
                ImportController.permissionOverride = true;
                Test.startTest();
                String documentId = ImportController.saveFile(
                    'donors.csv',
                    EncodingUtil.base64Encode(Blob.valueOf('Email\nana@example.org'))
                );
                Test.stopTest();
                Assert.isNotNull(documentId, 'The original can be downloaded again.');
            }

        }
    }

    @IsTest
    static void sendingNoFileIsNotAnError() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = true;
            Test.startTest();
            Assert.isNull(
                ImportController.saveFile('donors.csv', null),
                'A file too large to send is simply not kept; the import still runs.'
            );
            Test.stopTest();
        }
    }

    @IsTest
    static void aMissingBatchReadsAsNothingRatherThanThrowing() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Assert.isNull(ImportController.getBatch(null), 'No batch, no view, no exception.');
            Test.stopTest();
        }
    }

    private static Import_Batch__c committedBatch() {
        Import_Batch__c batch = ImportTestDataFactory.batch(permittedTemplate());
        batch.Is_Dry_Run__c = false;
        batch.Status__c = ImportBatchService.STATUS_COMPLETE;
        batch.Completed_At__c = Datetime.now().addMinutes(1);
        batch.Undo_Deadline__c = Datetime.now().addDays(30);
        update batch;
        insert new Contact(LastName = 'Ramirez', Created_By_Import_Batch__c = batch.Id);
        return batch;
    }

    @IsTest
    static void previewsAnUndoThenStartsIt() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            Assert.isTrue(ImportController.getBatch(batch.Id).canUndo, 'The list offers Undo.');

            ImportUndoService.Preview view = ImportController.previewUndo(batch.Id);
            Assert.areEqual(1, view.people, 'The screen is shown what would be removed.');

            Test.startTest();
            ImportController.BatchView started = ImportController.startUndo(batch.Id, view.total);
            Assert.areEqual(
                ImportBatchService.STATUS_UNDOING,
                started.status,
                'The batch is marked as being undone before the work starts.'
            );
            Assert.isFalse(started.canUndo, 'And no longer offers Undo.');
            Test.stopTest();
        }
    }

    @IsTest
    static void undoNeedsThePermission() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            ImportController.permissionOverride = false;
            try {
                ImportController.previewUndo(batch.Id);
                Assert.fail('Undoing an import needs the Manage BarnCRM Settings permission.');
            } catch (AuraHandledException expected) {
                Assert.areEqual(
                    Label.Core_Import_ErrorNoPermission,
                    expected.getMessage(),
                    'Saying so.'
                );
            }
        }
    }

    @IsTest
    static void offersTheColumnsAnInstalledModuleLoads() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = true;
            Test.startTest();
            List<ImportMapping.Target> targets = ImportController.getEntityTargets();
            Test.stopTest();

            ImportEntityProcessor installed = ImportEntityProcessors.find();
            Assert.areEqual(
                installed == null ? 0 : installed.targets().size(),
                targets.size(),
                'The picker offers exactly what the installed module loads, or nothing.'
            );
        }
    }

    @IsTest
    static void batchOptionsAreReadOrRefused() {
        System.runAs(TestUsers.admin()) {
            ImportController.BatchOptions none = ImportController.parseOptions(null);
            Assert.isNull(none.expectedCount, 'No options means no control totals.');
            ImportController.BatchOptions some = ImportController.parseOptions(
                '{"expectedCount": 3, "expectedAmount": null}'
            );
            Assert.areEqual(3, some.expectedCount, 'The count is read.');
            try {
                ImportController.parseOptions('{not json');
                Assert.fail('Unreadable options are refused.');
            } catch (ImportException e) {
                Assert.areEqual(
                    Label.Core_Import_ErrorOptionsUnreadable,
                    e.getMessage(),
                    'In words the administrator can act on.'
                );
            }
        }
    }
}
