/**
 * Correcting a rejected import row on screen and retrying it in place (C-49b, R-IR4, R-IB17a):
 * the corrections sit beside the untouched file values, a retry runs the import's own commit
 * path over only those rows and tags what it creates with the import, and every refusal says
 * why. The bulk test retries 251 corrected rows.
 *
 * A test may start one batch job, so a retry of many rows is driven through the processor
 * itself, in chunks, the way the platform would.
 */
@IsTest(
    testFor='ApexClass:ImportRowCorrectionController, ApexClass:ImportBatchService, ApexClass:ImportProcessorBatch'
)
private class ImportRowCorrectionTest {
    private static final Integer FILE_ROWS = 502;
    /** Every other row of the file has no last name, so 251 rows are rejected. */
    private static final Integer REJECTS = 251;
    private static final Integer CHUNK_ROWS = 200;

    /** A committed import with 251 rejected rows, built once, as the admin each test runs as. */
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
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
                        Math.mod(i, 2) == 0 ? '' : 'Surname' + i,
                        'fix' + i + '@example.org',
                        null
                    )
                );
            }
            ImportTestDataFactory.rows(batch, values);
            ImportBatchService.beginPass(batch.Id);
            update new Import_Batch__c(
                Id = batch.Id,
                Status__c = ImportBatchService.STATUS_COMMITTING,
                Is_Dry_Run__c = false,
                Started_At__c = Datetime.now(),
                Committed_By__c = UserInfo.getUserId()
            );
            drive(new ImportProcessorBatch(batch.Id, false));
        }
    }

    /** Runs a processor job's start, its chunks and its finish in this transaction. */
    private static void drive(ImportProcessorBatch job) {
        List<Import_Row__c> chunk = new List<Import_Row__c>();
        Database.QueryLocatorIterator found = job.start(null).iterator();
        while (found.hasNext()) {
            chunk.add((Import_Row__c) found.next());
            if (chunk.size() == CHUNK_ROWS) {
                job.execute(null, chunk);
                chunk = new List<Import_Row__c>();
            }
        }
        if (!chunk.isEmpty()) {
            job.execute(null, chunk);
        }
        job.finish(null);
    }

    private static Import_Batch__c committed() {
        return ImportBatchSelector.selectById([SELECT Id FROM Import_Batch__c LIMIT 1].Id);
    }

    private static List<Import_Row__c> rejectedRows() {
        return [
            SELECT Id, Row_Number__c, Raw_Values_JSON__c, Corrected_Values_JSON__c, Status__c
            FROM Import_Row__c
            WHERE Status__c = :ImportRowProcessor.STATUS_REJECTED
            WITH SYSTEM_MODE
            ORDER BY Row_Number__c
        ];
    }

    private static String lastNameFix(String lastName) {
        return JSON.serialize(new Map<String, Object>{ 'Last Name' => lastName });
    }

    private static String refusalOf(Exception e) {
        return e.getMessage();
    }

    @IsTest
    static void correctionsSitBesideTheFileValuesWhichNeverChange() {
        System.runAs(TestUsers.admin()) {
            ImportRowCorrectionController.permissionOverride = true;
            Import_Row__c row = rejectedRows()[0];
            Assert.areEqual(REJECTS, rejectedRows().size(), 'Every other row was rejected.');

            Test.startTest();
            ImportRowCorrectionController.RowView shown = ImportRowCorrectionController.saveCorrections(
                row.Id,
                JSON.serialize(
                    new Map<String, Object>{
                        'Last Name' => 'Fixed',
                        'City' => 'Portland',
                        'Not A Column' => 'x'
                    }
                )
            );
            Test.stopTest();

            Import_Row__c saved = [
                SELECT Raw_Values_JSON__c, Corrected_Values_JSON__c
                FROM Import_Row__c
                WHERE Id = :row.Id
            ];
            Assert.areEqual(row.Raw_Values_JSON__c, saved.Raw_Values_JSON__c, 'Raw never changes.');
            Assert.areEqual(
                lastNameFix('Fixed'),
                saved.Corrected_Values_JSON__c,
                'Only the column that differs is kept, and no unknown column.'
            );
            Assert.isTrue(shown.canCorrect, 'The committer may correct it.');
            Assert.areEqual(1, shown.fixedCount, 'One row is ready to retry.');
            for (ImportRowCorrectionController.ColumnView column : shown.columns) {
                if (column.column == 'Last Name') {
                    Assert.isTrue(column.corrected);
                    Assert.areEqual('', column.fileValue, 'The file value is shown beside it.');
                    Assert.areEqual('Fixed', column.correctedValue);
                } else {
                    Assert.isFalse(column.corrected, column.column);
                }
            }

            ImportRowCorrectionController.saveCorrections(row.Id, '{"Last Name": ""}');
            Assert.isNull(
                [SELECT Corrected_Values_JSON__c FROM Import_Row__c WHERE Id = :row.Id]
                .Corrected_Values_JSON__c,
                'Saving the file values again clears the corrections.'
            );
        }
    }

    @IsTest
    static void aCorrectedRowIsRetriedInPlaceThroughTheImportAndTagged() {
        System.runAs(TestUsers.admin()) {
            ImportRowCorrectionController.permissionOverride = true;
            Import_Batch__c before = committed();
            Import_Row__c row = rejectedRows()[0];
            ImportRowCorrectionController.saveCorrections(row.Id, lastNameFix('Fixed'));

            Test.startTest();
            Id jobId = ImportRowCorrectionController.retryRow(row.Id);
            Test.stopTest();

            Assert.isNotNull(jobId, 'A job was started.');
            Import_Row__c after = [
                SELECT Status__c, Raw_Values_JSON__c, Contact_1__c
                FROM Import_Row__c
                WHERE Id = :row.Id
            ];
            Assert.areEqual(ImportRowProcessor.STATUS_CREATED, after.Status__c, 'Loaded now.');
            Assert.areEqual(row.Raw_Values_JSON__c, after.Raw_Values_JSON__c, 'Raw unchanged.');
            Contact person = [
                SELECT LastName, Created_By_Import_Batch__c
                FROM Contact
                WHERE Id = :after.Contact_1__c
            ];
            Assert.areEqual('Fixed', person.LastName, 'The correction was read.');
            Assert.areEqual(before.Id, person.Created_By_Import_Batch__c, 'Tagged for the undo.');
            Import_Batch__c batch = committed();
            Assert.areEqual(ImportBatchService.STATUS_COMPLETE, batch.Status__c);
            Assert.areEqual(REJECTS - 1, batch.Rows_Rejected__c, 'Every row is counted again.');
            Assert.areEqual(
                before.Started_At__c,
                batch.Started_At__c,
                'The import keeps its start.'
            );
            Assert.isTrue(
                batch.Run_Log__c.contains(
                    String.format(Label.Core_Import_LogCorrectedRetry, new List<String>{ '1' })
                ),
                'The run log says so, after the commit\'s: ' + batch.Run_Log__c
            );
            Assert.isTrue(
                ImportUndoService.preview(batch.Id).total > 0,
                'The one undo covers what the retry created.'
            );
        }
    }

    @IsTest
    static void twoHundredFiftyOneCorrectedRowsAreRetriedTogether() {
        System.runAs(TestUsers.admin()) {
            List<Import_Row__c> corrections = new List<Import_Row__c>();
            for (Import_Row__c row : rejectedRows()) {
                corrections.add(
                    new Import_Row__c(
                        Id = row.Id,
                        Corrected_Values_JSON__c = lastNameFix('Bulk' + row.Row_Number__c)
                    )
                );
            }
            update corrections;
            Set<Id> fixed = ImportBatchService.fixedRowIds(committed().Id, null);
            Assert.areEqual(REJECTS, fixed.size(), 'Every corrected rejected row is found.');

            Test.startTest();
            // Started through the service, then run here in chunks: a test may run one chunk.
            System.abortJob(ImportBatchService.startRowRetry(committed().Id, null));
            drive(new ImportProcessorBatch(committed().Id, fixed));
            Test.stopTest();

            Import_Batch__c batch = committed();
            Assert.areEqual(0, batch.Rows_Rejected__c, 'None is rejected now.');
            Assert.areEqual(FILE_ROWS, batch.Rows_Created__c, 'Every row created someone.');
            Assert.areEqual(
                FILE_ROWS,
                [SELECT COUNT() FROM Contact WHERE Created_By_Import_Batch__c = :batch.Id],
                'All tagged with the one import.'
            );
            Assert.areEqual(0, rejectedRows().size());
        }
    }

    @IsTest
    static void eachRefusalSaysWhy() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committed();
            Import_Row__c rejected = rejectedRows()[0];
            Import_Row__c created = [
                SELECT Id
                FROM Import_Row__c
                WHERE Status__c = :ImportRowProcessor.STATUS_CREATED
                LIMIT 1
            ];
            List<String> said = new List<String>();

            ImportRowCorrectionController.permissionOverride = false;
            ImportRowCorrectionController.RowView view = ImportRowCorrectionController.getRow(
                rejected.Id
            );
            Assert.isFalse(view.canCorrect, 'Without the permission it is read only.');
            Assert.areEqual(Label.Core_Import_ErrorNoPermission, view.refusal);
            try {
                ImportRowCorrectionController.saveCorrections(rejected.Id, lastNameFix('X'));
            } catch (AuraHandledException e) {
                said.add(refusalOf(e));
            }

            ImportRowCorrectionController.permissionOverride = true;
            try {
                ImportRowCorrectionController.saveCorrections(created.Id, lastNameFix('X'));
            } catch (AuraHandledException e) {
                said.add(refusalOf(e));
            }
            try {
                ImportRowCorrectionController.retryAllFixed(rejected.Id);
            } catch (AuraHandledException e) {
                said.add(refusalOf(e));
            }
            ImportBatchService.openRetry(batch.Id);
            try {
                ImportRowCorrectionController.retryRow(rejected.Id);
            } catch (AuraHandledException e) {
                said.add(refusalOf(e));
            }

            Assert.areEqual(
                new List<String>{
                    Label.Core_Import_ErrorNoPermission,
                    Label.Core_Import_ErrorCorrectOnlyRejected,
                    Label.Core_Import_ErrorNoFixedRows,
                    Label.Core_Import_ErrorRetryByFileOpen
                },
                said
            );
            Assert.isNull(
                [SELECT Corrected_Values_JSON__c FROM Import_Row__c WHERE Id = :rejected.Id]
                .Corrected_Values_JSON__c,
                'Nothing refused was saved.'
            );
        }
    }

    @IsTest
    static void onlyTheCommitterMayRetry() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committed();
            // An existing user, so no user is inserted beside the batch update (mixed DML).
            User other = [
                SELECT Id
                FROM User
                WHERE Id != :UserInfo.getUserId() AND IsActive = TRUE
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            update new Import_Batch__c(Id = batch.Id, Committed_By__c = other.Id);

            Assert.areEqual(
                Label.Core_Import_ErrorRetryOtherUser,
                ImportBatchService.rowRetryRefusal(committed()),
                'Undo tells the import\'s records apart by the one person who committed it.'
            );
            Assert.isNull(ImportBatchService.rowRetryRefusal(batch), 'The committer may.');
        }
    }
}
