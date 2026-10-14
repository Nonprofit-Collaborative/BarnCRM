/**
 * A one-object template matching through the org's duplicate rules (canonical model R-IT16,
 * R-IT12): only rows that would create are asked, a record ID or key match wins, a match updates
 * the record instead of creating one, several follow Several Matches, a record another row loads
 * or an earlier chunk created or loaded is set aside, the dry run decides as the commit, a match
 * never overwrites another key, and a rule that cannot run rejects rather than creates. Which
 * records an org's rules call duplicates is the org's business and a test cannot create a rule,
 * so the matcher's answer is stubbed (`ImportDuplicateRuleMatcher.stubMatches`).
 *
 * Duplicate dismissals stand for an org's own object with an external ID, as in
 * `ImportObjectLoaderTest`. Every test runs as a minimal-profile user holding only BarnCRM
 * Admin.
 */
@IsTest(testFor='ApexClass:ImportObjectLoader')
private class ImportObjectDuplicateRuleTest {
    static {
        // Dismissals are the package's bookkeeping, which an import refuses; here they stand in
        // for an org's own object with an External ID, which Core does not otherwise have.
        DataProtectedFields.ordinaryForTest.add('duplicate_dismissal__c');
    }

    private static final Integer MANY = 200;
    private static final String OBJECT_NAME = 'Duplicate_Dismissal__c';

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

    /** A dismissal template asking the duplicate rules, and a batch of these rows. */
    private static void given(String operation, List<Map<String, String>> values) {
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Pair Key', 'Record.Pair_Key__c'));
        mapping.columns.add(new ImportMapping.Column('Reason', 'Record.Reason__c'));
        if (operation == ImportObjectSchema.OPERATION_UPDATE) {
            mapping.columns.add(new ImportMapping.Column('Id', 'Record.Id'));
        }
        template = ImportTestDataFactory.template(mapping.serialize(), null);
        template.Target_Object__c = OBJECT_NAME;
        template.Load_Operation__c = operation;
        template.Use_Duplicate_Rules__c = true;
        if (operation == ImportObjectSchema.OPERATION_UPSERT) {
            template.Load_Match_Field__c = 'Pair_Key__c';
        }
        update template;
        template = ImportTemplateSelector.selectById(template.Id);
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, values);
    }

    private static ImportRowProcessor.Outcome run(Boolean dryRun) {
        ImportBatchService.beginPass(batch.Id);
        return chunk(ImportTestDataFactory.reload(batch.Id), dryRun);
    }

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
            SELECT
                Row_Number__c,
                Status__c,
                Error_Message__c,
                Gift_Id__c,
                Several_Matches__c,
                Duplicate_Rule_Match__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batch.Id
            ORDER BY Row_Number__c
        ];
    }

    private static Integer ruleMatchedRows() {
        return [
            SELECT COUNT()
            FROM Import_Row__c
            WHERE Import_Batch__c = :batch.Id AND Duplicate_Rule_Match__c = TRUE
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

    private static Map<String, String> row(String key, String reason) {
        return new Map<String, String>{ 'Pair Key' => key, 'Reason' => reason };
    }

    private static List<Duplicate_Dismissal__c> dismissals(Integer count) {
        List<Duplicate_Dismissal__c> result = new List<Duplicate_Dismissal__c>();
        for (Integer i = 0; i < count; i++) {
            result.add(new Duplicate_Dismissal__c(Pair_Key__c = 'K' + i, Reason__c = 'Old'));
        }
        insert result;
        return result;
    }

    private static Duplicate_Dismissal__c reread(Id recordId) {
        return [SELECT Pair_Key__c, Reason__c FROM Duplicate_Dismissal__c WHERE Id = :recordId];
    }

    // -------------------------------------------------------------------------------------
    // Insert: 200 rows, dry run and commit
    // -------------------------------------------------------------------------------------

    @IsTest
    static void twoHundredInsertRowsTheRulesMatchUpdateInsteadAndTheDryRunAgrees() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                List<Duplicate_Dismissal__c> existing = dismissals(MANY / 2);
                List<Map<String, String>> values = new List<Map<String, String>>();
                ImportDuplicateRuleMatcher.stubMatches = new Map<String, List<Id>>();
                for (Integer i = 0; i < MANY; i++) {
                    values.add(row('N' + i, 'New'));
                    if (i < MANY / 2) {
                        ImportDuplicateRuleMatcher.stubMatches.put(
                            'n' + i,
                            new List<Id>{ existing[i].Id }
                        );
                    }
                }
                given(ImportObjectSchema.OPERATION_INSERT, values);

                Test.startTest();
                ImportRowProcessor.Outcome preview = run(true);
                Integer allAfterPreview = [SELECT COUNT() FROM Duplicate_Dismissal__c];
                Integer ticked = ruleMatchedRows();
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.areEqual(MANY / 2, preview.updated, 'The matched half: ' + rowErrors());
                Assert.areEqual(MANY / 2, preview.created, 'The rest would be created.');
                Assert.areEqual(MANY / 2, allAfterPreview, 'The dry run writes nothing.');
                Assert.areEqual(MANY / 2, ticked, 'The dry run ticks the rows the rules matched.');
                Assert.isTrue(
                    preview.notes.contains(Label.Core_Import_LogDuplicateRuleMatchesRecords),
                    'And says so in the run log.'
                );
                Assert.areEqual(preview.updated, committed.updated, 'The commit decides the same.');
                Assert.areEqual(preview.created, committed.created, 'Row for row.');
                Assert.areEqual(
                    MANY,
                    [SELECT COUNT() FROM Duplicate_Dismissal__c],
                    'No second copy of a matched record.'
                );
                Assert.areEqual(
                    'New',
                    reread(existing[0].Id).Reason__c,
                    'The matched record takes the row values.'
                );
                Assert.areEqual(MANY / 2, ruleMatchedRows(), 'Ticked after the commit too.');
                Assert.areEqual(
                    MANY / 2,
                    ImportJournalService.entryCount(batch.Id, ImportJournalService.PHASE_COMMIT),
                    'The updates are journaled for undo.'
                );
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // Precedence, several matches, one record per row
    // -------------------------------------------------------------------------------------

    @IsTest
    static void anUpsertKeyMatchWinsAndARuleMatchNeverOverwritesAnotherKey() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                List<Duplicate_Dismissal__c> existing = dismissals(3);
                // A record with no key yet takes the row's.
                existing[1].Pair_Key__c = null;
                update existing[1];
                ImportDuplicateRuleMatcher.stubMatches = new Map<String, List<Id>>{
                    // Were the key row asked, the rules would send it to the other record.
                    'k0' => new List<Id>{ existing[1].Id },
                    'n1' => new List<Id>{ existing[1].Id },
                    'n3' => new List<Id>{ existing[2].Id }
                };
                given(
                    ImportObjectSchema.OPERATION_UPSERT,
                    new List<Map<String, String>>{
                        row('K0', 'Key'),
                        row('N1', 'Rule'),
                        row('N3', 'Rule')
                    }
                );

                Test.startTest();
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.areEqual(2, committed.updated, 'Two update: ' + rowErrors());
                Assert.areEqual('Key', reread(existing[0].Id).Reason__c, 'The key found its own.');
                Duplicate_Dismissal__c matched = reread(existing[1].Id);
                Assert.areEqual('Rule', matched.Reason__c, 'The rules found the other.');
                Assert.areEqual('N1', matched.Pair_Key__c, 'And it takes the row key.');
                List<Import_Row__c> loaded = rows();
                Assert.isFalse(loaded[0].Duplicate_Rule_Match__c, 'A key match is not ticked.');
                Assert.isTrue(loaded[1].Duplicate_Rule_Match__c, 'A rule match is.');
                Assert.areEqual(
                    String.format(
                        Label.Core_Import_ErrorDuplicateRuleKeyDiffers,
                        new List<String>{
                            Schema.SObjectType.Duplicate_Dismissal__c.fields.Pair_Key__c.getLabel()
                        }
                    ),
                    loaded[2].Error_Message__c,
                    'A match holding another key is rejected.'
                );
                Assert.areEqual('K2', reread(existing[2].Id).Pair_Key__c, 'Its key is kept.');
                Assert.areEqual(
                    3,
                    [SELECT COUNT() FROM Duplicate_Dismissal__c],
                    'Nothing is created.'
                );
            }
        }
    }

    @IsTest
    static void severalMatchesSetAsideARecordAnEarlierChunkLoaded() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                List<Duplicate_Dismissal__c> existing = dismissals(2);
                ImportDuplicateRuleMatcher.stubMatches = new Map<String, List<Id>>{
                    'n0' => new List<Id>{ existing[0].Id },
                    'n9' => new List<Id>{ existing[0].Id, existing[1].Id }
                };
                given(
                    ImportObjectSchema.OPERATION_INSERT,
                    new List<Map<String, String>>{ row('N0', 'First'), row('N9', 'Second') }
                );
                template.Several_Matches__c = ImportTemplateService.SEVERAL_MOST_RECENT;
                update template;
                template = ImportTemplateSelector.selectById(template.Id);

                Test.startTest();
                List<Id> chosen = new List<Id>();
                for (Boolean dryRun : new List<Boolean>{ true, false }) {
                    ImportBatchService.beginPass(batch.Id);
                    List<Import_Row__c> staged = ImportTestDataFactory.reload(batch.Id);
                    chunk(new List<Import_Row__c>{ staged[0] }, dryRun);
                    chunk(new List<Import_Row__c>{ staged[1] }, dryRun);
                    chosen.add(rows()[1].Gift_Id__c);
                }
                Test.stopTest();

                Assert.areEqual(
                    existing[1].Id,
                    chosen[0],
                    'The dry run sets aside the record the first chunk loads: ' + rowErrors()
                );
                Assert.areEqual(
                    chosen[0],
                    chosen[1],
                    'The commit chooses the same, though the first chunk changed that record.'
                );
            }
        }
    }

    @IsTest
    static void severalMatchesRejectTheRowOrTakeTheMostRecentlyChanged() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                List<Duplicate_Dismissal__c> existing = dismissals(2);
                ImportDuplicateRuleMatcher.stubMatches = new Map<String, List<Id>>{
                    'n0' => new List<Id>{ existing[0].Id, existing[1].Id }
                };
                given(
                    ImportObjectSchema.OPERATION_INSERT,
                    new List<Map<String, String>>{ row('N0', 'New') }
                );

                Test.startTest();
                ImportRowProcessor.Outcome rejected = run(true);
                Import_Row__c first = rows()[0];
                template.Several_Matches__c = ImportTemplateService.SEVERAL_MOST_RECENT;
                update template;
                template = ImportTemplateSelector.selectById(template.Id);
                ImportRowProcessor.Outcome taken = run(true);
                Test.stopTest();

                Assert.areEqual(1, rejected.rejected, 'Several matches reject by default.');
                Assert.areEqual(
                    Label.Core_Import_ErrorSeveralDuplicateRuleRecords,
                    first.Error_Message__c,
                    'Said in words.'
                );
                Assert.isTrue(first.Several_Matches__c, 'And ticked.');
                Assert.areEqual(1, taken.updated, 'Most recent takes one: ' + rowErrors());
                Assert.isTrue(rows()[0].Several_Matches__c, 'Still ticked so it can be read.');
            }
        }
    }

    @IsTest
    static void aRecordAnotherRowLoadsIsNotLoadedTwiceAndOneTheImportCreatedIsNotTaken() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                List<Duplicate_Dismissal__c> existing = dismissals(1);
                ImportDuplicateRuleMatcher.stubMatches = new Map<String, List<Id>>{
                    'n0' => new List<Id>{ existing[0].Id },
                    'n4' => new List<Id>{ existing[0].Id },
                    'n2' => new List<Id>{ existing[0].Id }
                };
                given(
                    ImportObjectSchema.OPERATION_INSERT,
                    new List<Map<String, String>>{
                        row('N0', 'New'),
                        row('N1', 'New'),
                        row('N4', 'New'),
                        row('N2', 'New'),
                        row('N3', 'New')
                    }
                );

                Test.startTest();
                ImportBatchService.beginPass(batch.Id);
                List<Import_Row__c> staged = ImportTestDataFactory.reload(batch.Id);
                ImportRowProcessor.Outcome first = chunk(
                    new List<Import_Row__c>{ staged[0], staged[1], staged[2] },
                    false
                );
                Id createdByImport = [
                    SELECT Id
                    FROM Duplicate_Dismissal__c
                    WHERE Pair_Key__c = 'N1'
                ]
                .Id;
                // The rules would now call the record the first chunk created a match.
                ImportDuplicateRuleMatcher.stubMatches.put('n3', new List<Id>{ createdByImport });
                ImportRowProcessor.Outcome second = chunk(
                    new List<Import_Row__c>{ staged[3], staged[4] },
                    false
                );
                Test.stopTest();

                List<Import_Row__c> loaded = rows();
                Assert.areEqual(1, first.updated, 'The first row takes the record.');
                Assert.areEqual(1, first.created, 'The unmatched row creates.');
                Assert.areEqual(
                    Label.Core_Import_ErrorDuplicateRuleRecordRepeated,
                    loaded[2].Error_Message__c,
                    'A second row of the chunk matched to it is rejected.'
                );
                Assert.areEqual(
                    Label.Core_Import_ErrorDuplicateRuleRecordRepeated,
                    loaded[3].Error_Message__c,
                    'And one in a later chunk.'
                );
                Assert.areEqual(
                    1,
                    second.created,
                    'A record the import created is not taken, as the dry run could not see it.'
                );
                Assert.isFalse(loaded[4].Duplicate_Rule_Match__c, 'So that row is not ticked.');
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // When the rules are not asked
    // -------------------------------------------------------------------------------------

    @IsTest
    static void withNoRuleToAskEveryRowCreatesAndTheRunLogSaysSo() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                ImportDuplicateRuleMatcher.stubUnavailable = true;
                given(
                    ImportObjectSchema.OPERATION_INSERT,
                    new List<Map<String, String>>{ row('N0', 'New'), row('N1', 'New') }
                );

                Test.startTest();
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.areEqual(2, committed.created, 'Nothing is rejected: ' + rowErrors());
                Assert.isTrue(
                    committed.notes.contains(Label.Core_Import_LogNoDuplicateRuleRecords),
                    'The run log says the rules were not asked.'
                );
            }
        }
    }

    @IsTest
    static void anUpdateByRecordIdNeverAsksTheRules() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                List<Duplicate_Dismissal__c> existing = dismissals(2);
                ImportDuplicateRuleMatcher.stubMatches = new Map<String, List<Id>>{
                    'n0' => new List<Id>{ existing[1].Id }
                };
                Map<String, String> values = row('N0', 'New');
                values.put('Id', existing[0].Id);
                given(ImportObjectSchema.OPERATION_UPDATE, new List<Map<String, String>>{ values });

                Test.startTest();
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.areEqual(1, committed.updated, 'The ID decides: ' + rowErrors());
                Assert.areEqual('New', reread(existing[0].Id).Reason__c, 'Its record changes.');
                Assert.areEqual('Old', reread(existing[1].Id).Reason__c, 'Not the rule match.');
                Assert.areEqual(0, ruleMatchedRows(), 'Nothing is ticked.');
                Assert.isFalse(
                    ImportObjectLoader.createsRecords(ImportObjectSchema.OPERATION_UPDATE_BY_FIELD),
                    'An update by a field creates nothing either.'
                );
                Assert.isTrue(
                    ImportObjectLoader.createsRecords(ImportObjectSchema.OPERATION_UPSERT),
                    'An upsert can.'
                );
            }
        }
    }

    @IsTest
    static void whenARuleCannotBeRunTheRowsThatWouldCreateAreRejected() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                dismissals(1);
                ImportDuplicateRuleMatcher.stubFailure = true;
                given(
                    ImportObjectSchema.OPERATION_UPSERT,
                    new List<Map<String, String>>{ row('K0', 'Key'), row('N1', 'New') }
                );

                Test.startTest();
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.isTrue(ImportDuplicateRuleMatcher.lastAskFailed(), 'The ask failed.');
                Assert.areEqual(1, committed.updated, 'The key row still loads.');
                Assert.areEqual(1, committed.rejected, 'The row that would create does not.');
                Assert.areEqual(
                    Label.Core_Import_ErrorDuplicateRulesUnavailable,
                    rows()[1].Error_Message__c,
                    'Said in words.'
                );
                Assert.areEqual(
                    1,
                    [SELECT COUNT() FROM Duplicate_Dismissal__c],
                    'No possible duplicate is created.'
                );
            }
        }
    }
}
