/**
 * The controller: the permission gate on everything that changes anything, and the shapes the
 * two screens are built against.
 */
@IsTest
private class ImportControllerTest {
    @TestSetup
    static void setUp() {
        TestDataFactory.defaultSettings();
    }

    /**
     * The person a test that saves a file runs as: an administrator created for that test alone.
     *
     * Not the running user, because the running user's private library is shared with every other
     * test class running in parallel, and a save into it fails when another test's transaction
     * rolls back at the same moment. The full explanation is on `ReceiptTestDataFactory.issuer`.
     */
    private static User importer() {
        return TestDataFactory.createUser('Importer', new List<String>{ 'Nonprofit_Admin' });
    }

    private static Import_Template__c permittedTemplate() {
        ImportController.permissionOverride = true;
        return ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
    }

    @IsTest
    static void refusesEveryChangeWithoutThePermission() {
        ImportController.permissionOverride = false;
        Test.startTest();
        try {
            ImportController.getTemplates();
            Assert.fail('Importing needs the Manage Nonprofit Settings permission.');
        } catch (Exception e) {
            Assert.isTrue(
                e.getMessage().contains('Manage Open Impact Settings'),
                'And says which permission and who to ask: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void reportsWhetherTheUserMayImport() {
        ImportController.permissionOverride = true;
        Assert.isTrue(ImportController.canImport(), 'Permitted.');
        ImportController.permissionOverride = false;
        Assert.isFalse(ImportController.canImport(), 'Not permitted.');
    }

    @IsTest
    static void listsTemplatesForTheWizard() {
        ImportController.permissionOverride = true;
        Test.startTest();
        List<ImportController.TemplateView> templates = ImportController.getTemplates();
        Test.stopTest();
        Assert.isFalse(templates.isEmpty(), 'The shipped mappings are offered on first use.');
        Assert.isNotNull(templates[0].name, 'Each one has a name to show.');
        Assert.isNotNull(templates[0].mapping, 'And its mapping, so the picker can start from it.');
    }

    @IsTest
    static void suggestsAMappingAndPrefersTheTemplateOwnChoices() {
        Import_Template__c template = permittedTemplate();

        Test.startTest();
        String document = ImportController.suggestMapping(
            template.Id,
            new List<String>{ 'First Name', 'Email', 'Board seat expiry' }
        );
        Test.stopTest();

        Map<String, String> targets = ImportMapping.parse(document).targetsBySourceKey();
        Assert.areEqual('Contact1.Email', targets.get('email'), 'A known heading is suggested.');
        Assert.isFalse(
            targets.containsKey('board seat expiry'),
            'And one nobody recognizes loads nothing rather than being guessed at.'
        );
    }

    /**
     * Do not load is a choice, and a saved choice wins over the column library: a heading the
     * library recognizes, set to Do not load and saved, is still Do not load when the next
     * file with that heading is uploaded, rather than silently mapped again.
     */
    @IsTest
    static void aSavedDoNotLoadWinsOverARecognizedHeading() {
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

    @IsTest
    static void createsABatchAndSavesTheMappingWithIt() {
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
            '{"expectedCount": 12, "expectedAmount": 480.25, "saveDonationMatching": true, ' +
            '"donationMatching": "Never match", "matchDateWindowDays": 10}'
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
            SELECT Donation_Matching__c, Match_Date_Window_Days__c
            FROM Import_Template__c
            WHERE Id = :template.Id
        ];
        Assert.areEqual('Never match', matching.Donation_Matching__c, 'Donation matching is kept.');
        Assert.areEqual(10, matching.Match_Date_Window_Days__c, 'With its window.');
        Assert.areEqual('donors.csv', view.fileName, 'With the name the administrator uploaded.');
        Assert.isTrue(
            [SELECT Column_Mapping_JSON__c FROM Import_Template__c WHERE Id = :template.Id]
                .Column_Mapping_JSON__c.contains('Contact1.Phone'),
            'And the mapping was saved back, so next month needs no work.'
        );
    }

    @IsTest
    static void stagesRowsFromTheBrowserPage() {
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

    @IsTest
    static void runsADryRunAndReportsTheBatchBack() {
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

    @IsTest
    static void returnsRejectedRowsForTheExceptionsFile() {
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
        List<ImportController.RowView> rejected = ImportController.getRows(
            batch.Id,
            ImportRowProcessor.STATUS_REJECTED,
            0
        );
        Test.stopTest();

        Assert.areEqual(1, rejected.size(), 'Only the rejected row comes back.');
        Assert.areEqual(3, rejected[0].rowNumber, 'Named by its row number in the file.');
        Assert.areEqual(
            Label.Core_Import_ErrorLastNameMissing,
            rejected[0].errorMessage,
            'With the reason the administrator can act on.'
        );
        Assert.isNotNull(rejected[0].values, 'And the original values, for the exceptions file.');
    }

    @IsTest
    static void listsRecentImportsWithoutThePermission() {
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

    @IsTest
    static void keepsTheUploadedFileWhenOneIsSent() {
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

    @IsTest
    static void sendingNoFileIsNotAnError() {
        ImportController.permissionOverride = true;
        Test.startTest();
        Assert.isNull(
            ImportController.saveFile('donors.csv', null),
            'A file too large to send is simply not kept; the import still runs.'
        );
        Test.stopTest();
    }

    @IsTest
    static void aMissingBatchReadsAsNothingRatherThanThrowing() {
        Test.startTest();
        Assert.isNull(ImportController.getBatch(null), 'No batch, no view, no exception.');
        Test.stopTest();
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

    @IsTest
    static void undoNeedsThePermission() {
        Import_Batch__c batch = committedBatch();
        ImportController.permissionOverride = false;
        try {
            ImportController.previewUndo(batch.Id);
            Assert.fail('Undoing an import needs the Manage Nonprofit Settings permission.');
        } catch (AuraHandledException expected) {
            Assert.areEqual(
                Label.Core_Import_ErrorNoPermission,
                expected.getMessage(),
                'Saying so.'
            );
        }
    }

    @IsTest
    static void offersTheColumnsAnInstalledModuleLoads() {
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

    @IsTest
    static void batchOptionsAreReadOrRefused() {
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
