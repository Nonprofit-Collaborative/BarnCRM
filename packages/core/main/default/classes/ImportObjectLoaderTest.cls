/**
 * A template that loads one object (canonical model R-IT12 to R-IT14): insert, update by record
 * Id and upsert by an external ID, each at 200 rows in one chunk; the dry run that decides as
 * the commit would and writes nothing; lookups by ID and by name, and the rules for none and for
 * several; a value its field cannot take; a repeated key; match only; the journal.
 *
 * Duplicate dismissals stand for an object with an external ID and no automation, and
 * affiliations for one with lookups and its own rules. Both are Core's, so the tests run on
 * every org shape. Every test runs as a minimal-profile user holding only BarnCRM Admin, since
 * every read and save is in that user's own mode.
 */
@IsTest
private class ImportObjectLoaderTest {
    static {
        // Dismissals are the package's bookkeeping, which an import refuses; here they stand in
        // for an org's own object with an External ID, which Core does not otherwise have.
        DataProtectedFields.ordinaryForTest.add('duplicate_dismissal__c');
    }

    private static final Integer MANY = 200;

    private static Import_Template__c template;
    private static Import_Batch__c batch;

    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    private static User admin() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    /** A template loading this object, with these columns (source, target, lookup field). */
    private static void given(
        String objectName,
        String operation,
        List<List<String>> columns,
        List<Map<String, String>> values
    ) {
        ImportMapping mapping = new ImportMapping();
        for (List<String> column : columns) {
            ImportMapping.Column mapped = new ImportMapping.Column(column[0], column[1]);
            mapped.lookupField = column.size() > 2 ? column[2] : null;
            mapping.columns.add(mapped);
        }
        template = ImportTestDataFactory.template(mapping.serialize(), null);
        template.Target_Object__c = objectName;
        template.Load_Operation__c = operation;
        if (operation == ImportObjectSchema.OPERATION_UPSERT) {
            template.Load_Match_Field__c = 'Pair_Key__c';
        }
        update template;
        template = ImportTemplateSelector.selectById(template.Id);
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, values);
    }

    private static void set(Schema.SObjectField field, String value) {
        template.put(field, value);
        update template;
        template = ImportTemplateSelector.selectById(template.Id);
    }

    /** One pass over every row as one chunk. */
    private static ImportRowProcessor.Outcome run(Boolean dryRun) {
        ImportBatchService.beginPass(batch.Id);
        return chunk(ImportTestDataFactory.reload(batch.Id), dryRun);
    }

    /** One chunk of the current pass. */
    private static ImportRowProcessor.Outcome chunk(List<Import_Row__c> rows, Boolean dryRun) {
        batch = ImportBatchSelector.selectById(batch.Id);
        return ImportRowProcessor.process(
            batch,
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c, template.Default_Values_JSON__c),
            rows,
            dryRun
        );
    }

    private static List<Import_Row__c> rows() {
        return [
            SELECT Row_Number__c, Status__c, Error_Message__c, Gift_Id__c, Several_Matches__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batch.Id
            ORDER BY Row_Number__c
        ];
    }

    private static String rowErrors() {
        List<String> errors = new List<String>();
        for (Import_Row__c row : rows()) {
            if (row.Error_Message__c != null) {
                errors.add(row.Row_Number__c + ': ' + row.Error_Message__c);
            }
        }
        return String.join(errors, '; ');
    }

    private static Integer pages(String phase) {
        return [
            SELECT COUNT()
            FROM Import_Journal__c
            WHERE Import_Batch__c = :batch.Id AND Phase__c = :phase
        ];
    }

    private static List<List<String>> dismissalColumns() {
        return new List<List<String>>{
            new List<String>{ 'Pair Key', 'Record.Pair_Key__c' },
            new List<String>{ 'Reason', 'Record.Reason__c' }
        };
    }

    private static List<Map<String, String>> dismissalRows(Integer count, String reason) {
        List<Map<String, String>> result = new List<Map<String, String>>();
        for (Integer i = 0; i < count; i++) {
            result.add(new Map<String, String>{ 'Pair Key' => 'K' + i, 'Reason' => reason });
        }
        return result;
    }

    private static List<Duplicate_Dismissal__c> dismissals(Integer count, String reason) {
        List<Duplicate_Dismissal__c> result = new List<Duplicate_Dismissal__c>();
        for (Integer i = 0; i < count; i++) {
            result.add(new Duplicate_Dismissal__c(Pair_Key__c = 'K' + i, Reason__c = reason));
        }
        insert result;
        return result;
    }

    private static Integer dismissalsWith(String reason) {
        return [SELECT COUNT() FROM Duplicate_Dismissal__c WHERE Reason__c = :reason];
    }

    // -------------------------------------------------------------------------------------
    // 200 rows: insert, update, upsert, dry run
    // -------------------------------------------------------------------------------------

    @IsTest
    static void twoHundredInsertRowsLoadInOneChunkAfterADryRunThatWritesNothing() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                given(
                    'Duplicate_Dismissal__c',
                    ImportObjectSchema.OPERATION_INSERT,
                    dismissalColumns(),
                    dismissalRows(MANY, 'Loaded')
                );

                Test.startTest();
                ImportRowProcessor.Outcome preview = run(true);
                Integer afterPreview = dismissalsWith('Loaded');
                Integer journalAfterPreview = pages(ImportJournalService.PHASE_CREATED);
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.areEqual(MANY, preview.created, 'The dry run says every row creates.');
                Assert.areEqual(0, afterPreview, 'And creates nothing.');
                Assert.areEqual(0, journalAfterPreview, 'Nor journals anything.');
                Assert.areEqual(
                    MANY,
                    committed.created,
                    'The commit creates every row: ' + rowErrors()
                );
                Assert.areEqual(MANY, dismissalsWith('Loaded'), 'All two hundred are there.');
                Assert.areEqual(
                    MANY,
                    ImportJournalService.entryCount(batch.Id, ImportJournalService.PHASE_CREATED),
                    'Every creation is journaled, since the object has no batch tag.'
                );
                Assert.areEqual(
                    2,
                    pages(ImportJournalService.PHASE_CREATED),
                    'At most a hundred creations to a page.'
                );
                for (Import_Row__c row : rows()) {
                    Assert.areEqual(ImportRowProcessor.STATUS_CREATED, row.Status__c, 'Created.');
                    Assert.isNotNull(row.Gift_Id__c, 'The resulting record is on the row.');
                }
            }

        }
    }

    @IsTest
    static void twoHundredUpdatesByIdChangeOnlyWhatDiffersAndJournalTheValueBefore() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                List<Duplicate_Dismissal__c> stored = dismissals(MANY, 'Old');
                List<Map<String, String>> values = new List<Map<String, String>>();
                for (Integer i = 0; i < MANY; i++) {
                    values.add(
                        new Map<String, String>{
                            'Id' => stored[i].Id,
                            'Reason' => i == 0 ? 'Old' : 'New'
                        }
                    );
                }
                given(
                    'Duplicate_Dismissal__c',
                    ImportObjectSchema.OPERATION_UPDATE,
                    new List<List<String>>{
                        new List<String>{ 'Id', 'Record.Id' },
                        new List<String>{ 'Reason', 'Record.Reason__c' }
                    },
                    values
                );

                Test.startTest();
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.areEqual(MANY - 1, committed.updated, 'Every changed row: ' + rowErrors());
                Assert.areEqual(1, committed.matched, 'A row that changes nothing is matched.');
                Assert.areEqual(0, committed.created, 'An update never creates.');
                Assert.areEqual(MANY - 1, dismissalsWith('New'), 'The new reasons are saved.');
                Import_Journal__c page = [
                    SELECT Entries_JSON__c
                    FROM Import_Journal__c
                    WHERE
                        Import_Batch__c = :batch.Id
                        AND Phase__c = :ImportJournalService.PHASE_COMMIT
                    LIMIT 1
                ];
                Map<String, Object> entry = ImportJournalService.entries(page)[0];
                Map<String, Object> reason = (Map<String, Object>) ((Map<String, Object>) entry.get(
                        'fields'
                    ))
                    .values()[0];
                Assert.areEqual('Old', reason.get('before'), 'The value before is journaled.');
                Assert.areEqual(
                    MANY - 1,
                    ImportJournalService.entryCount(batch.Id, ImportJournalService.PHASE_COMMIT),
                    'One entry per changed record.'
                );
            }

        }
    }

    @IsTest
    static void twoHundredUpsertRowsUpdateWhatTheyFindAndCreateTheRest() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                dismissals(MANY / 2, 'Old');
                given(
                    'Duplicate_Dismissal__c',
                    ImportObjectSchema.OPERATION_UPSERT,
                    dismissalColumns(),
                    dismissalRows(MANY, 'New')
                );

                Test.startTest();
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.areEqual(MANY / 2, committed.updated, 'The half found: ' + rowErrors());
                Assert.areEqual(MANY / 2, committed.created, 'The half not found is created.');
                Assert.areEqual(MANY, dismissalsWith('New'), 'Every record holds the new reason.');
                Assert.areEqual(
                    MANY,
                    [SELECT COUNT() FROM Duplicate_Dismissal__c],
                    'Nothing found was created again.'
                );
                Assert.areEqual(
                    MANY / 2,
                    ImportJournalService.entryCount(batch.Id, ImportJournalService.PHASE_CREATED),
                    'The creations are journaled.'
                );
                Assert.areEqual(
                    MANY / 2,
                    ImportJournalService.entryCount(batch.Id, ImportJournalService.PHASE_COMMIT),
                    'And the updates.'
                );
            }

        }
    }

    @IsTest
    static void aDryRunOfTwoHundredUpsertRowsDecidesAsTheCommitAndWritesNothing() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                dismissals(MANY / 2, 'Old');
                given(
                    'Duplicate_Dismissal__c',
                    ImportObjectSchema.OPERATION_UPSERT,
                    dismissalColumns(),
                    dismissalRows(MANY, 'New')
                );

                Test.startTest();
                ImportRowProcessor.Outcome preview = run(true);
                Integer newAfterPreview = dismissalsWith('New');
                Integer allAfterPreview = [SELECT COUNT() FROM Duplicate_Dismissal__c];
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.areEqual(
                    MANY / 2,
                    preview.updated,
                    'The dry run finds the half that exists.'
                );
                Assert.areEqual(MANY / 2, preview.created, 'And says the rest would be created.');
                Assert.areEqual(0, newAfterPreview, 'It changes nothing.');
                Assert.areEqual(MANY / 2, allAfterPreview, 'And creates nothing.');
                Assert.areEqual(preview.updated, committed.updated, 'The commit decides the same.');
                Assert.areEqual(preview.created, committed.created, 'Row for row.');
            }

        }
    }

    // -------------------------------------------------------------------------------------
    // Lookups (R-IT13)
    // -------------------------------------------------------------------------------------

    private static Id organizationType() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
    }

    private static Account organization(String name) {
        Account created = new Account(Name = name, RecordTypeId = organizationType());
        insert created;
        return created;
    }

    private static Contact person(String lastName) {
        Contact created = new Contact(FirstName = 'Ana', LastName = lastName);
        insert created;
        return created;
    }

    private static void givenAffiliations(List<Map<String, String>> values) {
        given(
            'Affiliation__c',
            ImportObjectSchema.OPERATION_INSERT,
            new List<List<String>>{
                new List<String>{ 'Person', 'Record.Contact__c' },
                new List<String>{ 'Employer', 'Record.Organization__c', 'Name' },
                new List<String>{ 'Role', 'Record.Role__c' },
                new List<String>{ 'Since', 'Record.Start_Date__c' }
            },
            values
        );
    }

    private static Map<String, String> affiliation(Id personId, String employer, String role) {
        return new Map<String, String>{
            'Person' => personId,
            'Employer' => employer,
            'Role' => role,
            'Since' => '2026-01-15'
        };
    }

    @IsTest
    static void lookupsFindTheirParentByIdAndByNameIgnoringCase() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Contact ana = person('Ramirez');
                Account rose = organization('Rose City Arts');
                givenAffiliations(
                    new List<Map<String, String>>{
                        affiliation(ana.Id, 'rose city arts', 'Treasurer')
                    }
                );

                Test.startTest();
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.areEqual(1, committed.created, 'Loaded: ' + rowErrors());
                Affiliation__c loaded = [
                    SELECT Contact__c, Organization__c, Role__c, Start_Date__c
                    FROM Affiliation__c
                    WHERE Role__c = 'Treasurer'
                ];
                Assert.areEqual(ana.Id, loaded.Contact__c, 'The person by ID.');
                Assert.areEqual(rose.Id, loaded.Organization__c, 'The organization by its name.');
                Assert.areEqual(
                    Date.newInstance(2026, 1, 15),
                    loaded.Start_Date__c,
                    'The date read.'
                );
            }

        }
    }

    @IsTest
    static void aLookupThatFindsNobodyRejectsTheRowOrIsLeftEmptyWhenAsked() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Contact ana = person('Ramirez');
                givenAffiliations(
                    new List<Map<String, String>>{ affiliation(ana.Id, 'Nobody Inc', 'Volunteer') }
                );

                Test.startTest();
                ImportRowProcessor.Outcome rejecting = run(true);
                set(Import_Template__c.Lookup_Not_Found__c, ImportObjectSchema.LOOKUP_LEAVE_EMPTY);
                ImportRowProcessor.Outcome leaving = run(true);
                Test.stopTest();

                Assert.areEqual(
                    1,
                    rejecting.rejected,
                    'No organization by that name rejects the row.'
                );
                Assert.areEqual(1, leaving.created, 'Leave it empty loads the rest of the row.');
                Assert.isFalse(leaving.notes.isEmpty(), 'And the run log says so.');
            }

        }
    }

    @IsTest
    static void aLookupThatFindsSeveralRejectsOrTakesTheMostRecentlyChanged() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Contact ana = person('Ramirez');
                organization('Rose City Arts');
                organization('Rose City Arts');
                givenAffiliations(
                    new List<Map<String, String>>{
                        affiliation(ana.Id, 'Rose City Arts', 'Volunteer')
                    }
                );

                Test.startTest();
                ImportRowProcessor.Outcome rejecting = run(true);
                Boolean ticked = rows()[0].Several_Matches__c;
                set(
                    Import_Template__c.Several_Matches__c,
                    ImportTemplateService.SEVERAL_MOST_RECENT
                );
                ImportRowProcessor.Outcome taking = run(true);
                Test.stopTest();

                Assert.areEqual(1, rejecting.rejected, 'Several parents reject by default.');
                Assert.isTrue(ticked, 'The row says several matched.');
                Assert.areEqual(
                    1,
                    taking.created,
                    'The most recently changed is taken when asked.'
                );
            }

        }
    }

    // -------------------------------------------------------------------------------------
    // A row is one record (R-IT12)
    // -------------------------------------------------------------------------------------

    @IsTest
    static void aValueItsFieldCannotTakeRejectsTheRowNamingIt() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Contact ana = person('Ramirez');
                organization('Rose City Arts');
                Map<String, String> badDate = affiliation(ana.Id, 'Rose City Arts', 'Volunteer');
                badDate.put('Since', 'soon');
                Map<String, String> tooLong = affiliation(
                    ana.Id,
                    'Rose City Arts',
                    'x'.repeat(256)
                );
                givenAffiliations(new List<Map<String, String>>{ badDate, tooLong });

                Test.startTest();
                ImportRowProcessor.Outcome preview = run(true);
                Test.stopTest();

                List<Import_Row__c> loaded = rows();
                Assert.areEqual(2, preview.rejected, 'Neither row loads part of itself.');
                Assert.isTrue(loaded[0].Error_Message__c.contains('soon'), 'The value is named.');
                Assert.isTrue(loaded[1].Error_Message__c.contains('255'), 'And the length.');
            }

        }
    }

    @IsTest
    static void updateRefusesAnIdThatIsWrongOfAnotherObjectOrGone() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Duplicate_Dismissal__c gone = dismissals(1, 'Old')[0];
                delete gone;
                Contact ana = person('Ramirez');
                given(
                    'Duplicate_Dismissal__c',
                    ImportObjectSchema.OPERATION_UPDATE,
                    new List<List<String>>{
                        new List<String>{ 'Id', 'Record.Id' },
                        new List<String>{ 'Reason', 'Record.Reason__c' }
                    },
                    new List<Map<String, String>>{
                        new Map<String, String>{ 'Id' => 'not an id', 'Reason' => 'New' },
                        new Map<String, String>{ 'Id' => ana.Id, 'Reason' => 'New' },
                        new Map<String, String>{ 'Id' => gone.Id, 'Reason' => 'New' }
                    }
                );

                Test.startTest();
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                List<Import_Row__c> loaded = rows();
                Assert.areEqual(3, committed.rejected, 'None loads.');
                Assert.areEqual(0, committed.created, 'And nothing is created for them.');
                Assert.isTrue(loaded[0].Error_Message__c.contains('not an id'), 'Not an ID.');
                Assert.isTrue(loaded[1].Error_Message__c.contains(ana.Id), 'Another object.');
                Assert.areEqual(
                    Label.Core_Import_ErrorRecordNotFound,
                    loaded[2].Error_Message__c,
                    'A record that is gone.'
                );
            }

        }
    }

    @IsTest
    static void aRowNamingARecordAnEarlierChunkNamedIsRejected() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                List<Map<String, String>> values = dismissalRows(3, 'New');
                values[2].put('Pair Key', 'k0');
                given(
                    'Duplicate_Dismissal__c',
                    ImportObjectSchema.OPERATION_UPSERT,
                    dismissalColumns(),
                    values
                );

                Test.startTest();
                ImportBatchService.beginPass(batch.Id);
                List<Import_Row__c> staged = ImportTestDataFactory.reload(batch.Id);
                ImportRowProcessor.Outcome first = chunk(
                    new List<Import_Row__c>{ staged[0], staged[1] },
                    false
                );
                ImportRowProcessor.Outcome second = chunk(
                    new List<Import_Row__c>{ staged[2] },
                    false
                );
                Test.stopTest();

                Assert.areEqual(2, first.created, 'The first chunk loads: ' + rowErrors());
                Assert.areEqual(
                    1,
                    second.rejected,
                    'The same key, ignoring case, in a later chunk.'
                );
                Assert.areEqual(
                    Label.Core_Import_ErrorRecordRepeated,
                    rows()[2].Error_Message__c,
                    'Said in words.'
                );
            }

        }
    }

    @IsTest
    static void matchOnlyRejectsARowThatWouldCreate() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                dismissals(1, 'Old');
                given(
                    'Duplicate_Dismissal__c',
                    ImportObjectSchema.OPERATION_UPSERT,
                    dismissalColumns(),
                    dismissalRows(2, 'New')
                );
                update new Import_Batch__c(Id = batch.Id, Match_Only__c = true);

                Test.startTest();
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.areEqual(1, committed.updated, 'The row that matches loads.');
                Assert.areEqual(1, committed.rejected, 'The one that would create does not.');
                Assert.areEqual(
                    1,
                    [SELECT COUNT() FROM Duplicate_Dismissal__c],
                    'Nothing created.'
                );
            }

        }
    }

    @IsTest
    static void aProtectedFieldIsNamedOnceAndNeverWritten() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Contact ana = person('Ramirez');
                organization('Rose City Arts');
                given(
                    'Affiliation__c',
                    ImportObjectSchema.OPERATION_INSERT,
                    new List<List<String>>{
                        new List<String>{ 'Person', 'Record.Contact__c' },
                        new List<String>{ 'Employer', 'Record.Organization__c', 'Name' },
                        new List<String>{ 'Sample', 'Record.Sample_Data__c' }
                    },
                    new List<Map<String, String>>{
                        new Map<String, String>{
                            'Person' => ana.Id,
                            'Employer' => 'Rose City Arts',
                            'Sample' => 'true'
                        }
                    }
                );

                Test.startTest();
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.areEqual(1, committed.created, 'The row loads: ' + rowErrors());
                Assert.isFalse(
                    [SELECT Sample_Data__c FROM Affiliation__c LIMIT 1].Sample_Data__c,
                    'The sample data mark is the package own.'
                );
                Assert.isTrue(
                    committed.notes.contains(
                        String.format(
                            Label.Core_Import_LogFieldProtected,
                            new List<String>{
                                Affiliation__c.Sample_Data__c.getDescribe().getLabel()
                            }
                        )
                    ),
                    'Named once in the run log.'
                );
            }

        }
    }

    @IsTest
    static void aTemplateThatCannotLoadRejectsEveryRowWithItsReason() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                given(
                    'Contact',
                    ImportObjectSchema.OPERATION_INSERT,
                    new List<List<String>>{ new List<String>{ 'Last', 'Record.LastName' } },
                    new List<Map<String, String>>{
                        new Map<String, String>{ 'Last' => 'Ramirez' },
                        new Map<String, String>{ 'Last' => 'Chen' }
                    }
                );

                Test.startTest();
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.areEqual(2, committed.rejected, 'People are not inserted here.');
                Assert.isTrue(
                    rows()[0].Error_Message__c.contains('record ID'),
                    'The reason is on the row.'
                );
                Assert.areEqual(
                    0,
                    [SELECT COUNT() FROM Contact WHERE LastName IN ('Ramirez', 'Chen')],
                    'Nobody created.'
                );
            }

        }
    }

    @IsTest
    static void aDryRunStartsAndRunsThroughTheImportBatchOrIsRefusedFirst() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                given(
                    'Duplicate_Dismissal__c',
                    ImportObjectSchema.OPERATION_UPDATE,
                    dismissalColumns(),
                    dismissalRows(MANY, 'New')
                );
                String refused;
                try {
                    ImportBatchService.startDryRun(batch.Id);
                } catch (ImportException e) {
                    refused = e.getMessage();
                }
                set(Import_Template__c.Load_Operation__c, ImportObjectSchema.OPERATION_INSERT);

                Test.startTest();
                ImportBatchService.startDryRun(batch.Id);
                Test.stopTest();

                Import_Batch__c finished = ImportBatchSelector.selectById(batch.Id);
                Assert.areEqual(
                    Label.Core_Import_ErrorIdColumnMissing,
                    refused,
                    'An update with no record ID column never starts.'
                );
                Assert.areEqual(
                    ImportBatchService.STATUS_DRY_RUN_COMPLETE,
                    finished.Status__c,
                    'An insert runs through the import batch: ' + finished.Run_Log__c
                );
                Assert.areEqual(MANY, finished.Rows_Created__c, 'Every row would be created.');
                Assert.areEqual(0, [SELECT COUNT() FROM Duplicate_Dismissal__c], 'Nothing is.');
            }

        }
    }
}
